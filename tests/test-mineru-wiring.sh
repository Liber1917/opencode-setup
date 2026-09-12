#!/bin/bash
# ============================================================================
# MinerU agent 侧接线单测: mineru_agent_wiring()(INSTALL_MINERU=1 装完 python 包后调用)
#   ① 首跑: skill 部署(preset-skills/mineru-local → ~/.config/opencode/skills/)
#      + Flash MCP 幂等合并(opencode.json mcp.mineru-flash 三字段精确落盘,
#      既有 mcp 条目与顶层键保留) + 隐私知会行在场 + uv 缺失黄警带 curl 指引不阻断
#   ② 幂等重跑: skill "已存在"不重复部署;文本级 '"mineru-flash"' 恰现 1 次(不重复写)
#   ③ 无 python3: 跳过 MCP 合并黄警不炸,skill 部署仍完成
#   ④ MUST NOT 守卫与接线调用点(静态): 步骤12 preset-skills glob 未选
#      INSTALL_MINERU=1 时跳过 mineru-local;INSTALL_MINERU 分支内调用接线函数;
#      收尾清单含 MinerU 接线动态复核行
#   ⑤ skill 内容与实测 CLI 对齐: name/mineru -p 用法/-b pipeline/-b vlm-engine;
#      不出现不存在的 '-b vlm' 取值(backend_options.py 实测: pipeline|vlm-engine|hybrid-engine)
#
# 测试口径: 抽函数法(同 test-upgrade.sh)——sed 抽出 mineru_agent_wiring 函数体,
#   受控 HOME/CONFIG_DIR/SCRIPT_DIR 下驱动;JSON 合并用真实 python3(测真行为);
#   uv 缺失场景用受控 PATH(sysbin 仅 bash/mkdir/cp/python3,无 uvx)。
#
# 运行: bash tests/test-mineru-wiring.sh  (仓库根或任意目录均可;可重复执行)
# ============================================================================
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/setup-opencode.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "✗ 未找到 $SCRIPT"
  exit 1
fi

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# 抽函数(列首定义行锚定;函数内 python 段全为列首行且无列首 "}",sed 区间闭合在函数尾)
sed -n '/^mineru_agent_wiring() {/,/^}$/p' "$SCRIPT" > "$TMPD/funcs.sh"
if ! grep -q '^mineru_agent_wiring() {' "$TMPD/funcs.sh"; then
  echo "✗ 红灯: setup-opencode.sh 中未抽出 mineru_agent_wiring()(尚未实现?)"
  exit 1
fi
if [ ! -f "$ROOT/preset-skills/mineru-local/SKILL.md" ]; then
  echo "✗ 红灯: 未找到 preset-skills/mineru-local/SKILL.md(尚未实现?)"
  exit 1
fi

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3——不应出现: $2" ;; *) ok "$3" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3——期望[$2] 实际[$1]"; fi; }

# 受控 PATH: sysbin(bash/mkdir/cp/python3,无 uvx → uv 缺失分支可测)
SYSBIN="$TMPD/sysbin"; mkdir -p "$SYSBIN"
for c in bash mkdir cp python3; do
  _p="$(command -v "$c")" && ln -sf "$_p" "$SYSBIN/$c"
done
SYSBIN_NOPY="$TMPD/sysbin-nopy"; mkdir -p "$SYSBIN_NOPY"
for c in bash mkdir cp; do
  _p="$(command -v "$c")" && ln -sf "$_p" "$SYSBIN_NOPY/$c"
done

# run_wiring <home> <path>: 受控环境 source 函数后调用,回显全部输出
run_wiring() {
  env HOME="$1" PATH="$2" SCRIPT_DIR="$ROOT" GREEN="" YELLOW="" BLUE="" NC="" bash -c '
    CONFIG_DIR="$HOME/.config/opencode"
    source "$1"
    mineru_agent_wiring
  ' _ "$TMPD/funcs.sh" 2>&1
}

# json_check <home> <python表达式(c 为已加载的 opencode.json dict)>: 表达式为真退出 0
json_check() {
  env HOME="$1" python3 -c "
import json, sys
with open('$1/.config/opencode/opencode.json') as f:
    c = json.load(f)
sys.exit(0 if ($2) else 1)
"
}

echo "== ① 首跑: skill 部署 + Flash MCP 合并(uv 缺失黄警不阻断) =="
H1="$TMPD/h1"; mkdir -p "$H1/.config/opencode"
cat > "$H1/.config/opencode/opencode.json" << 'EOF'
{
  "version": "0.9.9",
  "mcp": {
    "codegraph": {"type": "local", "command": ["/x/codegraph", "serve", "--mcp"], "enabled": true}
  }
}
EOF
OUT1="$(run_wiring "$H1" "$SYSBIN")"; RC1=$?
assert_eq "$RC1" "0" "① 首跑退出码 0(uv 缺失不阻断)"
assert_contains "$OUT1" "preset-skill 已部署: mineru-local" "① skill 部署成功回显"
[ -f "$H1/.config/opencode/skills/mineru-local/SKILL.md" ]
assert_eq "$?" "0" "① SKILL.md 落在 ~/.config/opencode/skills/mineru-local/"
assert_contains "$OUT1" "Flash MCP(mineru-flash)已合并" "① MCP 合并成功回显"
assert_contains "$OUT1" "云端处理" "① 隐私知会行在场"
assert_contains "$OUT1" "astral.sh/uv" "① uv 缺失黄警带 curl 指引"
json_check "$H1" 'c["mcp"]["mineru-flash"] == {"type": "local", "command": ["uvx", "mineru-open-mcp"], "enabled": True}'
assert_eq "$?" "0" "① mcp.mineru-flash 三字段(type/command/enabled)精确落盘"
json_check "$H1" 'c["mcp"]["codegraph"]["command"] == ["/x/codegraph", "serve", "--mcp"] and c["version"] == "0.9.9"'
assert_eq "$?" "0" "① 既有 mcp 条目与顶层键保留"

echo "== ② 幂等重跑: 不重复部署/不重复写 =="
OUT2="$(run_wiring "$H1" "$SYSBIN")"; RC2=$?
assert_eq "$RC2" "0" "② 重跑退出码 0"
assert_contains "$OUT2" "已存在" "② skill 已存在回显(不重复部署)"
json_check "$H1" 'c["mcp"]["mineru-flash"] == {"type": "local", "command": ["uvx", "mineru-open-mcp"], "enabled": True}'
assert_eq "$?" "0" "② 重跑后 mineru-flash 值仍精确"
CNT="$(grep -c '"mineru-flash"' "$H1/.config/opencode/opencode.json")"
assert_eq "$CNT" "1" "② 文本级 mineru-flash 键恰现 1 次(不重复写)"

echo "== ③ 无 python3: 跳过 MCP 合并不炸,skill 部署仍完成 =="
H3="$TMPD/h3"; mkdir -p "$H3/.config/opencode"
printf '{\n  "version": "0.9.9"\n}\n' > "$H3/.config/opencode/opencode.json"
OUT3="$(run_wiring "$H3" "$SYSBIN_NOPY")"; RC3=$?
assert_eq "$RC3" "0" "③ 无 python3 退出码 0"
assert_contains "$OUT3" "跳过 Flash MCP 合并" "③ 跳过 MCP 合并黄警在场"
[ -f "$H3/.config/opencode/skills/mineru-local/SKILL.md" ]
assert_eq "$?" "0" "③ skill 部署不受 python3 缺失影响"

echo "== ④ MUST NOT 守卫与接线调用点(静态断言) =="
SCRIPT_TXT="$(cat "$SCRIPT")"
assert_contains "$SCRIPT_TXT" '[ "$name" = "mineru-local" ] && [ "${INSTALL_MINERU:-0}" != "1" ]' \
  "④ 步骤12 glob 守卫: 未选 INSTALL_MINERU=1 不部署 mineru-local"
CALLS="$(grep -c '^  mineru_agent_wiring$' "$SCRIPT")"
if [ "${CALLS:-0}" -ge 1 ] 2>/dev/null; then ok "④ INSTALL_MINERU=1 分支内调用 mineru_agent_wiring"; else bad "④ 未检出调用点(mineru_agent_wiring)"; fi
assert_contains "$SCRIPT_TXT" "MinerU 接线" "④ 收尾清单含 MinerU 接线动态复核行"

echo "== ⑤ skill 内容与实测 CLI 对齐 =="
SKILL_TXT="$(cat "$ROOT/preset-skills/mineru-local/SKILL.md")"
assert_contains "$SKILL_TXT" "name: mineru-local" "⑤ frontmatter name: mineru-local"
assert_contains "$SKILL_TXT" "mineru -p" "⑤ 核心用法 mineru -p 在场"
assert_contains "$SKILL_TXT" "-b pipeline" "⑤ 后端 -b pipeline 在场(CPU/零幻觉)"
assert_contains "$SKILL_TXT" "-b vlm-engine" "⑤ 后端 -b vlm-engine 在场(高精度;实测取值)"
assert_not_contains "$SKILL_TXT" "\`-b vlm\`" "⑤ 不使用不存在的 '-b vlm' 取值"
assert_contains "$SKILL_TXT" "Flash MCP" "⑤ Flash MCP 交叉引用在场(双路暴露)"
DEPLOYED="$(cat "$H1/.config/opencode/skills/mineru-local/SKILL.md")"
assert_contains "$DEPLOYED" "mineru -p" "⑤ 部署副本与仓库源一致(含核心用法)"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = "0" ] || exit 1
exit 0
