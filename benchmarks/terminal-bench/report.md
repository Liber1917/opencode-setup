# Terminal-Bench 双配置对比报告(分支实装验证)

> 2026-08-28 · opencode-setup PR #2 验证 · GLM-5.1

## 测试设计

| 组 | 配置 | 说明 |
|---|---|---|
| 对照 | 裸 opencode(tb 默认) | 无权限配置 |
| 实验 | 裸 opencode + **E-Ⅰ 权限红线(无头版)** | 分支步骤12的权限产物,base64 注入 |

- benchmark: terminal-bench(original-tasks)
- 任务: hello-world / simple-sheets-put / recover-obfuscated-files / simple-web-scraper(4 个轻量任务)
- 模型: zhipuai-coding-plan/glm-5.1(key 经 auth.json 注入)
- 自定义 agent: 扩展 tb 的 opencode agent(zhipuai provider 支持)

## 最终结果

| 任务 | 对照组 | 实验组(权限红线·无头版) |
|---|---|---|
| hello-world | ✅ | ✅ |
| simple-sheets-put | ✅ | ✅ |
| recover-obfuscated-files | ✅ | ✅ |
| simple-web-scraper | ✅ | ✅ |
| **总计** | **4/4 (100%)** | **4/4 (100%)** |

**结论:权限红线(无头版)不损失任务成功率。**

## 过程中抓出并修复的 4 个真 bug(benchmark 的真正价值)

| # | Bug | 根因 | 修复 |
|---|---|---|---|
| 1 | JSON `comment` 键被 schema 拒绝 | `Expected PermissionActionConfig` | 移除注释键,说明移到 shell 层 |
| 2 | `webfetch` 格式错误 | 传了对象,schema 要 Action 字符串 | `"webfetch": "ask"` |
| 3 | **无头模式 ask=auto-reject(认知盲区)** | `opencode run` 无 TTY,ask 直接拒绝;交互红线在 CI/benchmark 全军覆没(实测 1/4) | 新增 `--headless` 双模板:硬 deny 保留,兜底 ask→allow,补 11 个工具键 |
| 4 | 权限评估涉及多工具维度 | 模型可能走 bash/Read/glob 任一路径;`external_directory` 也参与评估 | 无头版补全 read/edit/glob/external_directory 等键 |

## 关键认知(纸面设计学不到)

1. **opencode 权限匹配**:`Wildcard.match` 全锚定正则(`^ls.*$`),`findLast` 后匹配优先——规则语义与直觉有差异,必须实测
2. **模型工具选择的随机性**:同一任务模型可能选 bash ls / Read / glob 不同路径,权限必须覆盖全工具面
3. **交互红线 ≠ 无头红线**:无头场景(自动化/CI/benchmark)需要独立基线——这个发现直接改变 E 模块设计(双模板已固化)
4. **benchmark 前配置从未真跑过**:权限模板、auth 注入都是首次端到端验证——纸面 schema 正确≠运行时正确

## 工程产物

- `e-modules/gen-permissions.sh` v2:双模板(交互/无头)
- tb 自定义 agent 方案(zhipuai 支持 + auth.json 注入)可复用
- 所有修复已提交至 e-modules-impl 分支
