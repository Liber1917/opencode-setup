#!/bin/bash
# ============================================================================
# interactive_component_menu() 单测(菜单逻辑三态 + 三道门)
#
# 方法: 用 sed 从 setup-opencode.sh 抽出函数体(sed 区间锚定列首定义行),
#       写入临时文件后在 bash 子进程里 source,管道喂 stdin 驱动,
#       断言 stdout 回显与 INSTALL_*/SUPERPOWERS_ROUTER 变量副作用。
#       不执行脚本主体,无任何安装动作。
#
# 三态: 正常输入("1 3") / 非法输入(重输后合法、混合非法、连续 3 次超限) /
#       空输入(直接回车=全不装)
# 三门: 任一选装环境变量已设 → 跳过; SETUP_INTERACTIVE=0 → 一票否决;
#       无 TTY 且未 SETUP_FORCE_MENU → 跳过(非交互零变化)
#
# 运行: bash tests/test-interactive-menu.sh  (仓库根或任意目录均可)
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

# 抽函数: 定义行与闭括号均在列首,函数体内无列首 "}"
sed -n '/^interactive_component_menu() {/,/^}$/p' "$SCRIPT" > "$TMPD/menu-func.sh"
if ! grep -q '^interactive_component_menu() {' "$TMPD/menu-func.sh"; then
  echo "✗ 红灯: setup-opencode.sh 中未抽出 interactive_component_menu() 函数(尚未实现?)"
  exit 1
fi

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3——不应出现: $2" ;; *) ok "$3" ;; esac; }

# menu_run <printf格式串stdin> [K=V ...]
# 子进程末行输出 FLAGS:<GSD>|<DCP>|<MINERU>|<SPROUTER>|<CMODULES>(未设=0)
menu_run() {
  local feed="$1"; shift || true
  printf '%b' "$feed" | env "$@" bash -c '
    source "$1"
    interactive_component_menu
    echo "FLAGS:${INSTALL_GSD:-0}|${INSTALL_DCP:-0}|${INSTALL_MINERU:-0}|${SUPERPOWERS_ROUTER:-0}|${INSTALL_CMODULES:-0}"
  ' _ "$TMPD/menu-func.sh"
}

echo "== 三态①: 正常输入 =="
out="$(menu_run '1 3\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "FLAGS:1|0|1|0|0" "『1 3』→ GSD+MinerU 选中"
assert_contains "$out" "将安装: GSD, MinerU" "选中回显"
assert_not_contains "$out" "AGPL 确认将在安装时进行" "未选 DCP → 无 AGPL 提示"

out="$(menu_run '2 4\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "FLAGS:0|1|0|1|0" "『2 4』→ DCP+superpowers 路由选中"
assert_contains "$out" "AGPL 确认将在安装时进行" "选 DCP → AGPL 确认门将提示"

out="$(menu_run '4\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "FLAGS:0|0|0|1|0" "『4』→ 仅 superpowers 路由"

out="$(menu_run '5\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "FLAGS:0|0|0|0|1" "『5』→ 记忆/自进化选中"
assert_contains "$out" "将安装: 记忆/自进化" "第 5 项选中回显"
assert_contains "$out" "mem0 偏好记忆+SkillOpt 夜间提炼" "第 5 项菜单文案"

out="$(menu_run '1 5\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "FLAGS:1|0|0|0|1" "『1 5』→ GSD+记忆/自进化"

echo "== 三态②: 非法输入 =="
out="$(menu_run 'abc\n1\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "无效" "非法输入提示重输"
assert_contains "$out" "FLAGS:1|0|0|0|0" "重输后合法选择生效"

out="$(menu_run 'x\ny\nz\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "3 次" "连续 3 次非法提示超限"
assert_contains "$out" "FLAGS:0|0|0|0|0" "超限 → 按全不装"

out="$(menu_run '1 x\n\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "无效" "混合输入(1 x)判非法"
assert_contains "$out" "FLAGS:0|0|0|0|0" "非法轮次不留残留选择(1 不生效)"

out="$(menu_run '6\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "无效" "『6』超出合法集判非法"
assert_contains "$out" "1-5" "合法集提示为 1-5"
assert_contains "$out" "FLAGS:0|0|0|0|0" "『6』后 EOF → 按全不装"

out="$(menu_run '5 x\n\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "无效" "混合输入(5 x)判非法"
assert_contains "$out" "FLAGS:0|0|0|0|0" "非法轮次不留残留选择(5 不生效)"

echo "== 三态③: 空输入 =="
out="$(menu_run '\n' SETUP_FORCE_MENU=1)"
assert_contains "$out" "FLAGS:0|0|0|0|0" "直接回车 → 全不装"
assert_contains "$out" "全不装" "全不装回显"

out="$(menu_run '' SETUP_FORCE_MENU=1)"
assert_contains "$out" "FLAGS:0|0|0|0|0" "stdin 立即 EOF → 默认全不装,不挂死"

echo "== 门①: 任一选装环境变量已设 → 菜单跳过(兼容铁律) =="
out="$(menu_run '1 3\n' SETUP_FORCE_MENU=1 INSTALL_GSD=1)"
assert_contains "$out" "FLAGS:1|0|0|0|0" "INSTALL_GSD=1 显式 → 语义不被菜单改写"
assert_not_contains "$out" "可选组件" "无菜单横幅"

out="$(menu_run '5\n' SETUP_FORCE_MENU=1 INSTALL_CMODULES=1)"
assert_contains "$out" "FLAGS:0|0|0|0|1" "INSTALL_CMODULES=1 显式 → 语义不被菜单改写"
assert_not_contains "$out" "可选组件" "无菜单横幅(INSTALL_CMODULES 也在跳过门串中)"

out="$(menu_run '4\n' SETUP_FORCE_MENU=1 CONFIRM_AGPL=1)"
assert_contains "$out" "FLAGS:0|0|0|0|0" "CONFIRM_AGPL=1 也视为已给路径"
assert_not_contains "$out" "可选组件" "无菜单横幅"

echo "== 门②: SETUP_INTERACTIVE=0 → 一票否决(优先于 FORCE) =="
out="$(menu_run '1 3\n' SETUP_FORCE_MENU=1 SETUP_INTERACTIVE=0)"
assert_contains "$out" "FLAGS:0|0|0|0|0" "强制关菜单后输入被忽略"
assert_not_contains "$out" "可选组件" "无菜单横幅"

echo "== 门③: 无 TTY 且未 FORCE → 跳过(非交互零变化) =="
out="$(menu_run '1 3\n')"
assert_contains "$out" "FLAGS:0|0|0|0|0" "管道输入被忽略"
assert_not_contains "$out" "可选组件" "无菜单横幅"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = "0" ] || exit 1
exit 0
