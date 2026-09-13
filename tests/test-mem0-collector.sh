#!/bin/bash
# ============================================================================
# mem0-collector 自研插件单测(c-modules/mem0-collector/plugin.js)
# 覆盖(任务规格四件套):
#   ① 提取逻辑单测: 偏好句/环境事实句 → 提取该句; assistant 句不提取; 无匹配 → [];
#      超限(>3)封顶; 密钥样句不提取(隐私); 插件注入注释块剥除; 短句噪音过滤
#   ② 幂等标记: 同 session 二次 session.idle 不重复收集(标记在场 + mem0 无二调)
#   ③ mem0 add 调用 mock: PATH 假 mem0 记录参数(不触网)——命令构造为 add <句>;
#      mem0 失败 fail-open(不写标记/通知, 不抛)
#   ④ 插件加载+hook 面: node ESM import 工厂 → event / messages.transform;
#      非 session.idle 事件忽略; mem0 CLI 缺席静默休眠
#   ⑤ transform 知会注入: 下次会话首条 user 消息注入(标记注释+条数+管理提示),
#      注入即消费通知文件, 消费后不再注入
#
# 手法: MEM0_COLLECTOR_DATA_DIR 重定向数据位到受控 TMPD; 假 mem0 落日志;
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
DATA="$TMPD/data"; mkdir -p "$DATA"
MEM0_LOG="$TMPD/mem0.log"; : > "$MEM0_LOG"
# 受测模块: 内容同源复制(仅扩展名适配 node ESM 判定)
PUT="$TMPD/plugin-under-test.mjs"; cp "$PLUGIN_SRC" "$PUT"

# 假 mem0: 成功路径记录参数; MEM0_FAKE_RC=1 时不记录(模拟"未存入")
FAKEBIN="$TMPD/bin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/mem0" << 'EOF'
#!/bin/sh
if [ "${MEM0_FAKE_RC:-0}" = "0" ]; then printf '%s\n' "$*" >> "$MEM0_LOG"; fi
exit "${MEM0_FAKE_RC:-0}"
EOF
chmod +x "$FAKEBIN/mem0"

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3——期望[$2] 实际[$1]"; fi; }
file_exists() { [ -e "$1" ] && ok "$2" || bad "$2——文件缺席: $1"; }
file_absent() { [ -e "$1" ] && bad "$2——文件不应在场: $1" || ok "$2"; }

run_node() { # stdin=node 模块体; 统一注入受控 env
  env MEM0_COLLECTOR_DATA_DIR="$DATA" MEM0_LOG="$MEM0_LOG" PLUGIN_FILE="$PUT" \
    EXT_CASES_FILE="$EXT_CASES" MEM0_MSGS_S1="$MSGS1" MEM0_MSGS_S2="$MSGS2" \
    PATH="$FAKEBIN:$PATH" node --input-type=module - 2>"$TMPD/stderr.log"
}

echo "== ① 提取逻辑单测(extractFromMessages 纯函数) =="
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
OUT="$(run_node << 'NODEEOF'
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
if [ "$RC" = "0" ]; then ok "① 8 组提取用例全过(偏好/环境事实/assistant排除/无匹配/封顶/密钥/注释剥除/短句)"; else bad "① 提取用例未全过: $OUT"; fi

echo "== ②③④ 插件加载 + event 收集流 + 幂等 + mem0 mock =="
HOUT="$(run_node << 'NODEEOF'
const mod = await import(process.env.PLUGIN_FILE)
const hooks = await mod.Mem0CollectorPlugin({ client: {
  session: { messages: async () => ({ data: JSON.parse(process.env.MEM0_MSGS) }) },
} })
const shapeOk = typeof hooks.event === 'function' &&
  typeof hooks['experimental.chat.messages.transform'] === 'function'
const idle = (sid) => hooks.event({ event: { type: 'session.idle', properties: { sessionID: sid } } })
process.env.MEM0_MSGS = process.env.MEM0_MSGS_S1
await idle('ses_A')            // 有偏好 → 收集
await idle('ses_A')            // 幂等: 二次 idle 不重复
process.env.MEM0_MSGS = process.env.MEM0_MSGS_S2
await idle('ses_B')            // 无匹配 → 静默
await hooks.event({ event: { type: 'session.updated', properties: { sessionID: 'ses_C' } } })  // 非 idle 忽略
process.env.MEM0_FAKE_RC = '1'
process.env.MEM0_MSGS = process.env.MEM0_MSGS_S1
await idle('ses_D')            // mem0 失败 → fail-open
console.log(JSON.stringify({ shapeOk }))
NODEEOF
)"; HRC=$?
assert_eq "$HRC" "0" "④ 插件 import+工厂+hook 调用全程不抛(fail-open 兜底)"
assert_contains "$HOUT" '"shapeOk":true' "④ hook 面完整(event + messages.transform)"

MARKERS="$DATA/mem0-collector-markers"
file_exists "$MARKERS/ses_A.json" "② 会话标记文件在场(ses_A)"
file_exists "$DATA/mem0-collector-notice.json" "③ 通知文件在场(供下次会话注入)"
ADD_CNT="$(grep -c '^add ' "$MEM0_LOG")"
assert_eq "$ADD_CNT" "1" "②③ mem0 add 恰调 1 次(二次 idle 不重复; 无匹配/失败会话不调)"
assert_contains "$(cat "$MEM0_LOG")" "add 我喜欢简洁的 commit message" "③ 命令构造: mem0 add <提取句>"
file_absent "$MARKERS/ses_B.json" "② 无匹配会话不写标记(后续 idle 可续捕晚出偏好)"
file_absent "$MARKERS/ses_D.json" "③ mem0 失败不写标记(下次 idle 重试)"
file_absent "$MARKERS/ses_C.json" "④ 非 session.idle 事件忽略"

echo "== ⑤ transform 知会注入(下次会话首条 user 消息) =="
TOUT="$(run_node << 'NODEEOF'
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
assert_contains "$TOUT" 'mem0 search' "⑤ 管理提示(mem0 search / mem0 delete)在场"
assert_contains "$TOUT" '"noticeGone":true' "⑤ 通知文件注入后即消费(单次)"
assert_contains "$TOUT" '"noReinject":true' "⑤ 通知消费后不再注入"

echo "== ⑥ mem0 CLI 缺席: 静默休眠不写状态 =="
EMPTYBIN="$TMPD/emptybin"; mkdir -p "$EMPTYBIN"
DORMANT="$TMPD/data-dormant"; mkdir -p "$DORMANT"
NODE_BIN="$(command -v node)"
DOUT="$(env MEM0_COLLECTOR_DATA_DIR="$DORMANT" PLUGIN_FILE="$PUT" PATH="$EMPTYBIN" \
  "$NODE_BIN" --input-type=module - << 'NODEEOF'
const mod = await import(process.env.PLUGIN_FILE)
const hooks = await mod.Mem0CollectorPlugin({ client: {
  session: { messages: async () => ({ data: [
    { info: { role: 'user' }, parts: [{ type: 'text', text: '我喜欢静默休眠测试' }] },
  ] }) },
} })
await hooks.event({ event: { type: 'session.idle', properties: { sessionID: 'ses_E' } } })
console.log('dormant-done')
NODEEOF
)"; DRC=$?
assert_eq "$DRC" "0" "⑥ mem0 缺席 event 不抛"
assert_contains "$DOUT" "dormant-done" "⑥ 静默完成"
file_absent "$DORMANT/mem0-collector-markers/ses_E.json" "⑥ mem0 缺席不写标记(装后自动恢复收集)"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = "0" ] || exit 1
exit 0
