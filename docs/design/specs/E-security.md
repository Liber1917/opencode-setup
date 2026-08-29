## 方向 E:安全/可信/合规(2026-08-23 设计原则定稿)

### E-0 设计原则:为什么各家 harness 路径不同(约束决定架构,按约束拼装而非选边)

**三家对照**(全部官方/源码级一手资料,2026-08):

| 维度 | Claude Code | Codex(OpenAI) | DeepSeek Harness(dsh) |
|---|---|---|---|
| 核心模型 | 四层栈:模式→规则→hooks→沙箱 | 双轴:sandbox mode × approval policy 正交 | 预设=双旋钮绑定,插件化能力服务 |
| 沙箱 | bwrap/Seatbelt,文件+网络双隔离 | 同技术,网络默认关 | bwrap/Landlock/Seatbelt,仅文件系统(网络/进程不管) |
| AI 审批 | auto mode 两阶段分类器,4 个 bypass 免疫检查 | Auto-review 审阅 agent,熔断器 3 连拒/10 拒 | 无——纯确定性 fail-closed |
| 关键教训 | 规则只约束工具调用,不约束调用执行的代码 | 边界内自由+越界才审(200x 更少打断) | run_code 沙箱逃逸(CVSS 10.0):新执行路径=新逃逸面 |

**路径分化的三个约束(为什么互不照抄)**:

1. **商业模型**:AI 审批只有"模型厂商自营 harness"才养得起——Anthropic 免费承担分类器 token(订阅制),OpenAI 计入用量;**dsh 是开源+用户自备 key,加分类器=给用户加税,商业上不可能**→确定性 fail-closed 是它唯一正确的路。**我们属于 dsh 阵营**(配置层/用户付费 token)——常驻分类器不做,根因是商业逻辑不只是贵。
2. **用户画像**:Claude/Codex 用户=开发者(读得懂 bash,出错能自救)→敢给宽松默认;dsh 定位含非技术用户→审批必须确定性。Anthropic 原则:"**隔离强度匹配用户的监督能力**"。**我们的 preset 是默认配置——默认值要对最不懂的用户安全**(不会改配置的人),高级用户自己放宽——方向与 dsh 相反,取其保守度。
3. **架构位置**:Claude/Codex=封闭整品,纵深可任意深(管线 7 步、bypass 免疫层);dsh=插件框架,不能假设插件在场→"缺了就死"的 fail-closed。**我们是配置层,改不动内核**——能做=dsh 的确定性工具箱(规则/hook/文档/审计);不能做=深纵深(只能一键选装它们的现成轮子,如 bwrap)。

**拼装结论**(三家都没做的组合,我们靠 preset 双层机制天然支持):
- 抄 **dsh**:确定性工具箱(fail-closed 规则表、one-shot escalation 不持久授权、审批来源审计区分人/规则)+ 保守默认
- 抄 **Claude/Codex**:体验哲学(边界内自由+高危静默 deny 而非逐条问,默认大部分会话零弹窗);B 档一键选装它们的沙箱轮子
- 不抄:AI 审批/分类器(养不起+塞不进)
- **B 档诚实边界**(dsh run_code 逃逸的教训):bwrap 管 bash 子进程,不管 harness 内进程/未来新执行路径(MCP 任意代码/webfetch JS)——要向用户写明,不给虚假安全感

### E-1 开销预算硬约束(低开销安全,量化)

- 安全附加 **token 开销 = 0**(全部规则表/静态文件/一次性脚本,无常驻模型调用)
- 安全附加**延迟 ≤ 10ms/工具调用**(规则表+异步日志;对照 agentjail OPA ~8ms 中位)
- **弹窗频率:默认配置下大部分会话零弹窗**(高危静默 deny,宽带放行)——实证:摩擦每多一分用户就自建后门(Claude 数据:62% 用过 bypass,43% 自建 node:* 全开规则,25% 会话 bypass 起步)
- 审计存储 ≤ 50MB(轮转+30 天保留)

### E-2 模块性价比序(零开销必装 → 高开销不装)

| 档 | 模块 | 低开销形态 |
|---|---|---|
| **零开销必装** | 权限红线 | 按通道选姿态:bash 用 deny-list(rm -rf/force-push/secret-write 模式)+只读白名单;edit 限 workspace(堵 Tier 2 盲区:Claude auto mode 36.8% 状态变更经 Edit 绕过分类器的教训);规则表零模型调用;**加 escalation 通道(deny 后带 justification 单次升级,授权永不持久)+ 熔断器(连续拒绝→中止升级给人)+ 硬 deny 位(settings/自保护,用户级 allow 不可覆盖)** |
| | 密钥治理 | .gitignore 补全+0600 校验+**opencode.json 明文 key 迁移**(本会话亲历的现行问题) |
| | offline 开关 | OpenCode 配置一行(三路外联关闭) |
| | AGENT-CARD.md | 装完生成一次静态文件(能力/工具/自主度/审计位置) |
| | 成本上限 | timeout+预算 ceiling("4 控件"之二:超时/成本上限/结构化日志/独立凭证,配置级近零边际成本) |
| **低开销默认** | 审计 | JSONL 追加 observe-only(logira 式,每调用<1ms)+轮转+30 天;**审批来源必须记录(人批/规则放/deny)**——否则日志无取证价值(dsh 审计盲区教训) |
| | 供应链 | 装时一次:npm audit signatures(8-12s,provenance 异常是比 hash 更强的信号——Axios 事件证明 hash 防不住恶意维护者)+preset 锁版本+来源清单 |
| | 注入自检 | 装完跑一次冒烟(非常驻):AgentSec 扫 skill(npx 一条命令) |
| **中开销选装** | bwrap 沙箱 | B 档维持一键选装(84% 弹窗减少对冲配置维护;诚实边界如上) |
| **高开销不装** | 常驻分类器/hash 链签名审计 | 商业养不起/个人用户不需要 |

### E-3 四域框架(Ⅰ预防/Ⅱ检测/Ⅲ披露/Ⅳ数据域)

- Ⅰ 事故预防:权限红线+防护三层(A 红线审计/B bwrap/C devcontainer,D 移交)+密钥治理+供应链
- Ⅱ 检测响应:审计日志+注入自检+fail-loudly 异常告警
- Ⅲ 证据披露:AGENT-CARD+可复现哈希+按地区合规文档(provider 数据流向清单)
- Ⅳ 数据主权:offline+日志脱敏(入库前脱敏→占位符→执行前还原,failMode closed;中国红线"不留可识别身份记录")+session 生命周期(30 天清理)
- 范围边界:做到"配置层能表达的"为止;harness 级(overlay 回滚/VM 隔离/分类器)全记跟踪观察

### graphify vs codegraph 路由判定(2026-08-23 定稿,五仓实测证据链)

**证据**:benchmarks/graphify-vs-codegraph/report.md §1-5(五仓光谱:opencode-setup bash+md / paperclip TS 纯码 / openwork TS+MDX / redis C / CleanRL Python+文档重)

1. **按查询类型分工**(非仅内容类型):符号/文件定位 → codegraph(语言在其支持表内:TS/JS/Py/C/Go/Rust 等);概念/架构/文档问题 → graphify(文档语义节点是独特价值,CleanRL 文档贡献 +79% 节点);行级细节 → 两者皆弱,grep 兜底是常态(路由层实测 5 任务答案最终全靠 Grep/Glob 收口)
2. **语言覆盖是 codegraph 硬门槛**:bash/md 仓库零能力(opencode-setup 实测 0 节点)——**preset 部署时应检测项目语言再决定注册**;graphify 语言面宽(bash/md 均可)但代码符号定位弱且有整文件盲区(redis ae.c/config.c 缺席)
3. **成本模型**:codegraph 建图免费;graphify 全量含 deepseek 文档语义 pass($0.09-0.10/仓)——**graphify 按需建图,不常驻**
4. **共存与冲突**:双工具可共存(路由层实测 agent 自主选择,无打架);graphify **strict 模式禁用**(避免与 codegraph 引导/CodegraphFragment 形成"双先查我"门禁冲突)
5. grep_app 已移除(omo disabled_mcps;其"远程 GitHub 代码搜索"职能 2026 年已非主流,被本地 AST+web 搜索替代)

### 待纳入 skill 清单(已评审通过,等部署机制)

| skill | 来源 | 定位 | 挂法 |
|---|---|---|---|
| `ai-communication` | 自研(已入仓库 `preset-skills/`) | 沟通协议(原则层) | 待部署机制 |
| `grilling` | mattpocock/skills(231k★) | facts 归 agent / decisions 归用户 / 提问必附推荐答案;description 自带 'grill' 触发短语,用户说"grill me"即可拷问 | 待部署机制 |
| `discernment-nudge` | anthropics/skills(171k★,官方) | 软推核查:回答后一次性追加 2-3 个验证问题 | 待部署机制 |

**方向 D 子块①(对人交互)定案**:默认装 = grilling + discernment-nudge;选装 = sycophancy-challenger(高风险决策对抗审查)+ deep-interview(模糊大活的歧义门槛,审批门禁样板);不收 = 苏格拉底教学系(学习场景错位)+ grill-me(经查证为一行转发壳"Call the Skill tool with grilling",功能被 grilling 的触发条件完全覆盖,砍掉)。

**方向 D 子块②(流程规范)定案**:默认装 = mece-skill(uxderrick,单点 MECE 校验)+ prd-writing(从 assimovt/productskills 摘单点,产物契约级);选装 = oh-my-ipd(硬件/通信团队)/ boss-skill(Web 全栈交付)/ TestAny 研发套件(正式文档门禁公司)/ SAFe-Scrum 套件(多团队规模化);不收 = 纯 persona 模板(无可执行性)+ 70+ skill 大库整库引入(污染发现面,只按需摘点)。验收标准:可执行性 = 产物契约 + 门禁 + 计算校验,默认档只收"产物契约级"以上。

---
