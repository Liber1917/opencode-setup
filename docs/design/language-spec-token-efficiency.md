# 语言规范 × Token 效率 × 信息密度 — 论文全景

> 2026-08-23 · 主会话直查(arXiv/ACL/EMNLP/NeurIPS 2023-2026)· 回答:"让 AI 在思考和输出时遵循某种语言规范,能否降低 token 或提高信息密度?"

## 一句话总结

**能,但要分三层说**:①长度规范(显式 token 预算)效果最硬——省 50-69% token 只掉 <3% 准确率;②格式规范是双刃剑——约束输出格式伤推理,约束输入/指令格式涨性能;③语言选择(中 vs 英)基本是伪命题——tokenizer 决定一切,且成功率损失吞掉 token 节省。信息密度的正式度量已在信息论框架下成型(InfoGain/语义 surprisal),2026 年这条线正在从"提示词工程"走向"训练目标"。

---

## 1. 长度/预算规范(最硬的实证)

| 论文 | 核心数据 |
|---|---|
| **TALE: Token-Budget-Aware LLM Reasoning**(ACL 2025 Findings, arXiv 2412.18547) | prompt 里写"预算 N token"真的压缩思考:**预算合理时 258→86 token(-67%),准确率损失 <3%**;预算太小反而失效("Token Elasticity":给 10 token 实际跑 157)——预算要匹配难度 |
| **Token Complexity**(arXiv 2503.01141) | 31 种压缩指令 × 6 模型:**所有压缩策略落在同一条"长度-准确率"帕累托曲线上**——起作用的是长度本身,不是措辞;每题存在"最小 token 复杂度"阈值;带验证器的路由能逼近理论上界 |
| **BudgetThinker**(arXiv 2508.17196) | 训练时插入"剩余预算"控制 token + 课程式 RL:预算遵循精度大幅提升,**同预算下准确率 +4.9%** |
| **Budget Guidance**(ACL 2026 Findings) | 免微调:轻量预测器对"剩余思考长度"建 Gamma 分布,软引导生成——**紧预算下比基线 +26% 准确率,63% token 干完整思考的活** |
| **s1 等 thinking budget 反向线** | 测试时扩展的另一面:更多预算不一定更强(SWE 系任务上过度思考已实证有害,GSM8K-Zero 上 CoT 掉到直接作答之下) |

**落地含义**:给 agent 的系统提示加显式 token 预算指令是免费的 50%+ 节省;但预算要自适应(简单任务短预算,复杂任务放宽),固定预算两头受损。

## 2. 格式规范(双刃剑,方向决定一切)

| 论文 | 核心数据 |
|---|---|
| **Let Me Speak Freely?**(EMNLP 2024, arXiv 2408.02442) | **约束输出格式伤推理**:JSON-mode 强制解码在推理任务掉分严重(Last Letter 上 GPT-3.5 的 answer 键跑到 reason 前面,变直接作答);**但分类任务 JSON-mode 反而涨分**(约束答案空间减少选择错误) |
| **dottxt 反驳**(outlines 团队博客) | 复现发现原论文的坑:结构化生成 ≠ JSON-mode;**prompt 里展示结构 + 结构化解码时,structured 反超 unstructured**(0.77 vs 0.68)——结论:格式损害来自实现错误,不是结构本身 |
| **伪代码/代码作为思考语言**(多论文汇合) | **PAL**(ICML 2023):程序化推理比 CoT **+8%(GSM)/+40%(GSM-hard)**;**Chain of Code**(2023):BIG-Bench Hard 84%,**超 CoT 12 点**;**Language Models as Compilers**(EMNLP 2024):生成任务级伪代码再执行,胜过自然语言指令;**CodeAct**(ICML 2024):**代码作 action space 的 agent 比 JSON 工具调用成功率高 20%**(跨 17 模型) |
| 关键区分(Skill Engineering 综述) | **结构化输入/指令一致地涨分;过度约束的输出格式一致地掉分**——"规范指令"与"规范输出"是相反的干预 |

**落地含义**:规范"怎么下指令"(结构化/伪代码/typed)是正收益;规范"模型怎么想怎么答"(强制 JSON 输出)是负收益,除非任务本身是分类/抽取。我们的 ai-communication skill(规范回复结构)介于两者之间——它约束的是"呈现结构"而非"推理格式",且模型可自由展开推理后再组织输出,属于安全区;但要警惕它对推理密集任务的隐性税。

## 3. 语言选择(tokenizer 决定一切,成功率吞掉节省)

| 论文/实测 | 核心数据 |
|---|---|
| **Chinese Not More Efficient in Vibe Coding**(arXiv 2604.14210,SWE-bench Lite) | 中文 prompt 省 token 是**模型依赖**的:MiniMax-2.7 中文 1.28x 更贵 / GLM-5 中文 0.98x 更便宜;**但中文成功率全线更低**(掉 4.5-9.9pp)——期望成本=token/成功率,**换中文是负收益**;模型间 30pp 的成功率差 >> 语言效应 |
| **Mason AI Lab 六任务实测**(o200k/cl100k) | OpenAI tokenizer:中文平均 **1.34x**(o200k)~ **2.08x**(cl100k)token;代际改进砍掉 40% CJK 惩罚;**字符密度 ≠ token 效率**(中文 0.37x 字符但 1.34x token) |
| **Synthorai 跨七模型对比** | "每意义 token"视角:中文在 Claude 上仅 1.17x(密度对冲惩罚),**GLM/Kimi/DeepSeek 上中文≈持平**;最省 tokenizer 随语言翻转(Kimi 最省中文/DeepSeek 最省日语/GPT 最省欧洲语);**Claude 系 tokenizer 在所有语言都最贵(1.2-2.3x)** |
| **BPB tokenizer 基准**(MELLM 2026) | bits-per-byte 归一化后 SuperBPE 对中文/匈牙利语反而更差——跨语言 tokenizer 优化大多无效,标准 BPE 仍是强基线 |

**落地含义**:①"用英文思考省 token"在 GLM/自研模型上不成立(0.98x);②任何语言切换的收益都被成功率损失吞掉——**优先级:模型选择 >> prompt 质量 >> 语言选择**;③系统提示这种高复用文本,中文在国产模型上反而便宜,在 Claude 上贵 1.2-1.9x(可测)。

## 4. 信息密度的正式度量(信息论框架,2025-2026 成型)

| 论文 | 度量/结论 |
|---|---|
| **Think or Not?**(NeurIPS 2025) | **InfoBias**(响应级语义偏差)+ **InfoGain**(每步熵减):长推理链信息增益递减、错误答案 InfoBias 更高;熵驱动的 Adaptive Think:**QwQ-32B 平均 -50.8% token 且 +1.1% 准确率**(置信够了就停) |
| **InfoDensity**(arXiv 2603.17310) | 好推理 = 低不确定性收敛 + 单调进展;用 AUC+单调性奖励做 RL:**同准确率下大幅减 token**,抗 reward hacking |
| **CIB: Reasoning as Compression**(arXiv 2603.08462) | 把高效推理重构为**有损压缩**:每 token 按"语义 surprisal"计税(高信息 token 便宜、可预测填充昂贵)——**-48% token / -1.5% 准确率**,帕累托前沿可导航 |
| **Content Not Length**(arXiv 2606.30128) | 控制变量铁证:**同 DAG 内容下,纯长度对独立训练的推理模型几乎零贡献**(25 模型);有效的是"验证/检查内容"不是 verbosity——**CoT 的价值在内容密度,长度只是载体** |

**落地含义**:"每 token 信息量"已有可计算的代理指标(熵减/surprisal);给 agent skill 写"每句话都要携带新信息,禁止复述已知"这类**信息密度规范**是有理论依据的——但注意它是训练目标时效果最好,纯 prompt 表述的衰减更快。

## 5. 对 opencode-setup 的可落地形态(候选 preset skill:"dense-output")

综合实证,一个"语言规范 skill"应该只包含三类指令(有数据支撑的):

1. **显式 token 预算**(TALE 式):"回答此问题用不超过 N token"——预算自适应难度,宁松勿紧(Elasticity 效应)
2. **内容密度规范**(CIB/Content-not-Length 式):"每个中间步骤必须引入新信息(减少不确定性);禁止:复述任务、总结已知、铺垫性过渡"——这是最接近"提高信息密度"的 prompt 级表述
3. **指令结构化**(PAL/CodeAct 式,对 skill 作者而非终端用户):skill 的步骤指令用结构化/伪代码写,不写成流水账散文

**明确不做**(实证为负):强制输出 JSON 格式(伤推理);切换思考语言(收益被成功率吞);无预算的"be concise"(落在帕累托曲线上,不如显式预算)。

**未决问题**:"中文用户 + 国产模型(GLM)"组合下,系统提示/AGENTS.md 用中文是否系统性更省(Synthorai 数据暗示 ≈持平但任务相关)——值得用我们自己环境实测,一次脚本就能测。

---

# 补篇:好 token 的信息论量化(2026-08-24 追加)

## 标准(一句话)

**好 token = 让模型对答案的不确定性下降的 token**(InfoGain>0);坏 token = 可预测的填充(surprisal≈0);最坏的 token = 看似推进实则熵反弹(想歪的起点)。

## 指标全家福(全部可从概率读出,无需理解自然语言)

| 指标 | 定义 | 代表作 | 实践状态 |
|---|---|---|---|
| **Surprisal** | −log P(token\|前文):单 token 信息量 | CIB(arXiv 2603.08462)用它做 RL 训练税 | ✅ logprob 即得 |
| **InfoGain** | 一步推理前后答案分布熵的差 | Think or Not?(NeurIPS 2025) | ✅ 需答案分布 |
| **单调性** | 熵应单调下降,反弹=想歪点 | InfoDensity(arXiv 2603.17310) | ✅ |
| **Semantic Entropy** | 在"意义空间"而非词面空间算熵:多次采样→双向蕴含聚类→簇概率的熵 | Farquhar et al. **Nature 2024**(开源:github.com/jlko/semantic_uncertainty,411★) | ✅ 开源,**且有离散变体(不需 logprob,用采样频率近似)** |
| **SEP 探针** | 用单次生成的隐状态直接预测语义熵,近零开销 | OATML/semantic-entropy-probes | ✅ 开源(需隐状态访问) |
| **EPVI**(点态 V-信息) | CoT 相对输入引入的"模型可用新信息"——**黑盒可算** | Wang et al. LREC-COLING 2024 | ✅ 专为黑盒 API 设计 |
| **V-information** | 考虑计算约束的可用信息(违反数据处理不等式:计算能创造可用信息) | Xu et al. ICLR 2020(arXiv 2002.10689) | 理论基础,InfoNet(arXiv 2402.10158)提供免测试时优化的神经估计器 |
| **UID 均匀性** | 好推理的步级信息密度**局部均匀**(无尖峰),全局可非均匀 | arXiv 2510.06953:UID 选择使 AIME2025 相对提升 10-32% | ✅ 新且实用 |
| **EPR/WEPR** | 序列平均熵产率+加权变体,只用 API 给的 top-K logprob | arXiv 2509.04492:K≤10 就够,token 级实时可算 | ✅ **API 场景最佳** |

## 开放式任务的进展("有用的新 vs 无关的新")

- **Semantic Entropy 是当前最优解**:不是判断单 token,而是判断"整个答案的意义分布"——意义分布熵高=模型不知道自己要说什么=胡编区间。聚类靠双向蕴含(NLI 模型或 LLM 判断)
- **未解决**:surprisal 奖励"新"不奖励"有用"——高 surprisal 的无关新信息仍会被 CIB 类方法奖励。这正是"语义容错"方向与本方向的交叉空白
- **"高置信胡编"(high-certainty hallucination)是所有熵方法的盲区**:模型低熵地输出错误——需要熵之外的方法(SAR 加权相关性、judge LLM)

## 运行时"思考质量仪表"——已有人做了,而且不止一个

| 工具 | 是什么 |
|---|---|
| **ATLAS-RTC**(arXiv 2603.27905) | **token 级运行时控制器**:每步解码观察熵/漂移分,分级干预(logit 偏置→温度→掩码→回滚重导)——证明"实时信息流监控+干预"可行 |
| **Klarity**(github klara-research,开源) | 生产级工具包:熵分析+推理步骤质量分析(`<think>`标记切步)+语义聚类,支持 vLLM/Together,幻觉检测基准 80%+ |
| **TokenScope**(github Amirresm) | 解码时信号的交互检查:置信度/熵/surprisal/反事实分支 |
| **WEPR 在线版** | token 级分数可逐 token 实时显示("这是不可靠回答的局部风险") |
| **prompt-observatory** | 实时 token 流+困惑度热图+幻觉评分的面板 |

**结论:审计日志的 token 利用率指标在技术上完全可行——WEPR(仅 top-K logprob)或 UID 均匀性是最实际的两个候选。**

## 诚实边界(被实证的失败场景)

1. **高置信胡编**:低熵错误——所有纯熵方法的死穴(Simhi et al. "Trust Me I'm Wrong")
2. **Reward hacking**:InfoDensity 论文自己展示纯长度奖励会被 hack(压缩到损坏)——需要质量项约束
3. **Surprisal ≠ 有用**:新但无关的 token 被错误奖励(CIB 作者也承认)
4. **语义漂移不改变结构熵**:ATLAS-RTC 承认漂移检测只抓结构性违规,语义级走歪抓不到
5. **黑盒 API 只有 top-K logprob**:完整 InfoGain 算不了——但 WEPR 证明 K≤10 足够(这是给我们的好消息:OpenAI/Anthropic API 都给 top logprobs)

## 对两个落地件的最终判定

| 落地件 | 判定 |
|---|---|
| **① dense-output skill** | 可行:prompt 级用"信息密度规范"(每步须引入新信息/禁止复述)——UID 证据支持"均匀的信息流"是好输出的特征 |
| **② 审计日志 token 利用率指标** | 可行且有现成路径:API 的 top-K logprob(k≤10)→ WEPR 式 token 级分数 → 会话/步骤聚合 = 零语义分析的"这次会话 token 利用率"。**写进 E 方向审计模块的实现选项** |
