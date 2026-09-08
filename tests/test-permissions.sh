#!/bin/bash
# ============================================================================
# gen-permissions.sh 单测(三态生成+JSON 计数 / 沙箱断言 / 交互档位问句 /
# 非交互零变化)
#
# 方法: 三态与沙箱断言用 python3 解析生成 JSON 逐键断言+计数; 交互问句用
#       python3 pty.fork 造真终端([ -t 0 ] 为真、/dev/tty 可写), 预喂输入
#       驱动 read, 断言产物模板与问句回显; 非交互用管道//dev/null 断言问句
#       不触发、管道输入被忽略(零行为变化)。
#
# 四组:
#   ① 三态生成: 默认交互 59(14 deny/6 ask/39 allow) / --headless 8 deny /
#      --sandbox 6 deny; PERMISSION_MODE 环境变量与 flag 字节等价
#   ② 沙箱断言: 网络红线仍 deny、本机破坏类已删、ask 归零、"*"=allow 兜底
#   ③ 交互问句(pty): 回车→标准 / 选 2→沙箱(与 --sandbox 字节一致) /
#      非法×3→超限回退标准
#   ④ 非交互零变化: 管道//dev/null 不问不读, 产物与默认档字节一致
#
# 运行: bash tests/test-permissions.sh  (仓库根或任意目录均可)
# ============================================================================
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$ROOT/e-modules/gen-permissions.sh"

if [ ! -f "$GEN" ]; then
  echo "✗ 未找到 $GEN"
  exit 1
fi

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
assert_eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3——期望[$2] 实际[$1]"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3——未检出: $2" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3——不应出现: $2" ;; *) ok "$3" ;; esac; }

# jcount <file> <category> <value> — permission.<category> 中值为 <value> 的条数
jcount() {
  python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))["permission"].get(sys.argv[2])
if isinstance(c,dict):
    print(sum(1 for v in c.values() if v==sys.argv[3]))
elif isinstance(c,str):
    print(1 if c==sys.argv[3] else 0)
else:
    print(0)
' "$1" "$2" "$3"
}
# jtotal <file> <category> — permission.<category> 的键总数
jtotal() {
  python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))["permission"][sys.argv[2]]
print(len(c))
' "$1" "$2"
}
# jget <file> <bash键> — permission.bash 单键取值(不存在输出 <absent>)
jget() {
  python3 -c '
import json,sys
b=json.load(open(sys.argv[1]))["permission"].get("bash",{})
print(b.get(sys.argv[2],"<absent>"))
' "$1" "$2"
}
# jscalars <file> — 标量类工具(edit/read/...)逐行 "k=v"
jscalars() {
  python3 -c '
import json,sys
p=json.load(open(sys.argv[1]))["permission"]
for k,v in p.items():
    if not isinstance(v,dict): print(f"{k}={v}")
' "$1"
}

# pty_run <feed> <outfile> — 真终端跑默认档, 终端输出落 $TMPD/pty.out, echo 退出码
pty_run() {
  python3 - "$GEN" "$1" "$2" "$TMPD/pty.out" << 'PY'
import os, pty, select, sys, time
gen, feed, out, outf = sys.argv[1], sys.argv[2].encode(), sys.argv[3], sys.argv[4]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", gen, out])
data = b""
deadline = time.time() + 20
try:
    os.write(fd, feed)  # 预喂输入(pty 行缓冲, 子进程 read 时取用)
    done = False
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                done = True; break
            if not chunk:
                done = True; break
            data += chunk
        else:
            w, _ = os.waitpid(pid, os.WNOHANG)
            if w != 0:
                while True:  # 子进程已退, 吸干 pty 残留输出
                    r, _, _ = select.select([fd], [], [], 0.2)
                    if not r: break
                    try:
                        chunk = os.read(fd, 4096)
                    except OSError:
                        break
                    if not chunk: break
                    data += chunk
                done = True; break
    if not done:
        os.kill(pid, 9); os.waitpid(pid, 0)
        open(outf, "wb").write(data)
        print("TIMEOUT")
        sys.exit(0)
finally:
    try: os.close(fd)
    except OSError: pass
_, st = os.waitpid(pid, 0)
open(outf, "wb").write(data)
print(os.waitstatus_to_exitcode(st))
PY
}

echo "== ① 三态生成 + JSON 校验/计数 =="
bash "$GEN" "$TMPD/std.json" </dev/null 2>"$TMPD/std.err"
assert_eq "$?" "0" "默认档(非交互)生成 exit 0"
python3 -m json.tool "$TMPD/std.json" >/dev/null 2>&1
assert_eq "$?" "0" "默认档产物是合法 JSON"
assert_eq "$(jtotal "$TMPD/std.json" bash)" "59" "交互版 bash 规则总数=59"
assert_eq "$(jcount "$TMPD/std.json" bash deny)" "14" "交互版 bash deny=14"
assert_eq "$(jcount "$TMPD/std.json" bash ask)" "6" "交互版 bash ask=6(5 命名+* 兜底)"
assert_eq "$(jcount "$TMPD/std.json" bash allow)" "39" "交互版 bash allow=39"
assert_eq "$(jcount "$TMPD/std.json" edit deny)" "7" "交互版 edit deny=7(系统/凭据/自身配置)"
assert_eq "$(jcount "$TMPD/std.json" edit allow)" "2" "交互版 edit allow=2"
assert_eq "$(jcount "$TMPD/std.json" webfetch ask)" "1" "交互版 webfetch=ask"

bash "$GEN" --headless "$TMPD/hl.json" </dev/null 2>/dev/null
assert_eq "$?" "0" "--headless 生成 exit 0"
python3 -m json.tool "$TMPD/hl.json" >/dev/null 2>&1
assert_eq "$?" "0" "无头版产物是合法 JSON"
# 注: 无头档实为 7 deny(v2 起如此, 模板冻结不许动), 文档旧称"8 条红线"系多计
assert_eq "$(jtotal "$TMPD/hl.json" bash)" "8" "无头版 bash 规则总数=8"
assert_eq "$(jcount "$TMPD/hl.json" bash deny)" "7" "无头版 bash deny=7"
assert_eq "$(jcount "$TMPD/hl.json" bash allow)" "1" "无头版 bash allow=1(* 兜底)"
assert_eq "$(jscalars "$TMPD/hl.json" | grep -cv '=allow$')" "0" "无头版标量工具类全 allow"

bash "$GEN" --sandbox "$TMPD/sb.json" </dev/null 2>/dev/null
assert_eq "$?" "0" "--sandbox 生成 exit 0"
python3 -m json.tool "$TMPD/sb.json" >/dev/null 2>&1
assert_eq "$?" "0" "沙箱版产物是合法 JSON"
assert_eq "$(jtotal "$TMPD/sb.json" bash)" "7" "沙箱版 bash 规则总数=7"
assert_eq "$(jcount "$TMPD/sb.json" bash deny)" "6" "沙箱版 bash deny=6(网络不可逆)"
assert_eq "$(jcount "$TMPD/sb.json" bash ask)" "0" "沙箱版 bash ask=0(归零)"
assert_eq "$(jscalars "$TMPD/sb.json" | grep -cv '=allow$')" "0" "沙箱版标量工具类全 allow"

PERMISSION_MODE=sandbox bash "$GEN" "$TMPD/sb-env.json" </dev/null 2>/dev/null
cmp -s "$TMPD/sb.json" "$TMPD/sb-env.json"
assert_eq "$?" "0" "PERMISSION_MODE=sandbox 与 --sandbox 产物字节一致"
PERMISSION_MODE=headless bash "$GEN" "$TMPD/hl-env.json" </dev/null 2>/dev/null
cmp -s "$TMPD/hl.json" "$TMPD/hl-env.json"
assert_eq "$?" "0" "PERMISSION_MODE=headless 与 --headless 产物字节一致"
PERMISSION_MODE=bogus bash "$GEN" "$TMPD/bogus.json" </dev/null 2>/dev/null
[ "$?" -ne 0 ]
assert_eq "$?" "0" "非法 PERMISSION_MODE 报错退出"

echo "== ② 沙箱断言: 网络红线仍在, 本机破坏类已删, 兜底放行 =="
assert_eq "$(jget "$TMPD/sb.json" 'git push --force*')" "deny" "沙箱: force-push(全拼)仍 deny"
assert_eq "$(jget "$TMPD/sb.json" 'git push -f *')" "deny" "沙箱: force-push(-f)仍 deny"
assert_eq "$(jget "$TMPD/sb.json" 'curl*|*sh')" "deny" "沙箱: curl|sh 仍 deny"
assert_eq "$(jget "$TMPD/sb.json" 'wget*|*sh')" "deny" "沙箱: wget|sh 仍 deny"
assert_eq "$(jget "$TMPD/sb.json" 'cat >> ~/.ssh/authorized_keys*')" "deny" "沙箱: authorized_keys 持久化仍 deny"
assert_eq "$(jget "$TMPD/sb.json" 'gh release create*')" "deny" "沙箱: gh release create 仍 deny"
assert_eq "$(jget "$TMPD/sb.json" '*')" "allow" "沙箱: * 兜底=allow(docker/pip/npm 免弹窗)"
assert_eq "$(jget "$TMPD/sb.json" 'rm -rf *')" "<absent>" "沙箱: rm -rf 红线已删(隔离边界覆盖)"
assert_eq "$(jget "$TMPD/sb.json" 'mkfs*')" "<absent>" "沙箱: mkfs 红线已删"
assert_eq "$(jget "$TMPD/sb.json" 'git reset --hard*')" "<absent>" "沙箱: git reset --hard 红线已删"
assert_eq "$(jget "$TMPD/sb.json" 'sudo rm*')" "<absent>" "沙箱: sudo rm 红线已删"
assert_eq "$(jget "$TMPD/sb.json" 'crontab -r*')" "<absent>" "沙箱: crontab -r 红线已删"
assert_eq "$(jget "$TMPD/sb.json" 'docker run *')" "<absent>" "沙箱: docker 无显式键(走 * 兜底)"

echo "== ③ 交互档位问句(pty 真终端) =="
RC="$(pty_run $'\n' "$TMPD/pty1.json")"
assert_eq "$RC" "0" "问句-回车: exit 0"
PTY1="$(cat "$TMPD/pty.out" 2>/dev/null || true)"
assert_contains "$PTY1" "权限档位" "问句-回车: 档位横幅出现"
assert_contains "$PTY1" "选择 [1]:" "问句-回车: 默认提示 [1]"
assert_contains "$PTY1" "标准" "问句-回车: 回显标准档"
assert_eq "$(jtotal "$TMPD/pty1.json" bash)" "59" "问句-回车: 产物=交互版 59 条"

RC="$(pty_run $'2\n' "$TMPD/pty2.json")"
assert_eq "$RC" "0" "问句-选 2: exit 0"
PTY2="$(cat "$TMPD/pty.out" 2>/dev/null || true)"
assert_contains "$PTY2" "权限档位" "问句-选 2: 档位横幅出现"
assert_contains "$PTY2" "沙箱" "问句-选 2: 回显沙箱档"
cmp -s "$TMPD/pty2.json" "$TMPD/sb.json"
assert_eq "$?" "0" "问句-选 2: 产物与 --sandbox 字节一致(等价)"

RC="$(pty_run $'x\ny\nz\n' "$TMPD/pty3.json")"
assert_eq "$RC" "0" "问句-非法×3: exit 0"
PTY3="$(cat "$TMPD/pty.out" 2>/dev/null || true)"
assert_contains "$PTY3" "无效" "问句-非法×3: 逐次提示无效"
assert_contains "$PTY3" "3 次" "问句-非法×3: 超限提示"
assert_eq "$(jtotal "$TMPD/pty3.json" bash)" "59" "问句-非法×3: 超限回退标准档"

echo "== ③b setup 形态调用(stdin 未重定向/输出全吞, 提示走 /dev/tty) =="
# 精确复刻 setup-opencode.sh 步骤12: 命令替换 + >/dev/null 2>&1, 仅 stdin 是终端
python3 - "$GEN" "$TMPD/setup-shape.json" "$TMPD/pty.out" << 'PY'
import os, pty, select, sys, time
gen, out, outf = sys.argv[1], sys.argv[2], sys.argv[3]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-c",
        f'X=$(bash "{gen}" "{out}" >/dev/null 2>&1); echo "INNER_RC=$?"'])
os.write(fd, b"\n")
data = b""
deadline = time.time() + 15
while time.time() < deadline:
    r,_,_ = select.select([fd],[],[],1.0)
    if r:
        try: c = os.read(fd, 4096)
        except OSError: break
        if not c: break
        data += c
    else:
        w,_ = os.waitpid(pid, os.WNOHANG)
        if w: break
_, st = os.waitpid(pid, 0)
open(outf, "wb").write(data)
print(os.waitstatus_to_exitcode(st))
PY
SETUP_SHAPE="$(cat "$TMPD/pty.out" 2>/dev/null || true)"
assert_contains "$SETUP_SHAPE" "INNER_RC=0" "setup 形态: 内层 exit 0"
assert_contains "$SETUP_SHAPE" "权限档位" "setup 形态: 输出被吞仍可见(经 /dev/tty)"
assert_eq "$(jtotal "$TMPD/setup-shape.json" bash)" "59" "setup 形态: 回车=标准档 59 条"

echo "== ④ 非交互零变化(管道//dev/null 不问不读) =="
printf '2\n' | bash "$GEN" "$TMPD/pipe.json" 2>"$TMPD/pipe.err"
assert_eq "$?" "0" "管道喂 2: exit 0"
cmp -s "$TMPD/std.json" "$TMPD/pipe.json"
assert_eq "$?" "0" "管道喂 2: 输入被忽略, 产物=标准档(字节一致)"
assert_not_contains "$(cat "$TMPD/pipe.err")" "权限档位" "管道: 无档位问句"
assert_not_contains "$(cat "$TMPD/std.err")" "权限档位" "/dev/null: 无档位问句"

echo "== ⑤ -h 三态帮助 =="
bash "$GEN" -h > "$TMPD/help.txt" 2>&1 </dev/null
HELP="$(cat "$TMPD/help.txt")"
assert_contains "$HELP" "交互选档" "-h: 默认档=交互选档(问档位)"
assert_contains "$HELP" "--headless" "-h: 列出 --headless"
assert_contains "$HELP" "--sandbox" "-h: 列出 --sandbox"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" = "0" ] || exit 1
exit 0
