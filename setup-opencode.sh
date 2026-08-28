#!/bin/bash
# ============================================================================
# OpenCode 一键配置脚本
# 使用 Bun 作为运行时，自动安装所有依赖
# 支持 Linux / macOS / WSL
# ============================================================================

if [ -z "${BASH_VERSION:-}" ]; then
  echo "检测到非 bash 环境，自动以 bash 重新执行..."
  exec bash "$0" "$@"
fi

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 计时: step_begin 记起点, step_end 输出耗时, EXIT 时打印汇总表便于排查瓶颈
_step_t0=0
STEP_TIMES=()
STEP_NAMES=()
step_begin() { _step_t0=$(date +%s); }
step_end() {
  local n="$1" name="$2" d
  d=$(( $(date +%s) - _step_t0 ))
  STEP_TIMES[$n]="$d"
  STEP_NAMES[$n]="$name"
  echo -e "${BLUE}  - 步骤${n} 耗时 ${d}s${NC}"
}
step_summary() {
  local i total=0
  echo ""
  echo -e "${YELLOW}=== 各环节耗时 ===${NC}"
  for i in $(seq 1 11); do
    [ -z "${STEP_TIMES[$i]:-}" ] && continue
    printf "  [%s/12] %s: %ss\n" "$i" "${STEP_NAMES[$i]}" "${STEP_TIMES[$i]}"
    total=$(( total + STEP_TIMES[$i] ))
  done
  echo -e "${YELLOW}总耗时: ${total}s${NC}"
}
trap step_summary EXIT

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  OpenCode 一键配置脚本 (Bun 版)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ------------------------------------------------------------------
# 目录配置（支持环境变量覆盖）
# ------------------------------------------------------------------
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"

# root 环境无需 sudo；非 root 且有 sudo 时自动补前缀
SUDO=""
if [ "$(id -u)" != "0" ] && command -v sudo &> /dev/null; then
  SUDO="sudo"
fi

echo -e "${BLUE}目标目录:${NC}"
echo "  OpenCode: $CONFIG_DIR"
echo "  Claude:   $CLAUDE_DIR"
echo ""

# 确保 curl（下载依赖）；缺失时尝试 apt 安装，失败仅提示
if ! command -v curl &> /dev/null; then
  echo -e "${YELLOW}⚠ curl 未安装，尝试安装...${NC}"
  if command -v apt-get &> /dev/null && apt-get update >/dev/null 2>&1 && apt-get install -y curl >/dev/null 2>&1; then
    echo -e "${GREEN}✓ curl 已安装${NC}"
  else
    echo -e "${YELLOW}⚠ curl 安装失败，后续下载步骤可能不可用${NC}"
  fi
fi

# ------------------------------------------------------------------
# 步骤 1: 检测已有配置
# ------------------------------------------------------------------
echo -e "${YELLOW}[1/12] 检测已有配置...${NC}"
step_begin

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
step_end 1 "检测已有配置"
step_begin
echo -e "${YELLOW}[2/12] 创建配置目录...${NC}"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/skills"
mkdir -p "$CLAUDE_DIR"
echo -e "${GREEN}✓ 目录已创建${NC}"

# ------------------------------------------------------------------
# 步骤 3: 生成配置文件
# ------------------------------------------------------------------
step_end 2 "创建配置目录"
if [ "${SKIP_CONFIG:-0}" != "1" ]; then
  step_begin
  echo -e "${YELLOW}[3/12] 生成配置文件...${NC}"

  # opencode.json
  cat > "$CONFIG_DIR/opencode.json" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugin": [
    "oh-my-openagent@latest",
    "superpowers@git+https://github.com/obra/superpowers.git"
  ],
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
  step_end 3 "生成配置文件"
fi

# ------------------------------------------------------------------
# 步骤 4: apt 源测速优化（仅 apt 系系统；官方最快则不动，已自定义则跳过）
# ------------------------------------------------------------------
step_begin
echo -e "${YELLOW}[4/12] apt 源测速优化...${NC}"

if ! command -v apt-get &> /dev/null || [ "$SKIP_APT_MIRROR" = "1" ]; then
  echo -e "${BLUE}  - 非 apt 系统或已跳过（SKIP_APT_MIRROR=1），跳过源优化${NC}"
elif ! command -v curl &> /dev/null; then
  echo -e "${YELLOW}⚠ curl 未安装，跳过 apt 源测速（不影响其他步骤）${NC}"
else
  # 支持两种源文件格式：传统 sources.list / 24.04+ deb822 ubuntu.sources
  APT_SOURCES=""
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
    [ -f "$f" ] && APT_SOURCES="$f" && break
  done

  if [ -z "$APT_SOURCES" ]; then
    echo -e "${YELLOW}⚠ 未找到 apt 源文件，跳过源优化${NC}"
  else
    # 官方域名未被替换过才执行；FORCE_APT_MIRROR=1 强制重测
    if [ "$FORCE_APT_MIRROR" = "1" ] || grep -Eq 'archive\.ubuntu\.com|security\.ubuntu\.com' "$APT_SOURCES"; then
      APT_CODENAME="$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2)"
      [ -z "$APT_CODENAME" ] && APT_CODENAME="jammy"

      echo -e "${BLUE}  测速中 (发行版 $APT_CODENAME)...${NC}"
      BEST_MIRROR=""
      BEST_SPEED=0
      for M in mirrors.aliyun.com mirrors.tuna.tsinghua.edu.cn mirrors.ustc.edu.cn mirrors.huaweicloud.com mirrors.cloud.tencent.com mirrors.163.com archive.ubuntu.com; do
        # 单次下载测速（速度取两次采样最大值，避免抖动）
        SPEED=0
        for _ in 1 2; do
          S="$(curl -fsSL --connect-timeout 5 --max-time 10 -o /dev/null -w '%{speed_download}' "http://$M/ubuntu/dists/$APT_CODENAME/Release" 2>/dev/null || true)"
          S="${S%.*}"
          [ "${S:-0}" -gt "$SPEED" ] 2>/dev/null && SPEED="$S"
        done
        if [ "${SPEED:-0}" -gt 0 ] 2>/dev/null; then
          echo -e "  ${M}: $((SPEED / 1024)) KB/s"
          if [ "$SPEED" -gt "$BEST_SPEED" ] 2>/dev/null; then
            BEST_SPEED="$SPEED"
            BEST_MIRROR="$M"
          fi
        else
          echo -e "  ${M}: 不可达"
        fi
      done

      if [ -n "$BEST_MIRROR" ]; then
        if [ "$BEST_MIRROR" = "archive.ubuntu.com" ]; then
          echo -e "${GREEN}✓ 官方源最快 ($((BEST_SPEED / 1024)) KB/s)，保持不动${NC}"
        else
          cp "$APT_SOURCES" "${APT_SOURCES}.bak"
          # 仅替换主机名，保留协议与路径（同时覆盖传统与 deb822 格式）
          $SUDO sed -i "s|//archive\.ubuntu\.com|//$BEST_MIRROR|g; s|//security\.ubuntu\.com|//$BEST_MIRROR|g" "$APT_SOURCES"
          echo -e "${GREEN}✓ 已切换至 $BEST_MIRROR ($((BEST_SPEED / 1024)) KB/s)${NC}"
          echo -e "${BLUE}  原文件已备份: ${APT_SOURCES}.bak${NC}"
          if $SUDO apt-get update >/dev/null 2>&1; then
            echo -e "${GREEN}✓ apt update 验证通过${NC}"
          else
            echo -e "${YELLOW}⚠ apt update 失败，还原原源: sudo cp ${APT_SOURCES}.bak $APT_SOURCES${NC}"
          fi
        fi
      else
        echo -e "${YELLOW}⚠ 所有源均不可达（网络受限？），保持原配置${NC}"
      fi
    else
      echo -e "${BLUE}  - apt 源已自定义，跳过（FORCE_APT_MIRROR=1 可强制重测）${NC}"
    fi
  fi
fi

# ------------------------------------------------------------------
# 步骤 5: 检查前置依赖
# ------------------------------------------------------------------
step_end 4 "apt 源测速优化"
step_begin
echo -e "${YELLOW}[5/12] 检查前置依赖...${NC}"

# Bun 安装脚本需要 unzip
if ! command -v unzip &> /dev/null; then
  echo -e "${YELLOW}⚠ 缺少 unzip，正在安装...${NC}"
  if command -v apt-get &> /dev/null; then
    $SUDO apt-get install -y unzip
  elif command -v yum &> /dev/null; then
    $SUDO yum install -y unzip
  elif command -v brew &> /dev/null; then
    brew install unzip
  elif command -v apk &> /dev/null; then
    apk add unzip
  else
    echo -e "${RED}✗ 无法自动安装 unzip${NC}"
    echo "  请手动安装后重新运行"
    exit 1
  fi
  echo -e "${GREEN}✓ unzip 安装成功${NC}"
else
  echo -e "${GREEN}✓ unzip 已就绪${NC}"
fi

# OpenCode 引导脚本需要 node（找到原生二进制后会切换到原生运行）
if ! command -v node &> /dev/null; then
  echo -e "${YELLOW}⚠ 缺少 node，正在安装...${NC}"

  # 优先 npmmirror node 二进制（国内快），失败回退发行版包管理器
  NODE_INSTALLED=0
  if command -v curl &> /dev/null && command -v tar &> /dev/null; then
    NODE_ARCH="x64"
    case "$(uname -m)" in
      x86_64) NODE_ARCH="x64" ;;
      aarch64) NODE_ARCH="arm64" ;;
      *) NODE_ARCH="" ;;
    esac
    if [ -n "$NODE_ARCH" ]; then
      NODE_TMP="$(mktemp -d)"
      NODE_FILE=""
      NODE_V=""
      # 优先 LTS 系列（v24 → v22），取目录 JSON 中最新 linux 包名
      for V in latest-v24.x latest-v22.x; do
        NODE_FILE="$(curl -fsSL --connect-timeout 8 --max-time 20 "https://registry.npmmirror.com/-/binary/node/$V/" 2>/dev/null | grep -o "\"name\":\"node-v[0-9.]*-linux-$NODE_ARCH.tar.xz\"" | head -1 | cut -d'"' -f4 || true)"
        if [ -n "$NODE_FILE" ]; then
          NODE_V="$V"
          break
        fi
      done
      if [ -n "$NODE_FILE" ] && curl -fsSL --connect-timeout 8 --max-time 180 -o "$NODE_TMP/node.tar.xz" "https://registry.npmmirror.com/-/binary/node/$NODE_V/$NODE_FILE" 2>/dev/null; then
        :
      fi
      NODE_DIR="$(tar -tJf "$NODE_TMP/node.tar.xz" 2>/dev/null | head -1 | cut -d/ -f1)"
      if [ -n "$NODE_DIR" ] && tar -xJf "$NODE_TMP/node.tar.xz" -C "$NODE_TMP" 2>/dev/null; then
        mkdir -p /usr/local/lib/nodejs
        cp -r "$NODE_TMP/$NODE_DIR" /usr/local/lib/nodejs/
        ln -sf "/usr/local/lib/nodejs/$NODE_DIR/bin/node" /usr/local/bin/node
        ln -sf "/usr/local/lib/nodejs/$NODE_DIR/bin/npm" /usr/local/bin/npm
        ln -sf "/usr/local/lib/nodejs/$NODE_DIR/bin/npx" /usr/local/bin/npx
        NODE_INSTALLED=1
        echo -e "${GREEN}✓ node 安装成功（npmmirror 二进制，$(node --version)）${NC}"
      fi
      rm -rf "$NODE_TMP"
    fi
  fi

  if [ "$NODE_INSTALLED" != "1" ]; then
    echo -e "${YELLOW}npmmirror 下载失败，回退系统包管理器...${NC}"
    if command -v apt-get &> /dev/null; then
      curl -fsSL https://deb.nodesource.com/setup_lts.x | ${SUDO:+$SUDO -E }bash - 2>/dev/null
      $SUDO apt-get install -y nodejs
    elif command -v yum &> /dev/null; then
      curl -fsSL https://rpm.nodesource.com/setup_lts.x | ${SUDO:+$SUDO -E }bash - 2>/dev/null
      $SUDO yum install -y nodejs
    elif command -v brew &> /dev/null; then
      brew install node
    else
      echo -e "${RED}✗ 无法自动安装 node${NC}"
      echo "  请手动安装后重新运行"
      exit 1
    fi
  fi

  if command -v node &> /dev/null; then
    echo -e "${GREEN}✓ node 安装成功 ($(node --version))${NC}"
  else
    echo -e "${RED}✗ node 安装失败，请手动安装${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}✓ node 已就绪 ($(node --version))${NC}"
fi

echo -e "${YELLOW}配置 npm 镜像源 ($NPM_REGISTRY)...${NC}"
if ! grep -q "^registry=" "$HOME/.npmrc" 2>/dev/null; then
  echo "registry=$NPM_REGISTRY" >> "$HOME/.npmrc"
  echo -e "${GREEN}✓ npm 镜像源已配置 (npm/npx/bun 共用)${NC}"
else
  echo -e "${BLUE}  - ~/.npmrc 已有 registry 配置，跳过${NC}"
fi

# Python 生态: 无 pip 则用 ensurepip 引导, pip 可用时才配置清华 PyPI 镜像
if command -v python3 &> /dev/null; then
  PIP_READY=0
  if python3 -m pip --version &> /dev/null; then
    PIP_READY=1
  else
    echo -e "${YELLOW}⚠ 缺少 pip，正在引导安装...${NC}"
    if python3 -m ensurepip --upgrade >/dev/null 2>&1 && python3 -m pip --version &> /dev/null; then
      PIP_READY=1
      echo -e "${GREEN}✓ pip 引导完成 ($(python3 -m pip --version 2>/dev/null | cut -d' ' -f2))${NC}"
    else
      echo -e "${YELLOW}⚠ ensurepip 失败（可手动执行: sudo apt install python3-pip）${NC}"
    fi
  fi

  if [ "$PIP_READY" = "1" ]; then
    PIP_CONF="$HOME/.config/pip/pip.conf"
    if [ -f "$HOME/.pip/pip.conf" ]; then
      PIP_CONF="$HOME/.pip/pip.conf"
    fi
    if ! grep -q "index-url" "$PIP_CONF" 2>/dev/null; then
      mkdir -p "$(dirname "$PIP_CONF")"
      printf '[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple\ntrusted-host = pypi.tuna.tsinghua.edu.cn\n' > "$PIP_CONF"
      echo -e "${GREEN}✓ PyPI 镜像源已配置 (清华, $PIP_CONF)${NC}"
    else
      echo -e "${BLUE}  - pip 已有 index-url 配置，跳过${NC}"
    fi
  fi
fi

# ------------------------------------------------------------------
# 步骤 6: 安装 Bun 运行时
# ------------------------------------------------------------------
step_end 5 "检查前置依赖"
step_begin
echo -e "${YELLOW}[6/12] 安装 Bun 运行时...${NC}"

ensure_bun() {
  local bun_cmd=""
  if command -v bun >/dev/null 2>&1; then
    bun_cmd="bun"
  elif [ -f "$HOME/.bun/bin/bun" ]; then
    export PATH="$HOME/.bun/bin:$PATH"
    bun_cmd="$HOME/.bun/bin/bun"
  elif [ -f "/usr/local/bin/bun" ]; then
    bun_cmd="/usr/local/bin/bun"
  fi

  if [ -n "$bun_cmd" ] && "$bun_cmd" --version >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Bun 已安装 ($("$bun_cmd" --version))${NC}"
    return 0
  fi

  if [ -n "$bun_cmd" ]; then
    echo -e "${YELLOW}⚠ 检测到损坏的 Bun，清理后重新安装...${NC}"
    rm -f "$HOME/.bun/bin/bun" "$HOME/.bun/bin/bunx"
  fi

  echo "正在安装 Bun（优先 npm 镜像，失败回退 npmmirror 二进制，再回退官方脚本）..."
  if npm i -g bun >/dev/null 2>&1 && command -v bun >/dev/null 2>&1 && bun --version >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Bun 安装成功 ($(bun --version))${NC}"
    return 0
  fi

  echo -e "${YELLOW}⚠ npm 安装失败，尝试 npmmirror 二进制...${NC}"
  if command -v unzip >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    BUN_ARCH="x64"
    case "$(uname -m)" in
      x86_64) BUN_ARCH="x64" ;;
      aarch64) BUN_ARCH="aarch64" ;;
      *) BUN_ARCH="" ;;
    esac
    if [ -n "$BUN_ARCH" ]; then
      BUN_VERSION="$(curl -fsSL --connect-timeout 8 --max-time 20 "https://registry.npmmirror.com/-/binary/bun/" 2>/dev/null | grep -o '"name":"bun-v[0-9.]*/"' | sed 's/"name":"//; s/\/"//' | sort -V | tail -1 || true)"
      BUN_TMP="$(mktemp -d)"
      if [ -n "$BUN_VERSION" ] && curl -fsSL --connect-timeout 8 --max-time 180 -o "$BUN_TMP/bun.zip" "https://registry.npmmirror.com/-/binary/bun/$BUN_VERSION/bun-linux-$BUN_ARCH.zip" 2>/dev/null && unzip -qo "$BUN_TMP/bun.zip" -d "$BUN_TMP" && [ -f "$BUN_TMP/bun-linux-$BUN_ARCH/bun" ]; then
        mkdir -p "$HOME/.bun/bin"
        install -m 0755 "$BUN_TMP/bun-linux-$BUN_ARCH/bun" "$HOME/.bun/bin/bun"
        ln -sf "$HOME/.bun/bin/bun" "$HOME/.bun/bin/bunx"
        export PATH="$HOME/.bun/bin:$PATH"
        rm -rf "$BUN_TMP"
        echo -e "${GREEN}✓ Bun 安装成功 (npmmirror 二进制, $(bun --version))${NC}"
        return 0
      fi
      rm -rf "$BUN_TMP"
    fi
  fi

  echo -e "${YELLOW}⚠ npmmirror 下载失败，回退官方安装脚本...${NC}"
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

if [ ! -f "$HOME/.bunfig.toml" ]; then
  printf '[install]\nregistry = "%s"\n' "$NPM_REGISTRY" > "$HOME/.bunfig.toml"
  echo -e "${GREEN}✓ Bun registry 已配置 ($NPM_REGISTRY)${NC}"
else
  echo -e "${BLUE}  - ~/.bunfig.toml 已存在，跳过${NC}"
fi

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
# 步骤 7: 安装 OpenCode
# ------------------------------------------------------------------
step_end 6 "安装 Bun 运行时"
step_begin
echo -e "${YELLOW}[7/12] 安装 OpenCode...${NC}"

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
# 步骤 8: 安装 oh-my-openagent 插件
# ------------------------------------------------------------------
step_end 7 "安装 OpenCode"
step_begin
echo -e "${YELLOW}[8/12] 安装 oh-my-openagent 插件...${NC}"

cd "$CONFIG_DIR"
if [ ! -d "node_modules" ] || [ ! -d "node_modules/oh-my-openagent" ]; then
  bun add oh-my-openagent@latest 2>&1 | tail -3
  echo -e "${GREEN}✓ oh-my-openagent 插件安装完成${NC}"
else
  echo -e "${GREEN}✓ oh-my-openagent 插件已存在${NC}"
fi

echo -e "${YELLOW}应用 omo 模型跟随补丁...${NC}"
OMO_PATCH_FILE="$(mktemp /tmp/omo-patch.XXXXXX.mjs)"
cat > "$OMO_PATCH_FILE" << 'OMO_PATCH_EOF'
import { readFileSync, writeFileSync } from "node:fs";

const file = process.argv[2];
if (!file) {
  console.error("usage: node omo-follow-system-default.mjs <dist/index.js>");
  process.exit(1);
}
let src = readFileSync(file, "utf8");
let changed = 0;

const p1Marker = "Model resolved via system default (before hardcoded fallback chain)";
if (!src.includes(p1Marker)) {
  const anchor =
    '      log3("No available model found in user fallback_models, falling through to hardcoded chain");\n' +
    "    }\n" +
    "  }\n" +
    "  if (fallbackChain && fallbackChain.length > 0) {";
  const replacement =
    '      log3("No available model found in user fallback_models, falling through to hardcoded chain");\n' +
    "    }\n" +
    "  }\n" +
    "  if (systemDefaultModel !== undefined) {\n" +
    '    log3("Model resolved via system default (before hardcoded fallback chain)", { model: systemDefaultModel });\n' +
    '    return { model: systemDefaultModel, provenance: "system-default", attempted };\n' +
    "  }\n" +
    "  if (fallbackChain && fallbackChain.length > 0) {";
  if (!src.includes(anchor)) throw new Error("patch1 anchor not found (omo dist changed)");
  src = src.replace(anchor, replacement);
  const tail =
    "  if (systemDefaultModel === undefined) {\n" +
    '    log3("No model resolved - systemDefaultModel not configured");\n' +
    "    return;\n" +
    "  }\n" +
    '  log3("Model resolved via system default", { model: systemDefaultModel });\n' +
    '  return { model: systemDefaultModel, provenance: "system-default", attempted };\n';
  if (!src.includes(tail)) throw new Error("patch1 tail not found");
  src = src.replace(tail, "");
  changed++;
}

const p2Marker = "[resolveModelForDelegateTask] system default before hardcoded chain";
if (!src.includes(p2Marker)) {
  const anchor = "  const fallbackChain = input.fallbackChain;\n" + "  if (fallbackChain && fallbackChain.length > 0) {";
  const replacement =
    "  const systemDefaultModel = normalizeModel(input.systemDefaultModel);\n" +
    "  if (systemDefaultModel) {\n" +
    '    deps.log?.("[resolveModelForDelegateTask] system default before hardcoded chain", { model: systemDefaultModel });\n' +
    "    return { model: systemDefaultModel };\n" +
    "  }\n" +
    "  const fallbackChain = input.fallbackChain;\n" +
    "  if (fallbackChain && fallbackChain.length > 0) {";
  if (!src.includes(anchor)) throw new Error("patch2 anchor not found");
  src = src.replace(anchor, replacement);
  const tail =
    "  const systemDefaultModel = normalizeModel(input.systemDefaultModel);\n" +
    "  if (systemDefaultModel) {\n" +
    "    return { model: systemDefaultModel };\n" +
    "  }\n" +
    "  return;\n";
  if (!src.includes(tail)) throw new Error("patch2 tail not found");
  src = src.replace(tail, "  return;\n");
  changed++;
}

if (changed > 0) {
  writeFileSync(file, src);
  console.log("omo patch applied");
} else {
  console.log("omo patch already applied");
}
OMO_PATCH_EOF

if [ -f "$CONFIG_DIR/node_modules/oh-my-openagent/dist/index.js" ] && node "$OMO_PATCH_FILE" "$CONFIG_DIR/node_modules/oh-my-openagent/dist/index.js"; then
  echo -e "${GREEN}✓ omo 模型跟随补丁已应用（子代理跟随 opencode.json 的 model）${NC}"
else
  echo -e "${YELLOW}⚠ omo 补丁失败（omo 版本可能已变化，子代理将回退硬编码模型链）${NC}"
fi
rm -f "$OMO_PATCH_FILE"

# ------------------------------------------------------------------
# 步骤 9: 安装 GSD Core 工作流
# ------------------------------------------------------------------
step_end 8 "安装 oh-my-openagent 插件"
step_begin
echo -e "${YELLOW}[9/12] 安装 GSD Core 工作流...${NC}"

# 检测是否已安装（检查 opencode 命令行目录下是否有 gsd 命令）
if ls "$CONFIG_DIR/command/gsd-"* &>/dev/null 2>&1; then
  echo -e "${GREEN}✓ GSD Core 命令已存在${NC}"
else
  if command -v npx &> /dev/null; then
    echo "正在安装 GSD Core（官方继任项目，原生支持 OpenCode）..."
    echo ""

    # GSD Core 官方安装命令
    # 自动检测 OpenCode 配置目录，安装 agent 和 command 到对应位置
    npx --yes @opengsd/gsd-core@latest --opencode --global

    echo ""
    echo -e "${GREEN}✓ GSD Core 安装完成${NC}"
    echo -e "${BLUE}  重启 OpenCode 后即可使用 /gsd-* 命令${NC}"
  else
    echo -e "${YELLOW}⚠ npx 未安装，跳过 GSD Core${NC}"
    echo "  确保 Node.js 已安装，然后手动执行:"
    echo "    npx --yes @opengsd/gsd-core@latest --opencode --global"
  fi
fi

# ------------------------------------------------------------------
# 步骤 10: 安装 CodeGraph MCP（代码图索引）
# ------------------------------------------------------------------
step_end 9 "安装 GSD Core 工作流"
step_begin
echo -e "${YELLOW}[10/12] 安装 CodeGraph MCP...${NC}"

CG_BIN="$(command -v codegraph 2>/dev/null || true)"
if [ -z "$CG_BIN" ]; then
  if command -v npm &> /dev/null; then
    echo -e "${YELLOW}正在安装 codegraph（npmmirror 源，约 30-60s，超时 120s）...${NC}"
    CG_INSTALL_LOG="$(mktemp)"
    if timeout 120 npm i -g --registry="$NPM_REGISTRY" @colbymchenry/codegraph > "$CG_INSTALL_LOG" 2>&1; then
      NPM_PREFIX="$(npm config get prefix)"
      CG_BIN="$NPM_PREFIX/bin/codegraph"
      if [ -x "$CG_BIN" ]; then
        echo -e "${GREEN}✓ codegraph 安装完成 ($CG_BIN)${NC}"
        # 脚本装的 node 为官方二进制布局，全局 bin 可能不在 PATH，补入
        if ! command -v codegraph &> /dev/null; then
          export PATH="$NPM_PREFIX/bin:$PATH"
          if ! grep -q "NPM_PREFIX/bin" "$HOME/.bashrc" 2>/dev/null; then
            echo "" >> "$HOME/.bashrc"
            echo "# npm 全局 bin" >> "$HOME/.bashrc"
            echo "export PATH=\"$NPM_PREFIX/bin:\$PATH\"" >> "$HOME/.bashrc"
          fi
        fi
      else
        echo -e "${YELLOW}⚠ codegraph 安装失败（已装但未找到二进制），跳过 MCP 注册${NC}"
        tail -5 "$CG_INSTALL_LOG"
        echo "  装好后重新运行脚本即可注册 MCP"
        CG_BIN=""
      fi
    else
      echo -e "${YELLOW}⚠ codegraph 安装失败（超时或网络错误），跳过 MCP 注册${NC}"
      tail -5 "$CG_INSTALL_LOG"
      echo "  可手动重试: npm i -g --registry=$NPM_REGISTRY @colbymchenry/codegraph"
      CG_BIN=""
    fi
    rm -f "$CG_INSTALL_LOG"
  else
    echo -e "${YELLOW}⚠ npm 未安装，跳过 codegraph${NC}"
    echo "  手动安装: npm i -g @colbymchenry/codegraph"
  fi
else
  echo -e "${GREEN}✓ codegraph 已存在 ($CG_BIN)${NC}"
fi

# codegraph 可用时才注册 MCP；command 用绝对路径，避免 PATH 问题
if [ -n "$CG_BIN" ] && [ -f "$CONFIG_DIR/opencode.json" ]; then
  if node -e '
    const fs = require("fs");
    const p = process.argv[1];
    const bin = process.argv[2];
    const c = JSON.parse(fs.readFileSync(p, "utf8"));
    c.mcp = c.mcp || {};
    c.mcp.codegraph = { type: "local", command: [bin, "serve", "--mcp"], enabled: true };
    fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n");
  ' "$CONFIG_DIR/opencode.json" "$CG_BIN" 2>/dev/null; then
    echo -e "${GREEN}✓ codegraph MCP 已注册到 opencode.json (绝对路径)${NC}"
  else
    echo -e "${YELLOW}⚠ codegraph MCP 注册失败，可手动添加${NC}"
  fi
fi

echo -e "${BLUE}  在项目目录运行 'codegraph init' 生成索引${NC}"
echo -e "${BLUE}  重启 OpenCode 后 codegraph_* 工具生效${NC}"

# ------------------------------------------------------------------
# 步骤 11: 安装 RTK（Rust Token Killer，压缩命令输出节省 Token）
# 零认证：版本号走 api.github.com，下载走镜像链（gh-proxy → ghfast → 官方直连）
# ------------------------------------------------------------------
step_end 10 "安装 CodeGraph MCP"
step_begin
echo -e "${YELLOW}[11/12] 安装 RTK（命令输出压缩，节省 Token 开支）...${NC}"

if command -v rtk &> /dev/null; then
  echo -e "${GREEN}✓ rtk 已安装 ($(rtk --version))${NC}"
else
  # 动态获取最新版本号（无需认证），失败则回退已知版本
  RTK_VERSION="$(curl -fsSL --connect-timeout 10 "https://api.github.com/repos/rtk-ai/rtk/releases/latest" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
  [ -z "$RTK_VERSION" ] && RTK_VERSION="v0.45.0"

  # 架构检测: x86_64 用 musl 静态二进制（零依赖），aarch64 用 gnu
  RTK_ASSET=""
  case "$(uname -m)" in
    x86_64)  RTK_ASSET="rtk-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64) RTK_ASSET="rtk-aarch64-unknown-linux-gnu.tar.gz" ;;
    *) echo -e "${YELLOW}⚠ 不支持的架构 $(uname -m)，跳过 RTK 安装${NC}" ;;
  esac

  if [ -n "$RTK_ASSET" ]; then
    RTK_URL="https://github.com/rtk-ai/rtk/releases/download/$RTK_VERSION/$RTK_ASSET"
    RTK_TMP="$(mktemp -d)"
    RTK_OK=0
    # 镜像链（全部无认证）: gh-proxy.com → ghfast.top → 官方直连
    for MIRROR in "https://gh-proxy.com/" "https://ghfast.top/" ""; do
      echo -e "${BLUE}  尝试下载: ${MIRROR}${RTK_URL}${NC}"
      if curl -fsSL --connect-timeout 12 --max-time 90 -o "$RTK_TMP/rtk.tar.gz" "${MIRROR}${RTK_URL}"; then
        RTK_OK=1
        break
      fi
    done

    if [ "$RTK_OK" = "1" ] && tar -xzf "$RTK_TMP/rtk.tar.gz" -C "$RTK_TMP" && [ -f "$RTK_TMP/rtk" ]; then
      # 优先 /usr/local/bin，非 root 回退 ~/.local/bin
      if install -m 0755 "$RTK_TMP/rtk" /usr/local/bin/rtk 2>/dev/null; then
        echo -e "${GREEN}✓ rtk 安装完成: $(rtk --version)${NC}"
      else
        mkdir -p "$HOME/.local/bin"
        install -m 0755 "$RTK_TMP/rtk" "$HOME/.local/bin/rtk"
        export PATH="$HOME/.local/bin:$PATH"
        echo -e "${GREEN}✓ rtk 安装完成: $(rtk --version)（~/.local/bin）${NC}"
      fi
    else
      echo -e "${YELLOW}⚠ rtk 下载失败（网络受限时可手动从 https://github.com/rtk-ai/rtk/releases 下载）${NC}"
    fi
    rm -rf "$RTK_TMP"
  fi
fi

# OpenCode 集成（幂等，无认证）
if command -v rtk &> /dev/null; then
  if [ -f "$CONFIG_DIR/plugins/rtk.ts" ]; then
    echo -e "${BLUE}  - rtk opencode 插件已存在，跳过 init${NC}"
  else
    printf 'n\n' | rtk init --opencode -g >/dev/null 2>&1 || true
    if [ -f "$CONFIG_DIR/plugins/rtk.ts" ]; then
      echo -e "${GREEN}✓ rtk opencode 插件安装完成（重启 OpenCode 后自动压缩命令输出）${NC}"
    else
      echo -e "${YELLOW}⚠ rtk init 失败，可手动执行: rtk init --opencode -g${NC}"
    fi
  fi
  rtk telemetry disable >/dev/null 2>&1 || true
fi

# 让当前终端也能用 Bun（.bashrc 刚写入的 PATH）
# shellcheck source=/dev/null
. "$HOME/.bashrc" 2>/dev/null || true

step_end 11 "安装 RTK"

# ------------------------------------------------------------------
# 步骤 12: 安全/能力增强模块(可选, SKIP_SECURITY=1 跳过)
# 依据 spec: E 方向六模块(权限红线/审计/安全自检/合规) + B 方向环境画像
# e-modules/ 随仓库分发, 安装时部署到 CONFIG_DIR
# ------------------------------------------------------------------
step_begin
echo -e "${YELLOW}[12/12] 安全与能力增强模块...${NC}"

MOD_DIR="$CONFIG_DIR/opencode-setup-modules"

if [ "$SKIP_SECURITY" = "1" ]; then
  echo -e "${BLUE}  - 已跳过（SKIP_SECURITY=1）${NC}"
elif [ -d "$(dirname "$0")/e-modules" ]; then
  # 部署 e-modules 到配置目录
  mkdir -p "$MOD_DIR" "$MOD_DIR/devcontainer"
  cp "$(dirname "$0")/e-modules/"*.sh "$MOD_DIR/" 2>/dev/null
  cp "$(dirname "$0")/e-modules/devcontainer/"*.json "$(dirname "$0")/e-modules/devcontainer/"*.md "$MOD_DIR/devcontainer/" 2>/dev/null
  chmod +x "$MOD_DIR"/*.sh 2>/dev/null

  echo -e "${BLUE}  - e-modules 已部署到 $MOD_DIR${NC}"

  # ① 权限红线(merge 进 opencode.json 的 permission 段)
  if command -v python3 >/dev/null 2>&1; then
    "$MOD_DIR/gen-permissions.sh" /tmp/.perm.json >/dev/null 2>&1 && python3 - "$CONFIG_DIR/opencode.json" << 'PYEOF'
import json,sys
p=sys.argv[1]
try:
    c=json.load(open(p))
except: c={"$schema":"https://opencode.ai/config.json"}
try:
    perm=json.load(open('/tmp/.perm.json'))['permission']
    c['permission']=perm
    json.dump(c,open(p,'w'),ensure_ascii=False,indent=2)
    print("OK")
except Exception as e:
    print(f"SKIP:{e}")
PYEOF
    echo -e "${GREEN}  ✓ 权限红线已合并到 opencode.json${NC}"
  else
    echo -e "${YELLOW}  ⚠ 无 python3，跳过权限合并（可手动运行 $MOD_DIR/gen-permissions.sh）${NC}"
  fi

  # ② 审计
  "$MOD_DIR/audit-init.sh" init >/dev/null 2>&1 && echo -e "${GREEN}  ✓ 审计模块已初始化（JSONL+脱敏+熔断+30天轮转）${NC}"

  # ③ 安全自检 + AGENT-CARD
  "$MOD_DIR/security-check.sh" 2>&1 | tail -3 | sed 's/^/  /' || true

  # ④ 合规文档
  "${MOD_DIR}/gen-compliance.sh" >/dev/null 2>&1 && echo -e "${GREEN}  ✓ 合规文档已生成（compliance/COMPLIANCE.md）${NC}" || echo -e "${YELLOW}  ⚠ 合规文档生成跳过${NC}"

  echo -e "${GREEN}  ✓ 安全/能力增强完成${NC}"
  echo -e "${BLUE}    模块: $MOD_DIR (权限红线/审计/自检/合规)${NC}"
else
  echo -e "${YELLOW}  ⚠ 未找到 e-modules（源码仓库外运行?）——跳过增强模块${NC}"
fi

step_end 12 "安全与能力增强"

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
echo "  1. 如需 API 提供商，编辑 opencode.json 添加 provider 配置:"
echo "     $EDITOR $CONFIG_DIR/opencode.json"
echo "     e.g. {\"provider\":{\"anthropic\":{\"options\":{\"apiKey\":\"sk-...\"}}}}"
echo ""
echo "  2. 如使用 DeepSeek 等兼容 API，baseURL 填:"
echo '     "https://api.deepseek.com/anthropic"'
echo ""
echo "  3. 调整模型路由（可选）:"
echo "     $EDITOR $CONFIG_DIR/oh-my-openagent.json"
echo "     为 agent 添加 model 字段即可覆盖默认模型，例如:"
echo '     "oracle": {"model": "deepseek/deepseek-v4-flash"}'
echo ""
echo "  4. 运行 OpenCode:"
echo "     opencode"
echo ""
echo "  5. 查看已安装的 skills:"
echo '     skill({name: "superpowers/brainstorming"})'
echo ""
echo -e "${BLUE}配置文件位置:${NC}"
echo "  OpenCode:     $CONFIG_DIR/opencode.json"
echo "  模型路由:     $CONFIG_DIR/oh-my-openagent.json"
echo "  Claude 配置:  $CLAUDE_DIR/settings.json"
echo "  GSD 工作流:   $GSD_DIR"
echo "  CodeGraph:    项目目录运行 codegraph init 生成索引"
echo ""
echo -e "${YELLOW}⚠ WSL 注意事项:${NC}"
echo "  Bun 路径已写入 ~/.bashrc，新终端自动生效"
echo "  如果输入 'opencode' 仍报错 'node: not found'，请执行:"
echo "    source ~/.bashrc"
echo "  或重启终端"
