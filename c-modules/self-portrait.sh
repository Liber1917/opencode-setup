#!/usr/bin/env bash
# opencode-setup · C-Ⅰ 自我画像(self-portrait) v2
# 依据: specs/C-embodiment.md C-1/C-5(复用 B 架构, 读 opencode 运行时)
# 边界: 密钥永不入画像(C-1 硬约束);输出 0600
# v2 修复: C-1(shell 变量不再内插进 python 源码,全走环境变量) C-2(except 收窄+报错可见) C-3(表头过滤)
set -euo pipefail
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OUT="${SELF_PORTRAIT_OUT:-$CONFIG_DIR/self-portrait.json}"

# 从 opencode 运行时读模型/能力(不碰 auth/key 字段)
if command -v opencode >/dev/null 2>&1; then
  SP_MODELS=$(timeout 20 opencode models 2>/dev/null | tail -n +2 | sed 's/\x1b\[[0-9;]*m//g' | head -30 || echo "")
else
  SP_MODELS=""
fi
export SP_CONFIG_DIR="$CONFIG_DIR" SP_MODELS SP_OUT="$OUT"

python3 << 'PYSP'
import json,os,sys,datetime
cfg=os.environ["SP_CONFIG_DIR"]

def safe_json(p, fn, default):
    try:
        return fn(json.load(open(p)))
    except Exception as e:  # C-2: 收窄+日志可见
        print(f"  ⚠ 解析 {os.path.basename(p)} 失败: {e}", file=sys.stderr)
        return default

agents = safe_json(f"{cfg}/oh-my-openagent.json",
    lambda c: {k: v.get("model", "跟随主配置") for k, v in c.get("agents", {}).items()}, {})
oc = safe_json(f"{cfg}/opencode.json", lambda c: c, {})
mcp = list(oc.get("mcp", {}).keys())
perm = oc.get("permission", {}).get("bash", {})
if isinstance(perm, str):
    perm_summary = {"bash": f"all-{perm}"}
else:
    perm_summary = {"bash_rules": len(perm),
                    "deny": sum(1 for v in perm.values() if v == "deny"),
                    "ask": sum(1 for v in perm.values() if v == "ask"),
                    "allow": sum(1 for v in perm.values() if v == "allow")}

skills_dir = f"{cfg}/skills"
skills = len([d for d in (os.listdir(skills_dir) if os.path.isdir(skills_dir) else [])
              if os.path.isdir(os.path.join(skills_dir, d))])  # C-5: 只数目录

models = [m for m in os.environ.get("SP_MODELS", "").splitlines() if m.strip()]

portrait = {
    "generated": datetime.datetime.now().isoformat(timespec="seconds"),
    "note": "密钥永不入画像(spec C-1)",
    "available_models": models,
    "agent_routing": agents,
    "skills_installed": skills,
    "mcp_servers": mcp,
    "permission_summary": perm_summary,
}
out = os.environ["SP_OUT"]
tmp = out + ".tmp"
json.dump(portrait, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
os.replace(tmp, out)
print(f"✓ self-portrait → {out}")
PYSP
chmod 600 "$OUT" 2>/dev/null || true
