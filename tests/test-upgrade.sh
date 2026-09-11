#!/bin/bash
# ============================================================================
# 动态升级 P1/P2 单测: --upgrade 入口段(upgrade_restore_context)+ 自更新段(P2)
#   1. 状态清单在场 → UC_* 还原 + INSTALL_*/CONFIRM_AGPL 环境变量导出
#      (核心: 修裸重跑误剥——dcp:true 必须带回 INSTALL_DCP=1 CONFIRM_AGPL=1)
#   2. 无状态清单(v1.0 前安装) → 考古模式,现场探测重建 UC_*
#   3. P2 自更新段: git 路径(origin 不可达不崩不重启 / 本地 origin 正向 ff-pull+重启)
#      + curl 路径(同版本 diff 相同防循环不重启 / 新版校验后替换重启 / 坏文件双校验拒绝)
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

echo "== E2. 步骤12 权限段: UPGRADE_MODE=1 跳过 gen-permissions(抽段+打桩) =="
# oct 实测疏漏回归: --upgrade 走到步骤 12, gen-permissions.sh 交互档位问句
# 仍弹(命令替换只重定向 stdout/stderr 吞不掉 stdin, 光标闪烁卡在等输入)。
# 升级语义=保留现有权限配置, 不重问不重生成; 全新安装路径行为不变(对照)。
sed -n '/^  # ① 权限红线/,/^  # ② 审计/p' "$SCRIPT" | sed '$d' > "$TMPD/permblk.sh"
grep -q 'gen-permissions.sh' "$TMPD/permblk.sh" \
  && ok "权限段①已抽出(gen-permissions 调用在场)" || bad "权限段①未抽出(锚点失效)"

# 打桩 gen-permissions: 探针落盘证明被调, 产物给最小合法 permission 段
PERM_STUB="$TMPD/modstub"; mkdir -p "$PERM_STUB"
cat > "$PERM_STUB/gen-permissions.sh" << 'EOF'
#!/bin/bash
echo called >> "$PERM_PROBE"
printf '{"permission": {"webfetch": "ask"}}\n' > "$1"
EOF
chmod +x "$PERM_STUB/gen-permissions.sh"

# run_perm <UPGRADE_MODE> <probe> <cfgdir>: 受控环境 source 抽出的权限段①
run_perm() {
  env HOME="$TMPD" PATH="$SYSBIN" MOD_DIR="$PERM_STUB" PERM_TMP="$TMPD/perm-tmp.json" \
    CONFIG_DIR="$3" PERM_PROBE="$2" UPGRADE_MODE="$1" \
    GREEN="" YELLOW="" BLUE="" NC="" bash -c 'source "$1"' _ "$TMPD/permblk.sh" 2>&1
}

CFG_U="$TMPD/cfgU"; mkdir -p "$CFG_U"
printf '{"marker": "keep"}\n' > "$CFG_U/opencode.json"
cp "$CFG_U/opencode.json" "$TMPD/perm-original.json"
rm -f "$TMPD/probe-upg"
out="$(run_perm 1 "$TMPD/probe-upg" "$CFG_U")"; rc=$?
assert_eq "$rc" "0" "升级模式权限段退出码 0"
assert_contains "$out" "升级模式: 保留现有权限配置" "升级模式打保留现有权限配置行"
assert_contains "$out" "重新生成用 bash" "保留行带重新生成指引"
[ ! -f "$TMPD/probe-upg" ] && ok "升级模式不调 gen-permissions(探针未落盘)" || bad "升级模式仍调了 gen-permissions(问句会卡等输入)"
diff -q "$TMPD/perm-original.json" "$CFG_U/opencode.json" >/dev/null 2>&1 \
  && ok "升级模式 opencode.json 字节未动(权限配置原样保留)" || bad "升级模式改写了 opencode.json"

CFG_F="$TMPD/cfgF"; mkdir -p "$CFG_F"
printf '{"marker": "keep"}\n' > "$CFG_F/opencode.json"
rm -f "$TMPD/probe-fresh"
out="$(run_perm 0 "$TMPD/probe-fresh" "$CFG_F")"; rc=$?
assert_eq "$rc" "0" "非升级权限段退出码 0"
[ -f "$TMPD/probe-fresh" ] && ok "非升级照常调 gen-permissions(全新安装行为不变)" || bad "非升级漏调 gen-permissions(回归)"
assert_contains "$out" "权限红线已合并到 opencode.json" "非升级合并成功行在场"
grep -q '"webfetch": "ask"' "$CFG_F/opencode.json" \
  && ok "非升级权限段真合入 opencode.json(在场复核)" || bad "非升级权限段未落进配置"
grep -q '"marker": "keep"' "$CFG_F/opencode.json" \
  && ok "非升级合并不清空既有配置" || bad "非升级合并清掉了既有键"

echo "== E3. gen-permissions 双保险: PERM_NO_ASK=1 真终端不问直落标准档 =="
GEN="$ROOT/e-modules/gen-permissions.sh"
bash "$GEN" "$TMPD/perm-ref.json" </dev/null 2>/dev/null
# perm_pty <env前缀>: pty 真终端跑 gen-permissions(预喂回车), 回显退出码;
#   终端输出落 $TMPD/perm-pty.out, 产物落 $TMPD/perm-out.json
perm_pty() {
  python3 - "$GEN" "$TMPD/perm-out.json" "$TMPD/perm-pty.out" "$1" << 'PY'
import os, pty, select, sys, time
gen, out, outf, envexpr = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-c", f'{envexpr} exec bash "{gen}" "{out}"'])
os.write(fd, b"\n")  # 预喂回车(问句触发即取用;未触发则闲置, 无害)
data = b""
st = None
deadline = time.time() + 15
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if r:
        try:
            c = os.read(fd, 4096)
        except OSError:
            break
        if not c:
            break
        data += c
    else:
        w, s = os.waitpid(pid, os.WNOHANG)
        if w:
            st = s
            break
if st is None:
    _, st = os.waitpid(pid, 0)
open(outf, "wb").write(data)
print(os.waitstatus_to_exitcode(st))
PY
}
RC="$(perm_pty 'PERM_NO_ASK=1')"
assert_eq "$RC" "0" "PERM_NO_ASK=1 真终端 exit 0"
assert_not_contains "$(cat "$TMPD/perm-pty.out" 2>/dev/null || true)" "权限档位" \
  "PERM_NO_ASK=1 不弹档位问句"
cmp -s "$TMPD/perm-ref.json" "$TMPD/perm-out.json"
assert_eq "$?" "0" "PERM_NO_ASK=1 产物=标准档(与非交互参照字节一致)"
RC="$(perm_pty '')"
assert_eq "$RC" "0" "对照(无 PERM_NO_ASK) exit 0"
assert_contains "$(cat "$TMPD/perm-pty.out" 2>/dev/null || true)" "权限档位" \
  "对照(无 PERM_NO_ASK)问句照常弹(全新安装档位问句行为不变)"

echo "== F. P2 自更新段抽取(入口块锚定: 注释头 → upgrade_restore_context 调用前) =="
# 与 A-D 同法的"入口段单元测试": 主流程副作用重,抽出内联段受控执行;
# exec 打桩为函数遮蔽内建 → 重启只回显不换进程,可断言 不崩/不重启/真重启 三态
sed -n '/^  # P2 自更新/,/^  upgrade_restore_context$/p' "$SCRIPT" | sed '$d' > "$TMPD/selfup.sh"
grep -q 'SCRIPT_GIT_DIR=' "$TMPD/selfup.sh" && ok "自更新段已抽出(git 路径变量在场)" || bad "自更新段未抽出(锚点失效或尚未实现)"
grep -qF 'gh-proxy.com' "$TMPD/selfup.sh" && ok "自更新段含 curl 回退源(gh-proxy)" || bad "自更新段缺 curl 回退源"

# exec 打桩驱动器: 函数遮蔽内建 exec,source 自更新段后自然结束
cat > "$TMPD/selfup-driver.sh" << 'EOF'
exec() { echo "RESTARTED: $*"; }
source "$1"
EOF

# curl 桩: 回放下载(FAKE_CURL_SRC → 最后一个参数即 -o 目标);探针文件证明 curl 真被调用
CURLBIN="$TMPD/curlbin"; mkdir -p "$CURLBIN"
cat > "$CURLBIN/curl" << 'EOF'
#!/bin/bash
echo called >> "$CURL_PROBE"
[ -n "${FAKE_CURL_FAIL:-}" ] && exit 22
cp "$FAKE_CURL_SRC" "${@: -1}"
EOF
chmod +x "$CURLBIN/curl"

GITC="-c user.email=t@t -c user.name=t"

echo "== G. 自更新 git 路径: 假 origin 不可达 → NEW_C 取不到=0 → 不 exec 不崩 =="
FIXG="$TMPD/fixg"; mkdir -p "$FIXG"
git -C "$FIXG" init -q && git -C "$FIXG" symbolic-ref HEAD refs/heads/main
git -C "$FIXG" $GITC commit -q --allow-empty -m init
git -C "$FIXG" remote add origin "$TMPD/definitely-missing-origin.git"
out="$(env HOME="$TMPD" SCRIPT_DIR="$FIXG" PATH="$CURLBIN:$PATH" \
  CURL_PROBE="$TMPD/curl-probe" FAKE_CURL_FAIL=1 \
  bash "$TMPD/selfup-driver.sh" "$TMPD/selfup.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "origin 不可达自更新段退出码 0(不崩)"
assert_not_contains "$out" "RESTARTED" "不可达 origin 不触发 exec 重启"
assert_not_contains "$out" "脚本自更新" "不可达 origin 不打自更新成功文案"

echo "== H. 自更新 git 路径正向: 本地 origin 领先 1 提交 → ff-pull + 重启新版 =="
UP="$TMPD/upstream"; mkdir -p "$UP"
git -C "$UP" init -q && git -C "$UP" symbolic-ref HEAD refs/heads/main
echo v1 > "$UP/f" && git -C "$UP" add f && git -C "$UP" $GITC commit -q -m v1
FIXH="$TMPD/fixh" && git clone -q "$UP" "$FIXH"
echo v2 > "$UP/f" && git -C "$UP" $GITC commit -q -am v2
# PATH 放必失败 curl 桩: git 分支本不触 curl,若意外落入 curl 分支也离线安全
out="$(env HOME="$TMPD" SCRIPT_DIR="$FIXH" PATH="$CURLBIN:$PATH" \
  CURL_PROBE="$TMPD/curl-probe" FAKE_CURL_FAIL=1 \
  bash "$TMPD/selfup-driver.sh" "$TMPD/selfup.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "正向自更新退出码 0"
assert_contains "$out" "拉取 1 个新提交" "领先 1 提交打拉取对账行"
assert_contains "$out" "RESTARTED" "ff-pull 成功后 exec 重启新版"
assert_eq "$(git -C "$FIXH" rev-parse HEAD)" "$(git -C "$UP" rev-parse HEAD)" \
  "ff-pull 真的发生(fixh HEAD 追平 upstream HEAD)"

echo "== I. 自更新 curl 路径防循环: 下载与自身同版本 → 不替换不重启 =="
FIXI="$TMPD/fixi"; mkdir -p "$FIXI"; cp "$SCRIPT" "$FIXI/setup-opencode.sh"
rm -f "$TMPD/curl-probe"
# $0 经 bash -c 的 NAME 参数指向自身副本(与下载内容相同 → diff 相同 → 防循环分支)
out="$(env HOME="$TMPD" SCRIPT_DIR="$FIXI" PATH="$CURLBIN:$PATH" \
  CURL_PROBE="$TMPD/curl-probe" FAKE_CURL_SRC="$FIXI/setup-opencode.sh" \
  bash -c 'exec() { echo "RESTARTED: $*"; }; source "$1"' \
  "$FIXI/setup-opencode.sh" "$TMPD/selfup.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "同版本下载退出码 0"
[ -f "$TMPD/curl-probe" ] && ok "curl 分支真被走到(探针落盘)" || bad "curl 未被调用(路径未覆盖)"
assert_not_contains "$out" "RESTARTED" "同版本不 exec 重启(防循环)"
assert_not_contains "$out" "脚本自更新完成" "同版本不打自更新成功文案"
diff -q "$SCRIPT" "$FIXI/setup-opencode.sh" >/dev/null 2>&1 \
  && ok "同版本下自身未被替换" || bad "同版本下自身被错误替换"

echo "== J. 自更新 curl 路径正向: 下载到新版 → 双校验通过替换自身 + 重启 =="
FIXJ="$TMPD/fixj"; mkdir -p "$FIXJ"; cp "$SCRIPT" "$FIXJ/setup-opencode.sh"
cp "$SCRIPT" "$TMPD/newver.sh" && echo "# upstream vNew" >> "$TMPD/newver.sh"
rm -f "$TMPD/curl-probe"
out="$(env HOME="$TMPD" SCRIPT_DIR="$FIXJ" PATH="$CURLBIN:$PATH" \
  CURL_PROBE="$TMPD/curl-probe" FAKE_CURL_SRC="$TMPD/newver.sh" \
  bash -c 'exec() { echo "RESTARTED: $*"; }; source "$1"' \
  "$FIXJ/setup-opencode.sh" "$TMPD/selfup.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "新版替换路径退出码 0"
assert_contains "$out" "脚本自更新完成(curl)" "打 curl 自更新成功文案"
assert_contains "$out" "RESTARTED" "替换后 exec 重启新版"
grep -q '# upstream vNew' "$FIXJ/setup-opencode.sh" \
  && ok "新版内容已替换到自身" || bad "自身未换成新版内容"

echo "== K. 自更新 curl 路径守卫: 坏下载(远小于 50KB)→ 双校验拒绝,不替换不重启 =="
FIXK="$TMPD/fixk"; mkdir -p "$FIXK"; cp "$SCRIPT" "$FIXK/setup-opencode.sh"
printf 'echo garbage\n' > "$TMPD/bad.sh"
out="$(env HOME="$TMPD" SCRIPT_DIR="$FIXK" PATH="$CURLBIN:$PATH" \
  CURL_PROBE="$TMPD/curl-probe" FAKE_CURL_SRC="$TMPD/bad.sh" \
  bash -c 'exec() { echo "RESTARTED: $*"; }; source "$1"' \
  "$FIXK/setup-opencode.sh" "$TMPD/selfup.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "坏下载退出码 0(拒绝但不清算)"
assert_not_contains "$out" "RESTARTED" "坏文件不 exec 重启"
diff -q "$SCRIPT" "$FIXK/setup-opencode.sh" >/dev/null 2>&1 \
  && ok "坏文件不替换自身(大小双校验生效)" || bad "坏文件错误替换了自身"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = 0 ] || exit 1
exit 0


# ── 自更新版本前进校验(oct CDN 缓存毒实测)──
t "同版本不替换(缓存毒拒绝)" '' 'print_ok "同版拒"' 'grep -m1 "^SETUP_VERSION=" "$0"'
t "坏语法不替换" '' 'print_ok "语法拒"' 'bash -n /dev/null 2>/dev/null && echo syn || echo syn-fail'
