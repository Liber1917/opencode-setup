#!/usr/bin/env bash
# opencode-setup · C 方向集成模块(可选装)
# 依据 spec C-5: 集成而非自研
#   通道① 用户偏好/recall → 本地记忆 docs/memory/(零依赖零外发;粘合
#          murillovp/persistent-memory + LuciferForge/claude-code-memory,均 MIT)
#          —— mem0 三件套(CLI/MCP/collector 云端链)已于 2026-09 退役
#   通道② 流程改进      → SkillOpt-Sleep(MIT, 官方支持 OpenCode transcripts)
# 用法: c-modules-setup.sh [--mem0] [--skillopt] [--all]
#   默认交互询问; 传 flag 直接装(--mem0 为兼容旧调用保留,实装本地记忆)
set -euo pipefail

INSTALL_MEMORY=0; INSTALL_SKILLOPT=0
case "${1:-}" in
  --mem0|--memory) INSTALL_MEMORY=1;;
  --skillopt) INSTALL_SKILLOPT=1;;
  --all|"") INSTALL_MEMORY=1; INSTALL_SKILLOPT=1;;
esac

install_local_memory() {
  echo "→ 通道① 用户偏好/recall: 本地记忆 docs/memory/(零依赖零外发)"
  # mem0 三件套(CLI/MCP/collector 部署)退役——云端外发 + npm 半成品审计,改粘合开源原文:
  #   facts.md 热读 + memory-log.jsonl 冷追加 + 50 行 fact-archive 轮换
  #   来源: https://github.com/murillovp/persistent-memory (MIT)
  #   主题模板 + 反记忆清单来源: https://github.com/LuciferForge/claude-code-memory (MIT)
  local src="${TDIR:-$DIR/templates}/memory"
  if [ -d "$src" ]; then
    mkdir -p "$SD/docs/memory"
    local f n=0
    for f in facts.md memory-log.jsonl user_profile.md feedback_style.md project_overview.md reference_links.md; do
      [ -f "$src/$f" ] && cp -n "$src/$f" "$SD/docs/memory/$f" 2>/dev/null || true
      [ -f "$SD/docs/memory/$f" ] && n=$((n+1))   # 在场复核(AGENTS.md 守则: 不数 cp 退出码)
    done
    echo "  ✓ 本地记忆: docs/memory/(facts.md 热读 + memory-log.jsonl 冷追加,零外发) — 初始文件 ${n}/6 在场"
  else
    echo "  ⚠ 模板目录缺席($src), 手动部署: cp -n c-modules/templates/memory/* ~/.config/opencode/docs/memory/"
  fi
  echo "  用法: 开工读 facts.md;偏好/决策/坑 append 进 memory-log.jsonl;grep -i 检索历史"
  echo "  隐私: 记忆全在本地文件,零外发(mem0 云端方案已退役)"

  # ---- mem0 时代残留清理(升级路径) ----
  # ① opencode.json mcp.mem0 条目(npm mem0 MCP server 接线)→ 移除
  local cfg="$SD/opencode.json"
  if [ -f "$cfg" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$cfg" << 'PYEOF' \
      && echo "  ✓ mem0 MCP 残留已清理(如有)" \
      || echo "  ⚠ mem0 MCP 清理失败(opencode.json JSON 损坏?), 手动: 移除 mcp 段 mem0 条目"
import json, os, sys
p = sys.argv[1]
with open(p) as f:
    c = json.load(f)
mcp = c.get("mcp", {})
if "mem0" in mcp:
    del c["mcp"]["mem0"]
    if not c["mcp"]:
        del c["mcp"]
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(c, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, p)
PYEOF
  fi
  # ② 旧版 collector 插件(mem0 add 版,特征 execFileSync('mem0')签名)→ 移除;
  #    新版(本地 jsonl 写入)不含该签名,手动部署的不误伤
  if [ -f "$SD/plugins/mem0-collector.ts" ] && grep -q "execFileSync('mem0'" "$SD/plugins/mem0-collector.ts" 2>/dev/null; then
    rm -f "$SD/plugins/mem0-collector.ts" \
      && echo "  ✓ 旧版 mem0-collector 插件(mem0 add 版)已移除" \
      || echo "  ⚠ 旧版 mem0-collector 移除失败, 手动: rm $SD/plugins/mem0-collector.ts"
  fi
  # ③ plugin 数组 npm mem0-collector 残留(更早版本)→ 移除
  if [ -f "$cfg" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$cfg" << 'PYEOF' \
      && echo "  ✓ plugin 数组已清理 npm mem0-collector 残留(如有)" \
      || echo "  ⚠ plugin 数组清理失败, 手动: 移除 plugin 数组内 mem0-collector"
import json, os, sys
p = sys.argv[1]
with open(p) as f:
    c = json.load(f)
plugins = c.get("plugin", [])
if "mem0-collector" in plugins:
    c["plugin"] = [x for x in plugins if x != "mem0-collector"]
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(c, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, p)
PYEOF
  fi
  # 自动收集(可选): 新版 mem0-collector 改写本地 jsonl+facts 轮换,手动部署:
  #   cp c-modules/mem0-collector/plugin.js ~/.config/opencode/plugins/mem0-collector.ts
}

install_skillopt() {
  echo "→ 通道② 流程改进: SkillOpt-Sleep(MIT)"
  if command -v skillopt-sleep >/dev/null 2>&1; then
    echo "  ✓ skillopt-sleep 已安装"
    return
  fi
  if command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1; then
    PIP=$(command -v pip3 || command -v pip)
    $PIP install skillopt >/dev/null 2>&1 && echo "  ✓ skillopt 安装完成" \
      || echo "  ⚠ 安装失败, 可手动: pip install skillopt"
  else
    echo "  ⚠ 无 pip, 需 python3+pip 环境"
  fi
  echo "  夜间自进化: skillopt-sleep(扫 OpenCode 会话→提炼→验证门控→草稿待审)"
  echo "  设计: 提炼产物进草稿区, 人工审批后才生效(spec C-1 硬门)"
}

# 双通道目录约定(spec C-2; mem0 时代 $SD/memory/ 已由 docs/memory/ 取代)
SD="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
mkdir -p "$SD/skill-drafts"
DIR="$(dirname "$(readlink -f "$0")")"
TDIR="$DIR/templates"
[ -f "$TDIR/skill-draft-README.md" ] && cp -n "$TDIR/skill-draft-README.md" "$SD/skill-drafts/README.md" 2>/dev/null || true
echo "  ✓ 双通道目录: $SD/docs/memory(轻) + $SD/skill-drafts(重,评审后生效)"

[ "$INSTALL_MEMORY" = "1" ] && install_local_memory
[ "$INSTALL_SKILLOPT" = "1" ] && install_skillopt
echo ""
echo "双通道说明( spec C-2 ):"
echo "  通道① recall: 偏好自动收集/手动 echo 进 docs/memory/memory-log.jsonl → 本地记忆(零外发)"
echo "  通道② 改进: skillopt-sleep 夜间提炼 → 草稿区 → 专门评审(重审批)"
