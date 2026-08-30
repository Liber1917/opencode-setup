#!/usr/bin/env bash
# opencode-setup · E-Ⅱ 审计模块 v2 (observe-only)
# 修复: A-1(JSONL python json.dumps 组装) + A-2(真连续 deny 熔断) + A-3(接线原子写)
set -euo pipefail
AUDIT_DIR="${OPENCODE_AUDIT_DIR:-$HOME/.local/share/opencode-audit}"
LOG="$AUDIT_DIR/audit.jsonl"
MAX_BYTES=$((10*1024*1024)); KEEP=3; MAX_AGE_DAYS=30

init() {
  mkdir -p "$AUDIT_DIR"
  cat > "$AUDIT_DIR/hook.sh" << 'HOOK'
#!/usr/bin/env bash
set -euo pipefail
DIR="${OPENCODE_AUDIT_DIR:-$(dirname "$(readlink -f "$0")")}"
LOG="$DIR/audit.jsonl"
TYPE="$1"; TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
INPUT=$(cat 2>/dev/null || echo '{}')
python3 - "$TYPE" "$TS" "$INPUT" >> "$LOG" << 'PYAUDIT' 2>/dev/null || echo '{"parse":"fail"}' >> "$LOG"
import json,sys,re
etype,ts,raw=sys.argv[1],sys.argv[2],sys.argv[3]
try: d=json.loads(raw or "{}")
except Exception: d={}
g=lambda k:(d.get(k) if isinstance(d.get(k),str) else "null")
cmd=str(d.get("command") or d.get("input") or "")
cmd=re.sub(r"(sk-[A-Za-z0-9_-]{8})[A-Za-z0-9_-]+",r"\1***",cmd)
cmd=re.sub(r"(Bearer\s+[A-Za-z0-9_.-]{8})[A-Za-z0-9_.-]+",r"\1***",cmd)
print(json.dumps({"ts":ts,"src":etype,"session":g("sessionID"),"tool":g("tool"),"cmd":cmd[:500]},ensure_ascii=False,separators=(",",":")))
PYAUDIT
# 真连续 deny 熔断(末尾连续计数)
[ "$TYPE" = "deny" ] && command -v python3 >/dev/null 2>&1 && \
python3 - "$LOG" >> "$DIR/alerts.jsonl" 2>/dev/null << 'PYCB' || true
import json,sys,datetime
try:
    rows=[json.loads(l) for l in open(sys.argv[1]).readlines()[-30:] if l.strip()]
    rows=[r for r in rows if r.get("session") not in (None,"null")]
    n=0
    for r in reversed(rows):
        if r.get("src") in ("deny","reject"): n+=1
        else: break
    if n>=5: print(json.dumps({"ts":datetime.datetime.utcnow().isoformat(timespec="seconds")+"Z","alert":"circuit-breaker","session":rows[-1]["session"],"consecutive_denies":n}))
except Exception: pass
PYCB
HOOK
  chmod +x "$AUDIT_DIR/hook.sh"
  CFG="$HOME/.config/opencode/opencode.json"
  if command -v python3 >/dev/null 2>&1 && [ -f "$CFG" ]; then
    python3 - "$CFG" "$AUDIT_DIR" << 'PYEOF' >/dev/null
import json,sys,os
cfg_path,audit_dir=sys.argv[1],sys.argv[2]
try: c=json.load(open(cfg_path))
except Exception: c={"$schema":"https://opencode.ai/config.json"}
c["event"]={k:[{"type":"command","command":f"{audit_dir}/hook.sh {k.split('.')[1]}"}] for k in ["permission.ask","permission.deny","permission.allow","permission.reject"]}
tmp=cfg_path+".tmp"; json.dump(c,open(tmp,"w"),ensure_ascii=False,indent=1); os.replace(tmp,cfg_path)
PYEOF
    echo "  ✓ 审计 hook 接线(四通道+JSON 安全)" >&2
  else
    echo "  ⚠ 无 python3,手动合并 event 段" >&2
  fi
  echo "✓ 审计目录: $AUDIT_DIR(脱敏+熔断+30天)" >&2
}

rotate() {
  [ -f "$LOG" ] || exit 0
  SIZE=$(stat -c%s "$LOG" 2>/dev/null || stat -f%z "$LOG" 2>/dev/null || echo 0)
  [ "$SIZE" -gt "$MAX_BYTES" ] && {
    for i in $(seq $((KEEP-1)) -1 1); do [ -f "$LOG.$i" ] && mv "$LOG.$i" "$LOG.$((i+1))"; done
    mv "$LOG" "$LOG.1"; echo "✓ 轮转" >&2
  }
  find "$AUDIT_DIR" -name "audit.jsonl*" -mtime +"$MAX_AGE_DAYS" -delete 2>/dev/null || true
}

case "${1:-init}" in
  init) init ;;
  --rotate|rotate) rotate ;;
  *) echo "用法: $0 [init|--rotate]" >&2; exit 1 ;;
esac
