#!/usr/bin/env bash
# opencode-setup · E-Ⅲ 出环硬门控 v1 (evidence-gated completion)
# 落地完成时幻觉调研(arXiv 2606.09863): 宣称完成时由独立于推理环的脚本复核,
# 双控(推理环内自评 + 环外机器复核)把假成功 44-52% → 3%。
# AGENTS.md 在场守则的机器执行层: 不信"应该成功了",只认 command -v / 文件存在 / 测试退出码。
#
# 子命令:
#   check  [workdir] [选项]  阻断模式: 任一项失败 → 退出码 1(/completion-gate 调用)
#   report [workdir] [选项]  报告模式: 同样输出,恒退出 0(不阻断人工收尾)
# 挂载形态说明: opencode 1.18.29 的 config schema 无 event 键且实测(含 TUI)不触发
#   event 命令,无 Stop/session.idle 等价事件 → 挂 /completion-gate 斜杠命令
#   (commands/completion-gate.md),由 setup 步骤 12 部署。
# 选项:
#   --session <id>         指定会话 ID(默认: DB 中 directory 匹配 workdir 的最新会话)
#   --message <text>       内联"最后一条 assistant 消息"(测试/CI 注入口)
#   --message-file <file>  同上,从文件读
set -uo pipefail

DB_PATH="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
# 声明复核的名词→在场检查映射(硬编码小批,诚实覆盖;扩展在此追加)
# 格式: 名词=检查命令 的命令名;缺省查 command -v <名词>
NOUN_CMDS="opencode mineru skillopt=skillopt-sleep mem0 rtk codegraph bun node"

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

MODE="${1:-}"
case "$MODE" in
  check|report|-h|--help) ;;
  *) echo "用法: $(basename "$0") check|report [workdir] [--session id] [--message text] [--message-file f]" >&2
     [ "$MODE" = "" ] || echo "未知子命令: $MODE" >&2
     exit 2 ;;
esac
[ "$MODE" = "-h" ] || [ "$MODE" = "--help" ] && usage 0
shift

WORKDIR=""
SESSION_ID=""
MESSAGE_TEXT=""
MESSAGE_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session) SESSION_ID="${2:-}"; shift 2 ;;
    --message) MESSAGE_TEXT="${2:-}"; shift 2 ;;
    --message-file) MESSAGE_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage 0 ;;
    -*) echo "未知选项: $1" >&2; exit 2 ;;
    *) if [ -z "$WORKDIR" ]; then WORKDIR="$1"; else echo "多余参数: $1" >&2; exit 2; fi; shift ;;
  esac
done
WORKDIR="${WORKDIR:-$PWD}"
[ -d "$WORKDIR" ] || { echo "✗ 工作目录不存在: $WORKDIR" >&2; exit 2; }

# ---------------------------------------------------------------------------
# 会话证据提取: SQLite → {session, edited, text}
#   edited: 会话中是否用过 edit/write/patch 工具(判定"agent 编辑过文件")
#   text:   最后一条 assistant 消息的全部文本部分
# 无 python3 / 无 DB / 无匹配会话 → edited=null, text=""
# ---------------------------------------------------------------------------
read_session_evidence() {
  command -v python3 >/dev/null 2>&1 || { echo '{"session":null,"edited":null,"text":""}'; return; }
  python3 - "$DB_PATH" "$WORKDIR" "$SESSION_ID" << 'PYEV' 2>/dev/null || echo '{"session":null,"edited":null,"text":""}'
import json, os, sqlite3, sys
db_path, workdir, session_id = sys.argv[1], sys.argv[2], sys.argv[3]
out = {"session": None, "edited": None, "text": ""}
try:
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    if not session_id:
        row = db.execute(
            "select id from session where directory=? order by time_updated desc limit 1",
            (os.path.realpath(workdir),)).fetchone()
        session_id = row[0] if row else ""
    if session_id:
        exists = db.execute("select 1 from session where id=?", (session_id,)).fetchone()
        if exists:
            out["session"] = session_id
            n = db.execute(
                """select count(*) from part where session_id=?
                   and json_extract(data,'$.type')='tool'
                   and json_extract(data,'$.tool') in ('edit','write','patch')""",
                (session_id,)).fetchone()[0]
            out["edited"] = n > 0
            msg = db.execute(
                """select id from message where session_id=?
                   and json_extract(data,'$.role')='assistant'
                   order by time_created desc limit 1""", (session_id,)).fetchone()
            if msg:
                parts = db.execute(
                    """select data from part where message_id=?
                       and json_extract(data,'$.type')='text' order by time_created""",
                    (msg[0],)).fetchall()
                out["text"] = "\n".join(json.loads(p[0]).get("text", "") for p in parts)
except Exception:
    pass
print(json.dumps(out, ensure_ascii=False))
PYEV
}

EVIDENCE="$(read_session_evidence)"
EV_SESSION="$(printf '%s' "$EVIDENCE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("session") or "")' 2>/dev/null || true)"
EV_EDITED="$(printf '%s' "$EVIDENCE" | python3 -c 'import json,sys; v=json.load(sys.stdin).get("edited"); print("null" if v is None else str(v).lower())' 2>/dev/null || echo null)"
EV_TEXT="$(printf '%s' "$EVIDENCE" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin).get("text") or "")' 2>/dev/null || true)"
[ -n "$MESSAGE_FILE" ] && EV_TEXT="$(cat "$MESSAGE_FILE" 2>/dev/null || true)"
[ -n "$MESSAGE_TEXT" ] && EV_TEXT="$MESSAGE_TEXT"

declare -a OUT_LINES
declare -i NFAIL=0
add() { OUT_LINES+=("$1"); }

# --- ① git 卫生: 有未提交变更且会话中 agent 编辑过文件 → 未过 -------------
check_git() {
  local dirty
  git -C "$WORKDIR" rev-parse --git-dir >/dev/null 2>&1 || { add "[-] git 卫生   非 git 仓库,跳过"; return; }
  dirty="$(git -C "$WORKDIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$dirty" = "0" ]; then
    add "[✓] git 卫生   工作区干净"
  elif [ "$EV_EDITED" = "true" ]; then
    add "[✗] git 卫生   ${dirty} 处未提交变更,且会话有 edit/write 工具记录——宣称完成前需 commit 或说明"
    NFAIL+=1
  else
    local basis
    if [ -n "$EV_SESSION" ]; then basis="会话 $EV_SESSION 无 edit/write 记录"; else basis="未定位到会话"; fi
    add "[-] git 卫生   ${dirty} 处未提交变更,但无会话编辑证据($basis)——人工确认是否需提交"
  fi
}

# --- ② 测试通过: 检出测试痕迹即跑(timeout -s KILL 300),非零 → 未过 -------
check_tests() {
  local cmd="" how=""
  if [ -f "$WORKDIR/package.json" ] && python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("scripts",{}).get("test") else 1)' "$WORKDIR/package.json" 2>/dev/null; then
    if command -v npm >/dev/null 2>&1; then cmd="npm test"; how="package.json scripts.test"
    elif command -v bun >/dev/null 2>&1; then cmd="bun run test"; how="package.json scripts.test"
    else add "[✗] 测试通过   检出 package.json test 脚本但无 npm/bun 运行器"; NFAIL+=1; return; fi
  elif [ -f "$WORKDIR/Makefile" ] && grep -qE '^test[a-z0-9_-]*:' "$WORKDIR/Makefile"; then
    command -v make >/dev/null 2>&1 || { add "[✗] 测试通过   检出 Makefile test 目标但无 make"; NFAIL+=1; return; }
    cmd="make test"; how="Makefile test"
  elif python3 - "$WORKDIR" << 'PYPY' 2>/dev/null
import glob, os, sys
w = sys.argv[1]
traces = [f for f in (os.path.join(w, "pytest.ini"), os.path.join(w, "conftest.py")) if os.path.isfile(f)]
traces += glob.glob(os.path.join(w, "tests", "test_*.py")) + glob.glob(os.path.join(w, "test", "test_*.py"))
pyproject = os.path.join(w, "pyproject.toml"); setupcfg = os.path.join(w, "setup.cfg")
for f in (pyproject,):
    if os.path.isfile(f):
        txt = open(f, encoding="utf-8", errors="ignore").read()
        if "[tool.pytest.ini_options]" in txt: traces.append(f)
if os.path.isfile(setupcfg):
    txt = open(setupcfg, encoding="utf-8", errors="ignore").read()
    if "[tool:pytest]" in txt: traces.append(setupcfg)
sys.exit(0 if traces else 1)
PYPY
  then
    cmd="python3 -m pytest"; how="pytest 痕迹"
  fi
  if [ -z "$cmd" ]; then
    add "[-] 测试通过   未检出测试痕迹(package.json test / Makefile test / pytest),跳过"
    return
  fi
  local rc tail
  tail="$(mktemp)"
  (cd "$WORKDIR" && timeout -s KILL 300 $cmd) >"$tail" 2>&1 </dev/null
  rc=$?
  if [ "$rc" -eq 0 ]; then
    add "[✓] 测试通过   $how → $cmd 退出码 0"
  else
    add "[✗] 测试通过   $how → $cmd 退出码 $rc$(tail -n 2 "$tail" | sed 's/^/ ⏎ /' | tr '\n' ' ')"
    NFAIL+=1
  fi
  rm -f "$tail"
}

# --- ③ 声明-在场一致性: 扫最后一条 assistant 消息的完成声明,逐名词/文件复核 ---
# 模式: 已安装|已配置|…+名词(≤24 字符间距) / 名词+已… / ✓ 行含名词;
#       已生成|已创建|已写入|已部署 + 文件名(*.sh/*.json/等) → 文件存在性
check_claims() {
  if [ -z "$EV_TEXT" ]; then
    add "[-] 声明-在场  无会话消息源(--message/--message-file 或会话 DB),跳过"
    return
  fi
  local res
  res="$(GATE_MSG="${EV_TEXT:0:65536}" python3 - "$WORKDIR" "$NOUN_CMDS" 2>/dev/null << 'PYCLAIM'
import os, re, shutil, sys
workdir, noun_specs = sys.argv[1], sys.argv[2].split()
VERB = r'已(?:安装|配置|合并|生成|部署|创建|写入|修复|完成|就绪)'
FILE_VERB = r'已(?:生成|创建|写入|部署)'
FILE_RE = r'[A-Za-z0-9_][A-Za-z0-9_./-]*\.(?:sh|json|md|py|ts|js|yaml|yml|toml|env|conf|txt)'
GAP = r'[^\n。;,，；]{0,24}'
msg = os.environ.get("GATE_MSG", "")
ok, missing = [], []
def claim_present(item, check):
    (ok if check else missing).append(item)
for spec in noun_specs:
    noun, _, cmd = spec.partition("=")
    if not re.search(VERB + GAP + re.escape(noun), msg) and not re.search(re.escape(noun) + GAP + VERB, msg) \
       and not any(noun in line for line in msg.splitlines() if "✓" in line):
        continue
    claim_present(noun, shutil.which(cmd or noun) is not None)
files = set()
for m in re.finditer(FILE_VERB + r'[^\n。;,，；]{0,48}', msg):
    files.update(f.group(0) for f in re.finditer(FILE_RE, m.group(0)))
for m in re.finditer(FILE_RE + r'[^\n。;,，；]{0,24}' + FILE_VERB, msg):
    files.add(m.group(1))
for f in files:
    claim_present(f, os.path.exists(os.path.join(workdir, f)) or os.path.exists(f))
known = {s.partition("=")[0] for s in noun_specs}
known_l = {k.lower() for k in known}
uncovered = []
def _uncovered_from(segment):
    for tok in re.findall(r'[A-Za-z][A-Za-z0-9_-]{2,}', segment):
        if tok.lower() not in known_l and tok not in files and tok not in uncovered:
            uncovered.append(tok)
for m in re.finditer(VERB + r'[^\n。;,，；]{0,24}', msg):
    _uncovered_from(m.group(0))
for m in re.finditer(r'[A-Za-z][A-Za-z0-9_-]{2,}[^\n。;,，；]{0,24}' + VERB, msg):
    _uncovered_from(m.group(0))
if missing: print("MISSING:" + "、".join(missing))
if ok: print("OK:" + "、".join(ok))
if uncovered: print("UNCOVERED:" + "、".join(sorted(uncovered)))
if not (missing or ok or uncovered):
    print("NONE:名词映射覆盖: " + "、".join(s.partition("=")[0] for s in noun_specs) + ";文件名模式 " + FILE_RE)
PYCLAIM
)"
  if [ -z "$res" ]; then
    add "[-] 声明-在场  声明解析器不可用(需 python3),跳过"
    return
  fi
  local miss_nouns ok_nouns unc_nouns
  miss_nouns="$(printf '%s\n' "$res" | grep '^MISSING:' | head -1 | cut -d: -f2-)"
  ok_nouns="$(printf '%s\n' "$res" | grep '^OK:' | head -1 | cut -d: -f2-)"
  unc_nouns="$(printf '%s\n' "$res" | grep '^UNCOVERED:' | head -1 | cut -d: -f2-)"
  if [ -n "$miss_nouns" ]; then
    add "[✗] 声明-在场  声明不在场: $miss_nouns——以 command -v / 文件存在为准,不得宣称完成"; NFAIL+=1
  elif [ -n "$ok_nouns" ]; then
    add "[✓] 声明-在场  $ok_nouns 声明均在场"
  elif [ -n "$unc_nouns" ]; then
    add "[-] 声明-在场  已知名词无命中,声明疑为映射外名词(见下)"
  else
    add "[-] 声明-在场  未检出完成声明($(printf '%s\n' "$res" | grep '^NONE:' | cut -d: -f2-))"
  fi
  # 诚实原则: 声明了映射外名词必须亮出"未验证",不许静默略过(AGENTS.md 在场守则)
  [ -n "$unc_nouns" ] && add "[!] 声明-在场  未覆盖名词(未验证): $unc_nouns——不在名词映射内,人工复核或扩充映射"
}

# --- ④ 明文密钥: 扫暂存/未提交文件(非 git 仓库则扫浅层文件) ---------------
check_secrets() {
  local files hit masked scope
  if git -C "$WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
    files="$(git -C "$WORKDIR" status --porcelain 2>/dev/null | sed -e 's/^...//' -e 's/.* -> //' -e 's/^"//' -e 's/"$//')"
    scope="git 未提交/未跟踪文件"
  else
    files="$(cd "$WORKDIR" && find . -maxdepth 3 -type f -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | sed 's|^\./||')"
    scope="非 git 仓库浅层文件"
  fi
  hit=""; skip_tests=0
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$WORKDIR/$f" ] || continue
    # 测试夹具豁免: tests?/ 目录或 test-*/*_test* 文件名默认跳过(内含假密钥是常态),
    # 豁免必须可见;GATE_STRICT_SECRETS=1 全量扫(真机教训: 自家测试的 sk-abcdefghij 被误拦)
    if [ "${GATE_STRICT_SECRETS:-0}" != "1" ] \
       && { printf '%s' "$f" | grep -qE '(^|/)(tests?|__tests__)/|(^|/)(test-[^/]*|[^/]*_test)\.[a-z]+$'; }; then
      skip_tests=$((skip_tests+1)); continue
    fi
    m="$(grep -hoE 'sk-[A-Za-z0-9]{20,}' "$WORKDIR/$f" 2>/dev/null | head -1)"
    [ -n "$m" ] && hit+="$f:${m:0:8}*** "
  done << EOF
$files
EOF
  if [ -n "$hit" ]; then
    add "[✗] 明文密钥   $hit——收尾前移除或改用环境变量"
    NFAIL+=1
  else
    add "[✓] 明文密钥   未检出 sk- 明文密钥(扫描范围: $scope;跳过测试夹具 $skip_tests 个,GATE_STRICT_SECRETS=1 全量扫)"
  fi
}

check_git
check_tests
check_claims
check_secrets

SEP="────────────────────────────────────────────"
REPORT="completion-gate: $WORKDIR(会话: ${EV_SESSION:-未定位})"
REPORT+=$'\n'"$(printf '%s\n' "${OUT_LINES[@]}")"
if [ "$NFAIL" -gt 0 ]; then
  REPORT+=$'\n'"结果: FAIL——$NFAIL 项未过,未过前不得宣称完成(exit 1)"
  FINAL_RC=1
else
  REPORT+=$'\n'"结果: PASS——四通道复核通过(exit 0)"
  FINAL_RC=0
fi

case "$MODE" in
  check) printf '%s\n%s\n' "$SEP" "$REPORT" >&2; exit "$FINAL_RC" ;;
  report) printf '%s\n%s\n' "$SEP" "$REPORT" >&2
          [ "$NFAIL" -gt 0 ] && printf '(report 模式: 仅报告不阻断)\n' >&2
          exit 0 ;;
esac
