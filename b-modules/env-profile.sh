#!/usr/bin/env bash
# opencode-setup · B-Ⅰ 环境画像(env-profile)
# 依据: specs/B-environment.md Phase 1(静态核心)
# 产出: $CONFIG_DIR/env-profile.md(agent 可读的环境摘要)
# 设计决策(评审确认): 按需读取(非自动注入) + 探测走审计
set -euo pipefail
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OUT="$CONFIG_DIR/env-profile.md"

ARCH=$(uname -m); KERNEL=$(uname -r | cut -d- -f1)
OS_ID=$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo unknown)
OS_VER=$(grep -E '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
PRIV=$([ "$(id -u)" = 0 ] && echo root || echo user)
PKG=none; for p in apt-get yum dnf brew apk pacman; do command -v $p >/dev/null 2>&1 && PKG=$p && break; done

TOOLS=""
for t in node npm bun git curl unzip python3 pip3 codegraph rtk opencode jq make gcc rg; do
  V=$(command -v "$t" >/dev/null 2>&1 && timeout 10 "$t" --version 2>/dev/null | head -1) || V=""
  [ -n "$V" ] && TOOLS="$TOOLS- $t ($V)"$'\n'
done

NPM_REG=""; command -v npm >/dev/null 2>&1 && NPM_REG=$(npm config get registry 2>/dev/null || echo "")

cat > "$OUT" << EOF
# 环境画像 (env-profile)

> 生成: $(date '+%Y-%m-%d %H:%M') · 刷新: bash env-profile.sh(或删除本文件后重跑 setup)
> 用途: agent 会话开始时可按需读取,避免"不知道环境里有啥"(Terminal-Bench: 24.1% 失败源于环境无知)

## 系统
- OS: $OS_ID $OS_VER ($ARCH, kernel $KERNEL)
- 权限: $PRIV
- 包管理器: $PKG

## 可用工具
${TOOLS:-(- 无)}## 镜像
- npm registry: ${NPM_REG:-未配置}

## 深度认知工具就绪状态
$(command -v codegraph >/dev/null 2>&1 && {
  if [ -d .codegraph ] || [ -L .codegraph ]; then
    echo "- codegraph: 已就绪(项目已 init)→ 遇到'谁调用X/X怎么工作'优先查 codegraph"
  else
    echo "- codegraph: 已安装未 init → 深度结构理解前建议先运行 codegraph init"
  fi
} || echo "- codegraph: 未安装 → 结构理解靠 glob/grep")

## 建议
- 执行命令前先用 command -v 确认工具存在;缺失时提示安装或走包管理器($PKG)
EOF

chmod 644 "$OUT"
echo "✓ 环境画像 → $OUT" >&2
