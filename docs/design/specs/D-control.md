## 方向 D 最终收口(2026-08-23,全部经查证/实测/四轮拷打)

### D-1 对人交互(定案)
默认 = grilling + discernment-nudge;选装 = sycophancy-challenger + deep-interview;不收 = 苏格拉底教学系 + grill-me(转发壳)。

### D-2 skill 构成(经三关验证定稿,见 benchmarks/triple-gate/report.md)
- **实测计数勘误**:实际清单 33 个(非 32,原报告行数计数误差)
- **三关结果**:静态关(5 组不可同装已排除)→ 动态关(专家评估法,含降级声明:容器无 runtime+150 次 agent 调用不可行)→ 泛化关(28/33=84.8% 纯 markdown 通用,5 个机制依赖)
- **默认装 29** = 必装核心 16(Δ≥2,三关全过:SP 8 + AG 8)+ 增强 13(Δ=1 按项目勾选);按需 4(writing-skills/context-engineering/deprecation-and-migration/performance-optimization);最小核可压至 16
- **成对交互发现**:interview-me × spec-driven-development 呈轻度重叠(次可加,−1.0)——保留但显式编排触发顺序,不设同门禁竞争
- **5 个机制依赖项**(subagent/chrome-devtools MCP/context7 MCP/外部 CLI)默认装需环境预配,否则退化为阅读价值
- **采纳标准四条**:产物契约 / 门禁 / 反合理化表 / eval(skill-creator V2 单测 + 目录 CI)
- **验证体系(完整四关,独立成文)**:详见 `benchmarks/VERIFICATION-PIPELINE.md`——静态碰撞/动态帕累托/碰撞裁决(单装臂+满配生态对照臂双臂设计)/泛化标注。双臂生态对照 = 满配(Docker 完整 opencode-setup+29 preset)与单装同题对跑,生态效应(满配−单装)测 harness 兼容性与叠加效果;终裁三方综合(专家×单装×满配),满配优先(部署位即用户体验)
- **第 2.5 关:碰撞裁决关**(skill-bench 式单点测分,2026-08-23 新增):碰撞对两侧 skill **分别单装**,跑同组任务(每组 3 个),有/无 skill、A/B 版分数矩阵,**分数定胜负**——替代人工读文判定。统一模型 GLM-5.3(zhipuai-coding-plan);成本控制:每格 2 次取中位,任务小型化
- **交叉检验原则(必须)**:专家评估(三关报告 §2)与实测裁决(碰撞关)互相印证——两者一致→高置信定案;不一致→标记分歧,复核任务效度后人工终裁;实测优先但任务效度是前置条件。交叉检验结果记入 benchmarks/collision-bench/
- **职责边界**:碰撞裁决关测"单点价值"(哪个 skill 更强),不测"共存路由"(静态关职责),不测"集合冗余"(帕累托职责)——三问三关,不可互替
- **+mece-skill + ai-communication + skill-creator V2**(管线外补充项)
- openwork 分发通道:两手抓——仓库为主(主权),openwork capability 包保持可用不急发(挂跟踪)

**G3 实测改判记录(2026-08-23,加采样后终局)**:brainstorming(SP) vs idea-refine(AG) 经 3 次采样取中位复测(benchmarks/collision-bench/report.md):基线 9 / SP 7 / AG 9——**实测稳定支持 AG,推翻专家"留 SP"判定**。但任务效度复核指出:评测形态(单发 prompt 求全量产出)与 SP"一问一停"方法论存在结构性张力,真实多轮交互中该张力不存在。**终局处置**:预设默认保留 SP brainstorming(多轮交互是真实主场景,SP 门禁文化与其余 superpowers 生态协同),idea-refine 进选装并标注"单发任务/一次性产出场景更优"。此案例同时确立验证体系原则:**评测形态与方法论的匹配度是任务效度的一部分,单发 bench 不能独裁多轮场景的取舍**。

### D-3 多 agent 协调(经 A2A/ANP/paperclip/k8s 查证)
- 轻场景(个人,≤5 agent/无预算/单人治理):**Operator 模式轻量实现**——声明式状态文件 + 对账循环(watch-diff-reconcile),k8s 十年工程先例,零依赖
- 重场景(20+ agent/预算硬限/多人和审计):**指路 paperclip**(AI 公司控制平面,有 OpenCode adapter),不自造
- A2A/ANP 层次不匹配(跨框架/跨组织才需要),记跟踪;ensemble 维持"未审计选装"

### D-4 拓扑标定(定案:跟踪观察)
| 跟踪项 | 触发条件 | 动作 |
|---|---|---|
| OpenCode 原生 agent teams(#12711) | 设计 issue 合并落地 | 文件即状态→原生任务板 |
| A2A | 跨 harness 协作场景出现 | 评估接入 |
| ANP | 开放 agent 互联网成型 | 知道就行 |
| overlay 回滚 | OpenCode 支持写时复制 | 红线升级为可回滚 |
| openwork 通道 | 两手抓,发包后看采用量 | 决定投入 |
| paperclip | 用户抱怨多 agent 管不过来 | 重场景深集成 |

### D-5 防护(移交给方向 E)
防护三层(A 权限红线+审计 / B bwrap 沙箱一键选装 / C devcontainer 按需)**归属 E 安全合规**;D 仅保留审批交互模式(plan-level 确认、auto mode、监控+打断)。

**方向 D 至此收口。**
