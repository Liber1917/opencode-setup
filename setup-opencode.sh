#!/bin/bash
# ============================================================================
# OpenCode 一键配置脚本
# 使用 Bun 作为运行时，自动安装所有依赖
# 支持 Linux / macOS / WSL
# ============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  OpenCode 一键配置脚本 (Bun 版)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ------------------------------------------------------------------
# 目录配置（支持环境变量覆盖）
# ------------------------------------------------------------------
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

echo -e "${BLUE}目标目录:${NC}"
echo "  OpenCode: $CONFIG_DIR"
echo "  Claude:   $CLAUDE_DIR"
echo ""

# ------------------------------------------------------------------
# 步骤 1: 检测已有配置
# ------------------------------------------------------------------
echo -e "${YELLOW}[1/7] 检测已有配置...${NC}"

if [ -f "$CONFIG_DIR/opencode.json" ] || [ -f "$CONFIG_DIR/oh-my-openagent.json" ]; then
  echo -e "${YELLOW}⚠ 发现现有配置文件${NC}"
  echo -n "是否备份后重新生成? (y/n) [n]: "
  read -r overwrite
  overwrite=${overwrite:-n}
  if [[ $overwrite =~ ^[Yy]$ ]]; then
    backup_dir="$HOME/opencode-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    [ -f "$CONFIG_DIR/opencode.json" ]         && cp "$CONFIG_DIR/opencode.json"         "$backup_dir/"
    [ -f "$CONFIG_DIR/oh-my-openagent.json" ]   && cp "$CONFIG_DIR/oh-my-openagent.json" "$backup_dir/"
    [ -f "$CONFIG_DIR/package.json" ]           && cp "$CONFIG_DIR/package.json"         "$backup_dir/"
    echo -e "${GREEN}✓ 已备份到: $backup_dir${NC}"
  else
    echo "跳过配置生成，使用现有配置。"
    SKIP_CONFIG=1
  fi
fi

# ------------------------------------------------------------------
# 步骤 2: 创建目录结构
# ------------------------------------------------------------------
echo -e "${YELLOW}[2/7] 创建配置目录...${NC}"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/skills"
mkdir -p "$CLAUDE_DIR"
echo -e "${GREEN}✓ 目录已创建${NC}"

# ------------------------------------------------------------------
# 步骤 3: 生成配置文件
# ------------------------------------------------------------------
if [ "${SKIP_CONFIG:-0}" != "1" ]; then
  echo -e "${YELLOW}[3/7] 生成配置文件...${NC}"

  # opencode.json
  cat > "$CONFIG_DIR/opencode.json" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "oh-my-openagent@latest"
  ],
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "YOUR_API_KEY_HERE",
        "baseURL": "https://api.anthropic.com"
      }
    }
  },
  "permission": {
    "read": {
      "~/.config/opencode/*": "allow",
      "~/.claude/*": "allow"
    },
    "external_directory": {
      "~/.config/opencode/*": "allow",
      "~/.claude/*": "allow"
    }
  }
}
EOF
  echo -e "${GREEN}  ✓ opencode.json${NC}"

  # oh-my-openagent.json
  cat > "$CONFIG_DIR/oh-my-openagent.json" << 'EOF'
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json",
  "agents": {
    "hephaestus": {"model": "anthropic/claude-sonnet-4-6"},
    "oracle": {"model": "anthropic/claude-sonnet-4-6"},
    "librarian": {"model": "anthropic/claude-sonnet-4-6"},
    "explore": {"model": "anthropic/claude-sonnet-4-6"},
    "multimodal-looker": {"model": "anthropic/claude-sonnet-4-6"},
    "prometheus": {"model": "anthropic/claude-sonnet-4-6"},
    "metis": {"model": "anthropic/claude-sonnet-4-6"},
    "momus": {"model": "anthropic/claude-sonnet-4-6"},
    "atlas": {"model": "anthropic/claude-sonnet-4-6"},
    "sisyphus-junior": {"model": "anthropic/claude-sonnet-4-6"}
  },
  "categories": {
    "visual-engineering": {"model": "anthropic/claude-sonnet-4-6"},
    "ultrabrain": {"model": "anthropic/claude-sonnet-4-6"},
    "deep": {"model": "anthropic/claude-sonnet-4-6"},
    "artistry": {"model": "anthropic/claude-sonnet-4-6"},
    "quick": {"model": "anthropic/claude-sonnet-4-6"},
    "unspecified-low": {"model": "anthropic/claude-sonnet-4-6"},
    "unspecified-high": {"model": "anthropic/claude-sonnet-4-6"},
    "writing": {"model": "anthropic/claude-sonnet-4-6"}
  }
}
EOF
  echo -e "${GREEN}  ✓ oh-my-openagent.json${NC}"

  # Claude settings
  if [ ! -f "$CLAUDE_DIR/settings.json" ]; then
    cat > "$CLAUDE_DIR/settings.json" << 'EOF'
{
  "hooks": {
    "SessionStart": [],
    "PostToolUse": [],
    "PreToolUse": []
  }
}
EOF
    echo -e "${GREEN}  ✓ settings.json (Claude)${NC}"
  else
    echo -e "${BLUE}  - settings.json 已存在，跳过${NC}"
  fi
fi

# ------------------------------------------------------------------
# 步骤 4: 安装 unzip（Bun 安装脚本依赖）
# ------------------------------------------------------------------
echo -e "${YELLOW}[4/7] 安装 unzip...${NC}"

install_unzip_if_missing() {
  if command -v unzip &> /dev/null; then
    return 0
  fi
  echo "正在安装 unzip..."
  if command -v apt-get &> /dev/null; then
    sudo -n apt-get install -y unzip 2>/dev/null || {
      echo -e "${YELLOW}⚠ 需要 sudo 权限安装 unzip${NC}"
      echo "  请手动执行: sudo apt-get install -y unzip"
      echo "  然后在当前终端重新运行此脚本"
      exit 1
    }
  elif command -v yum &> /dev/null; then
    sudo -n yum install -y unzip 2>/dev/null || {
      echo -e "${YELLOW}⚠ 需要 sudo 权限安装 unzip${NC}"
      echo "  请手动执行: sudo yum install -y unzip"
      exit 1
    }
  elif command -v brew &> /dev/null; then
    brew install unzip
  elif command -v apk &> /dev/null; then
    apk add unzip
  else
    echo -e "${RED}✗ 无法自动安装 unzip，请手动安装后重试${NC}"
    exit 1
  fi
}

install_unzip_if_missing
echo -e "${GREEN}✓ unzip 已就绪${NC}"

# ------------------------------------------------------------------
# 步骤 5: 安装 Bun 运行时
# ------------------------------------------------------------------
echo -e "${YELLOW}[5/8] 安装 Bun 运行时...${NC}"

ensure_bun() {
  if command -v bun &> /dev/null; then
    echo -e "${GREEN}✓ Bun 已安装 ($(bun --version))${NC}"
    return 0
  fi
  if [ -f "$HOME/.bun/bin/bun" ]; then
    export PATH="$HOME/.bun/bin:$PATH"
    echo -e "${GREEN}✓ Bun 已安装 ($(bun --version))${NC}"
    return 0
  fi
  if [ -f "/usr/local/bin/bun" ]; then
    echo -e "${GREEN}✓ Bun 已安装 ($(bun --version))${NC}"
    return 0
  fi

  echo "正在安装 Bun..."
  curl -fsSL https://bun.sh/install | bash
  if [ -f "$HOME/.bun/bin/bun" ]; then
    export PATH="$HOME/.bun/bin:$PATH"
    echo -e "${GREEN}✓ Bun 安装成功 ($(bun --version))${NC}"
  else
    echo -e "${RED}✗ Bun 安装失败，请手动安装: curl -fsSL https://bun.sh/install | bash${NC}"
    exit 1
  fi
}

ensure_bun

# 确保 bun 在 PATH 中
if ! command -v bun &> /dev/null; then
  export PATH="$HOME/.bun/bin:$PATH"
fi

# 如果用户 shell 配置中还没有 bun 路径，添加提示
if ! grep -q '\.bun/bin' "$HOME/.bashrc" 2>/dev/null && ! grep -q '\.bun/bin' "$HOME/.zshrc" 2>/dev/null; then
  echo -e "${BLUE}  提示: 建议将 Bun 加入 shell 配置:${NC}"
  echo "    echo 'export PATH=\"\$HOME/.bun/bin:\$PATH\"' >> ~/.bashrc"
fi

# ------------------------------------------------------------------
# 步骤 5: 安装 OpenCode
# ------------------------------------------------------------------
echo -e "${YELLOW}[6/8] 安装 OpenCode...${NC}"

if command -v opencode &> /dev/null; then
  echo -e "${GREEN}✓ OpenCode 已安装 ($(opencode --version 2>/dev/null || echo 'ok'))${NC}"
else
  echo "正在通过 Bun 安装 OpenCode..."
  bun install -g @opencode-ai/opencode

  # 验证安装
  if command -v opencode &> /dev/null; then
    echo -e "${GREEN}✓ OpenCode 安装成功${NC}"
  else
    # 尝试通过 ~/.bun/bin 寻找
    if [ -f "$HOME/.bun/bin/opencode" ]; then
      export PATH="$HOME/.bun/bin:$PATH"
      echo -e "${GREEN}✓ OpenCode 安装成功 ($(opencode --version))${NC}"
    else
      echo -e "${RED}✗ OpenCode 安装失败${NC}"
      echo "  请手动安装: bun install -g @opencode-ai/opencode"
      exit 1
    fi
  fi
fi

# ------------------------------------------------------------------
# 步骤 6: 安装 oh-my-openagent 插件
# ------------------------------------------------------------------
echo -e "${YELLOW}[7/8] 安装 oh-my-openagent 插件...${NC}"

cd "$CONFIG_DIR"
if [ ! -d "node_modules" ] || [ ! -d "node_modules/oh-my-openagent" ]; then
  bun add oh-my-openagent@latest 2>&1 | tail -3
  echo -e "${GREEN}✓ oh-my-openagent 插件安装完成${NC}"
else
  echo -e "${GREEN}✓ oh-my-openagent 插件已存在${NC}"
fi

# ------------------------------------------------------------------
# 步骤 8: 安装 GSD 工作流（可选）
# ------------------------------------------------------------------
echo -e "${YELLOW}[8/8] 安装 GSD 工作流...${NC}"

GSD_DIR="$CONFIG_DIR/get-shit-done"
if [ ! -d "$GSD_DIR" ]; then
  if command -v git &> /dev/null; then
    echo "正在克隆 GSD 仓库..."
    git clone https://github.com/OpenAgentsInc/gsd.git "$GSD_DIR" 2>/dev/null || \
    git clone https://github.com/OpenAgentsInc/get-shit-done.git "$GSD_DIR" 2>/dev/null || \
    echo -e "${YELLOW}⚠ GSD 克隆失败，可稍后手动安装${NC}"

    if [ -d "$GSD_DIR" ]; then
      echo -e "${GREEN}✓ GSD 安装完成${NC}"
    fi
  else
    echo -e "${YELLOW}⚠ git 未安装，跳过 GSD${NC}"
    echo "  安装 git 后手动执行:"
    echo "    git clone https://github.com/OpenAgentsInc/gsd.git $GSD_DIR"
  fi
else
  echo -e "${GREEN}✓ GSD 已存在${NC}"
fi

# ------------------------------------------------------------------
# 完成
# ------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  OpenCode 配置完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}下一步:${NC}"
echo ""
echo "  1. 编辑 API 密钥:"
echo "     $EDITOR $CONFIG_DIR/opencode.json"
echo "     将 YOUR_API_KEY_HERE 替换为你的 API 密钥"
echo ""
echo "  2. 如使用 DeepSeek 等兼容 API，修改 baseURL:"
echo '     "baseURL": "https://api.deepseek.com/anthropic"'
echo ""
echo "  3. 调整模型路由（可选）:"
echo "     $EDITOR $CONFIG_DIR/oh-my-openagent.json"
echo ""
echo "  4. 运行 OpenCode:"
echo "     opencode"
echo ""
echo -e "${BLUE}配置文件位置:${NC}"
echo "  OpenCode:     $CONFIG_DIR/opencode.json"
echo "  模型路由:     $CONFIG_DIR/oh-my-openagent.json"
echo "  Claude 配置:  $CLAUDE_DIR/settings.json"
echo "  GSD 工作流:   $GSD_DIR"
echo ""
echo -e "${YELLOW}⚠ WSL 注意事项:${NC}"
echo "  确保在 WSL 内执行此脚本 (而非 Windows 侧)"
echo "  使用 Bun 安装的 opencode 不会出现 'node: not found' 错误"
echo ""
