# opencode-setup

一键配置 [OpenCode](https://opencode.ai) 环境，集成 oh-my-openagent、GSD 工作流、CodeGraph MCP 和完整的 Agent 生态。

```bash
curl -fsSL https://raw.githubusercontent.com/Liber1917/opencode-setup/main/setup-opencode.sh | bash
```

或克隆后运行：

```bash
git clone https://github.com/Liber1917/opencode-setup.git
cd opencode-setup
./setup-opencode.sh
```

用 `sh` 运行也没问题——脚本检测到非 bash 环境会自动以 bash 重新执行。

## 特性

- **Bun 运行时** — 自动安装（npm 镜像优先，官方脚本回退），检测损坏自愈，避免跨平台 PATH 问题
- **npm 镜像加速** — 默认 npmmirror，国内网络下安装飞快，可用环境变量覆盖
- **oh-my-openagent** — 10 个 Agent + 8 个 Category 的模型路由
- **子代理模型跟随主配置** — 打补丁使子代理默认使用 opencode.json 的 `model`（而非硬编码模型链），显式 omo 配置优先
- **RTK 命令输出压缩** — 安装 [Rust Token Killer](https://github.com/rtk-ai/rtk) 并集成 OpenCode 插件，bash 命令输出进 LLM 前被智能压缩，节省 60-90% Token（零认证镜像源下载，国内网络友好）
- **apt 源自动测速** — 对 6 个国内镜像 + 官方源真实下载测速，自动切换最快源（官方最快则不动，已自定义则跳过）
- **GSD Core 工作流** — 项目全生命周期管理（官方继任项目，原生支持 OpenCode）
- **CodeGraph MCP** — 代码图索引工具（`codegraph_*` 工具族，项目内 `codegraph init` 后生效）
- **零假设** — 除 curl 和 git 外不依赖任何预装工具（node/bun 均自动安装）

## 安装效果

```
~/.config/opencode/
├── opencode.json           ←  Provider + MCP（gsd/codegraph）+ 插件配置（oh-my-openagent + superpowers）
├── oh-my-openagent.json    ←  Agent 模型路由
├── node_modules/           ←  oh-my-openagent + superpowers 插件
├── plugins/                ←  rtk.ts（命令输出压缩）
├── command/                ←  GSD Core 命令（/gsd-* 斜杠命令）
├── agents/                 ←  GSD Core 子 Agent
└── skills/                 ←  技能链接库

~/.claude/
└── settings.json           ←  Hooks 配置

~/.npmrc                    ←  npm 镜像源（npmmirror）
~/.bunfig.toml              ←  Bun registry 镜像
```

## 使用方式

安装脚本按 11 步执行：

1. 检测非 bash 环境并自动切换
2. 检测已有配置并备份
3. 生成 opencode.json（含 codegraph MCP）/ oh-my-openagent.json / Claude settings
4. apt 源测速优化（6 国内镜像 + 官方测速，最快者自动切换，失败自动还原）
5. 检查前置依赖：unzip、node（缺失自动安装）+ 配置 npm 镜像源
6. 安装 Bun 运行时（npm 镜像优先，失败回退官方脚本）+ Bun registry 配置
7. 通过 Bun 安装 OpenCode
8. 安装 oh-my-openagent 插件
9. 安装 GSD Core 工作流（npx 官方安装器）
10. 安装 CodeGraph CLI
11. 安装 RTK（镜像链下载，集成 OpenCode 插件，自动关闭遥测）

### 自定义路径

```bash
export OPENCODE_CONFIG_DIR=/custom/path/opencode
export CLAUDE_CONFIG_DIR=/custom/path/claude
./setup-opencode.sh
```

### 自定义 npm 镜像源

默认 `https://registry.npmmirror.com`。如需其他镜像或恢复官方源：

```bash
export NPM_REGISTRY=https://registry.npmjs.org
./setup-opencode.sh
```

脚本不会覆盖已有的 `~/.npmrc` 和 `~/.bunfig.toml` 中的 registry 配置。

### apt 源优化控制

apt 源测速默认执行：官方源最快则保持不动；若源文件已自定义（非官方域名）则跳过，避免覆盖手动配置。可用环境变量控制：

```bash
export SKIP_APT_MIRROR=1      # 完全跳过 apt 源优化
export FORCE_APT_MIRROR=1     # 强制重新测速并切换（即使已自定义）
./setup-opencode.sh
```

切换前自动备份原文件为 `sources.list.bak`；`apt-get update` 失败时提示还原命令。

### 备份

```bash
./backup-opencode-config.sh
```

## 配置

### API 密钥

```bash
nano ~/.config/opencode/opencode.json
```

```json
{
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "sk-your-key-here",
        "baseURL": "https://api.anthropic.com"
      }
    }
  }
}
```

**使用 DeepSeek**（Anthropic 兼容接口）：

```json
{
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "sk-your-deepseek-key",
        "baseURL": "https://api.deepseek.com/anthropic"
      }
    }
  }
}
```

### 模型路由（可选）

oh-my-openagent 使用源码内置的默认模型 + 回退链，开箱即用。

如需自定义，编辑 `~/.config/opencode/oh-my-openagent.json`，为 agent 添加 `model` 字段：

```json
{
  "agents": {
    "oracle": {"model": "deepseek/deepseek-v4-flash"},
    "explore": {"model": "deepseek/deepseek-v4-flash"},
    "sisyphus-junior": {"model": "deepseek/deepseek-v4-flash"}
  }
}
```

不设 model = 使用内置默认，优先级：
```
agent model > category model > 用户 fallback_models > OpenCode 默认 model > 源码内置回退链
```

## Agent 一览

| Agent | 职责 |
|-------|------|
| **hephaestus** | 构建与实现 |
| **oracle** | 架构、调试、高难度推理 |
| **librarian** | 外部文档、OSS 代码搜索 |
| **explore** | 代码库模式发现 |
| **multimodal-looker** | PDF/图片分析 |
| **prometheus** | 规划与策略 |
| **metis** | 预规划顾问 |
| **momus** | 计划评审 |
| **atlas** | 知识管理 |
| **sisyphus-junior** | 专注任务执行 |

## Category 一览

| Category | 适用场景 |
|----------|---------|
| visual-engineering | 前端、UI/UX、CSS |
| ultrabrain | 复杂逻辑、算法 |
| deep | 自主问题解决 |
| artistry | 创意/非常规方案 |
| quick | 单文件简单修改 |
| unspecified-low | 低难度杂项 |
| unspecified-high | 高难度杂项 |
| writing | 文档、写作 |

## GSD Core 工作流

GSD Core（[open-gsd/gsd-core](https://github.com/open-gsd/gsd-core)）是 GSD 的官方继任项目，原生支持 OpenCode。安装后无需额外配置即可使用 `/gsd-*` 命令：

| 命令 | 功能 |
|------|------|
| `/gsd-new-project` | 初始化项目 |
| `/gsd-plan-phase` | 创建执行计划 |
| `/gsd-execute-phase` | 带原子提交的执行 |
| `/gsd-progress` | 进度跟踪 |
| `/gsd-help` | 全部命令列表 |

## CodeGraph

脚本会在 opencode.json 中注册 codegraph MCP 并安装 CLI。索引按项目启用：

```bash
cd your-project
codegraph init        # 生成 .codegraph/ 索引（之后自动增量同步）
```

重启 OpenCode 后 `codegraph_explore` 等工具生效。无索引的目录中 MCP 自动休眠，不影响其他工具。

## RTK（Token 节省）

脚本安装 RTK 并注册 OpenCode 插件（`~/.config/opencode/plugins/rtk.ts`）。插件在 bash 工具执行前拦截命令，重写为 `rtk` 等价命令，输出进入 LLM 前被压缩（git/test/build 等常见命令节省 60-90% Token）。

```bash
rtk gain          # 查看累计节省统计
rtk discover      # 发现未被覆盖的命令
rtk init --opencode -g   # 重装/修复 OpenCode 插件
```

RTK 安装走镜像链（gh-proxy.com → ghfast.top → 官方直连），无需 GitHub 认证。重启 OpenCode 后生效。内置工具（Read/Grep/Glob 等）不走 bash hook，不受影响；命令失败时完整原始输出保存在 `~/.local/share/rtk/tee/` 可追溯。

## 常见问题

### 国内网络安装慢

脚本已默认使用 npmmirror 镜像（npm/npx/bun 全部走镜像），apt 源自动测速切换最快国内镜像。Bun 安装优先走 npm 镜像，不再依赖 GitHub。node 安装仍走 nodesource，若也慢请手动安装 node 后重跑脚本。RTK 下载走 GitHub 代理镜像链（gh-proxy.com → ghfast.top → 官方直连），任一源可用即成功。

### RTK 未生效

重启 OpenCode 后插件才加载。验证：

```bash
rtk --version     # 应显示 rtk 0.45.x
ls ~/.config/opencode/plugins/rtk.ts   # 插件文件存在
```

若插件文件缺失，手动执行 `rtk init --opencode -g`。

### `node: not found`

**原因**：在 WSL 中运行了 Windows npm 安装的 opencode。

**解决**：用 Bun 在 **WSL 内**重新安装：

```bash
# 确保在 WSL 内执行
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
bun install -g opencode-ai
```

### 插件不生效

重启 OpenCode 会话后生效。

### GSD Core 安装失败

确保 Node.js 已安装，然后手动运行：

```bash
npx --yes @opengsd/gsd-core@latest --opencode --global
```

### "未检测到 OpenCode 环境"

在 OpenCode 终端会话内运行命令。

## 环境要求

- bash（用 `sh` 运行会自动切换）
- curl / git / 网络连接

node、Bun、OpenCode 由脚本自动安装。

## 文件清单

| 文件 | 说明 |
|------|------|
| `setup-opencode.sh` | 统一安装脚本（唯一入口） |
| `backup-opencode-config.sh` | 配置文件手动备份工具 |

## License

MIT
