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
    return
  fi
  if command -v npm >/dev/null 2>&1; then
    npm install -g @mem0/cli >/dev/null 2>&1 && echo "  ✓ mem0 CLI 安装完成" \
      || echo "  ⚠ 安装失败, 可手动: npm install -g @mem0/cli"
  else
    echo "  ⚠ 无 npm, 可用 pip: pip install mem0-cli"
  fi
  echo "  初始化: mem0 init --agent --agent-caller opencode(需注册, 可选)"
  echo "  用法: mem0 add '偏好' / mem0 search '查询'"
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

[ "$INSTALL_MEMO" = "1" ] && install_mem0
[ "$INSTALL_SKILLOPT" = "1" ] && install_skillopt
echo ""
echo "双通道说明( spec C-2 ):"
echo "  通道① recall: 会话中 mem0 add '记住X' → 用户级 memory(轻审批/可撤销)"
echo "  通道② 改进: skillopt-sleep 夜间提炼 → 草稿区 → 专门评审(重审批)"
