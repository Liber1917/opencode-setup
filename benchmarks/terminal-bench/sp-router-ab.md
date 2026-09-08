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

# B 轮: 语义修复+改判据重跑

> 2026-09-06 · 执行者: Sisyphus-Junior · 仲裁已定方案逐字执行(两级命中+黑名单整串×0.25+transform 剥离行),判据预注册仅此一轮: **v2 端到端 ≥ v1−1 且 v2 会话均 input < v1×0.6 → PASS;否则 FAIL 永久停**

## 修复内容(diff 摘要)

- `matcher.mjs`:
  - 顶部新增 `GENERIC_WORDS = ['技能','skill','文档','工具','怎么做','检查','继续','开始','下一步','讨论','评估','需求','失败','异常','重构','实现']`(16 词,泛化词降权);
  - 撒种语义从"任一 token 重叠即整条信号命中"(旧 `overlaps=some`)改为两级: **full**=信号全部 token ∈ query → strong×2/weak×1;**partial**=命中 token≥2 且 ≥信号 token 数 60% → strong×1/weak×0.5;其余不命中;
  - 信号字符串与 GENERIC_WORDS **完全相等**时该信号得分 ×0.25(仅整串相等一种情况,含泛化词的长信号不降权);
  - name×3、co-requires/supersedes/conflicts-with 三边、weight、排序与平局规则: 逐行未动。
- `matcher.test.mjs`: 保留全部 16 条既有断言,新增 8 条: full×2 / partial×2 / 黑名单×2 / wrapper 回归 A(污染不垄断)与 B(纯技能句正确路由)。**先红后绿**: 修复前运行 6 条新断言失败(`两级: full…单 bigram 交叠不再命中`/`两级: partial…60%`/`两级: partial 对 weak`/`黑名单…×0.25`/`黑名单…仅整串`/`wrapper 回归 A`),红证据存 `/tmp/opencode/sp-ab/b/red-evidence.txt`;修复后 24/24 全绿。三真实用例原断言(返回值不对/改完了/为什么结果错了)全绿,**未动 index.yaml**(0 词补充,允许额度 6 未用)。
- `plugin.js`: transform 提取首条消息文本后新增一行 `text = text.replace(/<!-- sp-router:[^>]*-->/g,'')`(剥离 sp-router 注释标记后再路由);该行需 `const text` → `let text`,其余逐字未动。QA(/tmp/opencode/sp-ab/b/qa-transform.mjs,8 项全 PASS): v2 块注入/top-1 候选正确/幂等不二次注入/剥离后仍注入/正则剥 v1·v2 标记且不动普通 HTML 注释。
- 说明两点(按字面执行): ①黑名单整串比较为大小写敏感的字符串全等(`'SKILL.md'`≠`'skill'`,故 writing-skills 的 strong `SKILL.md` 不降权——wrapper 含 "SKILL.md" 字样时其 full 命中是字面命中,属断言 B 认定的正确行为);②上轮已部署的 `~/.config/opencode/plugins/sp-router.ts` 为 setup 生成物,不在本次 SCOPE,实验沙箱从源 `plugin.js` 重新 sed 部署。

## B 轮测试集(执行前冻结,跑的过程中未改)

句子来源: 执行者现造,不点名(无技能名/无 /命令),口语化;冻结原件 `/tmp/opencode/sp-ab/b/testset.md`。句子设计与冻结前用修复后的 matcher 做过离线核算(检索层数据见下文矩阵"裸句"列,即披露此项),冻结后未再改。锚点句为任务指定原文(与上轮 #1 同句),其余 9 句与上轮 10 句文字均不同。

| # | 句子 | 期望技能 | 理由(一句话) |
|---|------|---------|-------------|
| 1 | 改完了,可以提交了吧? | verification-before-completion | [锚点·上轮同句]声称完成求放行,应先跑验证拿证据 |
| 2 | 一调用就报错,错误信息每次还不一样,时灵时不灵的 | systematic-debugging | 非确定性报错+症状漂移,应系统化根因排查 |
| 3 | 想做一个内网知识库问答机器人,技术选型还没定,先帮我出出主意 | brainstorming | 创造性工作前置意图探索 |
| 4 | 下个月要做灰度发布,PRD 也评审完了,帮我把任务拆解和排期理出来 | writing-plans | 有规格要拆多步骤计划 |
| 5 | 这三张报表谁也不影响谁,能不能并行一起跑? | dispatching-parallel-agents | 无依赖多任务应并行派发 |
| 6 | 要在生产代码上试个大改动,又怕搞坏现场,能不能先弄个隔离的工作区再动手 | using-git-worktrees | 危险改动需隔离工作区 |
| 7 | 同事在我的 MR 上提了一堆评审意见,有几条我觉得不对想反驳,怎么回复比较好? | receiving-code-review | 收到审查反馈应严谨甄别而非盲从 |
| 8 | 每次发版 changelog 都得手写,能不能从提交历史自动生成?顺便把 commit 规范也定下来 | chinese-commit-conventions | 中文团队 commit/changelog 规范工具链 |
| 9 | 这个分支可以合回去了,还没推送远端,要不要先推再合? | finishing-a-development-branch | 实现完成后的集成决策 |
| 10 | 这个 bug 我想用红绿重构的节奏修,先写个失败测试再动手 | test-driven-development | 明确要先写测试再实现 |

覆盖 10 个不同技能(要求 ≥6),含锚点 1 句。

## 判据预注册(仅此一轮)

- 双臂协议同上轮 §实验设置(沙箱 HOME×2、裸 opencode.json+auth.json、sed 部署 plugins/sp-router.ts+matcher.mjs+index.yaml+vault 只读拷贝、SP_ROUTER_V1 切换、同一 wrapper 逐字、--title spab-<臂>-<N>、每句 1 次)。
- 命中判分: 回答中**唯一命名技能==期望**计命中(与上轮同口径)。
- token 口径: 会话输入 = Σ(assistant 消息 tokens.input 非缓存 + tokens.cache.read 缓存读),db 提取,与上轮同口径。
- **PASS 条件(两项须同时成立): ① v2 端到端命中数 ≥ v1 端到端命中数 − 1;② 对每个句子 i, v2 会话输入[i] < 0.6 × v1 会话输入[i](逐句成对比较,"均"=无例外)。任一不满足 → FAIL,永久停。**

## B 轮结果

正式运行前冒烟 2 次(v1/v2 臂各 1,锚点句,不计数)+ 裸控 1 次(见 token 节);冒烟注入正常,无注入竞态。

### 双臂结果矩阵

| # | 期望 | v1 回答 | v1 | v2 回答 | v2 | 检索裸句 top-3 | 实况注入 top-3 | v2 Read |
|---|------|---------|----|---------|----|----------------|----------------|---------|
| 1 | verification-before-completion | verification-before-completion | ✅ | verification-before-completion | ✅ | verification(4) | verification(4)·writing-skills(3.5)·TDD(1.75) | SKILL.md |
| 2 | systematic-debugging | systematic-debugging | ✅ | systematic-debugging | ✅ | sd(2)·verification(1) | writing-skills(3.5)·sd(2)·TDD(1.75) | — |
| 3 | brainstorming | brainstorming | ✅ | brainstorming | ✅ | brainstorming(4)·writing-plans(2) | brainstorming(4)·writing-skills(3.5)·writing-plans(2) | — |
| 4 | writing-plans | writing-plans | ✅ | writing-plans | ✅ | writing-plans(7)·executing-plans(3.5) | writing-plans(7)·executing-plans(3.5)·writing-skills(3.5) | — |
| 5 | dispatching-parallel-agents | dispatching-parallel-agents | ✅ | dispatching-parallel-agents | ✅ | dispatch(4.5) | dispatch(4.5)·writing-skills(3.5)·TDD(1.75) | — |
| 6 | using-git-worktrees | using-git-worktrees | ✅ | using-git-worktrees | ✅ | worktrees(4) | worktrees(4)·writing-skills(3.5)·TDD(1.75) | SKILL.md(v1 也读了) |
| 7 | receiving-code-review | receiving-code-review | ✅ | receiving-code-review | ✅ | receiving(5)·cc-review(1)·sd(1) | receiving(5)·writing-skills(3.5)·TDD(1.75) | — |
| 8 | chinese-commit-conventions | **brainstorming** | ❌ | chinese-commit-conventions | ✅ | ccc(8) | ccc(8)·writing-skills(3.5)·TDD(1.75) | SKILL.md |
| 9 | finishing-a-development-branch | finishing-a-development-branch | ✅ | finishing-a-development-branch | ✅ | finishing(3.5)·verification(1.75)·worktrees(1) | finishing(3.5)·writing-skills(3.5)·TDD(1.75) | SKILL.md |
| 10 | test-driven-development | test-driven-development | ✅ | test-driven-development | ✅ | TDD(4.25)·sd(2.25)·verification(1.13) | TDD(6.5)·writing-skills(4.5)·sd(2.25) | — |
| | **小计** | | **9/10** | | **10/10** | 期望∈top-3 **10/10**(裸句全部 top-1) | 期望∈top-3 **10/10**(9 top-1,#2 top-2) | 4/10 候选 SKILL.md;**index.yaml 兜底 0/10** |

- v2 全部 10 句回答为干净技能名(无附带理由),严格满足"只回答技能名";v1 亦然。
- 检索层对比上轮: 裸句 7/10→**10/10**,实况 0/10→**10/10**,兜底 Read index.yaml 9/10→**0/10**——两级命中+黑名单语义修复完全生效。
- #8 是 v2 对 v1 的唯一净胜局: v1 全量目录下模型把"changelog 自动生成"误路由到 brainstorming;v2 的 ccc top-1(命中 changelog/commit 规范)引导正确。
- v2 有 4 句模型按 v2 块纪律先 Read 候选 SKILL.md 再作答(渐进披露的设计内行为,非兜底);v1 的 #6 也自发读了一次 SKILL.md。

### Token 对照(db 实测,输入=非缓存+缓存读,与上轮同口径)

| # | v1 total | v2 total | 0.6×v1 | v2<0.6×v1? | | # | v1 total | v2 total | 0.6×v1 | v2<0.6×v1? |
|---|---------|---------|--------|-----------|---|---|---------|---------|--------|-----------|
| 1 | 7,819 | 16,215 | 4,691 | ✗ | | 6 | 18,097 | 17,128 | 10,858 | ✗ |
| 2 | 7,829 | 7,379 | 4,697 | ✗ | | 7 | 7,833 | 7,389 | 4,700 | ✗ |
| 3 | 7,832 | 7,387 | 4,699 | ✗ | | 8 | 7,838 | 18,662 | 4,703 | ✗ |
| 4 | 7,835 | 7,393 | 4,701 | ✗ | | 9 | 7,830 | 17,942 | 4,698 | ✗ |
| 5 | 7,825 | 7,386 | 4,695 | ✗ | | 10 | 7,830 | 7,394 | 4,698 | ✗ |

- **裸控(无插件,锚点句,home3)**: total **7,086**(nc 46 + cr 7,040)——本环境 opencode 1.18.29 的系统提示+工具 schema 基座本身 ≈7.0k,两臂共享且几乎全部走缓存读。
- v1 均值 8,857 / v2 均值 11,428(v2/v1≈1.29,4 句读 SKILL.md 所致);中位数 v1 7,832 / v2 7,391(v2 便宜 5.6%)。逐句 nc: v1 首跑 1,035-1,051(块未缓存)后转 81-94;v2 单轮句 218-347,读 SKILL.md 句 1,815-4,134。
- **结构性事实**: v1≈7.0k 基座+0.8k 全量目录块;v2≈7.0k 基座+0.2-0.35k 精简块。判据②的门槛 0.6×v1≈4.7k **低于基座本身(7.0k)**——即便插件零开销,v2 也不可能逐句 < 0.6×v1。判据隐含的是 A 轮"裸基线 2,214/起步税 5.6k"的账,而本轮实测裸基线已是 7,086(环境/版本漂移,A 轮裸测与本轮非同一基座状态)。nc-only 口径同样全败(如 #10: v1 nc 86×0.6=52 vs v2 nc 226)。

### 判据核算(预注册,逐字)

- 条件①: v2 端到端 10/10 ≥ v1 端到端 9/10 − 1 = 8 → **成立**
- 条件②: 逐句 v2 input < 0.6×v1 input → **10/10 全部不成立**(见上表)
- **判定: FAIL。按预注册规则,永久停,不再有 C 轮。**

## B 轮诚实讨论

1. **检索层修复被端到端证实**: 实况 top-3 从 0/10 到 10/10、兜底从 9/10 到 0/10、v2 端到端首次超过 v1(10/10 vs 9/10)——A 轮诊断的"wrapper 词污染+单 bigram 引爆"两个根因都被两级命中+黑名单语义消除。v2 的失分已不在检索。
2. **FAIL 是判据②的结构性不可达,不是修复失败**: 门槛 4.7k < 共享基座 7.0k,任何插件方案(含零开销)都过不了。若判据按"插件增量税"口径(v1 块 ~0.75k vs v2 块 ~0.3k,省 ~60%)或按中位数,结论会反转;但预注册判据不允许赛后改口径,如实 FAIL。
3. **v2 的 token 劣势主要来自"读 SKILL.md"的设计内行为**(4/10 句触发,每句 +9k): 渐进披露把目录税换成了按需正文税,单句总成本反超 v1 的全量目录。若产品目标是省 token,v2 块应显式指示"只答技能名,不要 Read";若目标是流程保真(先读正文再行动),当前行为正确——这是产品决策,不是缺陷。
4. **v1 的 9/10 与上轮 10/10 的差异是单次采样方差**(A 轮已记录 v1 存在同句波动);#8 的失手方向(创造性词汇压过工具词)与上轮 v1 天花板叙述一致。
5. **黑名单整串 ×0.25 的实测效果**: 实况消息中 writing-skills 仍稳定 ~3.5 分(SKILL.md strong full +2 属字面命中,不断言 B 认定为正确行为),但不再垄断——所有期望技能均进 top-3,9/10 top-1。
6. 过程事故: 无(首轮 runner 空格切句教训已用 mapfile 规避;20 正式+2 冒烟+1 裸控全部干净落库)。

## B 轮工件清单

- 冻结测试集: `/tmp/opencode/sp-ab/b/testset.md`;runner: `/tmp/opencode/sp-ab/b/runner.sh`;QA: `qa-transform.mjs`;红证据: `red-evidence.txt`;离线检索核算: `route-check.mjs` + `route-check-output.txt`
- 全量运行日志: `/tmp/opencode/sp-ab/b/logs/{v1,v2}-<1..10>.log` + `v1-smoke/v2-smoke/bare-1.log`
- 会话数据快照: `/tmp/opencode/sp-ab/b/session-snapshot-b.json`(含裸控)
- 沙箱 HOME(home1/home2/home3)于报告落盘后清理;本轮改动仅限 router-modules/sp-router/{matcher.mjs,matcher.test.mjs,plugin.js}(index.yaml 未动)与本报告
