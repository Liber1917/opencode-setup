#!/bin/bash
# ============================================================================
# 动态升级 P0 单测: SETUP_VERSION 常量 + --version/--upgrade/-h 参数解析
#                  + detect_components 在场探测 + write_state_file 状态清单
#
# 方法: 与 test-interactive-menu.sh 同款——sed 从 setup-opencode.sh 抽出函数体
#       (区间锚定列首定义行),bash 子进程 source 后在干净临时 HOME + 受控 PATH
#       (伪造在场命令 + crontab 桩 + 仅探测自身所需的 ls/grep/python3/git)下驱动,
#       宿主机已装工具不泄漏进探测结果;--version 等参数直跑全脚本头(参数解析
#       位于任何安装动作之前,exit 0 零副作用)。
#
# 在场守则(AGENTS.md): 断言全部对着实测在场——伪造 bin 里放什么,探测就必须报
#       什么;装前/装后两次写入,组件位翻转必须逐项吻合;permission_mode 阈值
#       (标准 59/无头 8/沙箱特征)与 e-modules/gen-permissions.sh 实生成模板
#       交叉核对,防档位漂移。
#
# 运行: bash tests/test-setup-state.sh  (仓库根或任意目录均可;可重复执行)
# ============================================================================
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/setup-opencode.sh"
GENPERM="$ROOT/e-modules/gen-permissions.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "✗ 未找到 $SCRIPT"
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "✗ 测试需 python3(状态清单本身依赖它)"; exit 1; }

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# 抽函数(列首定义行锚定;write_state_file 内 python heredoc 全用赋值语句构造
# dict,无列首 "}",保证 sed 区间闭合在函数尾)
sed -n '/^resolve_setup_version() {/,/^}$/p;/^detect_components() {/,/^}$/p;/^write_state_file() {/,/^}$/p' \
  "$SCRIPT" > "$TMPD/funcs.sh"
MISSING=0
for f in resolve_setup_version detect_components write_state_file; do
  grep -q "^$f() {" "$TMPD/funcs.sh" || { echo "✗ 红灯: setup-opencode.sh 中未抽出 $f()(尚未实现?)"; MISSING=1; }
done
[ "$MISSING" = 0 ] || exit 1

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3——不应出现: $2" ;; *) ok "$3" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3——期望[$2] 实际[$1]"; fi; }

# 受控 PATH: fakebin(伪造在场命令 + crontab 桩)+ sysbin(仅探测/写清单自身所需),
# 探测结果只由夹具决定,宿主机装过什么与本测试无关
SYSBIN="$TMPD/sysbin"; mkdir -p "$SYSBIN"
for c in bash ls grep python3 git; do
  _p="$(command -v "$c")" && ln -sf "$_p" "$SYSBIN/$c"
done
SYSBIN_NOPY="$TMPD/sysbin-nopy"; mkdir -p "$SYSBIN_NOPY"
for c in bash ls grep git; do
  _p="$(command -v "$c")" && ln -sf "$_p" "$SYSBIN_NOPY/$c"
done

# run_case <home> <path> <snippet文件>: 受控环境 source 函数后执行用例
run_case() {
  env HOME="$1" PATH="$2" SETUP_VERSION="v1.0" SCRIPT_DIR="$TMPD" ROOT="$ROOT" \
    GREEN="" YELLOW="" NC="" bash -c '
      CONFIG_DIR="$HOME/.config/opencode"
      source "$1"
      source "$2"
    ' _ "$TMPD/funcs.sh" "$3"
}

# state_field <file> <python表达式(对 d)>: 提取字段;json 非法时输出 __INVALID__
state_field() {
  python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("__INVALID__"); raise SystemExit
print(eval(sys.argv[2]))' "$1" "$2" 2>/dev/null
}

echo "== A. 参数解析(全脚本头直跑,在任何安装动作前 exit 0) =="
out="$(bash "$SCRIPT" --version 2>&1)"; rc=$?
assert_eq "$rc" "0" "--version 退出码 0"
assert_contains "$out" "v1.0" "--version 出版本(SETUP_VERSION 常量)"
if [ -d "$ROOT/.git" ]; then
  assert_contains "$out" "git:" "git 克隆场景附带 commit"
fi
assert_not_contains "$out" "一键配置脚本" "--version 不打安装横幅(未进主流程)"

out="$(bash "$SCRIPT" -h 2>&1)"; rc=$?
assert_eq "$rc" "0" "-h 退出码 0"
assert_contains "$out" "默认" "-h 用法含默认装"
assert_contains "$out" "--upgrade" "-h 用法含 --upgrade"
assert_contains "$out" "--version" "-h 用法含 --version"
out2="$(bash "$SCRIPT" --help 2>&1)"
assert_contains "$out2" "用法" "--help 等价 -h"

echo "== B. 版本解析(常量 vs git describe) =="
cat > "$TMPD/snip-ver-const.sh" << 'EOF'
resolve_setup_version
EOF
out="$(run_case "$TMPD/home-empty" "$SYSBIN" "$TMPD/snip-ver-const.sh")"
assert_eq "$out" "v1.0" "无 .git(curl 安装场景) → SETUP_VERSION 常量"
if [ -d "$ROOT/.git" ] && command -v git >/dev/null 2>&1; then
  cat > "$TMPD/snip-ver-git.sh" << 'EOF'
SCRIPT_DIR="$ROOT"
resolve_setup_version
EOF
  _want="$(git -C "$ROOT" describe --tags --always 2>/dev/null || true)"
  out="$(run_case "$TMPD/home-empty" "$SYSBIN" "$TMPD/snip-ver-git.sh")"
  assert_eq "$out" "$_want" "git 克隆场景 → git describe --tags --always 覆盖常量"
fi

echo "== C. 组件探测 + 状态清单(干净 HOME,装前 vs 装后) =="
HOME_C="$TMPD/homeC"; CFG="$HOME_C/.config/opencode"; mkdir -p "$CFG"
BIN="$TMPD/bin"; mkdir -p "$BIN"
cat > "$BIN/crontab" << 'EOF'
#!/bin/bash
# 测试桩: 受控回放 crontab -l(不碰真机);FAKE_CRONTAB_TEXT 非空=有表,空=无表
[ -n "${FAKE_CRONTAB_TEXT:-}" ] && { printf '%s\n' "$FAKE_CRONTAB_TEXT"; exit 0; }
exit 1
EOF
chmod +x "$BIN/crontab"

cat > "$TMPD/snip-write.sh" << 'EOF'
write_state_file
EOF
cat > "$TMPD/snip-detect.sh" << 'EOF'
detect_components
EOF

# --- 装前: 仅 opencode/bun 在场;无 dcp/gsd/sp-router/cron;无权限红线 ---
for t in opencode bun; do : > "$BIN/$t"; chmod +x "$BIN/$t"; done
cat > "$CFG/opencode.json" << 'EOF'
{
  "model": "zhipuai-coding-plan/glm-5.3",
  "plugin": ["oh-my-openagent@latest"]
}
EOF
out="$(run_case "$HOME_C" "$BIN:$SYSBIN" "$TMPD/snip-write.sh")"
assert_contains "$out" "状态清单 → " "装前写入打收尾一行"
assert_contains "$out" "vP1 升级账本" "收尾行标注 vP1 升级账本"
STATE="$CFG/.setup-state.json"
[ -f "$STATE" ] && ok ".setup-state.json 已落盘" || bad ".setup-state.json 未落盘"
[ ! -f "$STATE.tmp" ] && ok "原子写: 无 .tmp 残留" || bad "原子写失败: .tmp 残留"

out="$(state_field "$STATE" '"__OK__" if isinstance(d, dict) else "__INVALID__"')"
assert_eq "$out" "__OK__" "装前 json 合法(python json.load 通过)"
out="$(state_field "$STATE" 'd["script_version"]')"
assert_eq "$out" "v1.0" "script_version = 版本解析值(非 git 场景用常量)"
out="$(state_field "$STATE" 'd["installed_at"]')"
case "$out" in
  2[0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ok "installed_at 为 ISO 时间($out)" ;;
  *) bad "installed_at 非 ISO 格式: $out" ;;
esac
out="$(state_field "$STATE" 'd["flags"]["model"]')"
assert_eq "$out" "zhipuai-coding-plan/glm-5.3" "flags.model 实读 opencode.json"
out="$(state_field "$STATE" 'd["flags"]["permission_mode"]')"
assert_eq "$out" "unknown" "无权限红线(步骤12未跑) → permission_mode=unknown"

# 装前组件期望: 与夹具在场逐一对照(在场守则——探测必须等于夹具事实)
WANT_BEFORE="$(python3 -c 'import json
print(json.dumps({"opencode": True, "bun": True, "node": False, "rtk": False,
 "codegraph": False, "webmap": False, "opstate": False, "mem0": False,
 "skillopt-sleep": False, "mineru": False, "dcp": False, "gsd": False,
 "superpowers_router": False, "cmolecules_cron": False}, sort_keys=True))')"
out="$(state_field "$STATE" 'json.dumps(d["components"], sort_keys=True)')"
assert_eq "$out" "$WANT_BEFORE" "装前组件值与在场一致(14 项逐一吻合)"

# 中间态: cron 有其他条目但无 skillopt-sleep → 仍 false(不误报)
out="$(FAKE_CRONTAB_TEXT='0 5 * * * echo other-job' run_case "$HOME_C" "$BIN:$SYSBIN" "$TMPD/snip-detect.sh")"
assert_contains "$out" '"cmolecules_cron": false' "cron 有表但无 skillopt-sleep → false(不误报)"

# --- 装后: 其余 8 命令在场 + dcp 注册 + gsd 命令 + sp-router + cron 在册 ---
for t in node rtk codegraph webmap opstate mem0 skillopt-sleep mineru; do : > "$BIN/$t"; chmod +x "$BIN/$t"; done
python3 - "$CFG/opencode.json" << 'PYEOF'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["plugin"].append("opencode-dcp@latest")
tmp = p + ".tmp"
json.dump(c, open(tmp, "w"), indent=2)
import os; os.replace(tmp, p)
PYEOF
mkdir -p "$CFG/command" && : > "$CFG/command/gsd-help.md"
mkdir -p "$CFG/plugins" && : > "$CFG/plugins/sp-router.ts"

out="$(FAKE_CRONTAB_TEXT='0 3 * * * skillopt-sleep >> ~/.config/opencode/skill-drafts/sleep.log 2>&1' \
  run_case "$HOME_C" "$BIN:$SYSBIN" "$TMPD/snip-write.sh")"
assert_contains "$out" "状态清单 → " "装后重写成功(幂等: 每次运行收尾都重写)"

WANT_AFTER="$(python3 -c 'import json
print(json.dumps({"opencode": True, "bun": True, "node": True, "rtk": True,
 "codegraph": True, "webmap": True, "opstate": True, "mem0": True,
 "skillopt-sleep": True, "mineru": True, "dcp": True, "gsd": True,
 "superpowers_router": True, "cmolecules_cron": True}, sort_keys=True))')"
out="$(state_field "$STATE" 'json.dumps(d["components"], sort_keys=True)')"
assert_eq "$out" "$WANT_AFTER" "装后组件值与在场一致(dcp 以 opencode.json 实注册为准)"

# 装前 vs 装后 diff: 翻转的必须恰好是新增的 12 项,无一漏报/误报
DIFF_OUT="$(python3 - "$WANT_BEFORE" "$STATE" << 'PYEOF'
import json, sys
a = json.loads(sys.argv[1])
b = json.load(open(sys.argv[2]))["components"]
print(",".join(sorted(k for k in b if a.get(k) != b[k])))
PYEOF
)"
WANT_DIFF="cmolecules_cron,codegraph,dcp,gsd,mem0,mineru,node,opstate,rtk,skillopt-sleep,superpowers_router,webmap"
assert_eq "$DIFF_OUT" "$WANT_DIFF" "装前→装后 diff 恰好翻转 12 项新增组件"
[ ! -f "$STATE.tmp" ] && ok "装后原子写: 仍无 .tmp 残留" || bad "装后 .tmp 残留"

echo "== D. permission_mode 推断(与 gen-permissions.sh 实模板交叉核对) =="
if [ ! -f "$GENPERM" ]; then
  echo "  (跳过: 未找到 e-modules/gen-permissions.sh)"
else
  bash "$GENPERM" "$TMPD/perm-std.json" </dev/null >/dev/null 2>&1
  PERMISSION_MODE=headless bash "$GENPERM" "$TMPD/perm-hl.json" >/dev/null 2>&1
  PERMISSION_MODE=sandbox bash "$GENPERM" "$TMPD/perm-sb.json" >/dev/null 2>&1

  # 漂移防线: write_state_file 里烙的 59/8/沙箱特征必须仍与模板实况一致
  out="$(python3 -c 'import json,sys; b=json.load(open(sys.argv[1]))["permission"]["bash"]; print(len(b))' "$TMPD/perm-std.json")"
  assert_eq "$out" "59" "模板标准档仍 59 条(防档位漂移)"
  out="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["permission"]["bash"]))' "$TMPD/perm-hl.json")"
  assert_eq "$out" "8" "模板无头档仍 8 条(防档位漂移)"
  out="$(python3 -c 'import json,sys; b=json.load(open(sys.argv[1]))["permission"]["bash"]; print(b.get("curl*|*sh")=="deny" and "rm -rf *" not in b)' "$TMPD/perm-sb.json")"
  assert_eq "$out" "True" "模板沙箱档特征在(curl|sh deny 无 rm -rf)"

  # 三档 + custom + 无 opencode.json 逐档过 write_state_file
  perm_case() {  # perm_case <名> <permfile|-> <期望mode>
    python3 - "$CFG/opencode.json" "$2" << 'PYEOF'
import json, os, sys
p, perm_file = sys.argv[1], sys.argv[2]
cfg = {"model": "zhipuai-coding-plan/glm-5.3", "plugin": ["oh-my-openagent@latest"]}
if perm_file != "-":
    cfg["permission"] = json.load(open(perm_file))["permission"]
json.dump(cfg, open(p, "w"), indent=2)
PYEOF
    run_case "$HOME_C" "$BIN:$SYSBIN" "$TMPD/snip-write.sh" >/dev/null
    assert_eq "$(state_field "$STATE" 'd["flags"]["permission_mode"]')" "$3" "$1 → $3"
  }
  perm_case "标准档(59 条)" "$TMPD/perm-std.json" "standard"
  perm_case "无头档(8 条)" "$TMPD/perm-hl.json" "headless"
  perm_case "沙箱档(curl deny 无 rm -rf)" "$TMPD/perm-sb.json" "sandbox"

  # custom: 10 条含两类 deny → 不落入任何模板档
  python3 - "$CFG/opencode.json" << 'PYEOF'
import json, sys
p = sys.argv[1]
bash = {"curl*|*sh": "deny", "rm -rf *": "deny"}
bash.update({f"cmd{i}*": "allow" for i in range(8)})
cfg = {"model": "zhipuai-coding-plan/glm-5.3", "plugin": ["oh-my-openagent@latest"],
       "permission": {"bash": bash}}
json.dump(cfg, open(p, "w"), indent=2)
PYEOF
  run_case "$HOME_C" "$BIN:$SYSBIN" "$TMPD/snip-write.sh" >/dev/null
  assert_eq "$(state_field "$STATE" 'd["flags"]["permission_mode"]')" "custom" "10 条混合规则 → custom(不硬套模板)"

  rm -f "$CFG/opencode.json"
  run_case "$HOME_C" "$BIN:$SYSBIN" "$TMPD/snip-write.sh" >/dev/null
  assert_eq "$(state_field "$STATE" 'd["flags"]["permission_mode"]')" "unknown" "opencode.json 缺失 → unknown"
  out="$(state_field "$STATE" 'd["flags"]["model"]')"
  assert_eq "$out" "" "opencode.json 缺失 → model 空串"
  # dcp 探测同样依赖 opencode.json,缺失时不误报(此时组件里 dcp 应为 false)
  assert_eq "$(state_field "$STATE" 'd["components"]["dcp"]')" "False" "opencode.json 缺失 → dcp=false 不误报"
fi

echo "== E. python3 缺失降级(跳过+黄警,不阻断) =="
HOME_E="$TMPD/homeE"; mkdir -p "$HOME_E/.config/opencode"
out="$(run_case "$HOME_E" "$BIN:$SYSBIN_NOPY" "$TMPD/snip-write.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "python3 缺失: 退出码 0(降级不阻断)"
assert_contains "$out" "无 python3,跳过状态清单" "python3 缺失打黄警"
[ ! -f "$HOME_E/.config/opencode/.setup-state.json" ] && ok "降级时不落盘状态文件" || bad "降级路径不应写状态文件"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = 0 ] || exit 1
exit 0
