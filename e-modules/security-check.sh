#!/usr/bin/env bash
# opencode-setup · E-Ⅲ/Ⅳ 密钥治理 + AGENT-CARD 生成 + 装后安全自检(三合一)
# 依据: spec E-2 — 全部零/低开销, 装完一次跑
set -euo pipefail
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
PASS=0; WARN=0; FAIL=0

hdr(){ echo -e "\n=== $1 ==="; }
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
warn(){ echo "  ⚠ $1"; WARN=$((WARN+1)); }
bad(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

# ── 1. 密钥治理 ──────────────────────────────
hdr "密钥治理"
# 1a. opencode.json 明文 key 检测(本会话亲历的现行问题)
if [ -f "$CONFIG_DIR/opencode.json" ]; then
  PLAIN=$(python3 -c "
import json,re
s=open('$CONFIG_DIR/opencode.json').read()
hits=re.findall(r'[\"\x27](?:apiKey|api_key|key)[\"\x27]\s*:\s*[\"\x27](?!YOUR_API_KEY|sk-\*|\$\{)[A-Za-z0-9_\-]{12,}[\"\x27]', s)
print(len(hits))" 2>/dev/null || echo 0)
  [ "$PLAIN" -gt 0 ] && bad "opencode.json 含 $PLAIN 处疑似明文 key → 建议迁移 auth.json/环境变量" || ok "opencode.json 无明文 key"
fi
# 1b. auth.json 权限
for f in "$HOME/.local/share/opencode/auth.json"; do
  [ -f "$f" ] && { [ "$(stat -c%a "$f")" -le 600 ] && ok "auth.json 权限 $(stat -c%a "$f")" || { bad "auth.json 权限 $(stat -c%a "$f") (应≤600), 自动修复"; chmod 600 "$f"; }; }
done
# 1c. .gitignore 密钥文件
if [ -f .gitignore ]; then
  grep -qE "^\.env" .gitignore && ok ".gitignore 已含 .env*" || { echo ".env*" >> .gitignore; echo ".env.local" >> .gitignore; ok ".gitignore 补全 .env*"; }
else warn "无 .gitignore(非 git 项目可忽略)"
fi
# 1d. 项目目录 .env 检测
ls .env .env.local 2>/dev/null | head -1 | grep -q . && warn "存在 .env 文件——确认未被 git 追踪: git ls-files --error-unmatch .env" || true

# ── 2. offline / 数据主权提示 ──────────────────
hdr "数据主权"
if command -v python3 >/dev/null; then
  OFFLINE=$(python3 -c "import json;c=json.load(open('$CONFIG_DIR/opencode.json'));print(c.get('offline',False))" 2>/dev/null || echo "err")
  [ "$OFFLINE" = "True" ] && ok "offline 模式已开" || warn "offline 未开(自动更新/分享/代理三路外联)——国内合规场景建议开启"
fi

# ── 3. 供应链(装时一次) ──────────────────────
hdr "供应链"
if [ -f "$CONFIG_DIR/package.json" ]; then
  NPM_OUT=$(cd "$CONFIG_DIR" && timeout 30 npm audit signatures 2>&1 || true)
  if echo "$NPM_OUT" | grep -qi "provenance not found\|no provenance"; then
    N=$(echo "$NPM_OUT" | grep -ci "provenance not found\|no provenance")
    warn "$N 个包缺 provenance(锁版本+人工核对来源)"
  elif echo "$NPM_OUT" | grep -qi "error\|ENOTFOUND"; then
    warn "npm audit 不可用(离线可跳过)"
  else
    ok "npm audit signatures 通过"
  fi
else ok "无全局 package.json(跳过签名审计)"
fi

# ── 4. 注入冒烟(轻量) ────────────────────────
hdr "注入冒烟"
if [ -d "$CONFIG_DIR/skills" ]; then
  SKILL_N=$(ls "$CONFIG_DIR/skills" 2>/dev/null | wc -l)
  # 静态扫: skill 文件里的危险模式(curl|sh / 明文外发 / 硬编码密钥)
  timeout 30 grep -rl --include="SKILL.md" -E "curl[^|]*\|[[:space:]]*(ba)?sh|eval\(atob|sk-[A-Za-z0-9]{20,}" "$CONFIG_DIR/skills" > /tmp/.es_danger 2>/dev/null || true
  DANGER=$(wc -l < /tmp/.es_danger 2>/dev/null || echo 0); rm -f /tmp/.es_danger
  [ "$DANGER" -gt 0 ] && bad "$DANGER 个 skill 文件含危险模式(curl|sh/eval(atob/硬编码key)" || ok "skills 目录($SKILL_N 个)静态扫描无危险模式"
fi

# ── 5. AGENT-CARD 生成 ────────────────────────
hdr "AGENT-CARD 生成"
CARD="$CONFIG_DIR/AGENT-CARD.md"
MCP_LIST=$(python3 -c "import json;c=json.load(open('$CONFIG_DIR/opencode.json'));print(', '.join(c.get('mcp',{}).keys()) or '无')" 2>/dev/null || echo "未知")
SKILL_N=$(ls "$CONFIG_DIR/skills" 2>/dev/null | wc -l)
cat > "$CARD" << EOF2
# AGENT-CARD — 本机 agent 环境披露

> 生成时间: $(date '+%Y-%m-%d %H:%M') · 由 opencode-setup 安全自检生成 · EU AI Act Art.50 透明度义务的自助履行模板

## 能力与工具
- **MCP 服务**: $MCP_LIST
- **已装 skills**: $SKILL_N 个(目录: ~/.config/opencode/skills/)
- **插件**: oh-my-openagent / superpowers(见 opencode.json plugin 数组)

## 自主度
- 权限模式: 规则表 deny-first(bash 高危 deny / 花钱发布 ask / 只读 allow)
- escalation: ask 通道单次放行, 授权不持久
- 熔断: 单会话连续 5 次 deny → 告警(audit alerts.jsonl)

## 审计
- 位置: ~/.local/share/opencode-audit/audit.jsonl(observe-only, 30 天保留)
- 审批来源记录: ask=人批 / allow=规则 / deny=规则 / reject=人拒

## 数据流向
- offline 状态: 见上方自检结果
- 会话数据: 本地存储; 如启用分享功能需另行披露
EOF2
ok "AGENT-CARD.md → $CARD"

# ── 汇总 ─────────────────────────────────────
echo -e "\n═══ 安全自检汇总: $PASS 通过 / $WARN 警告 / $FAIL 失败 ═══"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
