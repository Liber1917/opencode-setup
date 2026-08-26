# skill 生态碰撞实测报告:addyosmani/agent-skills × obra/superpowers

- 生成日期:2026-08-23
- 数据源:superpowers 14 个 SKILL.md(本地 `/root/.cache/opencode/packages/superpowers@git+https:/github.com/obra/superpowers.git/node_modules/superpowers/skills/`)+ agent-skills 24 个 SKILL.md(GitHub API 拉取,base64 解码),共 38 个
- 方法:frontmatter 的 name+description 提取 → 分词(去停用词)→ 两两 Jaccard 相似度;四组已知撞车对拉全文做人工判定

---

## 0. 执行摘要(top-3 冲突对)

| 排名 | 冲突对 | 类型 | 判定 | 建议 |
|---|---|---|---|---|
| 1 | superpowers/using-superpowers ↔ agent-skills/using-agent-skills | 元技能(Meta-skill) | **冲突** | 二选一,保留宿主生态对应的那一个 |
| 2 | superpowers/test-driven-development ↔ agent-skills/test-driven-development | 同名同功能 | **冲突** | 二选一(内容 AG 更厚,门禁 SP 更严) |
| 3 | superpowers/brainstorming ↔ agent-skills/idea-refine | 触发门禁重叠 | **冲突(可合并)** | 保留 SP brainstorming,吸收 idea-refine 模板 |

关键实证结论:**description 分词 Jaccard 无法检出功能撞车**。四个已知撞车对在两两 Jaccard 中得分仅 0.000~0.050,全部跌出 top-15;真正的撞车信号是 ①触发门禁(frontmatter description 中的 MUST/Use when)重叠 ②同名 ③正文方法论同构。Jaccard 反而检出了描述层面相似的隐藏冲突(元技能对 0.105、writing-plans↔planning-and-task-breakdown 0.133)。

---

## 1. 碰撞矩阵(38 × 38 两两 Jaccard)

完整 38×38 矩阵见 `/tmp/opencode/skill-data/jaccard_pairs.json`(701 对)。

### 1.1 Top-15 最相似对(全量排序)

| # | Jaccard | 生态 | 左侧 | 右侧 | 跨生态 |
|---|---|---|---|---|---|
| 1 | 0.167 | SAME | superpowers/subagent-driven-development | superpowers/using-git-worktrees | 否 |
| 2 | 0.133 | CROSS | superpowers/writing-plans | agent-skills/planning-and-task-breakdown | **是** |
| 3 | 0.125 | SAME | superpowers/requesting-code-review | superpowers/writing-plans | 否 |
| 4 | 0.120 | CROSS | superpowers/brainstorming | agent-skills/frontend-ui-engineering | **是** |
| 5 | 0.111 | CROSS | superpowers/using-superpowers | agent-skills/using-agent-skills | **是** |
| 6 | 0.100 | SAME | superpowers/brainstorming | superpowers/writing-plans | 否 |
| 7 | 0.100 | SAME | superpowers/dispatching-parallel-agents | superpowers/subagent-driven-development | 否 |
| 8 | 0.100 | SAME | superpowers/executing-plans | superpowers/subagent-driven-development | 否 |
| 9 | 0.100 | CROSS | superpowers/executing-plans | agent-skills/code-review-and-quality | **是** |
| 10 | 0.098 | SAME | agent-skills/doubt-driven-development | agent-skills/source-driven-development | 否 |
| 11 | 0.091 | SAME | superpowers/brainstorming | superpowers/requesting-code-review | 否 |
| 12 | 0.091 | SAME | superpowers/using-superpowers | superpowers/writing-skills | 否 |
| 13 | 0.091 | SAME | agent-skills/context-engineering | agent-skills/using-agent-skills | 否 |
| 14 | 0.087 | SAME | agent-skills/ci-cd-and-automation | agent-skills/context-engineering | 否 |
| 15 | 0.083 | CROSS | superpowers/brainstorming | agent-skills/interview-me | **是** |

### 1.2 全部跨生态对(Jaccard ≥ 0.05)

| Jaccard | 左侧 | 右侧 | 是否需处理 |
|---|---|---|---|
| 0.133 | superpowers/writing-plans | agent-skills/planning-and-task-breakdown | 需协调(计划 vs 任务拆分,可串联) |
| 0.120 | superpowers/brainstorming | agent-skills/frontend-ui-engineering | 词面巧合,无需处理 |
| 0.111 | superpowers/using-superpowers | agent-skills/using-agent-skills | **元技能冲突,必须二选一** |
| 0.100 | superpowers/executing-plans | agent-skills/code-review-and-quality | 词面巧合 |
| 0.083 | superpowers/brainstorming | agent-skills/interview-me | 词面巧合 |
| 0.083 | superpowers/finishing-a-development-branch | agent-skills/test-driven-development | 词面巧合 |
| 0.077 | superpowers/dispatching-parallel-agents | agent-skills/frontend-ui-engineering | 词面巧合 |
| 0.077 | superpowers/writing-plans | agent-skills/incremental-implementation | 词面巧合 |
| 0.067 | superpowers/subagent-driven-development | agent-skills/context-engineering | 词面巧合 |
| 0.067 | superpowers/subagent-driven-development | agent-skills/using-agent-skills | 词面巧合 |
| 0.067 | superpowers/systematic-debugging | agent-skills/test-driven-development | 词面巧合 |
| 0.067 | superpowers/writing-skills | agent-skills/using-agent-skills | 词面巧合 |
| 0.062 | superpowers/writing-skills | agent-skills/ci-cd-and-automation | 词面巧合 |
| 0.059 | superpowers/requesting-code-review | agent-skills/planning-and-task-breakdown | 词面巧合 |
| 0.059 | superpowers/writing-plans | agent-skills/interview-me | 词面巧合 |
| 0.056 | superpowers/executing-plans | agent-skills/context-engineering | 词面巧合 |
| 0.056 | superpowers/executing-plans | agent-skills/using-agent-skills | 词面巧合 |
| 0.056 | superpowers/writing-plans | agent-skills/code-review-and-quality | 词面巧合 |
| 0.053 | superpowers/brainstorming | agent-skills/planning-and-task-breakdown | 词面巧合 |
| 0.053 | superpowers/requesting-code-review | agent-skills/code-review-and-quality | 已知撞车对之一(见 §2.4) |
| 0.053 | superpowers/systematic-debugging | agent-skills/ci-cd-and-automation | 词面巧合 |

注意:top-15 中大部分是生态内部相似(SP 内部流程技能天然共享"implementation/plan/subagent"等词汇),真正需要跨生态处理的只有 5 个跨生态对。

---

## 2. 四组已知撞车对判定

### 2.1 brainstorming ↔ idea-refine

| 维度 | superpowers/brainstorming | agent-skills/idea-refine |
|---|---|---|
| 长度 | 15,362 字符 / 250 行 | 8,083 字符 / 178 行 |
| 触发门禁 | 强:"You MUST use this before any creative work" | 弱:"Use when an idea is still vague" + 显式触发词(ideate/refine this idea) |
| 反合理化表 | 无独立表(有 Red Flags 章节) | 无表(有 Anti-patterns to Avoid + Red Flags) |
| 方法论 | 三路径(发散-收敛-设计)+ 架构路径 + Process Flow,23 个编号步骤 | 发散/收敛两阶段 + 结构化输出模板(Problem Statement/Assumptions/MVP Scope/Not Doing) |
| 独有内容 | 设计到实现的全链路,Checklist | 产出模板([Idea Name] 文档)、Verification 章节 |

**判定:冲突(触发门禁重叠)。** 两者都在"动手前的创意/需求打磨"阶段触发;SP 用 MUST 强门禁会优先抢到所有创意任务,idea-refine 的弱触发词几乎永远没机会执行。方法论均为"先发散后收敛",功能高度重叠;差异仅在输出形态(SP 出设计,AG 出 idea 文档模板)。

**建议:保留 superpowers/brainstorming,弃用 idea-refine。** 理由:①门禁更强、覆盖"需求→设计"全链路;②SP 生态内与 writing-plans/executing-plans 形成闭环。如舍不得模板,可把 idea-refine 的 [Idea Name] 输出模板手工并入 brainstorming(不装该 skill)。

### 2.2 test-driven-development ↔ test-driven-development(同名)

| 维度 | superpowers/test-driven-development | agent-skills/test-driven-development |
|---|---|---|
| 长度 | 8,999 字符 / 320 行 | 16,255 字符 / 398 行 |
| 触发门禁 | "Use when implementing any feature or bugfix, before writing implementation code" | "Use when implementing any logic, fixing any bug, or changing any behavior" |
| 反合理化表 | 有,10 行(含"测试后写=证明不了任何事"等) | 有,7 行(含"重复跑测试求安心"等) |
| 方法论 | Iron Law + 红绿重构 5 步(RED→Verify RED→GREEN→Verify GREEN→REFACTOR) | 红绿重构 3 步 + Prove-It 模式(修 bug)+ 测试金字塔 + DAMP/DRY + AAA |
| 独有内容 | Iron Law、Verify RED/GREEN 门禁、Debugging Integration | Test Pyramid 资源模型、Browser Testing with DevTools 集成、Subagent 测试、Test Anti-Patterns |

**判定:冲突(同名 + 同功能 + 门禁同时触发)。** 这是最直接的打架:两个 skill 名字完全一样,触发场景完全重叠,同时装必然随机命中其一,红绿循环一致但细节门禁不同(SP 强调先看测试失败再写实现,AG 强调先摸清技术栈)。

**建议:二选一。** 选择依据:
- 选 **agent-skills 版**:内容量近 2 倍,含测试金字塔/浏览器测试/Prove-It 模式,适合工程细节导向的 preset;
- 选 **superpowers 版**:Iron Law + Verify 门禁更严格,与 SP 的 systematic-debugging/verification-before-completion 协同更紧;
- 默认推荐:**superpowers 版**(保持生态一致性,门禁语义更强),若项目重前端浏览器测试则换 AG 版。

### 2.3 systematic-debugging ↔ debugging-and-error-recovery

| 维度 | superpowers/systematic-debugging | agent-skills/debugging-and-error-recovery |
|---|---|---|
| 长度 | 9,441 字符 / 283 行 | 10,471 字符 / 300 行 |
| 触发门禁 | "Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes" | "Use when tests fail, builds break, behavior doesn't match expectations" |
| 反合理化表 | 有,8 行(含"紧急没时间走流程"等) | 有,5 行(含"我知道 bug 在哪直接修"等) |
| 方法论 | Iron Law + 四阶段(根因调查→模式分析→假设与验证→实现) | Stop-the-Line 规则 + 6 步 triage(复现→定位→缩减→修根因→防复发→端到端验证) |
| 独有内容 | Pattern Analysis 阶段、Quick Reference、"无根因"处理 | 错误类型 triage(测试/构建/运行时)、错误输出不可信(安全)、插桩指南、Safe Fallback |

**判定:冲突(功能等价,方法论同构)。** 两者都是"根因优先、禁止猜修"的系统化调试;SP 四阶段与 AG 六步 triage 是同一思想的两种切分。门禁同时触发(任何 bug/测试失败),装两个必打架。SP 门禁更严(Iron Law + MUST),AG 覆盖面更广(含安全与错误分类)。

**建议:保留 superpowers/systematic-debugging(与 SP TDD/verification 生态协同),弃用 AG 版。** 若希望获得"错误输出不可信"安全章节,可手动摘录进 SP 版;不建议两版同装。

### 2.4 requesting-code-review ↔ code-review-and-quality

| 维度 | superpowers/requesting-code-review | agent-skills/code-review-and-quality |
|---|---|---|
| 长度 | 2,952 字符 / 95 行(四组中最薄) | 20,477 字符 / 396 行(四组中最厚) |
| 触发门禁 | "Use when completing tasks, implementing major features, or before merging" | "Use before merging any change" |
| 反合理化表 | 有,2 行(dispatch 子代理 / 上下文裁剪) | 有,9 行(质量门禁类,更全) |
| 方法论 | 发起评审流程:派 reviewer 子代理、裁剪上下文、示例 | 五轴评审(正确性/可读性/架构/安全/性能)+ 5 步评审流程 + Multi-Model Review + 32 项 checklist |
| 独有内容 | "如何发起一次评审"(请求方视角) | "如何执行一次评审"(评审方视角),结构补救、变更尺寸、死代码卫生 |

**判定:互补(视角不同,但触发门禁重叠)。** SP 版是"请求评审"的发起流程(请求方视角,2KB 很薄),AG 版是"执行评审"的质量检查(评审方视角,20KB 很厚)。两者职责正交,理论上可串联:SP 发起 → AG 执行。但触发门禁都挂在"before merging",同时装可能在完成阶段抢触发。

**建议:默认保留 agent-skills/code-review-and-quality,弃用 SP requesting-code-review。** 理由:①AG 版内容量 7 倍,评审执行能力完整(五轴+checklist);②SP 版的"派子代理评审"模式在 AG 的 Multi-Model Review Pattern 中有对应物;③若坚持子代理评审工作流,则反过来:保留 SP 版,把 AG 版作为其评审执行器(需 preset 显式编排,不能靠自动触发)。

---

## 3. 隐藏冲突(Jaccard 检出的非已知对)

| 冲突对 | Jaccard | 说明 | 建议 |
|---|---|---|---|
| superpowers/using-superpowers ↔ agent-skills/using-agent-skills | 0.111 | **两个元技能**:都管"如何发现/调用其他技能",都要求会话开始时激活 | **必须二选一**,按 preset 宿主生态选:superpowers 生态选 using-superpowers;agent-skills 生态选 using-agent-skills |
| superpowers/writing-plans ↔ agent-skills/planning-and-task-breakdown | 0.133(跨生态最高) | writing-plans 产出实现计划;planning-and-task-breakdown 把需求拆成有序任务 | 不冲突可串联(先写计划再拆任务),但触发场景接近,preset 中建议显式编排而非都设自动触发 |
| superpowers/brainstorming ↔ agent-skills/interview-me | 0.083 | interview-me 是逐问访谈提取意图,与 brainstorming 的需求探索有交叠 | 可共存(interview-me 用于需求极模糊时,触发词不同),preset 中把 interview-me 触发优先级降级 |

---

## 4. 建议默认装清单

### 4.1 superpowers 侧(保留 13 / 14)

| Skill | 处置 | 理由 |
|---|---|---|
| brainstorming | 保留 | 替代 idea-refine(§2.1) |
| test-driven-development | 保留 | 替代 AG 同名(§2.2) |
| systematic-debugging | 保留 | 替代 debugging-and-error-recovery(§2.3) |
| writing-plans / executing-plans | 保留 | 与 brainstorming 闭环,与 planning-and-task-breakdown 串联 |
| subagent-driven-development / dispatching-parallel-agents | 保留 | 无 AG 对应 |
| verification-before-completion | 保留 | 无 AG 对应,质量门禁 |
| requesting-code-review | **弃用** | 被 code-review-and-quality 覆盖(§2.4) |
| receiving-code-review | 保留 | 无 AG 对应 |
| using-git-worktrees / finishing-a-development-branch | 保留 | 无 AG 对应 |
| writing-skills | 保留 | 元技能,与 using-superpowers 配套 |
| using-superpowers | 保留 | 元技能(§3 二选一:本生态侧保留) |

### 4.2 agent-skills 侧(保留 19 / 24)

| Skill | 处置 | 理由 |
|---|---|---|
| idea-refine | **弃用** | 被 brainstorming 覆盖(§2.1) |
| test-driven-development | **弃用** | 同名冲突(§2.2),如重前端测试则反向取舍 |
| debugging-and-error-recovery | **弃用** | 被 systematic-debugging 覆盖(§2.3) |
| using-agent-skills | **弃用** | 元技能冲突(§3),宿主选 using-superpowers |
| code-review-and-quality | **保留** | 四撞车对中唯一建议保留的 AG 侧(§2.4) |
| planning-and-task-breakdown | 保留(或串联) | 与 writing-plans 可串联,不冲突 |
| api-and-interface-design | 保留 | 无 SP 对应 |
| browser-testing-with-devtools | 保留 | 无 SP 对应,且为 AG TDD 独有能力的载体 |
| ci-cd-and-automation | 保留 | 无 SP 对应 |
| code-simplification | 保留 | 无 SP 对应 |
| context-engineering | 保留 | 无 SP 对应(与 using-agent-skills 解耦后独立可用) |
| deprecation-and-migration | 保留 | 无 SP 对应 |
| documentation-and-adrs | 保留 | 无 SP 对应 |
| doubt-driven-development | 保留 | 无 SP 对应 |
| frontend-ui-engineering | 保留 | 无 SP 对应 |
| git-workflow-and-versioning | 保留 | 与 using-git-worktrees 无冲突(工具层 vs 流程层) |
| incremental-implementation | 保留 | 无 SP 对应 |
| interview-me | 保留(降级触发) | 与 brainstorming 交叠但可共存(§3) |
| observability-and-instrumentation | 保留 | 无 SP 对应 |
| performance-optimization | 保留 | 无 SP 对应 |
| security-and-hardening | 保留 | 无 SP 对应 |
| shipping-and-launch | 保留 | 无 SP 对应 |
| source-driven-development / spec-driven-development | 保留 | 无 SP 对应 |

### 4.3 汇总

- 默认装:superpowers 13 + agent-skills 19 = **32 个**(38 - 6 弃用)
- 弃用清单(6):agent-skills 的 idea-refine、test-driven-development、debugging-and-error-recovery、using-agent-skills + superpowers 的 requesting-code-review(共 5),另 1 个视选型二选一(AG TDD 反向取舍时换成弃 SP TDD,总数不变)
- 必冲突点(绝对不可同装):using-superpowers + using-agent-skills;两个 TDD;brainstorming + idea-refine;systematic-debugging + debugging-and-error-recovery

---

## 附录 A:方法说明

- 描述文本来源:各 SKILL.md frontmatter 的 `description` 字段(YAML 解析,支持块标量)
- 分词:小写化、非字母数字字符替换为空格、去停用词(约 260 个通用英文停用词)、词长 > 2
- Jaccard = |A ∩ B| / |A ∪ B|,两两计算 38×38 共 701 对(去自对)
- 完整对级数据:`/tmp/opencode/skill-data/jaccard_pairs.json`;原始 SKILL.md 全文缓存在 `/tmp/opencode/skill-data/{superpowers,agent-skills}/`
- 局限性:Jaccard 只反映描述措辞相似度;功能撞车由触发门禁(frontmatter description 的 MUST/Use when 场景)、skill 同名、正文方法论同构决定——三者已通过全文人工判定覆盖(§2)
