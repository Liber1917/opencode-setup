#!/usr/bin/env bash
# opencode-setup · E-Ⅱ 审计模块 (observe-only, logira 式)
# 设计依据: spec E-2 — JSONL 追加 <1ms/调用; 审批来源必记; 轮转+30天; 熔断器
# 依赖: opencode event hooks (实验特性; 不可用时降级为 session 日志定期归档)
# 用法:
#   audit-init.sh              → 安装 hook 配置片段 + 创建日志目录
#   audit-init.sh --rotate     → 立即轮转(可挂 cron)

set -euo pipefail
AUDIT_DIR="${OPENCODE_AUDIT_DIR:-$(dirname "$(readlink -f "$0")")}"
LOG="$AUDIT_DIR/audit.jsonl"
MAX_BYTES=$((10*1024*1024))   # 单文件 10MB
KEEP=3                        # 保留 3 个轮转文件 (~30MB)
MAX_AGE_DAYS=30
CIRCUIT_THRESHOLD=5           # 熔断: 单会话连续 deny ≥5 次 → 告警文件

init() {
  mkdir -p "$AUDIT_DIR"
  cat << EOF

# ── E-Ⅱ 审计模块:把以下片段合并进 opencode 配置(event hooks 可用时)──
# 位置: ~/.config/opencode/opencode.json 的 "event" 字段
{
  "event": {
    "permission.ask":    [{ "type": "command", "command": "$AUDIT_DIR/hook.sh ask" }],
    "permission.deny":   [{ "type": "command", "command": "$AUDIT_DIR/hook.sh deny" }],
    "permission.allow":  [{ "type": "command", "command": "$AUDIT_DIR/hook.sh allow" }],
    "permission.reject": [{ "type": "command", "command": "$AUDIT_DIR/hook.sh reject" }]
  }
}
# 说明:
#   - 来源天然区分: ask=弹窗给人 / deny=规则拒 / allow=规则放行(含白名单) / reject=人拒绝
#   - hook 不可用的降级: bash 包装器方案见 audit 兜底注释
EOF

  cat > "$AUDIT_DIR/hook.sh" << 'HOOK'
#!/usr/bin/env bash
# 审计 hook: stdin 收 event JSON, 追加一行 JSONL (observe-only, 永不阻断)
set -euo pipefail
DIR="${OPENCODE_AUDIT_DIR:-$(dirname "$(readlink -f "$0")")}"
LOG="$DIR/audit.jsonl"
TYPE="$1"   # ask|deny|allow|reject
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
INPUT=$(cat 2>/dev/null || echo '{}')
# 提取关键载荷(容错:字段缺失记 null)
SESSION=$(echo "$INPUT" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("sessionID","null"))' 2>/dev/null || echo null)
TOOL=$(echo "$INPUT" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("tool","null"))' 2>/dev/null || echo null)
# 脱敏: 命令串里的长 token/类 key 模式打码 (入库前脱敏, fail-safe: python 挂了就整体截断)
CMD=$(echo "$INPUT" | python3 -c '
import json,sys,re
d=json.load(sys.stdin)
c=str(d.get("command") or d.get("input") or "")
c=re.sub(r"(sk-[A-Za-z0-9_-]{8})[A-Za-z0-9_-]+", r"\1***", c)
c=re.sub(r"(Bearer\s+[A-Za-z0-9_.-]{8})[A-Za-z0-9_.-]+", r"\1***", c)
print(c[:500])' 2>/dev/null || echo "[REDACT-FAIL-TRUNCATED]")
printf '{"ts":"%s","src":"%s","session":"%s","tool":"%s","cmd":"%s"}\n' \
  "$TS" "$TYPE" "$SESSION" "$TOOL" "$CMD" >> "$LOG"

# 熔断器: 单会话连续 deny ≥ 阈值 → 写告警文件(fail-loudly, 不阻断进程)
if [ "$TYPE" = "deny" ] && [ "$SESSION" != "null" ]; then
  CONSEC=$(grep "\"session\":\"$SESSION\"" "$LOG" 2>/dev/null | grep -E '"src":"(deny|reject)"' | tail -8 | awk '{print ($0 ~ /"src":"(deny|reject)"/) ? "D" : "X"}' | tr -d '\n' | grep -o "D*$" | tr -d '\n' | wc -c)
  if [ "${CONSEC:-0}" -ge 5 ]; then
    printf '{"ts":"%s","alert":"circuit-breaker","session":"%s","consecutive_denies":%s}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SESSION" "$CONSEC" >> "$DIR/alerts.jsonl"
  fi
fi
HOOK
  chmod +x "$AUDIT_DIR/hook.sh"
  echo "✓ 审计目录: $AUDIT_DIR" >&2
  echo "✓ hook 脚本就位(含密钥脱敏 + 熔断器)" >&2
}

rotate() {
  [ -f "$LOG" ] || { echo "无日志"; exit 0; }
  SIZE=$(stat -c%s "$LOG")
  if [ "$SIZE" -gt "$MAX_BYTES" ]; then
    for i in $(seq $((KEEP-1)) -1 1); do [ -f "$LOG.$i" ] && mv "$LOG.$i" "$LOG.$((i+1))"; done
    mv "$LOG" "$LOG.1"
    echo "✓ 轮转完成 ($((SIZE/1024))KB → $LOG.1)" >&2
  fi
  # 30 天过期(含轮转文件)
  find "$AUDIT_DIR" -name "audit.jsonl*" -mtime +"$MAX_AGE_DAYS" -delete 2>/dev/null || true
  echo "✓ 过期清理(>${MAX_AGE_DAYS}天)完成" >&2
}

case "${1:-init}" in
  init) init ;;
  --rotate|rotate) rotate ;;
  *) echo "用法: $0 [init|--rotate]" >&2; exit 1 ;;
esac
