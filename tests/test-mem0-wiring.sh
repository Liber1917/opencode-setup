#!/bin/bash
# ============================================================================
# 本地记忆接线单测: c-modules-setup.sh install_local_memory()(mem0 三件套退役后)
#   ① 首跑: docs/memory/ 六件初始文件部署到位 + 知会行在场 + 不装 mem0 CLI
#      (npm 全程不被调) + opencode.json 不写 mcp.mem0
#   ② 幂等重跑: cp -n 不覆盖用户已改文件(facts.md 手工追加保留)
#   ③ mem0 时代残留清理: 预置 mcp.mem0 条目 + plugin 数组 npm mem0-collector +
#      旧版 collector 插件(execFileSync('mem0') 签名)→ 运行后全部移除;
#      新版 collector 文件(无该签名)不误伤
#   ④ MUST NOT 守卫(静态): 装器无 npm install -g @mem0/cli、无 @mem0/mcp-server
#      接线、无 mem0 CLI 探测分支; --mem0 兼容 flag 仍在; setup 主装器
#      INSTALL_CMODULES≠1 仍跳过
#   ⑤ 仓库资产: AGENTS.md 记忆契约(murillovp 6 行 + 反记忆清单 + fact-archive
#      轮换规则)在场; docs/memory/ 六件在场; templates/memory 六件在场;
#      仓库 memory-log.jsonl 逐行合法 JSON
#   ⑥ setup-opencode.sh 接线(静态): detect_components 探测 local_memory
#      (docs/memory/facts.md 文件在场); 菜单 _mk local_memory; 收尾汇总本地记忆;
#      升级还原含 UC_local_memory
#
# 测试口径: 抽函数法(同 test-mineru-wiring.sh)——sed 抽出 install_local_memory()
#   函数体,受控 HOME/SD/TDIR 下驱动;JSON 清理用真实 python3(测真行为)。
#
# 运行: bash tests/test-mem0-wiring.sh  (仓库根或任意目录均可;可重复执行)
# ============================================================================
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/c-modules/c-modules-setup.sh"
MAIN="$ROOT/setup-opencode.sh"
AGENTS="$ROOT/AGENTS.md"

if [ ! -f "$SCRIPT" ]; then
  echo "✗ 未找到 $SCRIPT"
  exit 1
fi

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# 抽函数(列首定义行锚定;函数内 python heredoc 段无列首 "}",sed 区间闭合在函数尾)
sed -n '/^install_local_memory() {/,/^}$/p' "$SCRIPT" > "$TMPD/funcs.sh"
if ! grep -q '^install_local_memory() {' "$TMPD/funcs.sh"; then
  echo "✗ 红灯: c-modules-setup.sh 中未抽出 install_local_memory()(尚未实现?)"
  exit 1
fi

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3——不应出现: $2" ;; *) ok "$3" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3——期望[$2] 实际[$1]"; fi; }
file_exists() { [ -e "$1" ] && ok "$2" || bad "$2——文件缺席: $1"; }
file_absent() { [ -e "$1" ] && bad "$2——文件不应在场: $1" || ok "$2"; }

# run_mem <home>: 受控 SD/TDIR 下 source 函数后调用,回显全部输出
# (TDIR 指向仓库真模板——部署内容一致性可断言;SD 推导同装器顶层约定)
run_mem() {
  env HOME="$1" SD="${OPENCODE_CONFIG_DIR:-$1/.config/opencode}" \
    TDIR="$ROOT/c-modules/templates" \
    bash -c 'source "$1"; install_local_memory' _ "$TMPD/funcs.sh" 2>&1
}

# json_check <home> <python表达式(c 为已加载的 opencode.json dict,文件缺席视作 {})>: 表达式为真退出 0
json_check() {
  env HOME="$1" python3 -c "
import json, sys
try:
    with open('$1/.config/opencode/opencode.json') as f:
        c = json.load(f)
except FileNotFoundError:
    c = {}
sys.exit(0 if ($2) else 1)
" 2>/dev/null
}

echo "== ① 首跑: docs/memory/ 初始文件部署 + 知会 + 零 mem0 安装 =="
H1="$TMPD/h1"; mkdir -p "$H1/.config/opencode"
OUT1="$(run_mem "$H1")"; RC1=$?
assert_eq "$RC1" "0" "① 首跑退出码 0"
assert_contains "$OUT1" "本地记忆: docs/memory/(facts.md 热读 + memory-log.jsonl 冷追加,零外发)" "① 知会行(本地方案)在场"
assert_contains "$OUT1" "6/6 在场" "① 六件初始文件在场复核回显"
assert_not_contains "$OUT1" "mem0 CLI" "① 不再安装 mem0 CLI"
for f in facts.md memory-log.jsonl user_profile.md feedback_style.md project_overview.md reference_links.md; do
  file_exists "$H1/.config/opencode/docs/memory/$f" "① 部署 $f"
done
assert_not_contains "$OUT1" "mem0 MCP 已接线" "① 不再接线 mem0 MCP"
json_check "$H1" '"mem0" not in c.get("mcp", {})'
assert_eq "$?" "0" "① opencode.json 未写 mcp.mem0(即使文件不存在也不创建)"
if cmp -s "$H1/.config/opencode/docs/memory/facts.md" "$ROOT/c-modules/templates/memory/facts.md"; then
  ok "① facts.md 部署内容与模板逐字节一致"
else
  bad "① facts.md 部署内容与模板漂移"
fi

echo "== ② 幂等重跑: cp -n 不覆盖用户已改文件 =="
printf -- '- 我自己追加的用户偏好\n' >> "$H1/.config/opencode/docs/memory/facts.md"
OUT2="$(run_mem "$H1")"; RC2=$?
assert_eq "$RC2" "0" "② 重跑退出码 0"
assert_contains "$(cat "$H1/.config/opencode/docs/memory/facts.md")" "我自己追加的用户偏好" "② 用户手改 facts.md 不被覆盖"
assert_contains "$OUT2" "6/6 在场" "② 重跑仍六件在场(cp -n 幂等)"

echo "== ③ mem0 时代残留清理(升级路径) =="
H3="$TMPD/h3"; mkdir -p "$H3/.config/opencode/plugins"
cat > "$H3/.config/opencode/opencode.json" << 'EOF'
{
  "mcp": {
    "codegraph": {"type": "local", "command": ["/x/codegraph", "serve", "--mcp"], "enabled": true},
    "mem0": {"type": "local", "command": ["npx", "-y", "@mem0/mcp-server"], "enabled": true}
  },
  "plugin": ["oh-my-openagent@latest", "mem0-collector"]
}
EOF
printf 'execFileSync(%s, [add])\n' "'mem0'" > "$H3/.config/opencode/plugins/mem0-collector.ts"
printf '// new local-jsonl collector, no mem0 call\n' > "$H3/.config/opencode/plugins/other-plugin.ts"
OUT3="$(run_mem "$H3")"; RC3=$?
assert_eq "$RC3" "0" "③ 残留清理场景退出码 0"
assert_contains "$OUT3" "mem0 MCP 残留已清理" "③ MCP 清理知会在场"
json_check "$H3" 'c["mcp"]["codegraph"]["command"] == ["/x/codegraph", "serve", "--mcp"]'
assert_eq "$?" "0" "③ 既有 mcp 条目(codegraph)保留"
json_check "$H3" '"mem0" not in c.get("mcp", {})'
assert_eq "$?" "0" "③ mcp.mem0 已移除"
json_check "$H3" 'c["plugin"] == ["oh-my-openagent@latest"]'
assert_eq "$?" "0" "③ plugin 数组 npm mem0-collector 已移除(既有条目保留)"
file_absent "$H3/.config/opencode/plugins/mem0-collector.ts" "③ 旧版 collector(mem0 add 签名)已删除"
file_exists "$H3/.config/opencode/plugins/other-plugin.ts" "③ 无关插件不误伤"
file_exists "$H3/.config/opencode/docs/memory/facts.md" "③ 残留清理不阻断初始文件部署"

echo "== ④ MUST NOT 守卫与兼容面(静态断言) =="
SCRIPT_TXT="$(cat "$SCRIPT")"
assert_not_contains "$SCRIPT_TXT" 'npm install -g @mem0/cli' "④ 不再 npm 装 mem0 CLI"
assert_not_contains "$SCRIPT_TXT" '@mem0/mcp-server' "④ 不再接线 mem0 MCP server(退役)"
assert_not_contains "$SCRIPT_TXT" 'mem0 init' "④ 不再引导 mem0 init 云端注册"
assert_contains "$SCRIPT_TXT" '--mem0|--memory) INSTALL_MEMORY=1' "④ --mem0 兼容 flag 保留(实装本地记忆)"
assert_contains "$SCRIPT_TXT" '[ "$INSTALL_MEMORY" = "1" ] && install_local_memory' "④ install_local_memory 仅在显式选定时调用"
assert_contains "$SCRIPT_TXT" "LuciferForge/claude-code-memory" "④ 粘合来源标注在场(LuciferForge)"
assert_contains "$SCRIPT_TXT" "murillovp/persistent-memory" "④ 粘合来源标注在场(murillovp)"
MAIN_TXT="$(cat "$MAIN")"
assert_contains "$MAIN_TXT" 'if [ "${INSTALL_CMODULES:-0}" != "1" ]; then' "④ 主装器 INSTALL_CMODULES≠1 仍跳过(不默认装)"

echo "== ⑤ 仓库资产: AGENTS.md 契约 + docs/memory/ 初始文件 =="
AGENTS_TXT="$(cat "$AGENTS")"
assert_contains "$AGENTS_TXT" 'This repo keeps persistent context in `docs/memory/`.' "⑤ 契约引导行(murillovp 原文)在场"
assert_contains "$AGENTS_TXT" 'read `docs/memory/facts.md` (kept under ~50 lines)' "⑤ facts.md 热读契约在场"
assert_contains "$AGENTS_TXT" 'append to `docs/memory/memory-log.jsonl`' "⑤ jsonl 冷追加契约在场"
assert_contains "$AGENTS_TXT" 'grep -i "<term>" docs/memory/memory-log.jsonl' "⑤ grep 检索契约在场"
assert_contains "$AGENTS_TXT" '不要存进记忆的东西(代码能 tell 你的都不存)' "⑤ 反记忆清单(LuciferForge 改写)在场"
assert_contains "$AGENTS_TXT" '只存: 用户偏好、纠错记录(错→改→因)、决策及原因、外部资源指针' "⑤ 只存四类清单在场"
assert_contains "$AGENTS_TXT" 'facts.md 上限 50 行,超限把最旧的搬入 memory-log.jsonl(type:"fact-archive")' "⑤ fact-archive 轮换规则在场"
assert_contains "$AGENTS_TXT" 'murillovp/persistent-memory' "⑤ 契约来源标注在场"
for f in facts.md memory-log.jsonl user_profile.md feedback_style.md project_overview.md reference_links.md; do
  file_exists "$ROOT/docs/memory/$f" "⑤ 仓库 docs/memory/$f"
  file_exists "$ROOT/c-modules/templates/memory/$f" "⑤ 部署模板 templates/memory/$f"
done
head -1 "$ROOT/docs/memory/user_profile.md" | grep -q '^---' \
  && ok "⑤ 主题模板 frontmatter 保留" \
  || bad "⑤ 主题模板 frontmatter 丢失"
REPO_JSONL_OK="$(python3 - "$ROOT/docs/memory/memory-log.jsonl" << 'PYEOF'
import json, sys
try:
    lines = [l for l in open(sys.argv[1], encoding='utf-8').read().splitlines() if l.strip()]
    for l in lines: json.loads(l)
    print('OK' if lines else 'EMPTY')
except Exception as e:
    print('BAD:' + str(e))
PYEOF
)"
assert_eq "$REPO_JSONL_OK" "OK" "⑤ 仓库 memory-log.jsonl 逐行合法 JSON"

echo "== ⑥ setup-opencode.sh 接线(静态断言) =="
assert_contains "$MAIN_TXT" 'local_memory\": $present' "⑥ 状态清单探测 local_memory"
assert_contains "$MAIN_TXT" '[ -f "$CONFIG_DIR/docs/memory/facts.md" ]; then present=true' "⑥ 探测判据 = docs/memory/facts.md 文件在场"
assert_not_contains "$MAIN_TXT" 'for k in opencode bun node rtk codegraph webmap opstate mem0 skillopt-sleep mineru' "⑥ 探测循环不再含 mem0/skillopt-sleep"
assert_contains "$MAIN_TXT" '_mk local_memory' "⑥ 菜单预选键改 local_memory"
assert_contains "$MAIN_TXT" 'EXTRAS_SUM:+$EXTRAS_SUM }本地记忆' "⑥ 收尾汇总按 docs/memory 在场报本地记忆"
assert_contains "$MAIN_TXT" 'UC_local_memory:-false' "⑥ 升级还原含 UC_local_memory(新状态清单)"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = "0" ] || exit 1
exit 0
