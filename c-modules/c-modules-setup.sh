#!/usr/bin/env bash
# opencode-setup · C 方向集成模块(可选装)
# 依据 spec C-5: 集成而非自研
#   通道① 用户偏好/recall → mem0(Apache-2.0, 原生支持 OpenCode)
#   通道② 流程改进      → SkillOpt-Sleep(MIT, 官方支持 OpenCode transcripts)
# 用法: c-modules-setup.sh [--mem0] [--skillopt] [--all]
#   默认交互询问; 传 flag 直接装
set -euo pipefail

INSTALL_MEMO=0; INSTALL_SKILLOPT=0
case "${1:-}" in
  --mem0) INSTALL_MEMO=1;;
  --skillopt) INSTALL_SKILLOPT=1;;
  --all|"") INSTALL_MEMO=1; INSTALL_SKILLOPT=1;;
esac

install_mem0() {
  echo "→ 通道① 用户偏好/recall: mem0(Apache-2.0)"
  if command -v mem0 >/dev/null 2>&1; then
    echo "  ✓ mem0 已安装: $(mem0 --version 2>/dev/null || echo OK)"
  elif command -v npm >/dev/null 2>&1; then
    npm install -g @mem0/cli >/dev/null 2>&1 && echo "  ✓ mem0 CLI 安装完成" \
      || echo "  ⚠ 安装失败, 可手动: npm install -g @mem0/cli"
  else
    echo "  ⚠ 无 npm, 可用 pip: pip install mem0-cli"
  fi
  echo "  初始化(免注册,Agent Mode 自助签发免费 key): mem0 init --agent --agent-caller opencode"
  echo "  用法: mem0 add '偏好' / mem0 search '查询';数据默认存 mem0 云,自托管可设 MEM0_BASE_URL"

  # ---- agent 侧暴露层(裸 CLI agent 不会自发用, 同 MinerU 双路教训) ----
  # 接线依据(不猜): opencode.ai/docs/plugins + 本地插件先例(sp-router.ts/rtk.ts,
  # setup-opencode.sh 实测)——plugins/ 顶层 .ts 自动发现;plugin 数组只认 npm 包。
  # mem0 MCP 走 npm 包 → 数组/mcp 段接线;自动收集改自研本地插件(npm
  # mem0-collector@0.7.0 半成品退役:TUI 静默/不写 mem0/只落 pending_sync 队列,
  # 源码审计三环断裂——自研闭合, 见 c-modules/mem0-collector/plugin.js)。
  local cfg="$SD/opencode.json"
  if [ -f "$cfg" ] && command -v python3 >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
    python3 - "$cfg" << 'PYEOF' \
      && echo "  ✓ mem0 MCP 已接线(agent 可调 add/search 记忆工具)" \
      || echo "  ⚠ mem0 MCP 合并失败(opencode.json JSON 损坏?), 手动: mcp 段加 mem0 条目(npx -y @mem0/mcp-server)"
import json, os, sys
p = sys.argv[1]
with open(p) as f:
    c = json.load(f)
c.setdefault("mcp", {})
c["mcp"]["mem0"] = {"type": "local", "command": ["npx", "-y", "@mem0/mcp-server"], "enabled": True}
tmp = p + ".tmp"
with open(tmp, "w") as f:
    json.dump(c, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, p)
PYEOF
  else
    echo "  ⚠ 跳过 mem0 MCP 接线(缺 opencode.json/python3/npx 之一), 不阻断"
  fi
  # 自研 collector 本地插件部署: plugins/ 顶层 .ts 唯一正确形态(.mjs 毒丸),
  # 不进 plugin 数组(sp-router.ts/rtk.ts 先例);幂等(cp 覆盖同内容)
  if [ -n "${MEM0_COLLECTOR_SRC:-}" ]; then
    mkdir -p "$SD/plugins"
    # 管道部署回退: 源文件不在场(单文件拉取时 plugin.js 缺席)——从远端补拉(镜像链)
    if [ ! -f "$MEM0_COLLECTOR_SRC" ]; then
      _mc_tmp="$(mktemp /tmp/mem0-collector-XXXXXX.mjs)"
      curl -fsSL --max-time 30 "https://gh-proxy.com/https://raw.githubusercontent.com/Liber1917/opencode-setup/main/c-modules/mem0-collector/plugin.js" -o "$_mc_tmp" 2>/dev/null \
        || curl -fsSL --max-time 30 "https://raw.githubusercontent.com/Liber1917/opencode-setup/main/c-modules/mem0-collector/plugin.js" -o "$_mc_tmp" 2>/dev/null || true
      if [ -s "$_mc_tmp" ] && node --check "$_mc_tmp" 2>/dev/null; then
        MEM0_COLLECTOR_SRC="$_mc_tmp"
        echo "  - 管道模式: plugin.js 从远端补拉成功"
      else
        rm -f "$_mc_tmp" 2>/dev/null || true
      fi
    fi
    if [ -f "$MEM0_COLLECTOR_SRC" ] && cp "$MEM0_COLLECTOR_SRC" "$SD/plugins/mem0-collector.ts" 2>/dev/null \
      && [ -f "$SD/plugins/mem0-collector.ts" ]; then
      echo "  ✓ mem0-collector 自研插件已部署 → plugins/mem0-collector.ts(session.idle 启发式收集 → mem0 add → 下次会话 TUI 知会)"
    else
      echo "  ⚠ 跳过 mem0-collector 部署(源文件缺席且远端补拉失败), 不阻断"
    fi
  else
    echo "  ⚠ 跳过 mem0-collector 部署(MEM0_COLLECTOR_SRC 未设), 不阻断"
  fi
  # 旧版残留迁移: plugin 数组曾登记 npm mem0-collector → 移除(本地插件不进数组)
  if [ -f "$cfg" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$cfg" << 'PYEOF' \
      && echo "  ✓ plugin 数组已清理 npm mem0-collector 残留(如有)" \
      || echo "  ⚠ plugin 数组清理失败(opencode.json JSON 损坏?), 手动: 移除 plugin 数组内 mem0-collector"
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
  echo "  隐私: 记忆数据存 mem0 云端(Agent Mode 免费 key);介意可 MEM0_BASE_URL 自托管;collector 密钥样文本一律不提取"
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

# 双通道目录约定(spec C-2)
SD="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
mkdir -p "$SD/memory" "$SD/skill-drafts"
DIR="$(dirname "$(readlink -f "$0")")"
TDIR="$DIR/templates"
MEM0_COLLECTOR_SRC="${MEM0_COLLECTOR_SRC:-$DIR/mem0-collector/plugin.js}"
[ -f "$TDIR/memory-preferences.md" ] && cp -n "$TDIR/memory-preferences.md" "$SD/memory/preferences.md" 2>/dev/null || true
[ -f "$TDIR/skill-draft-README.md" ] && cp -n "$TDIR/skill-draft-README.md" "$SD/skill-drafts/README.md" 2>/dev/null || true
echo "  ✓ 双通道目录: $SD/memory(轻) + $SD/skill-drafts(重,评审后生效)"

[ "$INSTALL_MEMO" = "1" ] && install_mem0
[ "$INSTALL_SKILLOPT" = "1" ] && install_skillopt
echo ""
echo "双通道说明( spec C-2 ):"
echo "  通道① recall: 会话中 mem0 add '记住X' → 用户级 memory(轻审批/可撤销)"
echo "  通道② 改进: skillopt-sleep 夜间提炼 → 草稿区 → 专门评审(重审批)"
