# sp-router v1/v2 对照判决实验(P1 闸门实验)

> 2026-09-06 · 执行者: Sisyphus-Junior(未参与 matcher 编写,独立性满足) · 服务于 `.omo/plans/sp-router-graph-v2.md` Wave 2b
> 判决立场: 预注册闸门 **"v2 端到端 ≥8/10 且 > v1 端到端 → PASS,否则 FAIL(计划就地停止)"**,不预设 v2 好坏

## TL;DR

| 指标 | v1 臂(全量目录) | v2 臂(matcher top-3+模型终选) |
|---|---|---|
| 端到端命中 | **10/10** | **9/10**(失手: #6 chinese-git-workflow→using-superpowers) |
| 检索层(离线 route(裸句)) | — | 7/10 |
| 检索层(实况 route(完整首条消息)) | — | **0/10**(wrapper 词污染,top-3 十句全同) |
| 会话总输入 token(均值) | ~7,804 | ~17,058(9/10 触发兜底 Read index.yaml,两轮放大) |

**闸门判定: FAIL。** v2 端到端 9/10 达到 ≥8 的绝对线,但不满足 "> v1"(v1 满分 10/10,v1 在本测试集上处于天花板)。按预注册规则,计划就地停止,Wave 3(routing 日志/BT 夜审)不予放行。

v2 的 9/10 是**兜底路径的功劳而非检索层的功劳**: 实况注入的 top-3 因实验协议 wrapper 的"技能/SKILL.md/skill"字样被 writing-skills(15 分)垄断,十句的注入候选完全相同且全不含期望技能;模型 9 次自觉走"以上不覆盖时 Read index.yaml 全量匹配"兜底救回。唯一失手的一次(#6)恰是模型没走兜底、把协议元问题映射到被污染候选 using-superpowers 的那次。

## 实验设置

- 对照臂部署(两臂同构,仅环境变量切换):
  - 沙箱 HOME ×2(`home1`/`home2`),裸 `opencode.json`(仅 model 字段,plugin 数组为空)+ 拷贝 auth.json
  - 插件部署完全复刻 `setup-opencode.sh` L675 的方式: `sed s|__SP_VAULT__|<vault>|g plugin.js > plugins/sp-router.ts`,同目录放 `matcher.mjs`+`index.yaml`(v2 需要);vault 为 20 个 SKILL.md 的只读拷贝
  - v1 臂: `SP_ROUTER_V1=1`(plugin.js L107 确认: 该变量=1 时强制走 v1 全量目录块);v2 臂: 不设该变量
- 调用协议(任务原文,两臂逐字相同): `opencode run --model zhipuai-coding-plan/glm-5.3 "用户在会话里说了:『<句子>』。根据下方技能指引,你会先 Read 哪一个技能的 SKILL.md?只回答技能名"`
- 同一模型 glm-5.3,两臂均未设置 temperature(取服务端默认,条件一致);cwd 相同;`--title spab-<臂>-<N>` 标记会话
- 注入验证: opencode 存储的是 transform 前原文,故以三条旁证判定注入已发生——①模型推理显式遍历目录/候选(db reasoning part);②v1 臂会话输入 token ~7.8k(裸基线 2,214,见 token 节);③模型能输出 20 个技能的精确名(裸模型无从得知)。20 次正式运行 + 3 次冒烟中**注入竞态 0 次出现**,显式注入等价物未启用
- 污染控制(冒烟阶段发现并封堵): 裸配置模型会**用工具浏览 cwd 发现 vault 目录**并自行读 SKILL.md(冒烟 reasoning 实证)。正式运行核查 db: 两臂 20 个会话除 v2 设计内的 `Read plugins/index.yaml` 兜底外**零工具调用**,无工作区窥探
- 过程事故(如实记录): 首版 runner 按空格切句,把含空格的第 6/7/8 句拆成碎片跑了 16 个会话——整批作废,清 db 后用 `mapfile` 整行解析重跑;正式数据不含事故批次

## 测试集(执行前冻结,跑的过程中未改)

句子来源: 执行者现造,不点名(无技能名/无 /命令),口语化;`/tmp/opencode/sp-ab/testset.md` 为冻结原件。

| # | 句子 | 期望技能 | 理由(一句话) |
|---|------|---------|-------------|
| 1 | 改完了,可以提交了吧? | verification-before-completion | [锚点]声称完成求放行,应先跑验证拿证据 |
| 2 | 线上订单接口一到高峰就超时,低峰完全正常,日志也看不出啥 | systematic-debugging | 间歇性症状+无头绪,应系统化根因排查 |
| 3 | 我想给团队搞个周报自动汇总的工具,还没想清楚怎么做,先聊聊? | brainstorming | 创造性工作前置意图探索;含"怎么做"(2a 探针) |
| 4 | 下季度要做支付重构,需求文档写好了,帮我把实施步骤理出来 | writing-plans | 有规格要拆多步骤计划 |
| 5 | 这三个环境的配置互相不依赖,能不能同时弄,一个个来太慢了 | dispatching-parallel-agents | 无依赖多任务应并行派发 |
| 6 | 公司代码库要迁到码云,SSH key 和流水线都得重新配 | chinese-git-workflow | 国内 Git 平台迁移凭据/CI 配置 |
| 7 | reviewer 在 PR 上留了二十多条评论,有几条我觉得不对,直接改吗? | receiving-code-review | 收到审查反馈应严谨甄别而非盲从 |
| 8 | 功能分支测试全绿了,是直接合回主干还是先发个草稿 PR? | finishing-a-development-branch | 实现完成+测试全过后的集成决策 |
| 9 | 我们组的提交信息五花八门,想统一一下格式再配上钩子检查 | chinese-commit-conventions | 中文团队 commit 规范+钩子工具链 |
| 10 | 这个新需求要动核心模块,不想在当前工作目录里改,怕把没提交的东西搞乱 | using-git-worktrees | 危险改动需隔离工作区 |

覆盖 10 个不同技能(要求 ≥6),含任务指定锚点句 1 句。

## 双臂结果矩阵

| # | 期望 | v1 回答 | v1 | v2 回答 | v2 | 检索(裸句)top-3 | 期望∈top-3 | 实况注入 top-3(route(完整消息)) | 兜底触发 |
|---|------|---------|----|---------|----|------------------|-----------|-----------------------------------|---------|
| 1 | verification-before-completion | verification-before-completion | ✅ | verification-before-completion | ✅ | verification(4.5)·commit-conv(3)·finishing(1) | ✅ | writing-skills(15)·using-superpowers(9)·TDD(7.5) | 是 |
| 2 | systematic-debugging | systematic-debugging | ✅ | systematic-debugging | ✅ | commit-conv(1) 仅 1 项 | ❌ | writing-skills(15)·using-superpowers(9)·TDD(7.5) | 是 |
| 3 | brainstorming | brainstorming | ✅ | brainstorming | ✅ | mcp-builder(5)·brainstorming(3)·writing-plans(2.5) | ✅ | writing-skills(15)·using-superpowers(10)·TDD(7.5) | 是 |
| 4 | writing-plans | writing-plans | ✅ | writing-plans | ✅ | chinese-doc(4)·executing-plans(3.5)·TDD(3) | ❌ | writing-skills(15)·TDD(11.9)·using-superpowers(9) | 是 |
| 5 | dispatching-parallel-agents | dispatching-parallel-agents | ✅ | dispatching-parallel-agents | ✅ | git-workflow(3)·brainstorming(2)·dispatching(2) | ✅ | writing-skills(15)·using-superpowers(9)·TDD(7.5) | 是 |
| 6 | chinese-git-workflow | chinese-git-workflow | ✅ | **using-superpowers** | ❌ | requesting(5)·git-workflow(3)·receiving(2.5) | ✅ | writing-skills(15)·TDD(9.9)·using-superpowers(9) | **否** |
| 7 | receiving-code-review | receiving-code-review | ✅ | receiving-code-review | ✅ | finishing(2)·receiving(2)·verification(1.5) | ✅ | writing-skills(15)·using-superpowers(9)·TDD(7.5) | 是 |
| 8 | finishing-a-development-branch | finishing-a-development-branch | ✅ | finishing-a-development-branch | ✅ | finishing(7)·TDD(7)·verification(6.5) | ✅ | TDD(15.9)·writing-skills(15)·using-superpowers(9) | 是 |
| 9 | chinese-commit-conventions | chinese-commit-conventions | ✅ | chinese-commit-conventions | ✅ | requesting(7)·verification(5)·receiving(3.5) | ❌ | writing-skills(15)·using-superpowers(10)·TDD(7.5) | 是 |
| 10 | using-git-worktrees | using-git-worktrees | ✅ | using-git-worktrees | ✅ | worktrees(5)·commit-conv(3)·verification(2) | ✅ | writing-skills(15)·using-superpowers(9)·TDD(7.5) | 是 |
| | **小计** | | **10/10** | | **9/10** | | **7/10** | | **0/10** | **9/10** |

v2 判分说明: #2/#8/#9 回复为"技能名+理由"格式(违背"只回答技能名"的格式要求但技能名唯一且正确),按"唯一命名技能==期望"计命中;#6 回复唯一命名 using-superpowers,计失手。

## 检索层诊断(区分"检索错"与"终选错")

**① 实况检索 0/10——wrapper 词污染(本实验最大发现)。** 插件 transform 对**整条首条消息**路由(plugin.js L109),而实验协议的固定包装含"技能指引/技能的/SKILL.md"等词。matcher 的 `overlaps()` 是"任一 token 重叠即整条信号命中"(matcher.mjs L231),于是 writing-skills 的 8 条信号(写个技能/新技能/创建技能/编辑技能/SKILL.md/技能模板/技能/skill/验证技能)每条都被"技能"或"SKILL.md"单字重叠引爆,累计 15 分;TDD 再经 co-requires 白拿 7.5+。十句的注入 top-3 几乎完全相同且全不含期望技能。**v2 的端到端 9/10 全部来自兜底路径**(模型发现 3 候选不覆盖→Read index.yaml→全量 20 技能里自己匹配),检索层对端到端的净贡献为 0,反而在 #6 主动误导了一次。

**② 离线检索(裸句)7/10——错例全属同一病理: 单 bigram 交叠引爆弱信号(2a 已知问题的放大复现)。**
- #2 systematic-debugging **零撒种**: 句子说"高峰超时/低峰正常/日志看不出",索引只有"时好时坏/复现/回归"——真实人话与触发词的词汇空缺。
- #4 期望 writing-plans 榜上无名: "文档"一个 bigram 让 chinese-documentation 的"中文文档(strong)/文档(weak)/写文档(weak)"连环命中拿 4 分;"步骤"喂了 executing-plans;writing-plans 自身仅"需求(weak)"1 分。
- #9 期望 chinese-commit-conventions 缺席: "提交信息"命中其 weak(+1)不敌"检查/一下"交叠引爆的 requesting-code-review(7)与 verification(5)。
- #3 2a 探针句("怎么做")**复现且更糟**: brainstorming 确实吃到"怎么做/怎么设计"(3 分),但"工具"一个 bigram 让 mcp-builder 的 5 条信号连环命中拿 5 分反超——"怎么做弱信号过宽"不是孤例,而是"任一 token 重叠=全信号命中"语义的系统性症状。

**③ 终选层表现其实优秀。** v2 端到端 9/10 中 9 次是"检索 top-3 全错→模型读全量索引→答对": glm-5.3 拿到 20 行索引后的匹配能力与 v1 全量目录等价(对照 v1 的 10/10)。即: 失败不在模型终选,在检索撒种语义。

## Token 对照(db 实测,输入=非缓存+缓存读)

抽固定 3 句(#1/#5/#9,含 v1-5 一次缓存未命中样本):

| 句 | v1 会话输入 | v1 输出 | v2 会话输入 | v2 输出 | v2 兜底 |
|---|---|---|---|---|---|
| #1 | 7,794(nc 50+cr 7,744) | 6 | 17,103(nc 2,703+cr 14,400) | 33 | Read×1 |
| #5 | 7,803(nc **1,019**+cr 6,784) | 8 | 16,985(nc 2,585+cr 14,400) | 32 | Read×1 |
| #9 | 7,804(nc 60+cr 7,744) | 7 | 16,778(nc 2,186+cr 14,592) | 93 | Read×1 |
| 裸基线(无插件,句 1) | 2,214(nc) | 132 | — | — | (工具窥探,作废仅作底数) |

- v1 起步税 ≈ 7.8k−2.2k ≈ **5.6k tok/首轮**(全量目录块,CJK 按 glm 分词很贵);v2 首轮新增 ≈ 2.2k−3.6k(nc 口径)——**单轮起步税 v2 确实低约一半以上**。
- 但 v2 本协议下会话总输入反超 v1 一倍多: 兜底 Read 让会话变两轮,index.yaml 全文+重放上下文计入。若检索层不被污染(理想 7/10 命中),多数会话无需兜底,v2 总量优势才能兑现——**token 论证依赖检索层先修好**。
- #5 v1 的 nc=1,019 是远端 prompt cache 未命中的单次波动,如实保留;两臂同 db 口径,不影响横向结论。

## 闸门判定

- v2 端到端 9/10 ≥ 8 ✅
- v2 端到端 9/10 > v1 端到端 10/10 ❌
- **判定: FAIL**。按计划预注册规则("v2 不明显优于 v1 就地停止"),Wave 3/4 停止,不做 routing.jsonl/BT 夜审/setup 接线。

## 诚实讨论

1. **v1 的 10/10 是"强模型+全量目录"的天花板效应。** glm-5.3 对 20 行带描述目录的语义匹配近乎完美(锚点句上 v1 冒烟首跑曾选错 finishing,正式批 10/10,说明单次运行存在方差——见下)。任何压缩候选方案在该模型×该规模(20 技能)下都难以"显著优于"全量,只能打平或更差。v2 的相对收益空间被模型能力挤压,这是判决 FAIL 的结构性原因,不全是 v2 实现的错。
2. **单次运行方差。** 每句只跑 1 次(协议规定);v1 冒烟(同句 1)曾答 finishing-a-development-branch,正式批答对——v1 真实水平按单次采样可能在 9-10/10 波动;v2 同理。但即便给 v1 记 9/10(方差下修),v2 9/10 也只是打平不过线,FAIL 结论稳健。
3. **注入竞态处理。** 23 次运行(20 正式+3 冒烟)注入全部发生(旁证三重验证,见实验设置节),显式注入等价物(v1 routerBlock 手工渲染拼 prompt)一次都未启用。竞态在本批未复现,但"db 存 transform 前原文、注入只能旁证"这一点本身就是可观测性缺口,值得 plugin 侧补一行落痕。
4. **协议 wrapper 对 v2 不公平吗?** 公平与不公平各占一半: 生产中用户首条消息不会包含"SKILL.md/技能"字样,wrapper 污染是实验协议放大的人为因素——但这恰是判决实验该抓的鲁棒性缺陷: `任一 token 重叠即命中`的撒种语义对任何含元词/常用词的消息都脆弱(mcp-builder×"工具"、chinese-documentation×"文档"在**裸句**上同样爆炸,与 wrapper 无关)。修好撒种语义之前,v2 检索层在真实消息分布下的表现不可信。
5. **模型知识污染风险。** glm-5.3 可能从训练数据认识 superpowers-zh 技能体系(裸跑在无注入时也组织出了 verification/chinese-commit-conventions 等讨论——尽管该次是工具窥探所致,无法完全排除先验)。若模型自带技能先验,会同时抬高两臂,对"v2>v1"的相对比较构成系统性压平。本实验无法剥离该因素,如实声明。
6. **2a 复现结论。** 复现,且诊断为系统性: "怎么做"确实把 brainstorming 撒上种,但任何共享单个 bigram 的信号串都会整条命中,"工具/文档/检查/步骤"皆成污染源;2a 应从"补/删触发词"升级为"改重叠语义"。

## 失败模式与(供计划复盘的)修复方向

- 根因一: `overlaps = tokens.some(...)`(matcher.mjs L231)——单 token 重叠即整条信号满分命中。修复方向: 要求信号与查询共享 ≥2 个 bigram(或按重叠 token 数/信号长度折算得分),单字共享不计。
- 根因二: 对整条首条消息路由,无停用/元词剥离。修复方向: 剥离协议性元词,或仅对用户话语主体路由。
- 根因三: 词汇空缺(超时/间歇/偶发/日志看不出 ≠ 时好时坏;实施步骤/排期缺失)。修复方向: 补 strong/weak 信号(计划允许,人批)。
- 兜底设计(索引指针+模型全量匹配)在本次实测中是 v2 最可靠的部分——若重跑,建议保留并以此为基线对照"修好检索后的 top-3"。
- 以上均为建议,是否修 matcher 后重跑 P1,属计划方决策,本报告不越权执行。

## 工件清单

- 冻结测试集: `/tmp/opencode/sp-ab/testset.md`;runner: `/tmp/opencode/sp-ab/runner.sh`
- 全量运行日志: `/tmp/opencode/sp-ab/logs/{v1,v2}-<1..10>.log`(每句完整输出)+ `v1-smoke/v2-smoke/bare-1.log`
- 会话数据快照(db 提取): `/tmp/opencode/sp-ab/session-snapshot.json`(沙箱 HOME 清理后仍可复核)
- 沙箱 HOME(home1/home2/home3)与 vault 拷贝已于报告落盘后清理;router-modules 全程只读未动
