# opencode-setup

一键配置 [OpenCode](https://opencode.ai) 环境，集成 oh-my-openagent、GSD 工作流和完整的 Agent 生态。

```bash
curl -fsSL https://raw.githubusercontent.com/Liber1917/opencode-setup/main/setup-opencode.sh | bash
```

或克隆后运行：

```bash
git clone https://github.com/Liber1917/opencode-setup.git
cd opencode-setup
./setup-opencode.sh
```

## 特性

- **Bun 运行时** — 无需预装 Node.js，自动安装 Bun，避免跨平台 PATH 问题
- **oh-my-openagent** — 10 个 Agent + 8 个 Category 的模型路由
- **GSD 工作流** — 项目全生命周期管理
- **零假设** — 不依赖任何预装工具（除 curl 和 git）

## 安装效果

```
~/.config/opencode/
├── opencode.json           ←  Provider + 插件配置（oh-my-openagent + superpowers）
├── oh-my-openagent.json    ←  Agent 模型路由
├── node_modules/           ←  oh-my-openagent + superpowers 插件
├── get-shit-done/          ←  GSD 工作流（自动克隆）
└── skills/                 ←  技能链接库

~/.claude/
└── settings.json           ←  Hooks 配置
```

## 使用方式

### 标准安装

```bash
curl -fsSL https://raw.githubusercontent.com/Liber1917/opencode-setup/main/setup-opencode.sh | bash
```

安装脚本会自动：
1. 检测已有配置并备份
2. 生成 opencode.json / oh-my-openagent.json / Claude settings
3. 安装 Bun 运行时（如未安装）
4. 通过 Bun 安装 OpenCode
5. 安装 oh-my-openagent 插件
6. 安装 GSD 工作流

### 自定义路径

```bash
export OPENCODE_CONFIG_DIR=/custom/path/opencode
export CLAUDE_CONFIG_DIR=/custom/path/claude
./setup-opencode.sh
```

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
agent model > category model > 用户 fallback_models > 源码内置回退链 > OpenCode 默认
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

## GSD 工作流

GSD (Get Shit Done) 提供完整的项目生命周期管理：

| 命令 | 功能 |
|------|------|
| `/gsd-new-project` | 初始化项目 |
| `/gsd-plan-phase` | 创建执行计划 |
| `/gsd-execute-phase` | 带原子提交的执行 |
| `/gsd-progress` | 进度跟踪 |
| `/gsd-help` | 全部命令列表 |

## 常见问题

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

### GSD 克隆失败

```bash
git clone https://github.com/OpenAgentsInc/gsd.git ~/.config/opencode/get-shit-done
```

### "未检测到 OpenCode 环境"

在 OpenCode 终端会话内运行命令。

## 环境要求

- curl（安装 Bun 用）
- git（安装 GSD 用）
- 网络连接

Bun 和 OpenCode 由脚本自动安装。

## 文件清单

| 文件 | 说明 |
|------|------|
| `setup-opencode.sh` | **统一安装脚本（推荐）** |
| `backup-opencode-config.sh` | 配置文件备份 |

## License

MIT
