#!/usr/bin/env bash
# opencode-setup · E-Ⅵ 实时心跳(只读审计流角标 CLI)
# 用途: opencode 会话中随时 `heartbeat` 一行看清节奏——工具调用/事件速率/最近活动/子代理状态
# 数据源: 本地审计流 audit.jsonl 四通道(ask/allow/deny/reject,字段 ts/src/session/tool/cmd)
#   注: 审计流无 token 字段,不造假数(在场守则);token 口径需读 opencode.db,超出零依赖边界故不做
# 调研结论(2026-09-12): @opencode-ai/plugin v1.18.x 存在 TUI 插件面(TuiPluginModule/ui.Slot/
#   home_bottom 槽位,opencode 1.18.30 二进制在场),但需 Solid JSX 模块且本仓规则下无本地加载
#   路径(plugins/*.ts=server 面先例,plugin 数组只认 npm 包),无头环境不可实证渲染 → 按预案降级
#   为查询命令(零依赖,数据全部本地;不注入每轮消息,零常驻税)
# 口径: "工具调用" = 窗口内同 (tool,cmd) 相邻 2 秒内事件去重后计数(ask+allow 成对只计一次)
#   "最近会话" = 窗口内最新事件所属 session(其余 session 事件不计入该会话调用数)
set -euo pipefail
AUDIT_DIR="${OPENCODE_AUDIT_DIR:-$HOME/.local/share/opencode-audit}"
LOG="$AUDIT_DIR/audit.jsonl"
TAIL_N="${HEARTBEAT_TAIL:-50}"

case "${1:-}" in
  -h|--help) echo "用法: heartbeat [窗口行数](默认 $TAIL_N;读 $LOG 尾部算一行指标)"; exit 0 ;;
  ''|*[!0-9]*) ;;
  *) TAIL_N="$1" ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "✗ heartbeat 需要 python3" >&2; exit 1; }
[ -f "$LOG" ] || { echo "♥ 审计流无数据($LOG 不存在;步骤 12 audit-init 初始化后生效)"; exit 0; }

python3 - "$LOG" "$TAIL_N" << 'PYHB'
import sys, json, datetime
from collections import deque
log, tail_n = sys.argv[1], max(int(sys.argv[2]), 2)

def parse_ts(s):
    try: return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
    except ValueError:
        try: return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
        except ValueError: return None

evs = []
with open(log, encoding="utf-8", errors="replace") as f:
    for line in deque(f, maxlen=tail_n):
        try: e = json.loads(line)
        except Exception: continue
        if not isinstance(e, dict): continue
        t = parse_ts(str(e.get("ts") or ""))
        if t is None: continue
        evs.append((t, e))
if not evs:
    print(f"♥ 审计流无事件(窗口 {tail_n} 行无合法 ts;数据源: {log})"); sys.exit(0)

evs.sort(key=lambda x: x[0])
sid = next((e.get("session") for _, e in reversed(evs)
            if isinstance(e.get("session"), str) and e["session"] not in ("", "null")), None)
cur = [(t, e) for t, e in evs if sid is None or e.get("session") == sid]

calls, last_t, last_key = 0, None, None
for t, e in cur:
    tool = e.get("tool")
    if not isinstance(tool, str) or tool == "null": continue
    key = (tool, e.get("cmd"))
    if key == last_key and t - last_t <= 2:
        last_t = t; continue
    calls += 1; last_t, last_key = t, key

sub = sum(1 for _, e in cur if e.get("tool") in ("task", "spawn"))
span = evs[-1][0] - evs[0][0]
rate = (len(evs) - 1) / (span / 60.0) if span > 0 else float(len(evs))
age = (datetime.datetime.now(datetime.timezone.utc).timestamp() - evs[-1][0])

def fmt_age(s):
    if s < 0: return "刚刚"
    if s < 90: return f"{int(s)} 秒前"
    if s < 5400: return f"{int(s // 60)} 分钟前"
    if s < 129600: return f"{int(s // 3600)} 小时前"
    return f"{int(s // 86400)} 天前"

sid_txt = f"sid:{sid[:8]}" if sid else "无会话标记"
print(f"♥ 最近会话({sid_txt}): {calls} 工具调用 | 近 {len(evs)} 事件 {rate:.1f}/min | "
      f"最近事件: {fmt_age(age)} | 子代理: {'活跃' if sub else '无'}")
PYHB
