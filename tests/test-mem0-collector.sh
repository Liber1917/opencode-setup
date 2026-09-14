#!/bin/bash
# ============================================================================
# mem0-collector 本地记忆改造单测(c-modules/mem0-collector/plugin.js)
# 存储改造(2026-09): mem0 三件套(CLI/MCP/collector 云端链)退役,插件改为写本地
#   docs/memory/memory-log.jsonl(murillovp/persistent-memory 格式,MIT),
#   并承接 facts.md 50 行 fact-archive 轮换(照 murillovp 设计)。
# 覆盖:
#   ① 提取逻辑单测(不变): 偏好句/环境事实句 → 提取该句; assistant 句不提取;
#      无匹配 → []; 超限(>3)封顶; 密钥样句不提取(隐私); 注入注释块剥除; 短句噪音过滤
#   ② 幂等标记: 同 session 二次 session.idle 不重复收集(标记在场 + jsonl 无二写)
#   ③ jsonl 格式断言: 每行合法 JSON 且含 date/type/summary 三键;偏好写入
#      type:"user-preference";date 为 ISO 日期(YYYY-MM-DD);追加不破坏既有行
#   ④ 插件加载+hook 面: node ESM import 工厂 → event / messages.transform;
#      非 session.idle 事件忽略;全程 fail-open 不抛
#   ⑤ transform 知会注入: 下次会话首条 user 消息注入(标记注释+条数+本地 grep
#      管理提示), 注入即消费通知文件, 消费后不再注入
#   ⑥ facts.md 50 行轮换: 造 55 行 → 最旧事实搬入 jsonl(type:"fact-archive")
#      → facts.md 恢复 50 行以内; 头部/注释行不搬
#   ⑦ 尾换行修复: jsonl 失尾换行时追加自动修复(murillovp 实测坑),全文件仍合法
#
# 手法: MEM0_COLLECTOR_DATA_DIR 重定向标记/通知,MEM0_COLLECTOR_MEMORY_DIR
#       重定向记忆目录(facts.md+memory-log.jsonl)——双目录均受控,不触真机;
#       插件源复制为 .mjs 后 import(仓库无 package.json:type=module,
#       .js 直 import 会被 node 判 CJS——matcher.mjs 先例同由)。
# 运行: bash tests/test-mem0-collector.sh  (可重复执行)
# ============================================================================
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_SRC="$ROOT/c-modules/mem0-collector/plugin.js"

if [ ! -f "$PLUGIN_SRC" ]; then
  echo "✗ 红灯: 未找到 $PLUGIN_SRC(插件尚未实现)"
  exit 1
fi

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
DATA="$TMPD/data"; mkdir -p "$DATA"          # 标记/通知位
MEMD="$TMPD/memdir"; mkdir -p "$MEMD"        # 记忆位(facts.md + memory-log.jsonl)
# 受测模块: 内容同源复制(仅扩展名适配 node ESM 判定)
PUT="$TMPD/plugin-under-test.mjs"; cp "$PLUGIN_SRC" "$PUT"

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3——期望[$2] 实际[$1]"; fi; }
file_exists() { [ -e "$1" ] && ok "$2" || bad "$2——文件缺席: $1"; }
file_absent() { [ -e "$1" ] && bad "$2——文件不应在场: $1" || ok "$2"; }

run_node() { # stdin=node 模块体; 统一注入受控 env
  env MEM0_COLLECTOR_DATA_DIR="$DATA" MEM0_COLLECTOR_MEMORY_DIR="$MEMD" \
    EXT_CASES_FILE="$EXT_CASES" MEM0_MSGS_S1="$MSGS1" MEM0_MSGS_S2="$MSGS2" \
    node --input-type=module - 2>"$TMPD/stderr.log"
}

echo "== ① 提取逻辑单测(extractFromMessages 纯函数,逻辑不变) =="
EXT_CASES="$TMPD/ext-cases.json"
MSGS1='[{"info":{"role":"user"},"parts":[{"type":"text","text":"我喜欢简洁的 commit message。顺便看下这个函数。"}]},{"info":{"role":"assistant"},"parts":[{"type":"text","text":"好的,已了解。"}]}]'
MSGS2='[{"info":{"role":"user"},"parts":[{"type":"text","text":"帮我看看这个报错。TypeError: undefined"}]},{"info":{"role":"user"},"parts":[{"type":"text","text":"再检查一下网络"}]}]'
python3 - "$EXT_CASES" << 'PYEOF'
import json, sys
cases = [
  ["偏好句提取(仅该句)", [
    {"info":{"role":"user"},"parts":[{"type":"text","text":"我喜欢简洁的 commit message。顺便看下这个函数。"}]},
    {"info":{"role":"assistant"},"parts":[{"type":"text","text":"好的,已了解。"}]},
  ], ["我喜欢简洁的 commit message"]],
  ["assistant 偏好句不提取", [
    {"info":{"role":"assistant"},"parts":[{"type":"text","text":"记住:测试要全覆盖"}]},
  ], []],
  ["环境事实句提取", [
    {"info":{"role":"user"},"parts":[{"type":"text","text":"我们用的是 bun 不是 npm"}]},
  ], ["我们用的是 bun 不是 npm"]],
  ["无匹配静默空", [
    {"info":{"role":"user"},"parts":[{"type":"text","text":"帮我看看这个报错。TypeError: undefined"}]},
    {"info":{"role":"user"},"parts":[{"type":"text","text":"再检查一下网络"}]},
  ], []],
  ["超限封顶3条", [
    {"info":{"role":"user"},"parts":[{"type":"text","text":"我喜欢用bun打包一。我喜欢用pnpm装二。我喜欢用tab缩进三。我喜欢dark主题四。我喜欢中文命名五。"}]},
  ], ["我喜欢用bun打包一", "我喜欢用pnpm装二", "我喜欢用tab缩进三"]],
  ["密钥样句不提取(隐私)", [
    {"info":{"role":"user"},"parts":[{"type":"text","text":"记住 sk-abcdefgh12345678 是我的key"}]},
  ], []],
  ["注入注释块剥除", [
    {"info":{"role":"user"},"parts":[{"type":"text","text":"<!--mem0-collector:notice-->\n<!--other-->\n以后总是先跑测试再提交"}]},
  ], ["以后总是先跑测试再提交"]],
  ["短句噪音过滤(<6字)", [
    {"info":{"role":"user"},"parts":[{"type":"text","text":"记住啊"}]},
  ], []],
]
json.dump(cases, open(sys.argv[1], "w"), ensure_ascii=False)
PYEOF
OUT="$(env MEM0_COLLECTOR_DATA_DIR="$DATA" MEM0_COLLECTOR_MEMORY_DIR="$MEMD" \
  EXT_CASES_FILE="$EXT_CASES" PLUGIN_FILE="$PUT" \
  node --input-type=module - 2>"$TMPD/stderr.log" << 'NODEEOF'
import fs from 'node:fs'
const { extractFromMessages } = await import(process.env.PLUGIN_FILE)
const cases = JSON.parse(fs.readFileSync(process.env.EXT_CASES_FILE, 'utf8'))
for (const [name, msgs, expect] of cases) {
  const got = extractFromMessages(msgs)
  if (JSON.stringify(got) !== JSON.stringify(expect)) {
    console.log(`FAIL ${name}: got ${JSON.stringify(got)} expect ${JSON.stringify(expect)}`)
    process.exitCode = 1
  }
}
console.log('extract-cases-done')
NODEEOF
)"; RC=$?
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'extract-cases-done' && ! printf '%s' "$OUT" | grep -q '^FAIL'; then
  ok "① 8 组提取用例全过(偏好/环境事实/assistant排除/无匹配/封顶/密钥/注释剥除/短句)"
else
  bad "① 提取用例未全过: $OUT"
fi

echo "== ②③④ 插件加载 + event 收集流 + 幂等 + jsonl 格式 =="
HOUT="$(env MEM0_COLLECTOR_DATA_DIR="$DATA" MEM0_COLLECTOR_MEMORY_DIR="$MEMD" \
  PLUGIN_FILE="$PUT" MEM0_MSGS_S1="$MSGS1" MEM0_MSGS_S2="$MSGS2" \
  node --input-type=module - 2>"$TMPD/stderr.log" << 'NODEEOF'
import fs from 'node:fs'
const mod = await import(process.env.PLUGIN_FILE)
const hooks = await mod.Mem0CollectorPlugin({ client: {
  session: { messages: async () => ({ data: JSON.parse(process.env.MEM0_MSGS) }) },
} })
const shapeOk = typeof hooks.event === 'function' &&
  typeof hooks['experimental.chat.messages.transform'] === 'function'
const idle = (sid) => hooks.event({ event: { type: 'session.idle', properties: { sessionID: sid } } })
process.env.MEM0_MSGS = process.env.MEM0_MSGS_S1
await idle('ses_A')            // 有偏好 → 收集进 jsonl
await idle('ses_A')            // 幂等: 二次 idle 不重复
process.env.MEM0_MSGS = process.env.MEM0_MSGS_S2
await idle('ses_B')            // 无匹配 → 静默
await hooks.event({ event: { type: 'session.updated', properties: { sessionID: 'ses_C' } } })  // 非 idle 忽略
console.log(JSON.stringify({ shapeOk }))
NODEEOF
)"; HRC=$?
assert_eq "$HRC" "0" "④ 插件 import+工厂+hook 调用全程不抛(fail-open 兜底)"
assert_contains "$HOUT" '"shapeOk":true' "④ hook 面完整(event + messages.transform)"

MARKERS="$DATA/mem0-collector-markers"
file_exists "$MARKERS/ses_A.json" "② 会话标记文件在场(ses_A)"
file_exists "$DATA/mem0-collector-notice.json" "③ 通知文件在场(供下次会话注入)"
file_absent "$MARKERS/ses_B.json" "② 无匹配会话不写标记(后续 idle 可续捕晚出偏好)"
file_absent "$MARKERS/ses_C.json" "④ 非 session.idle 事件忽略"
JSONL="$MEMD/memory-log.jsonl"
file_exists "$JSONL" "③ memory-log.jsonl 已创建(本地落盘,零外发)"

# jsonl 格式断言: 每行合法 JSON + 三键齐全 + 类型/日期/摘要内容
FMT="$(python3 - "$JSONL" << 'PYEOF'
import json, sys, re
lines = [l for l in open(sys.argv[1], encoding='utf-8').read().splitlines() if l.strip()]
errs = []
prefs = []
for i, l in enumerate(lines):
    try:
        o = json.loads(l)
    except Exception as e:
        errs.append(f"line{i+1} 非法 JSON: {e}"); continue
    if not ({'date','type','summary'} <= set(o.keys())):
        errs.append(f"line{i+1} 缺键: {sorted(o.keys())}")
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', str(o.get('date',''))):
        errs.append(f"line{i+1} date 非 ISO 日期: {o.get('date')!r}")
    if o.get('type') == 'user-preference':
        prefs.append(o.get('summary',''))
print('FMT_ERR:' + ';'.join(errs) if errs else 'FMT_OK')
print('PREFS:' + json.dumps(prefs, ensure_ascii=False))
PYEOF
)"
assert_contains "$FMT" "FMT_OK" "③ jsonl 每行合法 JSON 且 date/type/summary 三键齐全(ISO 日期)"
PREF_CNT="$(printf '%s' "$FMT" | python3 -c "import json,sys; print(len(json.loads([l for l in sys.stdin if l.startswith('PREFS:')][0][6:])))")"
assert_eq "$PREF_CNT" "1" "②③ 偏好恰写 1 条(二次 idle 不重复; 无匹配会话不写)"
assert_contains "$FMT" "我喜欢简洁的 commit message" "③ 偏好摘要原文入库(type:user-preference)"

echo "== ⑤ transform 知会注入(下次会话首条 user 消息) =="
TOUT="$(env MEM0_COLLECTOR_DATA_DIR="$DATA" MEM0_COLLECTOR_MEMORY_DIR="$MEMD" \
  PLUGIN_FILE="$PUT" node --input-type=module - 2>"$TMPD/stderr.log" << 'NODEEOF'
import fs from 'node:fs'
const mod = await import(process.env.PLUGIN_FILE)
const hooks = await mod.Mem0CollectorPlugin({ client: { session: { messages: async () => ({ data: [] }) } } })
const out1 = { messages: [{ info: { role: 'user' }, parts: [{ type: 'text', text: '新会话第一问' }] }] }
await hooks['experimental.chat.messages.transform']({}, out1)
const injected = out1.messages[0].parts[0].text
const noticeGone = !fs.existsSync(process.env.MEM0_COLLECTOR_DATA_DIR + '/mem0-collector-notice.json')
const out2 = { messages: [{ info: { role: 'user' }, parts: [{ type: 'text', text: '第二问' }] }] }
await hooks['experimental.chat.messages.transform']({}, out2)
const noReinject = out2.messages[0].parts.length === 1
console.log(JSON.stringify({ injected, noticeGone, noReinject }))
NODEEOF
)"; TRC=$?
assert_eq "$TRC" "0" "⑤ transform 调用不抛"
assert_contains "$TOUT" 'mem0-collector:notice' "⑤ 注入块带幂等标记注释"
assert_contains "$TOUT" '收集了 1 条记忆' "⑤ 知会文案(条数)在场"
assert_contains "$TOUT" 'memory-log.jsonl' "⑤ 管理提示(本地 grep memory-log.jsonl)在场"
assert_contains "$TOUT" '"noticeGone":true' "⑤ 通知文件注入后即消费(单次)"
assert_contains "$TOUT" '"noReinject":true' "⑤ 通知消费后不再注入"

echo "== ⑥ facts.md 50 行轮换(55 行 → 最旧搬入 jsonl → 恢复 50 以内) =="
# 造 55 行 facts.md: 3 行头部(标题+注释) + 52 行事实
python3 - "$MEMD/facts.md" << 'PYEOF'
import sys
head = "# Facts\n<!-- Durable truths about this project. Keep under ~50 lines.\n     Add new facts here, archive oldest to memory-log.jsonl when it grows. -->\n"
facts = "".join(f"- 事实编号{i:02d}内容\n" for i in range(52))
open(sys.argv[1], "w", encoding="utf-8").write(head + facts)
PYEOF
ROT="$(env MEM0_COLLECTOR_DATA_DIR="$DATA" MEM0_COLLECTOR_MEMORY_DIR="$MEMD" \
  PLUGIN_FILE="$PUT" node --input-type=module - 2>"$TMPD/stderr.log" << 'NODEEOF'
import fs from 'node:fs'
const mod = await import(process.env.PLUGIN_FILE)
const hooks = await mod.Mem0CollectorPlugin({ client: {
  session: { messages: async () => ({ data: [
    { info: { role: 'user' }, parts: [{ type: 'text', text: '帮我看看普通问题,无偏好句' }] },
  ] }) },
} })
await hooks.event({ event: { type: 'session.idle', properties: { sessionID: 'ses_ROT' } } })  // 无偏好也触发轮换(房务)
const facts = fs.readFileSync(process.env.MEM0_COLLECTOR_MEMORY_DIR + '/facts.md', 'utf8')
const lines = facts.split('\n').length - (facts.endsWith('\n') ? 1 : 0)
const log = fs.readFileSync(process.env.MEM0_COLLECTOR_MEMORY_DIR + '/memory-log.jsonl', 'utf8')
const archives = log.split('\n').filter(Boolean).map(l => JSON.parse(l)).filter(o => o.type === 'fact-archive')
console.log(JSON.stringify({ lines, archives: archives.map(a => a.summary) }))
NODEEOF
)"; RRC=$?
assert_eq "$RRC" "0" "⑥ 轮换路径不抛(fail-open)"
FACT_LINES="$(printf '%s' "$ROT" | python3 -c "import json,sys; print(json.load(sys.stdin)['lines'])")"
if [ "$FACT_LINES" -le 50 ] 2>/dev/null; then ok "⑥ facts.md 恢复 50 行以内(实际 ${FACT_LINES} 行)"; else bad "⑥ facts.md 仍 ${FACT_LINES} 行,未轮换"; fi
ARCH_CNT="$(printf '%s' "$ROT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['archives']))")"
assert_eq "$ARCH_CNT" "5" "⑥ 恰 5 条最旧事实搬入 jsonl(55+3头部-50→头3+事实47,搬52-47)"
assert_contains "$ROT" '事实编号00' "⑥ 最旧(编号00)被搬入"
assert_not_dup="$(printf '%s' "$ROT" | python3 -c "import json,sys; a=[x for x in json.load(sys.stdin)['archives']]; print('DUP' if len(a)!=len(set(a)) else 'OK')")"
assert_eq "$assert_not_dup" "OK" "⑥ 轮换条目无重复"
FACT_REMAIN="$(cat "$MEMD/facts.md")"
case "$FACT_REMAIN" in *事实编号00*|*事实编号04*) bad "⑥ 已归档条目仍留在 facts.md";; *) ok "⑥ 已归档最旧条目已从 facts.md 删除";; esac
case "$FACT_REMAIN" in *事实编号51*) ok "⑥ 最新事实(编号51)保留在 facts.md";; *) bad "⑥ 最新事实不应被轮换";; esac
case "$FACT_REMAIN" in *"# Facts"*) ok "⑥ 标题行保留";; *) bad "⑥ 标题行被误搬";; esac
# 轮换写入的 fact-archive 行也须合法 JSON(复用格式断言)
FMT2="$(python3 - "$JSONL" << 'PYEOF'
import json, sys
errs = []
for i, l in enumerate([x for x in open(sys.argv[1], encoding='utf-8').read().splitlines() if x.strip()]):
    try: json.loads(l)
    except Exception as e: errs.append(str(i+1))
print('OK' if not errs else 'BAD:'+','.join(errs))
PYEOF
)"
assert_eq "$FMT2" "OK" "⑥ 轮换后 jsonl 全文件仍逐行合法"

echo "== ⑦ 尾换行修复: jsonl 失尾换行 → 追加自动修复(murillovp 实测坑) =="
python3 -c "
import json, sys
p = '$JSONL'
s = open(p, encoding='utf-8').read().rstrip('\n')  # 剥掉尾换行制造坑
open(p, 'w', encoding='utf-8').write(s)
"
NL="$(env MEM0_COLLECTOR_DATA_DIR="$DATA" MEM0_COLLECTOR_MEMORY_DIR="$MEMD" \
  PLUGIN_FILE="$PUT" node --input-type=module - 2>"$TMPD/stderr.log" << 'NODEEOF'
import fs from 'node:fs'
const mod = await import(process.env.PLUGIN_FILE)
const hooks = await mod.Mem0CollectorPlugin({ client: {
  session: { messages: async () => ({ data: [
    { info: { role: 'user' }, parts: [{ type: 'text', text: '我喜欢尾换行修复验证' }] },
  ] }) },
} })
await hooks.event({ event: { type: 'session.idle', properties: { sessionID: 'ses_NL' } } })
console.log('nl-done')
NODEEOF
)"; NLRC=$?
assert_eq "$NLRC" "0" "⑦ 失尾换行场景追加不抛"
assert_contains "$NL" "nl-done" "⑦ 追加完成"
TAILFIX="$(python3 - "$JSONL" << 'PYEOF'
import json, sys
lines = [l for l in open(sys.argv[1], encoding='utf-8').read().splitlines() if l.strip()]
bad = []
for i, l in enumerate(lines):
    try: json.loads(l)
    except Exception: bad.append(i+1)
print('OK' if not bad else 'BAD:'+','.join(map(str,bad)))
PYEOF
)"
assert_eq "$TAILFIX" "OK" "⑦ 追加后全文件逐行合法(无粘连腐蚀)"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = "0" ] || exit 1
exit 0
