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
echo -e "${YELLOW}[1/8] 检测已有配置...${NC}"

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
echo -e "${YELLOW}[2/8] 创建配置目录...${NC}"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/skills"
mkdir -p "$CLAUDE_DIR"
echo -e "${GREEN}✓ 目录已创建${NC}"

# ------------------------------------------------------------------
# 步骤 3: 生成配置文件
# ------------------------------------------------------------------
if [ "${SKIP_CONFIG:-0}" != "1" ]; then
  echo -e "${YELLOW}[3/8] 生成配置文件...${NC}"

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
  # 只注册 agent/category 结构，不设 model = 使用源码内置默认模型 + 回退链
  # 需要自定义时取消注释或添加 model 字段
  cat > "$CONFIG_DIR/oh-my-openagent.json" << 'EOF'
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json",
  "agents": {
    "hephaestus": {},
    "oracle": {},
    "librarian": {},
    "explore": {},
    "multimodal-looker": {},
    "prometheus": {},
    "metis": {},
    "momus": {},
    "atlas": {},
    "sisyphus-junior": {}
  },
  "categories": {
    "visual-engineering": {},
    "ultrabrain": {},
    "deep": {},
    "artistry": {},
    "quick": {},
    "unspecified-low": {},
    "unspecified-high": {},
    "writing": {}
  }
}
EOF
  echo -e "${GREEN}  ✓ oh-my-openagent.json（agent 已注册，model 留空=内置默认）${NC}"

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
# 步骤 4: 检查前置依赖
# ------------------------------------------------------------------
echo -e "${YELLOW}[4/8] 检查前置依赖...${NC}"

# Bun 安装脚本需要 unzip
if ! command -v unzip &> /dev/null; then
  echo -e "${RED}✗ 缺少 unzip，Bun 安装需要此工具${NC}"
  echo ""
  echo "  请手动安装后重新运行:"
  echo "    sudo apt-get install -y unzip   # Debian/Ubuntu"
  echo "    sudo yum install -y unzip       # CentOS/RHEL"
  echo "    brew install unzip              # macOS"
  echo ""
  exit 1
fi
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

# 如果 shell 配置中还没有 bun 路径，自动写入
BUN_PATH_LINE='export PATH="$HOME/.bun/bin:$PATH"'
if ! grep -q '\.bun/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo "" >> "$HOME/.bashrc"
  echo "# Bun" >> "$HOME/.bashrc"
  echo "$BUN_PATH_LINE" >> "$HOME/.bashrc"
  echo -e "${GREEN}✓ Bun 路径已写入 ~/.bashrc${NC}"
fi
# 确保当前会话也能用
export PATH="$HOME/.bun/bin:$PATH"

# ------------------------------------------------------------------
# 步骤 6: 安装 OpenCode
# ------------------------------------------------------------------
echo -e "${YELLOW}[6/8] 安装 OpenCode...${NC}"

# 确保 Bun 路径优先（避免 WSL 下 Windows npm 版本抢在前）
export PATH="$HOME/.bun/bin:$PATH"

if [ -f "$HOME/.bun/bin/opencode" ]; then
  echo -e "${GREEN}✓ OpenCode 已安装 ($(opencode --version))${NC}"
else
  echo "正在通过 Bun 安装 OpenCode..."
  bun install -g opencode-ai

  if [ -f "$HOME/.bun/bin/opencode" ]; then
    echo -e "${GREEN}✓ OpenCode 安装成功 ($(opencode --version))${NC}"
  else
    echo -e "${RED}✗ OpenCode 安装失败${NC}"
    echo "  请手动安装: bun install -g opencode-ai"
    exit 1
  fi
fi

# 检查是否有 Windows npm 安装的 opencode 冲突
WINDOWS_OPENCODE=$(command -v opencode 2>/dev/null || true)
if [ -n "$WINDOWS_OPENCODE" ] && echo "$WINDOWS_OPENCODE" | grep -q "/mnt/"; then
  echo -e "${YELLOW}⚠ 检测到 WSL 下存在 Windows npm 安装的 opencode${NC}"
  echo "  当前优先级: $HOME/.bun/bin > $WINDOWS_OPENCODE"
  echo "  如果输入 opencode 仍报错，请检查 PATH 顺序"
fi

# ------------------------------------------------------------------
# 步骤 7: 安装 oh-my-openagent 插件
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
echo "  Bun 路径已写入 ~/.bashrc，新终端自动生效"
echo "  如果输入 'opencode' 仍报错 'node: not found'，请执行:"
echo "    source ~/.bashrc"
echo "  或重启终端"
