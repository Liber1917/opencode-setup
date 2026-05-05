# OpenCode 环境统一分析

## 背景

在 WSL 环境中通过 Windows npm 安装 OpenCode 后运行，会出现 `node: not found` 错误。原因：

```
Windows npm install -g opencode
  → 生成 Windows 侧 shell 脚本 (AppData/Roaming/npm/opencode)
  → WSL 执行该脚本 → exec node → 找不到
```

## 解决方案：Bun 统一运行时

选择 Bun 作为统一运行时的原因：

| 方案 | 跨平台兼容性 | 需预装 | 备注 |
|------|-------------|--------|------|
| npm (Windows) | ❌ WSL 下 node: not found | Node.js | Windows 脚本调用 WSL 找不到 node |
| npm (WSL 内) | ✅ | Node.js | 需在 WSL 内重新安装 npm+node |
| **Bun** | ✅ **自包含** | 无 | Bun 自带运行时，无需 Node.js |

Bun 的优势：
- **自带 JavaScript 运行时** — 不依赖系统 Node.js
- **安装 OpenCode 时生成原生二进制** — 不会产生跨系统 PATH 问题
- **WSL/Linux/macOS 表现一致**

## 脚本统一

### 之前（3 个脚本，大量重复）

| 脚本 | 行数 | 特点 |
|------|------|------|
| `setup-opencode.sh` | 187 行 | 标准环境 |
| `setup-opencode-complete.sh` | 253 行 | 完整版，含备份检测 |
| `setup-opencode-portable.sh` | 233 行 | 可移植，环境变量 |

问题：
- 三个脚本 80% 代码重复
- 全部依赖 npm，版本号和包名有差异
- `opencode-ai` 包名错误（应为 `@opencode-ai/opencode`）
- 插件安装 `@opencode-ai/plugin@1.4.6` 不规范（应为 `oh-my-openagent@latest`）

### 之后（1 个脚本，清晰统一）

| 脚本 | 行数 | 特点 |
|------|------|------|
| `setup-opencode.sh` | ~280 行 | **唯一入口** |

合并了三个版本的优点：
- 环境变量支持自定义路径 ← portable.sh
- 已有配置检测+备份 ← complete.sh
- 界面友好的输出 ← 全部

## 修复的问题

1. **运行时**：npm → Bun（自包含，跨平台一致）
2. **包名**：`opencode-ai` → `@opencode-ai/opencode`（正确的 npm 包名）
3. **插件安装**：`@opencode-ai/plugin@1.4.6` → `oh-my-openagent@latest`（与 opencode.json plugin 配置一致）
4. **冗余脚本**：3 个 → 1 个

## 文件清单

| 文件 | 说明 |
|------|------|
| `setup-opencode.sh` | 统一安装脚本（唯一入口） |
| `backup-opencode-config.sh` | 配置备份工具 |
| `README.md` | 使用文档 |
| `OPENCODE-CONFIG-ANALYSIS.md` | 本分析文档 |
