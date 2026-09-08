#!/bin/bash
# ============================================================================
# completion-gate.sh 单测(出环硬门控)
#
# 方法: mktemp 造真实夹具项目(git 仓库 + package.json 测试脚本 + 声明文本
#       注入), 对三种场景各跑 check 断言退出码与输出关键词; 另断言
#       report 模式不阻断(同文退出 0)、密钥扫描、bash -n 语法、-h 用法。
#
# 场景:
#   ① 测试失败夹具: package.json test=exit 1, 已全部提交 → check 退出 1,
#      报"测试"失败项; report 同文但退出 0
#   ② 假声明夹具: 声明了不在场的工具+不存在的文件 → check 退出 1,
#      报声明项名词; 在场文件声明不误报
#   ③ 干净夹具: 测试通过+文件在场+无未提交变更 → check 退出 0 报 PASS
#   ④ 密钥夹具: 未提交文件含 sk- 明文密钥 → check 退出 1, 报文件且掩码
#
# 运行: bash tests/test-completion-gate.sh  (仓库根或任意目录均可)
# ============================================================================
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/e-modules/completion-gate.sh"

if [ ! -f "$GATE" ]; then
  echo "✗ 未找到 $GATE"
  exit 1
fi

TMPD="$(mktemp -d /tmp/completion-gate-test.XXXXXX)"
trap 'rm -rf "$TMPD"' EXIT

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3——期望[$2] 实际[$1]"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3——不应出现: $2" ;; *) ok "$3" ;; esac; }

git_init_commit() {  # <dir> — git 初始化并提交当前全部内容
  git -C "$1" init -q
  git -C "$1" add -A
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm init
}

# 本机保证不在场的工具名词(声明它必然构成假声明)
ABSENT_TOOL=""
for t in mineru mem0 skillopt-sleep; do
  command -v "$t" >/dev/null 2>&1 || { ABSENT_TOOL="$t"; break; }
done
[ -n "$ABSENT_TOOL" ] || { echo "✗ 本机 mineru/mem0/skillopt-sleep 全在场,无法构造假声明夹具"; exit 1; }

echo "== ⓪ 语法与用法 =="
bash -n "$GATE"
assert_eq "$?" "0" "bash -n 语法通过"
bash "$GATE" -h >"$TMPD/help.txt" 2>&1 </dev/null
assert_eq "$?" "0" "-h 退出 0"
assert_contains "$(cat "$TMPD/help.txt")" "check" "-h 列出 check 子命令"
assert_contains "$(cat "$TMPD/help.txt")" "report" "-h 列出 report 子命令"
bash "$GATE" bogus-subcommand >/dev/null 2>&1 </dev/null
[ "$?" -ne 0 ]
assert_eq "$?" "0" "未知子命令非零退出"

echo "== ① 测试失败夹具(check 阻断 / report 放行) =="
F1="$TMPD/f1-testfail"; mkdir -p "$F1"
printf '{"name":"f1","scripts":{"test":"exit 1"}}\n' > "$F1/package.json"
printf '# f1\n' > "$F1/notes.md"
git_init_commit "$F1"
bash "$GATE" check "$F1" >"$TMPD/f1.out" 2>&1 </dev/null
assert_eq "$?" "1" "check: 测试失败 → 退出码 1"
assert_contains "$(cat "$TMPD/f1.out")" "测试" "check: 报出测试失败项"
assert_contains "$(cat "$TMPD/f1.out")" "FAIL" "check: 结果标 FAIL"
bash "$GATE" report "$F1" >"$TMPD/f1r.out" 2>&1 </dev/null
assert_eq "$?" "0" "report: 同场景退出 0(不阻断)"
assert_contains "$(cat "$TMPD/f1r.out")" "测试" "report: 同样报出测试失败项"

echo "== ② 假声明夹具(声明-在场一致性) =="
F2="$TMPD/f2-claims"; mkdir -p "$F2"
printf '# f2\n' > "$F2/notes.md"
git_init_commit "$F2"
MSG="收尾汇报: ✓ 已安装 $ABSENT_TOOL 并已配置完成; 已生成 out/report.json; 已生成 notes.md; 测试均通过。"
bash "$GATE" check "$F2" --message "$MSG" >"$TMPD/f2.out" 2>&1 </dev/null
assert_eq "$?" "1" "check: 假声明 → 退出码 1"
CLAIM_LINE="$(grep '声明-在场' "$TMPD/f2.out")"
assert_contains "$CLAIM_LINE" "声明不在场" "check: 声明复核判 FAIL"
assert_contains "$CLAIM_LINE" "$ABSENT_TOOL" "check: 报出不在场工具名词"
assert_contains "$CLAIM_LINE" "out/report.json" "check: 报出不存在的声明文件"
assert_not_contains "$CLAIM_LINE" "notes.md" "check: 在场文件 notes.md 不误报"

echo "== ③ 干净夹具(全部通过) =="
F3="$TMPD/f3-clean"; mkdir -p "$F3"
printf '{"name":"f3","scripts":{"test":"exit 0"}}\n' > "$F3/package.json"
printf '# f3\n' > "$F3/notes.md"
git_init_commit "$F3"
bash "$GATE" check "$F3" --message "已完成。已生成 notes.md,已配置好本项目。" >"$TMPD/f3.out" 2>&1 </dev/null
assert_eq "$?" "0" "check: 干净场景 → 退出码 0"
assert_contains "$(cat "$TMPD/f3.out")" "PASS" "check: 结果标 PASS"
assert_not_contains "$(cat "$TMPD/f3.out")" "FAIL" "check: 无失败项"

echo "== ④ 密钥夹具(明文密钥扫描) =="
F4="$TMPD/f4-secret"; mkdir -p "$F4"
printf '# f4\n' > "$F4/notes.md"
git_init_commit "$F4"
# 密钥文件在提交之后写入 → 保持未跟踪态,落入"暂存/未提交文件"扫描范围
# 样例密钥用拼接构造,源文件不携带可被 sk- 扫描器命中的字面量
printf 'API_KEY=sk-abc%s\n' 'defghij0123456789xyz' > "$F4/config.env"
bash "$GATE" check "$F4" >"$TMPD/f4.out" 2>&1 </dev/null
assert_eq "$?" "1" "check: 明文密钥 → 退出码 1"
assert_contains "$(cat "$TMPD/f4.out")" "config.env" "check: 报出密钥所在文件"
assert_not_contains "$(cat "$TMPD/f4.out")" "sk-abcdefghij0123456789" "check: 输出对密钥掩码,不回显全文"

echo "== ⑤ 全场景无 bash 报错 =="
for f in "$TMPD"/f1.out "$TMPD"/f1r.out "$TMPD"/f2.out "$TMPD"/f3.out "$TMPD"/f4.out; do
  assert_not_contains "$(cat "$f" 2>/dev/null)" "syntax error" "$(basename "$f"): 无 syntax error"
  assert_not_contains "$(cat "$f" 2>/dev/null)" "command not found" "$(basename "$f"): 无 command not found"
done
# 未提交+无会话证据路径的 git 卫生行必须在场(f4 触发该分支)
assert_contains "$(cat "$TMPD/f4.out")" "git 卫生" "f4: git 卫生行未因报错丢失"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = "0" ] || exit 1
exit 0
