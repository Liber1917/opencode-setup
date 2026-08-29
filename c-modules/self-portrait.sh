#!/usr/bin/env bash
# opencode-setup · C-Ⅰ 自我画像(self-portrait)
# 依据: specs/C-embodiment.md C-1/C-5(复用 B 架构, 读 opencode 运行时)
# 边界: 密钥永不入画像(C-1 硬约束);输出 0600
set -euo pipefail
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OUT="$CONFIG_DIR/self-portrait.json"

# 从 opencode 运行时读模型/能力(不碰 auth/key 字段)
MODELS=$(command -v opencode >/dev/null 2>&1 && timeout 20 opencode models 2>/dev/null | head -30 || echo "[]")

AGENTS=$(python3 -c "
import json,os
p='$CONFIG_DIR/oh-my-openagent.json'
try:
    c=json.load(open(p))
    print(json.dumps({k:v.get('model','跟随主配置') for k,v in c.get('agents',{}).items()},ensure_ascii=False))
except: print('{}')")

SKILLS=$(ls "$CONFIG_DIR/skills" 2>/dev/null | wc -l)
MCP=$(python3 -c "
import json
try:
    c=json.load(open('$CONFIG_DIR/opencode.json'))
    print(json.dumps(list(c.get('mcp',{}).keys())))
except: print('[]')")

PERM_SUMMARY=$(python3 -c "
import json
try:
    c=json.load(open('$CONFIG_DIR/opencode.json'))
    p=c.get('permission',{})
    b=p.get('bash',{})
    if isinstance(b,str): print(json.dumps({'bash':'all-'+b}))
    else:
        print(json.dumps({'bash_rules':len(b),'deny':sum(1 for v in b.values() if v=='deny'),'ask':sum(1 for v in b.values() if v=='ask'),'allow':sum(1 for v in b.values() if v=='allow')}))
except: print('{}')")

python3 -c "
import json,sys
portrait = {
  'generated': __import__('datetime').datetime.now().isoformat(timespec='seconds'),
  'note': '密钥永不入画像(spec C-1)',
  'available_models': '''$MODELS'''.strip().split(chr(10)),
  'agent_routing': json.loads('''$AGENTS'''),
  'skills_installed': $SKILLS,
  'mcp_servers': json.loads('''$MCP'''),
  'permission_summary': json.loads('''$PERM_SUMMARY''')
}
json.dump(portrait, open('$OUT','w'), ensure_ascii=False, indent=1)
print('✓ self-portrait → $OUT')" 2>/dev/null || echo "⚠ 生成失败(检查 python3)"
chmod 600 "$OUT" 2>/dev/null || true
