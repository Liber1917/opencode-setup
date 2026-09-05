# sp-router — superpowers 路由模式(渐进披露移植)

## 问题

superpowers-zh 官方 OpenCode 插件两层急加载,实测 **9,158 token/对话起步税**(arm-sp 微任务基线):
1. `config` 钩子把 20 个 skill 目录注册进 opencode 扫描路径 → 全部 name+description 进 system prompt
2. `messages.transform` 把 using-superpowers **全文**注进首条消息(`<EXTREMELY_IMPORTANT>` 块)

## 方案

本插件替代官方急加载:
- **不注册**扫描路径(描述税归零)
- 首条消息只注入 ~400 token 能力清单(名称+一行命中时机+vault 路径)
- agent 命中场景 → `Read <vault>/<name>/SKILL.md` 按需加载正文(等价 Claude Code 渐进披露)

## 实测(2026-08-30, zhipuai glm-5.3)

| 指标 | 官方注入 | sp-router |
|---|---|---|
| 微任务基线输入 token | 9,158 | **936(−90%)** |
| 调试任务路由触发 | —(全文常驻) | ✓ agent 主动 Read systematic-debugging 并遵循 |
| 技能能力 | 全部 20 个 | 全部 20 个(vault 同一份) |

## 取舍(诚实边界)

- **强制性换发现性**: 官方 `<EXTREMELY_IMPORTANT>` 每轮硬约束"先查技能";路由模式靠清单+模型自觉。命中弱场景(用户没提"bug/计划"字样的隐性流程)可能漏触发 → 兜底:清单规则第 3 条指路 using-superpowers 元技能
- **vault 需在盘**: 官方模式插件缓存自带 skills;路由模式 setup 需 `git clone` superpowers-zh 到 `~/.config/opencode/sp-vault/`(更新 = `git pull`)
- **上游演进不同步**: 清单是快照(20 个技能一行时机)。上游新增技能后需重新生成——`python3` 提取 frontmatter 即可(见 plugin.js 注释)

## 启用(setup 生成时)

```bash
SUPERPOWERS_ROUTER=1 ./setup-opencode.sh
```

默认不启用(保持官方行为);已装用户手动切换:
```bash
git clone --depth 1 https://github.com/jnMetaCode/superpowers-zh.git ~/.config/opencode/sp-vault/superpowers
# opencode.json: plugin 数组移除 superpowers@git+..., 加入 "./plugins/sp-router/plugin.js"
cp router-modules/sp-router/plugin.js ~/.config/opencode/plugins/sp-router/  # 并替换 __SP_VAULT__ 占位符
```

## OpenCode 本地插件加载规则(踩坑实录,2026-08-30)

| 方式 | 结果 |
|---|---|
| `plugins/` 顶层 `.ts`(import 语法) | ✓ 加载(rtk.ts 同款,TS 转译无视 package.json type) |
| `plugins/` 顶层 `.js`(ESM import) | ✗ 静默失败(最近 package.json 无 type:module 按 CJS 解析) |
| `plugins/` 顶层 `.mjs` | ✗✗ **毒丸**:整个插件管线崩,连 npm 插件都不加载 |
| plugin 数组放文件路径(相对/绝对) | ✗ 数组只认 npm 包,文件路径被忽略 |
| `plugins/子目录/plugin.js` | ✗ 不发现(只扫顶层) |

**已知上游竞态**: `opencode run` 短命服务器存在插件加载竞态——同配置随机出现"插件生效/不生效"双峰(token 差 ~5x)。交互式 TUI(常驻进程)不受影响。影响所有本地插件(含官方),非本插件特有;基准与无头批量任务需多轮取样。

## 安全注意

vault 里的 SKILL.md 是第三方内容:读取走 Read 工具(受权限系统管辖),不自动执行其中脚本;与 webmap 的 S3 注入隔离原则一致。
