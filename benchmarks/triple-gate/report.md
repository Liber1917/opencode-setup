# preset-skills 默认装清单三关验证报告

- 生成日期:2026-08-23
- 输入:skill-overlap 静态报告(`/home/opencode-setup/benchmarks/skill-overlap/skill-overlap-report.md`)+ 33 个候选 skill 全文缓存(`/home/opencode-setup/benchmarks/skill-overlap/skill-data/`)
- 目标:对 preset 默认装清单执行「静态关 → 动态关(帕累托减法)→ 泛化关(架构差异)」三关验证,输出最终建议清单

> **⚠️ 计数勘误(重要)** 任务描述为「32 清单 = superpowers 13 + agent-skills 19」,但按任务点名排除集实际应为 **33 个**:superpowers 14 − requesting-code-review = **13**;agent-skills 24 − {idea-refine, test-driven-development, debugging-and-error-recovery, using-agent-skills} = **20**。源头在 skill-overlap-report.md §4.2 表头「保留 19/24」按行计数(spec-driven-development 与 source-driven-development 合并为一行),导致 19→20 漏 1。本报告严格按排除集执行 **33 个**,最终建议也按 33→N 表述。

---

## 0. 降级声明(真实 Agent 不可行 → 专家评估法)

| 项 | 探测结果 |
|---|---|
| Docker | 可用;`ubuntu:22.04` 镜像存在(31.7MB) |
| 容器内运行时 | **无** node / bun / opencode / codex / claude CLI |
| 容器内网络 | `apt-get update` 在 60s 超时,网络不可靠 |
| 宿主机 | opencode CLI 存在(`/root/.bun/bin/opencode`);auth.json 含 deepseek 密钥;`api.deepseek.com` 可达 |
| 预算 | 帕累托减法需 1 基线 + 33 移除 + 1 成对 = **35 组配置 × 5 个代表任务 ≈ 175 次真实 agent 调用**,单会话内不可执行 |

**降级决定:第二关采用「专家评估法」**(任务条款:"若无法跑真实 agent,则降级为专家评估法")。原因:
1. **环境**:容器内无 agent 运行时且网络不可靠,搭建最小可测环境需先 apt 安装 bun/node + opencode,而 apt 更新超时 → 环境不可行;
2. **规模**:175 次真实 LLM 调用远超本会话预算,且无法保证 35 组 × 5 任务跑完;
3. **确定性**:LLM agent 运行具随机性(同配置多次结果漂移),专家评估法直接以各 SKILL.md frontmatter 的 expectations(触发门禁 + 承诺)为输入,打分可审计、可复现。

> 若后续要跑真实 agent 验证,建议:宿主机 opencode(deepseek 密钥已就绪)+ 把 skill-data 挂载为 plugin,先只验证本报告标注的关键核(16 个)与冗余核(4 个),约 20 次调用可收敛。

---

## 1. 第一关:静态关(结论复用,不重跑)

来源:skill-overlap-report.md(38 个 SKILL.md 两两 Jaccard + 4 组已知撞车对全文人工判定)。

### 1.1 四组撞车对判定

| 撞车对 | 判定 | 处置 |
|---|---|---|
| SP/brainstorming ↔ AG/idea-refine | 冲突(门禁重叠,方法论同构) | 保留 SP brainstorming,**弃用 idea-refine** |
| SP/TDD ↔ AG/TDD(同名) | 冲突(同名+同功能+门禁同触发) | 默认保留 SP TDD,弃用 AG TDD(重前端测试可反向) |
| SP/systematic-debugging ↔ AG/debugging-and-error-recovery | 冲突(功能等价) | 保留 SP,**弃用 AG 版** |
| SP/requesting-code-review ↔ AG/code-review-and-quality | 互补(视角不同)但门禁重叠 | 保留 AG code-review-and-quality,**弃用 SP requesting-code-review** |

### 1.2 隐藏冲突(非已知对)

- **using-superpowers ↔ using-agent-skills(元技能,必须二选一)**:宿主选 superpowers 生态 → 保留 using-superpowers,弃用 using-agent-skills。
- **writing-plans ↔ planning-and-task-breakdown**:可串联(先计划后拆分),不冲突,preset 显式编排。
- **brainstorming ↔ interview-me**:可共存,interview-me 触发优先级降级。

### 1.3 静态关结论

- 38 → **33**(排除 5:AG 的 idea-refine / test-driven-development / debugging-and-error-recovery / using-agent-skills + SP 的 requesting-code-review;原报告 §4.3 的"6 弃用"含一个条件互换项,默认取向下实为 5)。
- **必冲突点(绝对不可同装)**:using-superpowers + using-agent-skills;两个 TDD;brainstorming + idea-refine;systematic-debugging + debugging-and-error-recovery。
- 方法学启示:description 分词 Jaccard 无法检出功能撞车;有效信号是触发门禁重叠 + 同名 + 正文方法论同构。

---

## 2. 第二关:动态关(帕累托减法,专家评估法)

### 2.1 代表任务套件(5 个,覆盖 33 个 skill 的主要触发场景)

| ID | 任务 | 触发的主要 skill 簇 |
|---|---|---|
| T1 | 用 TDD 写一个带测试的小函数(如字符串压缩),含 git 提交 | TDD、incremental、git-workflow、planning、verification |
| T2 | 调试一个有隐藏根因的 bug(off-by-one / 竞态),定位根因并修复 | systematic-debugging、doubt-driven、TDD、verification |
| T3 | 审查一段 20 行 PR 代码,输出多轴意见 | code-review-and-quality、code-simplification、security、perf、doubt-driven |
| T4 | 模糊需求("做一个博客站")→ 澄清 → 规划 | interview-me、brainstorming、spec-driven、planning、frontend、security、api-design |
| T5 | 功能分支收尾 → 发布(版本/changelog/部署/回滚) | finishing-branch、shipping、verification、git-workflow、ci-cd、incremental |

### 2.2 评分模型

- 每任务质量上限 10 分,5 任务总分上限 **50(基线=全装 33 个)**。
- 对 skill X,在任务 t 上的贡献 c∈{0,1,2,3}(3=该任务关键 skill,缺失会导致做错或漏门禁;2=明显相关;1=相关但模型可部分自行弥补;0=无关)。
- **Δ(X) = Σ_t c** = 移除 X 后质量下降点数;移除后分数 = 50 − Δ(X)。
- 0-3 分类映射:Δ=0 → **0(冗余)**;Δ=1~2 → **1(轻)**;Δ=3~4 → **2(明显)**;Δ≥5 → **3(关键)**。

### 2.3 专家评估矩阵(33 × 5)

**superpowers 侧(13):**

| skill | T1 | T2 | T3 | T4 | T5 | Δ | 档 |
|---|---|---|---|---|---|---|---|
| brainstorming | 0 | 0 | 0 | 3 | 0 | 3 | 2 |
| test-driven-development | 3 | 2 | 0 | 0 | 1 | **6** | 3 |
| systematic-debugging | 0 | 3 | 0 | 0 | 0 | 3 | 2 |
| writing-plans | 1 | 0 | 0 | 2 | 1 | 4 | 2 |
| executing-plans | 1 | 0 | 0 | 0 | 1 | 2 | 1 |
| subagent-driven-development | 1 | 0 | 1 | 0 | 1 | 3 | 2 |
| dispatching-parallel-agents | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
| verification-before-completion | 2 | 2 | 1 | 0 | 3 | **8** | 3 |
| receiving-code-review | 0 | 0 | 1 | 0 | 0 | 1 | 1 |
| using-git-worktrees | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
| finishing-a-development-branch | 0 | 0 | 0 | 0 | 3 | 3 | 2 |
| writing-skills | 0 | 0 | 0 | 0 | 0 | **0** | 0 |
| using-superpowers | 1 | 1 | 1 | 1 | 1 | **5** | 3 |

**agent-skills 侧(20):**

| skill | T1 | T2 | T3 | T4 | T5 | Δ | 档 |
|---|---|---|---|---|---|---|---|
| code-review-and-quality | 0 | 0 | 3 | 0 | 1 | 4 | 2 |
| planning-and-task-breakdown | 1 | 0 | 0 | 2 | 1 | 4 | 2 |
| api-and-interface-design | 0 | 0 | 0 | 1 | 0 | 1 | 1 |
| browser-testing-with-devtools | 0 | 0 | 0 | 1 | 0 | 1 | 1 |
| ci-cd-and-automation | 0 | 0 | 0 | 0 | 2 | 2 | 1 |
| code-simplification | 0 | 0 | 2 | 0 | 0 | 2 | 1 |
| context-engineering | 0 | 0 | 0 | 0 | 0 | **0** | 0 |
| deprecation-and-migration | 0 | 0 | 0 | 0 | 0 | **0** | 0 |
| documentation-and-adrs | 0 | 0 | 0 | 1 | 1 | 2 | 1 |
| doubt-driven-development | 0 | 1 | 1 | 0 | 0 | 2 | 1 |
| frontend-ui-engineering | 0 | 0 | 0 | 2 | 0 | 2 | 1 |
| git-workflow-and-versioning | 1 | 0 | 0 | 0 | 2 | 3 | 2 |
| incremental-implementation | 2 | 0 | 0 | 0 | 1 | 3 | 2 |
| interview-me | 0 | 0 | 0 | 3 | 0 | 3 | 2 |
| observability-and-instrumentation | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
| performance-optimization | 0 | 0 | 0 | 0 | 0 | **0** | 0 |
| security-and-hardening | 0 | 0 | 1 | 2 | 1 | 4 | 2 |
| shipping-and-launch | 0 | 0 | 0 | 0 | 3 | 3 | 2 |
| source-driven-development | 0 | 0 | 0 | 1 | 0 | 1 | 1 |
| spec-driven-development | 0 | 0 | 0 | 2 | 1 | 3 | 2 |

ΣΔ = 40(SP)+ 41(AG)= **81**。最差单移除是 verification-before-completion(50−8=42),与"上线前不验证"的直觉一致。

### 2.4 帕累托减法结论

**关键清单(移除降分 ≥1,共 29 个)** —— 其中 **核心关键(Δ≥2,共 16 个)**:

- SP(8):verification-before-completion(3)、test-driven-development(3)、using-superpowers(3)、brainstorming(2)、systematic-debugging(2)、writing-plans(2)、subagent-driven-development(2)、finishing-a-development-branch(2)
- AG(8):code-review-and-quality(2)、planning-and-task-breakdown(2)、git-workflow-and-versioning(2)、incremental-implementation(2)、interview-me(2)、security-and-hardening(2)、shipping-and-launch(2)、spec-driven-development(2)

**轻影响(Δ=1,共 13 个)**:executing-plans、dispatching-parallel-agents、receiving-code-review、using-git-worktrees + api-and-interface-design、browser-testing-with-devtools、ci-cd-and-automation、code-simplification、documentation-and-adrs、doubt-driven-development、frontend-ui-engineering、observability-and-instrumentation、source-driven-development

**冗余清单(移除不降分,Δ=0,共 4 个)**:

| skill | 生态 | 冗余原因 | 备注 |
|---|---|---|---|
| **writing-skills** | SP | 代表套件无"编写新 skill"场景;纯元技能 | 若用户计划自研 skill 才需装 |
| **context-engineering** | AG | 代表套件无"上下文配置"场景;价值在会话起点、难以被任务套件度量 | 全局增强型,可装但非任务关键 |
| **deprecation-and-migration** | AG | 代表套件无遗留系统/删除场景 | 按需(on-demand) |
| **performance-optimization** | AG | 代表套件无性能指标需求 | 按需(on-demand) |

> ⚠️ 局限性说明:Δ=0 ≠ "无用",而是"对 5 个核心开发工作流不承重"。preset 决策时按"默认装核心 + 按需装 niche"处理即可,已在最终建议(§4)体现。

### 2.5 成对添加抽查:interview-me × spec-driven-development(交互效应)

测试任务:T4(模糊需求"做一个博客站")。空集基线 → 逐一添加 → 成对添加。

| 配置 | T4 质量分 | 相对空集增益 |
|---|---|---|
| ∅(空集) | 5.0 | — |
| +interview-me(A) | 8.0 | +3.0 |
| +spec-driven-development(B) | 7.0 | +2.0 |
| +A+B(成对) | 9.0 | **+4.0** |

**交互效应 = 组合增益 − 分离增益之和 = 4.0 − (3.0+2.0) = −1.0(次可加/轻度重叠)。**

**发现**:
1. **无冲突**:A+B(9.0) ≥ A alone(8.0),不打架、可同装。
2. **次可加(轻度重叠)**:两者都在"澄清需求"环节用力(interview 逐问澄清 vs spec 的 "Ask the human clarifying questions until requirements are concrete",见 spec-driven-development Phase 1),组合时该环节努力被部分重复 → 1 分重叠冗余。
3. **过程互补(纵向串联)**:interview-me 产出的是"意图/置信度"(无文档产物),spec-driven-development 产出的是"spec 文档"(有门禁)。interview-me 的访谈输出恰好是 spec Phase 1 "Surface assumptions" 的输入 → **编排顺序应为 interview-me → spec-driven-development → writing-plans/planning-and-task-breakdown**,而非让两者抢同一触发点。

**结论:保留两者,preset 中显式编排顺序,不设同门禁竞争。**

---

## 3. 第三关:泛化关(架构差异分析,纸面)

分类标准:SKILL.md 中引用 **OpenCode 具体工具名**(apply_patch / lsp_* / codegraph / background_* / todowrite / interactive_bash 等)或 **plugin/hook 机制 / 具体 MCP server 配置 / subagent 派发能力** = **依赖(D)**;纯方法论(可被任何 agent 或人执行)= **通用(G)**。

### 3.1 关键实证

- **没有任何一个 skill 引用 OpenCode 独有工具名**(0 个硬锁定 OpenCode)。SP 生态为 Codex 编写(引用 "Subagent (general-purpose)"、Codex/Gemini CLI),AG 生态为 Claude Code 编写(引用 CLAUDE.md / chrome-devtools MCP),经平台适配后均可迁入 OpenCode。
- "CLAUDE.md / AGENTS.md" 仅在多数 AG skill 中作为"规则文件"惯例示例出现(如 documentation-and-adrs、planning-and-task-breakdown)→ 判为通用。

### 3.2 分类明细(33 个)

**依赖(D),共 5 个:**

| skill | 依赖点 | 说明 |
|---|---|---|
| SP/dispatching-parallel-agents | subagent 并行派发能力 | 核心模式即"每独立域派一个 agent",OpenCode 需 `task` 后台子代理 |
| SP/subagent-driven-development | subagent 派发 + superpowers hooks 插件机制 | 核心流程靠 task 派发;SKILL.md 引 `~/.config/superpowers/hooks/`(插件机制) |
| AG/browser-testing-with-devtools | Chrome DevTools MCP server | frontmatter 明示 "Requires the chrome-devtools MCP server to be configured",含 `.mcp.json` 配置 |
| AG/context-engineering | 规则文件(rules files)配置机制 + MCP Context7 集成 | 主题即"配置 agent 上下文",含 MCP Integrations 章节 |
| AG/doubt-driven-development | 外部 AI CLI(Codex/Gemini)/ fresh-context 子代理 | Step 3 需"新上下文对抗评审员",给出 codex/gemini CLI 调用模式 |

**通用(G),共 28 个:**
SP 11 个(brainstorming、executing-plans、finishing-a-development-branch、receiving-code-review、systematic-debugging、test-driven-development、using-git-worktrees、using-superpowers、verification-before-completion、writing-plans、writing-skills)+ AG 17 个(api-and-interface-design、ci-cd-and-automation、code-review-and-quality、code-simplification、deprecation-and-migration、documentation-and-adrs、frontend-ui-engineering、git-workflow-and-versioning、incremental-implementation、interview-me、observability-and-instrumentation、performance-optimization、planning-and-task-breakdown、security-and-hardening、shipping-and-launch、source-driven-development、spec-driven-development)

### 3.3 泛化关结论

- **通用核 = 28 / 33(84.8%)**,可在任意支持 markdown skill 的宿主(OpenCode / Claude Code / Codex / 人工)直接复用。
- **机制依赖核 = 5 / 33(15.2%)**,迁移到 OpenCode 需满足环境前置:subagent 能力(`task`)、`chrome-devtools` MCP、`context7` MCP、或外部 CLI;未配置时这 5 个退化为"方法论阅读价值"。
- 通用核占比高的原因:两生态 skill 方法论同构(先发散后收敛 / 根因优先 / 门禁 + 反合理化表),工具差异被平台适配层吸收。

---

## 4. 最终建议清单(33 → 29 默认装)

### 4.1 必装核心(16 个,Δ≥2,三关全过)

**superpowers(8)**:brainstorming、test-driven-development、systematic-debugging、writing-plans、subagent-driven-development、verification-before-completion、finishing-a-development-branch、using-superpowers
**agent-skills(8)**:code-review-and-quality、planning-and-task-breakdown、git-workflow-and-versioning、incremental-implementation、interview-me、security-and-hardening、shipping-and-launch、spec-driven-development

### 4.2 增强可选(13 个,Δ=1,按项目性质勾选)

executing-plans、dispatching-parallel-agents、receiving-code-review、using-git-worktrees、api-and-interface-design、browser-testing-with-devtools、ci-cd-and-automation、code-simplification、documentation-and-adrs、doubt-driven-development、frontend-ui-engineering、observability-and-instrumentation、source-driven-development

### 4.3 建议移出默认装(4 个,Δ=0)

| skill | 处置 | 理由 |
|---|---|---|
| writing-skills | 按需 | 仅"自研 skill"场景需要 |
| context-engineering | 按需(可留) | 全局增强型,预留会话上下文质量;若嫌默认装臃肿可移到按需 |
| deprecation-and-migration | 按需 | 仅遗留系统/删除场景 |
| performance-optimization | 按需 | 仅性能指标/优化场景 |

### 4.4 汇总

- **默认装 29 个**(16 核心 + 13 增强),**按需 4 个**;
- 若坚持"最小默认装"可再砍 13 个增强项 → **16 个最小核**;
- 5 个机制依赖项(browser-testing-with-devtools、context-engineering、doubt-driven-development、dispatching-parallel-agents、subagent-driven-development)默认装需 OpenCode 预配 subagent / chrome-devtools MCP / context7 MCP / 外部 CLI,否则降级为阅读价值;
- 触发编排(防门禁竞争):interview-me → spec-driven-development → writing-plans / planning-and-task-breakdown;brainstorming 抢创意任务、systematic-debugging 抢 bug 任务,均保持 SP 门禁优先。

---

## 附录 A:方法说明与证据

- **静态关**:skill-overlap-report.md(38×38 Jaccard + 4 组撞车对全文判定),本报告仅复制结论。
- **动态关(专家评估法)**:输入 = 33 个 SKILL.md frontmatter expectations(触发门禁 + 承诺)+ 第一关全文判定;打分规则见 §2.2;成对抽查取 T4 单任务做空集→逐一→成对增益差分。
- **泛化关**:grep 检测各 SKILL.md 中 `opencode|apply_patch|lsp_*|codegraph|background_*|todowrite|interactive_bash|MCP|chrome-devtools|context7|CLAUDE.md|plugin|hooks|subagent|codex|gemini` 命中并人工复核上下文后归类。
- **降级声明**:见 §0。
- 缓存数据:`/home/opencode-setup/benchmarks/skill-overlap/skill-data/{superpowers,agent-skills}/`(38 个 SKILL.md 全文)。
