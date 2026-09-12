#!/bin/bash
# ============================================================================
# heartbeat.sh 单测(实时心跳: 只读审计流角标 CLI)
#
# 方法: mktemp 造假 audit.jsonl 夹具(python3 生成相对当前时间的确定性事件),
#       对各场景跑 heartbeat 断言输出关键词;覆盖: 会话归属/成对去重/速率/
#       最近事件/子代理标记/多会话排除/坏行容忍/空数据/窗口参数。
#
# 口径(与 e-modules/heartbeat.sh 头注释一致):
#   工具调用 = 窗口内同 (tool,cmd) 相邻 2 秒内去重(ask+allow 只计一次)
#   最近会话 = 窗口内最新事件所属 session;其余 session 事件不计入调用数
#
# 运行: bash tests/test-heartbeat.sh  (仓库根或任意目录均可)
# ============================================================================
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HB="$ROOT/e-modules/heartbeat.sh"

if [ ! -f "$HB" ]; then
  echo "✗ 未找到 $HB"
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "✗ 测试需要 python3"; exit 1; }

TMPD="$(mktemp -d /tmp/heartbeat-test.XXXXXX)"
trap 'rm -rf "$TMPD"' EXIT

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3——期望[$2] 实际[$1]"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3——不应出现: $2" ;; *) ok "$3" ;; esac; }

# 夹具A: 主会话 ses_main 为最新事件归属;含 ask+allow 成对/跨会话/坏行
#   预期: 调用=5(bash 去重 1 + edit×2 + task + grep;ses_other 不计),窗口 7 事件,
#         span=270→30=240s → (7-1)/(240/60)=1.5/min,子代理=活跃(task 事件)
mk_fixture_a() {
  python3 - "$TMPD/a/audit.jsonl" <<'PY'
import json, sys, datetime
now = datetime.datetime.now(datetime.timezone.utc)
def ev(sec, src, ses, tool, cmd):
    ts = (now - datetime.timedelta(seconds=sec)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return json.dumps({"ts": ts, "src": src, "session": ses, "tool": tool, "cmd": cmd}, ensure_ascii=False)
rows = [
    ev(270, "ask",   "ses_main", "bash", "ls -la"),
    ev(268, "allow", "ses_main", "bash", "ls -la"),   # 同(tool,cmd) 2s 内 → 去重
    ev(180, "allow", "ses_main", "edit", "a.ts"),
    "garbage not json",
    '{"parse":"fail"}',                                # 坏行置中: ⑤ 窗口参数取尾 3 行均合法
    ev(120, "allow", "ses_main", "edit", "b.ts"),
    ev(90,  "allow", "ses_main", "task", "explore 调研"),
    ev(60,  "allow", "ses_other", "bash", "whoami"),  # 其他会话: 不计入主会话调用
    ev(30,  "allow", "ses_main", "grep", "foo"),      # 最新事件 → 最近会话=ses_main
]
open(sys.argv[1], "w").write("\n".join(rows) + "\n")
PY
}

echo "== ⓪ 语法与用法 =="
bash -n "$HB"
assert_eq "$?" "0" "bash -n 语法通过"
bash "$HB" -h >"$TMPD/help.txt" 2>&1 </dev/null
assert_eq "$?" "0" "-h 退出 0"
assert_contains "$(cat "$TMPD/help.txt")" "用法" "-h 列出用法"

echo "== ① 夹具A: 会话归属/成对去重/速率/子代理 =="
mkdir -p "$TMPD/a"; mk_fixture_a
OUT_A="$(OPENCODE_AUDIT_DIR="$TMPD/a" bash "$HB")"
RC_A=$?
assert_eq "$RC_A" "0" "正常数据退出 0"
assert_eq "$(printf '%s\n' "$OUT_A" | wc -l)" "1" "输出恰好一行"
assert_contains "$OUT_A" "sid:ses_main" "报出最近会话(最新事件归属)"
assert_contains "$OUT_A" "5 工具调用" "调用数=5(ask+allow 去重,他会有话不计)"
assert_not_contains "$OUT_A" "6 工具调用" "未去重/误计他会话则会出现 6"
assert_contains "$OUT_A" "近 7 事件" "窗口事件数=7(坏行跳过)"
assert_contains "$OUT_A" "1.5/min" "速率=1.5/min(span 240s,7 事件)"
assert_contains "$OUT_A" "子代理: 活跃" "task 事件 → 子代理活跃"
if printf '%s' "$OUT_A" | grep -qE '[0-9]+ 秒前'; then ok "最近事件报相对秒数"; else bad "最近事件未报相对秒数——实际[$OUT_A]"; fi

echo "== ② 夹具B: 无 task 事件 → 子代理无 =="
mkdir -p "$TMPD/b"
python3 - "$TMPD/b/audit.jsonl" <<'PY'
import json, sys, datetime
now = datetime.datetime.now(datetime.timezone.utc)
def ev(sec, src, ses, tool, cmd):
    ts = (now - datetime.timedelta(seconds=sec)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return json.dumps({"ts": ts, "src": src, "session": ses, "tool": tool, "cmd": cmd}, ensure_ascii=False)
open(sys.argv[1], "w").write(ev(20, "allow", "ses_solo", "bash", "pwd") + "\n")
PY
OUT_B="$(OPENCODE_AUDIT_DIR="$TMPD/b" bash "$HB")"
assert_contains "$OUT_B" "子代理: 无" "无 task 事件 → 子代理无"
assert_contains "$OUT_B" "1 工具调用" "单事件调用数=1"

echo "== ③ 同秒爆发: span=0 不除零 =="
mkdir -p "$TMPD/c"
python3 - "$TMPD/c/audit.jsonl" <<'PY'
import json, sys, datetime
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
rows = [json.dumps({"ts": ts, "src": "allow", "session": "ses_burst", "tool": t, "cmd": "c"}) for t in ("bash", "edit", "read")]
open(sys.argv[1], "w").write("\n".join(rows) + "\n")
PY
OUT_C="$(OPENCODE_AUDIT_DIR="$TMPD/c" bash "$HB")"
assert_eq "$?" "0" "同秒爆发退出 0"
assert_contains "$OUT_C" "3.0/min" "span=0 速率=事件数(下界口径)"

echo "== ④ 空数据路径 =="
mkdir -p "$TMPD/empty"; : > "$TMPD/empty/audit.jsonl"
OUT_E="$(OPENCODE_AUDIT_DIR="$TMPD/empty" bash "$HB")"
assert_eq "$?" "0" "空文件退出 0"
assert_contains "$OUT_E" "审计流无事件" "空文件报无事件"
OUT_M="$(OPENCODE_AUDIT_DIR="$TMPD/no-such-dir" bash "$HB")"
assert_eq "$?" "0" "目录不存在退出 0"
assert_contains "$OUT_M" "审计流无数据" "目录不存在报无数据"

echo "== ⑤ 窗口行数参数 =="
OUT_W="$(OPENCODE_AUDIT_DIR="$TMPD/a" bash "$HB" 3)"
assert_contains "$OUT_W" "近 3 事件" "位置参数收紧窗口到 3"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = "0" ] || exit 1
exit 0
