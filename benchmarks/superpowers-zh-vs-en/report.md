# superpowers-zh(中文版)vs obra/superpowers(英文原版)skill 质量评测

- 生成日期:2026-08-29
- 被测模型:GLM-5.1(`zhipuai-coding-plan/glm-5.1`),经 `opencode run --pure` 子进程实测
- 调用预算:20 次,实际 **15 次**(13 格 + 2 次复采样),0 超时 0 配额失败,全部 rc=0
- 评分人:编排者(逐 transcript + 产物打分,0-3 × 3 维:流程遵循/门禁执行/产出质量)
- 方法参考:`/home/opencode-setup/benchmarks/collision-bench/report.md §0`

---

## 1. 仓库定位

**结论:找到独立中文版仓库,主候选为 `jnMetaCode/superpowers-zh`(7,878 ⭐)。**

GitHub 搜索 `superpowers-zh` 共 30+ 结果,头部:

| 仓库 | ⭐ | 定位 |
|---|---|---|
| **jnMetaCode/superpowers-zh** | 7,878 | obra/superpowers 完整汉化 + 6 个中国原创 skill,独立仓库(非 GitHub fork,手工同步),2026-03 创建、**2026-08-18 仍在活跃 push**,支持 16 款 AI 编程工具安装 |
| squallopen/superpowers-zh-adapters | 35 | 中文触发/中文文档输出的适配层 |
| aaione/superpowers-zh、vinvcn/obra-superpowers-zh-CN 等 | ≤8 | 个人翻译镜像,不具代表性 |

obra/superpowers 仓库本身无中文分支/目录(其分发为 npm 包,本地缓存 v6.3.0,14 个 skill)。评测对象取 jnMetaCode/superpowers-zh(main 分支,已克隆至 `/tmp/opencode/superpowers-zh`)。

## 2. 结构对比

### 2.1 skill 清单

zh 版共 **20 个** skill = EN v6.3.0 全部 **14 个**(逐一对应,无缺漏)+ **6 个中国原创**:

`chinese-code-review`(282L)、`chinese-commit-conventions`(369L)、`chinese-documentation`(453L)、`chinese-git-workflow`(552L)、`mcp-builder`(260L)、`workflow-runner`(177L)——前四个为中国团队协作规范类,mcp-builder/workflow-runner 为工具集成类。

### 2.2 共有 skill 逐项对比(SKILL.md 行数 EN/ZH + 参考文件数)

| skill | EN-LC | ZH-LC | EN-ref | ZH-ref | 判读 |
|---|---|---|---|---|---|
| test-driven-development | 320 | 325 | 1 | 1 | 逐节对齐,翻译完整(含全部"借口-现实"表) |
| systematic-debugging | 283 | 289 | 10 | 10 | 逐节对齐,四阶段/红线/速查表俱全 |
| brainstorming | 250 | **161** | 3 | 3 | **版本滞后**:zh 为旧版固定 9 步清单结构;EN v6.3.0 已重写为"按复杂度分级路径" |
| executing-plans | 64 | **181** | 0 | 0 | 反向滞后:上游新版本大幅精简(64L),zh 仍是旧版详述 |
| subagent-driven-development | 568 | **341** | 4 | 4 | 同上,上游新版扩充,zh 停在旧版 |
| writing-skills | 679 | 679 | 6 | 6 | 行数完全一致,忠实翻译 |
| 其余 8 个(dispatching/finishing/receiving/requesting/worktrees/using-superpowers/verification/writing-plans) | — | ±10% 内 | — | — | 对齐良好 |

- **参考文件:全部 1:1 保留**(含 debug 的 10 个辅助文档、TDD 的 writing-good-tests.md、brainstorming 的 scripts/visual-companion 等)。
- **frontmatter 差异**:① description 全文中文化(触发词本地化——中文 prompt 匹配更强,英文 prompt 匹配变弱,本次未测英文 prompt 侧);② zh 增加字段 `version` / `license` / `metadata.hermes.tags`;③ 个别原创 skill 明确"仅显式调用,不要自动触发"(chinese-code-review)。
- **抽查 3 个共有 skill 正文**(brainstorming/systematic-debugging/test-driven-development):翻译完整、无截断、无节删;方法论硬门禁(HARD-GATE、铁律、红灯验证"必须执行"等)全部保留;仅 brainstorming 因上游版本差缺"分级路径"新结构。

### 2.3 版本结论

zh 版基于上游**旧版快照**(约 v5.x 时代),tdd/debugging 与 v6.3.0 基本同步,但 brainstorming / executing-plans / subagent-driven-development 落后上游一次重写。仓库活跃(8 月仍有 commit),存在追平可能。

## 3. skill-bench 实测

### 3.1 设计

- **单装实测**:每格独立目录,仅装 1 个被测 skill 至 `.opencode/skills/<name>/SKILL.md`(EN 侧取自本地 v6.3.0 缓存,zh 侧取自克隆仓库),加 `--pure` 防全局插件泄漏(沿用 collision-bench §0.2)。
- **prompt 全中文且不点名方法论**(区别于 collision-bench),目的:同时测 ①frontmatter 触发(中文 description vs 英文 description)②加载后流程遵循 ③产出质量。
- 任务:共有 skill 3 组 × 2 任务 × 2 侧(TDD:slugify 新功能 / discount 除 100 bug;debug:while-continue 死循环 / first_last 边界双 bug;brainstorm:习惯打卡 app / 记账 CLI)+ zh 独有 chinese-code-review × 1(代码审查 payment.py,埋 6 类问题)。
- `timeout 300`/格,实测 18–128s;模型 glm-5.1(与 collision-bench 的 5.3 不同,故不复用其数据)。

### 3.2 评分矩阵(0-3 × 流程/门禁/产出)

| 格 | EN 版 | ZH 版 | 关键证据 |
|---|---|---|---|
| tdd-1 slugify | 3/3/3 = **9** | 3/3/3 = **9** | 两侧均加载 skill、完整 RED(ModuleNotFoundError)→GREEN;zh 测试更全(14 vs 7,含非字符串/制表符边界) |
| tdd-2 discount(s1) | 1/1/3 = **5** | 3/3/3 = **9** | **EN 未触发 skill**:直接改一行+手动验证,零测试;zh 触发并 3 测试先失败后通过 |
| tdd-2 复采样(s2) | 3/3/3 = 9(取中位 **7**) | 3/3/3 = **9** | EN 仍**未自动触发**(0/2),但自行 Read 了 SKILL.md 文件后补走完整 TDD;zh 2/2 自动触发 |
| dbg-1 死循环 | 2/2/3 = **7** | 3/2/3 = **8** | zh 先复现取证(timeout exit=124 实证死循环,还排查了管道缓冲假象)再修;EN 直接给根因跳过复现 |
| dbg-2 first_last | 2/2/3 = **7** | 3/3/3 = **9** | zh 显式走 Phase1 复现双症状 → **修复前先写失败测试**(1 error+1 failure 精确对应双 bug)→ 修复 → 4 测试绿;EN 读码即修,仅事后断言 |
| br-1 习惯打卡 | 3/3/1 = **7** | 3/3/1 = **7** | 两侧均触发且忠实方法论但单发模式下"卡关":EN 一个澄清问题即停;zh 建 9 项 checklist 后停在"视觉伴侣"独立确认门(更早)。产出均未达 prompt 要求 |
| br-2 记账 CLI | 3/2/3 = **8** | 3/2/3 = **8** | 两侧均满额产出(MVP 命令集+3 方案存储对比+整数分存储决策+YAGNI),质量等价 |
| **共有 skill 小计(满分 54)** | **45** | **50** | |
| cr-1 zh 独有 | — | 未触发(**符合设计**:该 skill 声明仅显式调用);无 skill 基线仍找出全部 6 类问题(硬编码密钥+轮换建议/SQL 注入/可变默认参/连接未关/无回滚/浮点金额),产出质量 3 | 价值定位:话术模板/规范参考,非自动增强 |

### 3.3 关键发现

1. **中文 prompt 触发可靠性:zh 版占优(实证 tdd-2 组 2/2 vs 0/2)**。机制合理:zh description 含"修复 bug/实现功能"中文词,与中文 prompt 语义直接匹配;EN 英文 description 跨语言匹配更弱。EN 侧 s2 靠"看见项目目录里的 SKILL.md 手动读取"自救,说明触发缺口可部分自愈但不稳定。样本量 2,方向明确但幅度待更多采样。
2. **加载后的流程遵循:zh 版 debug 组更严格**(2/2 先复现取证、1 例修复前写失败测试;EN 2/2 均跳过复现直接修)。翻译质量本身无损,中文指令令 GLM-5.1 遵循度更高是合理解释。
3. **brainstorming 双侧同弱**:单发 prompt 下"一问一停/卡在确认门"与 collision-bench 对 SP 英文版的观察一致,是方法论与评测形态的张力,非翻译问题;zh 版还叠加上游旧结构(无分级路径,更"一刀切走全流程")。
4. **产物质量**:12 个共有格中 11 格两侧同为 3 分,无翻译导致的产出劣化。

## 4. 替换建议

**部分换(按场景混装),不建议全换。**

| 场景 | 建议 |
|---|---|
| 中文交互为主(GLM/Qwen/DeepSeek 等中文模型或中文团队) | **共有 14 个 skill 可整体换 zh 版**:翻译完整、参考文件 1:1、触发与流程遵循实测更优(45→50/54) |
| 英文交互为主 / 混合语言环境 | 保留 EN 版:zh 的 frontmatter 全中文,英文 prompt 触发匹配会反向受损(本次未实测,结构性风险) |
| brainstorming | 两版都不理想:EN v6.3.0 有上游新版分级路径,zh 版结构更旧;多轮交互场景两者皆可,单发产出场景均有"卡关"问题 |
| zh 独有 6 个 skill | **按需选装、非自动收益**:chinese-* 4 个是国内协作规范参考(其中 chinese-code-review 为显式调用型),适合国内团队;mcp-builder/workflow-runner 按工具栈需要 |
| 跟进策略 | zh 仓库活跃;若其同步上游 6.x(brainstorming/executing-plans/sdd 三处重写),可升级为"中文环境默认换、英文环境保留 EN" |

理由总结:zh 版不是劣化翻译,而是"完整汉化+触发本地化+轻微版本滞后"的 fork;质量差距主要来自上游版本差(3/14 个 skill)与使用语言场景,而非翻译本身。

## 5. 资源与复现

- 产物目录:`/tmp/opencode/cells/zve-*/`(transcript.txt + 代码/测试产物,prompt.txt 同置)
- 运行日志:`/tmp/opencode/cells/ZVE-RUNLOG.txt`;zh 仓库克隆:`/tmp/opencode/superpowers-zh`
- GLM-5.1 调用 15 次(≤20 预算):13 格首轮 + tdd-2 双侧复采样各 1
- 评分无降级(全部实测,无专家评估替位)
