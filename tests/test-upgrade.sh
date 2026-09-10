#!/bin/bash
# ============================================================================
# 动态升级 P1 单测: --upgrade 入口段(upgrade_restore_context)
#   1. 状态清单在场 → UC_* 还原 + INSTALL_*/CONFIRM_AGPL 环境变量导出
#      (核心: 修裸重跑误剥——dcp:true 必须带回 INSTALL_DCP=1 CONFIRM_AGPL=1)
#   2. 无状态清单(v1.0 前安装) → 考古模式,现场探测重建 UC_*
#
# 测试口径(诚实记录): 全脚本 --upgrade 会落入 12 步安装主流程(装包/写配置,
#   真机副作用过重),故按允许的"入口段单元测试抽函数法"——sed 抽出
#   upgrade_restore_context 函数体,受控 HOME/PATH 下驱动,断言:
#     - 状态路径: UC_* 逐项还原;INSTALL_DCP/CONFIRM_AGPL/INSTALL_MINERU 导出;
#       gsd:false → INSTALL_GSD 不导出(剥除分支不触发的入口层事实)
#     - .setup-state.json.prev 备份落盘
#     - 考古路径: 无状态文件 → 日志含"考古模式",UC_ 来自 detect_components 实测
#
# 运行: bash tests/test-upgrade.sh  (仓库根或任意目录均可;可重复执行)
# ============================================================================
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/setup-opencode.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "✗ 未找到 $SCRIPT"
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "✗ 测试需 python3(状态清单本身依赖它)"; exit 1; }

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# 抽函数(列首定义行锚定;upgrade_restore_context 内 python -c 代码段全为列首
# import/赋值/for/print 行,无列首 "}",保证 sed 区间闭合在函数尾)
sed -n '/^upgrade_restore_context() {/,/^}$/p;/^detect_components() {/,/^}$/p' \
  "$SCRIPT" > "$TMPD/funcs.sh"
MISSING=0
for f in upgrade_restore_context detect_components; do
  grep -q "^$f() {" "$TMPD/funcs.sh" || { echo "✗ 红灯: setup-opencode.sh 中未抽出 $f()(尚未实现?)"; MISSING=1; }
done
[ "$MISSING" = 0 ] || exit 1

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3——不应出现: $2" ;; *) ok "$3" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3——期望[$2] 实际[$1]"; fi; }

# 受控 PATH: fakebin(伪造在场命令 + crontab 桩)+ sysbin(仅函数自身所需)
SYSBIN="$TMPD/sysbin"; mkdir -p "$SYSBIN"
for c in bash ls grep python3 git cp; do
  _p="$(command -v "$c")" && ln -sf "$_p" "$SYSBIN/$c"
done
SYSBIN_NOPY="$TMPD/sysbin-nopy"; mkdir -p "$SYSBIN_NOPY"
for c in bash ls grep git cp; do
  _p="$(command -v "$c")" && ln -sf "$_p" "$SYSBIN_NOPY/$c"
done
BIN="$TMPD/bin"; mkdir -p "$BIN"
cat > "$BIN/crontab" << 'EOF'
#!/bin/bash
# 测试桩: 受控回放 crontab -l(不碰真机);FAKE_CRONTAB_TEXT 非空=有表,空=无表
[ -n "${FAKE_CRONTAB_TEXT:-}" ] && { printf '%s\n' "$FAKE_CRONTAB_TEXT"; exit 0; }
exit 1
EOF
chmod +x "$BIN/crontab"

# run_upgrade <home> <path> <snippet文件>: 受控环境 source 函数后执行用例;
# 断言用回显法——还原结果(环境变量)在子进程内打回 stdout,父进程断言
run_upgrade() {
  env HOME="$1" PATH="$2" SETUP_VERSION="v1.0" SCRIPT_DIR="$TMPD" \
    GREEN="" YELLOW="" NC="" bash -c '
      CONFIG_DIR="$HOME/.config/opencode"
      source "$1"
      upgrade_restore_context
      source "$2"
    ' _ "$TMPD/funcs.sh" "$3" 2>&1
}

# 回显还原后的选装开关(未导出=unset;[] 定界防空串与未设置混淆)
cat > "$TMPD/snip-report.sh" << 'EOF'
echo "INSTALL_DCP=${INSTALL_DCP:-unset} CONFIRM_AGPL=${CONFIRM_AGPL:-unset}"
echo "INSTALL_MINERU=${INSTALL_MINERU:-unset} INSTALL_GSD=${INSTALL_GSD:-unset}"
echo "SUPERPOWERS_ROUTER=${SUPERPOWERS_ROUTER:-unset} INSTALL_CMODULES=${INSTALL_CMODULES:-unset}"
echo "UC_MODEL=[${UC_MODEL-unset}]"
EOF

echo "== A. 状态清单还原(手造 dcp:true mineru:true gsd:false) =="
HOME_S="$TMPD/homeS"; CFG_S="$HOME_S/.config/opencode"; mkdir -p "$CFG_S"
cat > "$CFG_S/.setup-state.json" << 'EOF'
{
  "script_version": "v1.0",
  "installed_at": "2026-09-01T00:00:00+08:00",
  "components": {
    "opencode": true, "bun": true, "node": true, "rtk": true,
    "codegraph": true, "webmap": true, "opstate": true, "mem0": false,
    "skillopt-sleep": false, "mineru": true, "dcp": true, "gsd": false,
    "superpowers_router": false, "cmolecules_cron": false
  },
  "flags": { "model": "zhipuai-coding-plan/glm-5.3", "permission_mode": "standard" }
}
EOF
cp "$CFG_S/.setup-state.json" "$TMPD/state-original.json"

out="$(run_upgrade "$HOME_S" "$BIN:$SYSBIN" "$TMPD/snip-report.sh")"; rc=$?
assert_eq "$rc" "0" "入口段退出码 0"
assert_contains "$out" "状态清单已读: v1.0 → v1.0" "打版本对账行(旧版本 → 本版)"
assert_contains "$out" "INSTALL_DCP=1 CONFIRM_AGPL=1" "dcp:true → INSTALL_DCP=1 CONFIRM_AGPL=1(修裸重跑误剥的根)"
assert_contains "$out" "INSTALL_MINERU=1" "mineru:true → INSTALL_MINERU=1"
assert_contains "$out" "INSTALL_GSD=unset" "gsd:false → INSTALL_GSD 不导出(剥除分支入口层不触达)"
assert_contains "$out" "SUPERPOWERS_ROUTER=unset" "superpowers_router:false → 不导出"
assert_contains "$out" "INSTALL_CMODULES=unset" "mem0/skillopt 全 false → INSTALL_CMODULES 不导出"
assert_contains "$out" "UC_MODEL=[zhipuai-coding-plan/glm-5.3]" "flags.model 还原到 UC_MODEL"
assert_not_contains "$out" "考古模式" "状态清单在场不走考古"
assert_not_contains "$out" "not found" "连字符键(skillopt-sleep)不产生 command not found 噪声"
[ -f "$CFG_S/.setup-state.json.prev" ] && ok ".setup-state.json.prev 升级前备份已落盘" || bad ".prev 未落盘"
if diff -q "$TMPD/state-original.json" "$CFG_S/.setup-state.json.prev" >/dev/null 2>&1; then
  ok ".prev 内容与升级前清单一致"
else
  bad ".prev 与升级前清单不一致"
fi
if diff -q "$TMPD/state-original.json" "$CFG_S/.setup-state.json" >/dev/null 2>&1; then
  ok "入口段只读不写主清单(重写发生在收尾 write_state_file)"
else
  bad "入口段不应改写主清单"
fi

echo "== B. 状态还原全真变体(gsd/router/mem0 全 true) =="
HOME_T="$TMPD/homeT"; CFG_T="$HOME_T/.config/opencode"; mkdir -p "$CFG_T"
python3 - "$CFG_T/.setup-state.json" << 'PYEOF'
import json, sys
comps = {k: False for k in ["opencode","bun","node","rtk","codegraph","webmap",
  "opstate","skillopt-sleep","mineru","dcp","cmolecules_cron"]}
comps.update({"mem0": True, "gsd": True, "superpowers_router": True})
state = {"script_version": "v1.0", "installed_at": "2026-09-01T00:00:00+08:00",
  "components": comps, "flags": {"model": "", "permission_mode": "unknown"}}
json.dump(state, open(sys.argv[1], "w"), indent=2, ensure_ascii=False)
PYEOF
out="$(run_upgrade "$HOME_T" "$BIN:$SYSBIN" "$TMPD/snip-report.sh")"
assert_contains "$out" "INSTALL_GSD=1" "gsd:true → INSTALL_GSD=1(已装接线一根不剥)"
assert_contains "$out" "SUPERPOWERS_ROUTER=1" "superpowers_router:true → SUPERPOWERS_ROUTER=1"
assert_contains "$out" "INSTALL_CMODULES=1" "mem0:true → INSTALL_CMODULES=1"
assert_contains "$out" "INSTALL_DCP=unset" "dcp:false → INSTALL_DCP 不导出"
assert_contains "$out" "UC_MODEL=[]" "flags.model 空串 → UC_MODEL 空值(eval 不炸)"

echo "== C. 考古模式(无状态清单,v1.0 前安装) =="
HOME_A="$TMPD/homeA"; CFG_A="$HOME_A/.config/opencode"; mkdir -p "$CFG_A"
# 夹具在场事实: opencode/bun/mem0 命令在场 + dcp 已注册 + 无 gsd/router/cron
for t in opencode bun mem0; do : > "$BIN/$t"; chmod +x "$BIN/$t"; done
cat > "$CFG_A/opencode.json" << 'EOF'
{
  "model": "zhipuai-coding-plan/glm-5.3",
  "plugin": ["oh-my-openagent@latest", "opencode-dcp@latest"]
}
EOF
out="$(run_upgrade "$HOME_A" "$BIN:$SYSBIN" "$TMPD/snip-report.sh")"; rc=$?
assert_eq "$rc" "0" "考古路径退出码 0"
assert_contains "$out" "考古模式" "无状态清单打考古模式"
assert_contains "$out" "INSTALL_DCP=1 CONFIRM_AGPL=1" "考古: opencode.json 实注册 dcp → INSTALL_DCP=1 CONFIRM_AGPL=1"
assert_contains "$out" "INSTALL_CMODULES=1" "考古: mem0 命令在场 → INSTALL_CMODULES=1"
assert_contains "$out" "INSTALL_GSD=unset" "考古: 无 gsd 命令 → INSTALL_GSD 不导出"
assert_contains "$out" "INSTALL_MINERU=unset" "考古: 无 mineru 命令 → INSTALL_MINERU 不导出"
assert_not_contains "$out" "not found" "考古解析无 command not found 噪声(连字符键过滤)"
[ ! -f "$CFG_A/.setup-state.json" ] && ok "考古入口不落清单(落账在收尾 write_state_file)" || bad "入口段不应写状态清单"

echo "== D. python3 缺失但清单在场 → 落考古路径(入口 && 守卫) =="
out="$(run_upgrade "$HOME_S" "$BIN:$SYSBIN_NOPY" "$TMPD/snip-report.sh")"; rc=$?
assert_eq "$rc" "0" "无 python3 入口段退出码 0(降级不阻断)"
assert_contains "$out" "考古模式" "无 python3 → 同样考古(不读清单)"

echo "== E. 全脚本接线(静态断言,不执行安装主流程) =="
bash -n "$SCRIPT" && ok "bash -n 语法通过" || bad "bash -n 语法错误"
out="$(bash "$SCRIPT" --version 2>&1)"
assert_contains "$out" "v1.0" "--version 仍即时退出"
out="$(bash "$SCRIPT" -h 2>&1)"
assert_contains "$out" "--upgrade" "-h 用法含 --upgrade"
assert_not_contains "$out" "P1 实现" "-h 不再标 P1 未实现"
assert_contains "$out" "不剥已装接线" "-h 描述升级语义(不剥已装接线)"
grep -q 'UPGRADE_MODE=1$' "$SCRIPT" && ok "--upgrade 臂置旗 UPGRADE_MODE=1" || bad "--upgrade 臂未置旗"
grep -qF '[ "${UPGRADE_MODE:-0}" = "1" ] && overwrite=n' "$SCRIPT" \
  && ok "步骤 1 覆盖问句前有升级模式分叉(overwrite=n)" || bad "步骤 1 缺升级分叉"
grep -qF '[ "${UPGRADE_MODE:-0}" = "1" ] && return 0' "$SCRIPT" \
  && ok "交互菜单开头有升级模式分叉(直接 return)" || bad "交互菜单缺升级分叉"
grep -qF '升级模式: 首次安装已确认 AGPL,状态清单留档' "$SCRIPT" \
  && ok "DCP 确认门有升级模式知会行" || bad "DCP 确认门缺升级知会"
grep -qF '升级完成: 本次新装' "$SCRIPT" \
  && ok "收尾升级报告(diff 新旧清单)在场" || bad "收尾缺升级报告"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = 0 ] || exit 1
exit 0
