# 技能图路由方案调研:9 个候选对比与选型

> 2026-09-05 · 三路 subagent 并行调研(zread/GitHub API/unpkg 直读,未动任何本地代码) · 服务于 C-Phase2 路由 spec 的实现选型
> 前提:我们需要 OpenCode 接入 + 中文触发信号 + SkillOpt 夜审反馈闭环 + 图关系(不重不漏),MIT 硬约束

## 候选总览

| 候选 | 语言/形态 | License | 图能力 | 触发信号 | 反馈闭环 | OpenCode 接入 | 健康度 |
|---|---|---|---|---|---|---|---|
| **agent-skill-finder** | JS/Node≥20 npm | MIT | **3 类边+置信合并+BFS(防死锁)+AST去重** | BM25,❌CJK(中文查询零分) | **最强**:telemetry→LTR retrain(7天)+autoRewrite人审+rerankerFn | MCP stdio(不在 host 列表) | 13★,停更4月 |
| **SkillsMap** | TS/Node≥18 npm | MIT | 单边 DAG+环检测(报环路径)+拓扑 pathway | domain/regex/tags/BM25 四段权重可调,中文半失效 | 仅配置改写+rebuild | 无,需自写 CLI 包装 | 0★,停更2.5月 |
| **skillroute** | Py≥3.11 **零运行时依赖** | MIT | 关系加权和(非遍历),frontmatter 5 种关系 | lex+local-token+graph 混合,evidence 带 source_path/行号,**低置信返回澄清问题** | **traces(SQLite)+evals(JSON)+eval tune 网格搜权重** | **一等公民:harness install opencode** | 39★,**活跃**(push 09-03) |
| skill-router-mcp | TS MCP stdio | MIT | 无 | Ollama embedding+关键词降级(engine 不静默) | 无(benchmark 脚本) | 手写 mcp 条目 | 0★,6 commits 死 |
| tribunal-kit(模式) | node 编译 | MIT | supersedes/co-requires/conflicts-with | **strong/weak 双档触发词** | 静态编译索引 | 模式参考 | 成熟打包 |
| SKRT | Go 单二进制 CLI | MIT | pin/权重 | 7 策略,**CJK bigram 原生**+Gemini 翻译可选层 | smart-pin 从聊天史挖掘 | **默认扫 ~/.config/opencode/skills** | 2★ 微型 |
| @kernel.chat/skill-router | TS 库 | MIT | 无 | 关键词,**CJK 失效**(剥非 ASCII) | **Bradley-Terry recordOutcome**(win/loss 反馈) | 库嵌入 | 小 |
| @skill-tools/router | TS npm | Apache-2.0 | 冲突检测 | BM25+可插拔 embedding | 无 | 库 | 小 |
| SkillPilot | TS npm | MIT | 冲突感知 | 关键词+ONNX 语义 | 自学习权重 | 多 host 适配 | 新 |

## 完整评估卡(要点浓缩,全文见调研任务会话)

### ASF(agent-skill-finder)
- 图:BFS 只走 depends_on+complements,token 预算 4000,防"组合死锁";duplicate_of 边=AST 哈希+cosine≥0.97 去重
- 学习闭环:`src/learning/` telemetry→ltr.js→retrain.js(7 天周期)+autoRewrite(成功率<0.3 标记人审)+rerankerFn 注入
- CJK:`/[a-z0-9]+/g` 分词,中文全丢,中文查询退化为取前 topK
- OpenCode:`asf serve` MCP(不在 host 列表);透明劫持需 ~30 行 hook 适配器

### SkillsMap
- 四段:domain O(1) 预筛(砍 80%)→regex(ReDoS 防护)→tag 重叠(√ 归一)→BM25(磁盘缓存增量);权重 1.0/0.4/0.5/0.1 构造器可调
- DAG:DFS 环检测报完整路径+卸载被依赖阻止+pathway 拓扑链
- CJK:保留 \u00c0-\uffff 但空白切分,中文整句=1 巨 token,半失效
- 亮点:94 测试+CI+JSON Schema,工程质量好但零用户

### skillroute
- **唯一活跃**(39★,erichare 持续迭代),PyPI 0.4.0 零运行时依赖(自写 YAML 解析)
- evidence:`SkillExcerpt{kind,text≤700,source_path,start/end_line}`+reasons[]+score_breakdown{lex,sem,repo,graph,total};低置信→澄清问题
- 关系:requires/complements/conflicts/supersedes/same_domain frontmatter 解析;graph=自身关系加权(clamp±0.2),**非图遍历**
- 可编程闭环:route_traces 自动落 SQLite→`traces list --json`→evals 纯 JSON case→`eval tune` 网格搜权重→SKILLROUTE_WEIGHTS env 生效——**SkillOpt 夜审全链路现成**
- rug-pull 防护:content_hash(SHA-256 全引用文件)+外部 toolprint 锁

### skill-router-mcp
- 10 条 index-time 内容 lint(只标不拦):prompt-injection/concealment/exfiltration/credential-access/pipe-to-shell/destructive/decode-and-execute/known-exfil-endpoint/bypass-confirmation/opaque-blob(≥240b base64)
- 路径白名单模型(name sanitize→索引查找→canonicalize 验证);SEP-2640 skill:// 资源对齐
- Ollama embedding 降级不静默(engine 字段);48 查询实测 semantic 93.8% vs keyword 77.1%

### tribunal-kit 路由 schema(模式参考,非库)
- frontmatter `routing:`:domain(10 枚举)/tier/supersedes/co-requires/conflicts-with/trigger-signals.strong|weak/confidence-boost
- 冲突消解 5 规则:strong>weak → pro>basic → 特定域>一般域 → supersedes 弃 basic → conflicts 取信号计数高者
- 编译期索引换运行时零开销(183 skills 实证);Socratic Yield:置信<85 必须反问
- 注意:文档 schema 与索引实物有字段漂移(tier 枚举/domain 超集),自研需写校验器

### SKRT
- **CJK bigram 原生策略(≤75 分,本地无依赖)**+Layer0 Gemini 翻译可选层(有 key 才用,失败降级本地)
- 默认扫描 `~/.config/opencode/skills` ✓;smart-pin 从聊天记录挖掘使用频次自动建议 pin
- 2★/10 commits 微型项目——**算法借鉴价值>依赖价值**

### @kernel.chat/skill-router
- 简化 Bradley-Terry:β=σ/2,c=√(2β²+σ²),K=σ²/c,μ+=K(S−E);score=μ−2σ 保守分
- recordOutcome(技能,类别,win|loss) 纯函数——**audit 命中→win/漏检→loss 即完成反馈闭环**
- 坑:categorize 剥全部非 ASCII,中文查询必落 general 类;须自传 category 或换中文分类器

## 选型结论

**没有任何单一轮子同时满足我们的四个硬条件**(OpenCode 一等接入/中文信号/反馈闭环/图关系)。三个 MIT 算法件值得拆借,组合自研:

| 借鉴源 | 拆借件 | 规模 |
|---|---|---|
| tribunal-kit | strong/weak 触发词 schema + supersedes/co-requires/conflicts 三关系 + 编译期索引 | schema+~80 行编译器 |
| SKRT | CJK bigram 匹配策略(中文信号匹配) | ~50 行 |
| @kernel.chat | Bradley-Terry recordOutcome(SkillOpt 反馈驱动的自学习) | ~60 行 |
| skillroute(可选) | 若不想自研:整个路由+traces+evals+tune 闭环,代价是 Python 运行时依赖 | 整包引入 |

- 纯引入路线:skillroute(harness 一等支持+可编程闭环最全)+ Python 依赖代价
- **推荐路线:自研轻量 schema+三拆借件**,嵌进 sp-router 演进为 gate(Phase2 ①步),SkillOpt 夜审用 C2 判决的 env 注入形态喂反馈——零新增运行时依赖,全 MIT,算法均有参考实现
- 无论哪条路:**CJK 处理必须自建**(全部候选对中文路由都失效或半失效),SKRT 的 bigram 是最轻解
