#!/bin/bash
# ============================================================================
# mem0 agent 侧暴露层单测: install_mem0() 尾部接线(INSTALL_CMODULES=1 路径)
#   ① 首跑(npm/npx 假件在 PATH, mem0 缺席): mcp.mem0 三字段精确落盘 +
#      plugin 数组追加 "mem0-collector"(既有条目保留) + 知会行在场 +
#      npm 实际被调 @mem0/cli 与 mem0-collector 两个包
#   ② 幂等重跑: 文本级 "mem0-collector" 恰现 1 次, mcp.mem0 仍精确, plugin 数组不重复
#   ③ mem0 CLI 已在场: "已安装"分支不再装 CLI, 但接线仍执行(早 return→分支重构守卫)
#   ④ npx 缺失: MCP 合并黄警跳过不阻断, plugin 数组接线仍完成
#   ⑤ MUST NOT 守卫(静态): c-modules 装器仍需 --mem0/--all 显式选(不默认装);
#      setup-opencode.sh INSTALL_CMODULES≠1 仍跳过
#
# 测试口径: 抽函数法(同 test-mineru-wiring.sh)——sed 抽出 install_mem0() 函数体,
#   受控 HOME/SD 下驱动;JSON 合并用真实 python3(测真行为);
#   npm 用记录参数的假件(不触网);npx/mem0 用静默假件(仅 command -v 判定)。
#
# 接线依据(不猜, commit message 同源): opencode.ai/docs/plugins——npm 插件包在
#   opencode.json 的 plugin 数组按包名引用, 启动时 Bun 自动安装;本地文件插件才走
#   plugins/ 目录。mem0-collector@0.7.0 tarball 实测: 无 bin/无自有安装命令,
#   index.js 导出 OpenCode plugin 工厂({event:...}) → npm 插件包 → 数组引用。
#
# 运行: bash tests/test-mem0-wiring.sh  (仓库根或任意目录均可;可重复执行)
# ============================================================================
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/c-modules/c-modules-setup.sh"
MAIN="$ROOT/setup-opencode.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "✗ 未找到 $SCRIPT"
  exit 1
fi

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# 抽函数(列首定义行锚定;函数内 python heredoc 段无列首 "}",sed 区间闭合在函数尾)
sed -n '/^install_mem0() {/,/^}$/p' "$SCRIPT" > "$TMPD/funcs.sh"
if ! grep -q '^install_mem0() {' "$TMPD/funcs.sh"; then
  echo "✗ 红灯: c-modules-setup.sh 中未抽出 install_mem0()(尚未实现?)"
  exit 1
fi

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3——不应出现: $2" ;; *) ok "$3" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3——期望[$2] 实际[$1]"; fi; }

# 受控 PATH: 假 npm 记录参数到 $NPM_LOG(不触网);假 npx/mem0 静默退出
mk_fake() { # mk_fake <dir> <name> <body...>
  mkdir -p "$1"; printf '%s\n' "${@:3}" > "$1/$2"; chmod +x "$1/$2"
}
SYSBIN="$TMPD/sysbin"; mkdir -p "$SYSBIN"
for c in bash python3; do
  _p="$(command -v "$c")" && ln -sf "$_p" "$SYSBIN/$c"
done
mk_fake "$SYSBIN" npm  '#!/bin/sh' 'echo "$@" >> "$NPM_LOG"' 'exit 0'
mk_fake "$SYSBIN" npx  '#!/bin/sh' 'exit 0'
# 变体③: mem0 CLI 已在场
SYSBIN_MEM0="$TMPD/sysbin-mem0"; cp -r "$SYSBIN" "$SYSBIN_MEM0"
mk_fake "$SYSBIN_MEM0" mem0 '#!/bin/sh' 'case "$1" in --version) echo "0.1.0";; esac' 'exit 0'
# 变体④: 无 npx
SYSBIN_NONPX="$TMPD/sysbin-nonpx"; mkdir -p "$SYSBIN_NONPX"
for c in bash python3; do
  _p="$(command -v "$c")" && ln -sf "$_p" "$SYSBIN_NONPX/$c"
done
mk_fake "$SYSBIN_NONPX" npm '#!/bin/sh' 'echo "$@" >> "$NPM_LOG"' 'exit 0'

# run_mem0 <home> <path>: 受控环境 source 函数后调用,回显全部输出
# (SD 推导同 c-modules-setup.sh 顶层: OPENCODE_CONFIG_DIR 优先, 兜底 HOME/.config/opencode)
run_mem0() {
  env HOME="$1" PATH="$2" NPM_LOG="$3" bash -c '
    SD="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
    source "$1"
    install_mem0
  ' _ "$TMPD/funcs.sh" 2>&1
}

# json_check <home> <python表达式(c 为已加载的 opencode.json dict)>: 表达式为真退出 0
json_check() {
  env HOME="$1" python3 -c "
import json, sys
with open('$1/.config/opencode/opencode.json') as f:
    c = json.load(f)
sys.exit(0 if ($2) else 1)
" 2>/dev/null
}

seed_cfg() { # seed_cfg <home>: 预置既有 mcp 条目/顶层键/plugin 数组(模拟主装器产物)
  mkdir -p "$1/.config/opencode"
  cat > "$1/.config/opencode/opencode.json" << 'EOF'
{
  "version": "0.9.9",
  "mcp": {
    "codegraph": {"type": "local", "command": ["/x/codegraph", "serve", "--mcp"], "enabled": true}
  },
  "plugin": ["oh-my-openagent@latest"]
}
EOF
}

echo "== ① 首跑: mem0 MCP 合并 + mem0-collector 数组接线 + npm 双包实调 =="
H1="$TMPD/h1"; seed_cfg "$H1"
OUT1="$(run_mem0 "$H1" "$SYSBIN" "$H1/npm.log")"; RC1=$?
assert_eq "$RC1" "0" "① 首跑退出码 0"
assert_contains "$OUT1" "mem0 CLI 安装完成" "① mem0 CLI 安装分支回显"
assert_contains "$OUT1" "mem0 MCP 已接线" "① MCP 接线成功回显"
assert_contains "$OUT1" "mem0-collector 自动收集已接线" "① collector 接线成功回显"
assert_contains "$OUT1" "MEM0_BASE_URL 自托管" "① 隐私知会行在场"
json_check "$H1" 'c["mcp"]["mem0"] == {"type": "local", "command": ["npx", "-y", "@mem0/mcp-server"], "enabled": True}'
assert_eq "$?" "0" "① mcp.mem0 三字段(type/command/enabled)精确落盘"
json_check "$H1" 'c["plugin"] == ["oh-my-openagent@latest", "mem0-collector"]'
assert_eq "$?" "0" "① plugin 数组幂等追加 mem0-collector 且保留既有条目"
json_check "$H1" 'c["mcp"]["codegraph"]["command"] == ["/x/codegraph", "serve", "--mcp"] and c["version"] == "0.9.9"'
assert_eq "$?" "0" "① 既有 mcp 条目与顶层键保留"
assert_contains "$(cat "$H1/npm.log" 2>/dev/null)" "install -g @mem0/cli" "① npm 实调 @mem0/cli"
assert_contains "$(cat "$H1/npm.log" 2>/dev/null)" "install -g mem0-collector" "① npm 实调 mem0-collector"

echo "== ② 幂等重跑: 不重复写 =="
OUT2="$(run_mem0 "$H1" "$SYSBIN" "$H1/npm.log")"; RC2=$?
assert_eq "$RC2" "0" "② 重跑退出码 0"
CNT="$(grep -c '"mem0-collector"' "$H1/.config/opencode/opencode.json")"
assert_eq "$CNT" "1" "② 文本级 mem0-collector 恰现 1 次(不重复写)"
json_check "$H1" 'c["mcp"]["mem0"] == {"type": "local", "command": ["npx", "-y", "@mem0/mcp-server"], "enabled": True}'
assert_eq "$?" "0" "② 重跑后 mcp.mem0 值仍精确"
json_check "$H1" 'c["plugin"] == ["oh-my-openagent@latest", "mem0-collector"]'
assert_eq "$?" "0" "② plugin 数组无重复追加"
MCNT="$(grep -c '"mem0"' "$H1/.config/opencode/opencode.json")"
assert_eq "$MCNT" "1" "② 文本级 mcp 段 mem0 键恰现 1 次(不重复写)"

echo "== ③ mem0 CLI 已在场: 不重装, 接线仍执行 =="
H3="$TMPD/h3"; seed_cfg "$H3"
OUT3="$(run_mem0 "$H3" "$SYSBIN_MEM0" "$H3/npm.log")"; RC3=$?
assert_eq "$RC3" "0" "③ 已装场景退出码 0"
assert_contains "$OUT3" "mem0 已安装" "③ 已安装分支回显"
assert_not_contains "$OUT3" "mem0 CLI 安装完成" "③ 不重复安装 CLI"
json_check "$H3" 'c["mcp"]["mem0"]["command"] == ["npx", "-y", "@mem0/mcp-server"] and "mem0-collector" in c["plugin"]'
assert_eq "$?" "0" "③ CLI 已在场时接线仍完成(早 return 重构守卫)"

echo "== ④ npx 缺失: MCP 合并黄警跳过不阻断, collector 接线仍完成 =="
H4="$TMPD/h4"; seed_cfg "$H4"
OUT4="$(run_mem0 "$H4" "$SYSBIN_NONPX" "$H4/npm.log")"; RC4=$?
assert_eq "$RC4" "0" "④ 无 npx 退出码 0"
assert_contains "$OUT4" "跳过 mem0 MCP" "④ 跳过 MCP 合并黄警在场"
json_check "$H4" '"mem0" not in c.get("mcp", {})'
assert_eq "$?" "0" "④ mcp 段未写入 mem0(黄警=真跳过)"
json_check "$H4" '"mem0-collector" in c["plugin"]'
assert_eq "$?" "0" "④ plugin 数组接线不受 npx 缺失影响"

echo "== ⑤ MUST NOT 守卫与接线代码(静态断言) =="
SCRIPT_TXT="$(cat "$SCRIPT")"
assert_contains "$SCRIPT_TXT" '--mem0) INSTALL_MEMO=1' "⑤ 装器仍需 --mem0 显式选(不默认装)"
assert_contains "$SCRIPT_TXT" '[ "$INSTALL_MEMO" = "1" ] && install_mem0' "⑤ install_mem0 仅在显式选定时调用"
assert_contains "$SCRIPT_TXT" 'c["mcp"]["mem0"] = {"type": "local", "command": ["npx", "-y", "@mem0/mcp-server"], "enabled": True}' \
  "⑤ MCP 合并代码在场(python3 原子写)"
assert_contains "$SCRIPT_TXT" 'plugins.append("mem0-collector")' "⑤ plugin 数组幂等追加代码在场"
MAIN_TXT="$(cat "$MAIN")"
assert_contains "$MAIN_TXT" 'if [ "${INSTALL_CMODULES:-0}" != "1" ]; then' "⑤ 主装器 INSTALL_CMODULES≠1 仍跳过(不默认装)"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = "0" ] || exit 1
exit 0
