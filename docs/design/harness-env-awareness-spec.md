# Harness 级环境感知功能规格草案

> 定位:为 agentic CLI(harness)设计"环境感知"一等特性——不是 setup 脚本能装出来的东西,而是 harness 的系统级能力。
> 参考实现:Codex CLI world-state(状态机+增量注入)、Claude Code(权限/sandbox/statusline 集成)、Cursor(拉取式动态上下文)、Gemini CLI(Tier 分层)。
> 状态:草案,待评审。关联调研报告:`/home/agent-cognition-report.html`。
> 评审记录:§2.1 ProjectFragment→CodegraphFragment 已确认(2026-08-22),§9-1 确认"通用+OpenCode适配示例"

---

## 1. 设计目标

让 agent 在正确的时机、以正确的粒度、在权限允许的范围内,获知自身运行环境(OS/工具/网络/资源/项目状态),**不阻塞、不越权、可审计、可覆盖**。

三条硬约束(全部有实证):
1. **探测动作本身会被 EDR 盯上**(Sophos:certutil/bitsadmin 合法下载被阻断;Sigma 检测 system_profiler;Defender 挂在 PreToolUse hook 点)→ 探测必须低攻击面、可审计。
2. **静态注入被 token 成本惩罚**(Cursor A/B:静态→拉取后 MCP 调用 token 减少 46.9%;Claude Code skill_discovery 每轮 97% 无收益被迫改异步)→ 快照化、增量、按需。
3. **隐私面探测即告警**(~/.aws/credentials、DPAPI 凭据一碰就触发 Credential Access 规则;EDR 看不到意图)→ 探测严格限定只读静态信息。

---

## 2. 核心架构:Environment World-State(仿 Codex)

```
┌─────────────────────────────────────────────────┐
│ EnvironmentWorldState                            │
│  ├─ OS / 平台 / 架构        (process.platform)   │
│  ├─ shell / cwd / workspace                     │
│  ├─ git 快照 (branch/user/最近commit)           │
│  ├─ 工具清单 (command -v, 懒探测)               │
│  ├─ 网络策略 (allowed/denied domains)           │
│  ├─ 资源 (CPU/内存/磁盘, 可选)                  │
│  └─ codegraph 就绪 (已装/已init/新鲜度)         │
│                                                 │
│  方法:                                          │
│  ├─ snapshot() → 捕获当前完整状态               │
│  ├─ render_diff(prev) → 只注入变化的增量        │
│  ├─ probe(name) → 按需探测单个片段 (异步)       │
│  └─ validate() → 能力边界校验                  │
└─────────────────────────────────────────────────┘
```

### 2.1 片段(fragment)模式
每个环境片段是**类型化、可组合、可单测**的模块,带 `render()`:
- `OSFragment`、`GitFragment`、`ToolFragment`、`NetworkFragment`、`ResourceFragment`、`CodegraphFragment`
- 每个片段独立缓存、独立失效、独立权限标记

`CodegraphFragment` 的产出是**能力就绪声明**,而非信息注入——不注入项目结构(目录树 token ROI 差,浅层信息用 glob 工具调用等价获取,注入则是每会话无条件支付 100-300 token),只声明深度认知工具(codegraph)的就绪状态,让 agent 知道何时该用它。示例三种状态:
- **已就绪**(索引于 X 分钟前,覆盖 N 符号)→ 遇到"谁调用 X / X 怎么工作"优先查 codegraph
- **已安装未 init** → 建议运行 `codegraph init`
- **未安装** → 结构理解靠 glob/grep

### 2.2 注入策略(三层)
| 层 | 内容 | 时机 | 成本 |
|---|---|---|---|
| **静态核心** | 平台/OS/模型 ID | 会话开始,全局缓存 | 一次性 |
| **动态快照** | git 状态/cwd/工具清单 | 会话开始 + 变更时(diff) | 增量 |
| **按需探测** | codegraph就绪/资源/网络 | agent 工具调用时 JIT | 触发才付 |

### 2.3 异步就绪状态机(仿 Codex)
```
Pending ──探测──▶ Ready ──变更──▶ Stale ──重探──▶ Ready
   │                  │
   └─────▶ Failed ────┘  (失败显式浮出,不静默)
```
- 探测**不阻塞 turn**:Pending 期间 agent 继续工作,Ready 后增量注入
- **失败也是信息**:Failed 状态注入上下文("探测失败"本身告诉 agent 环境有异常)

---

## 3. 探测边界(能/不能)

### ✅ 能探测(只读静态,各产品一致)
- OS/平台/架构、shell、cwd、git 状态、工具存在性、资源量、网络策略(配置而非测速)

### ⛔ 不能探测(一碰就触发安全告警)
- 凭据文件(`~/.aws/credentials`、`~/.ssh/`)、浏览器数据(DPAPI/cookies)、个人数据
- 明文口令、API key、token
- **探测手段偏好**:读自身进程状态(`process.platform`、env vars、配置文件解析)而非 spawn 命令(`system_profiler`/`wmic` 有现成检测规则)

---

## 4. 权限集成(关键设计)

- 探测动作**走同一套 deny/ask/allow 规则 + PreToolUse hook**——harness 的探测通道 = 安全产品的监控通道(微软 Defender 已把 hook 点当作 AI agent 监控接口)
- 敏感探测(工具清单/网络状态)默认 allow(只读);隐私面探测默认 deny(根本不提供)
- ~~企业级:managed settings 最高优先级,不可被用户/agent 覆盖~~(评审删除:留待合规方向再议)

---

## 5. 用户交互与覆盖

| 机制 | 说明 |
|---|---|
| **用户环境声明优先** | 仿 `CLAUDE_ENV_FILE`:用户显式声明的环境覆盖自动探测结果 |
| **settings 优先级** | user > project,层级不可逆覆盖(企业 managed 层已删,留待合规方向再议) |
| **按需查看入口** | `env status` 命令/工具:用户与 agent 随时查看当前环境快照(snapshot 的副产品,不做持续显示的 statusline——与 TUI 重复) |
| **workspace trust dialog** | 首次进入目录征求同意(仿 Claude Code) |
| **显式 opt-out** | `--bare` / 禁用 env 注入开关 |

---

## 6. 安全合规约束

- **EU AI Act Recital 69**:数据最小化 + data protection by design 贯穿生命周期
- **GDPR Art 5(1)(c)**:最小化原则 → 运行时对每次工具调用的数据类别检查
- **API 级最小权限**(AI Act Art 15(4)):只暴露所需端点,"系统提示里写别删文件不是安全控制"
- **设计哲学**(Anthropic 工程结论):先在环境层做确定性边界,再在模型层引导行为

---

## 7. 测试与确定性

- **快照化输入**:测试时注入固定环境快照,不依赖真实环境(确定性)
- **可 mock**:每个 fragment 可 mock,单测独立
- **diff 正确性**:测试 render_diff 只输出变化
- **状态机测试**:Pending/Ready/Failed/Stale 转换全覆盖
- **攻击面测试**:探测手段无 spawn 命令 → 无 system_profiler 类检测命中

---

## 8. 实施路线(建议)

1. **Phase 1:静态核心 + git 快照**(最小可用:注入 `<env>` 块,覆盖 80% 场景)
2. **Phase 2:Fragment 抽象 + diff 注入**(快照/增量,对齐 Codex world-state)
3. **Phase 3:按需探测 + 状态机**(异步 Pending/Ready/Failed)
4. **Phase 4:权限集成 + `env status` 查看入口**(权限走 deny/ask/allow;按需查看环境快照,不做 statusline)

---

## 9. 评审进度

| # | 问题 | 状态 |
|---|---|---|
| 1 | 目标 harness:通用还是 OpenCode? | ✅ 已确认:通用设计 + OpenCode 适配示例 |
| 2 | 目录树注入默认开关? | ✅ 已确认:砍掉注入,ProjectFragment → CodegraphFragment(能力就绪声明) |
| 3 | 工具清单探测策略? | ✅ 已确认:会话开始快照 + 工具调用失败时懒重探;只声明可用性,codegraph 单独声明就绪 |
| 4 | statusline 做不做? | ✅ 已确认:选②——砍 statusline(与 TUI 重复),改为按需查看入口(如 `env status` 命令,用户/agent 随时查看环境快照,snapshot 的零成本副产品) |
| 5 | 企业 managed settings 时机? | ✅ 已确认:删除(企业层留待合规方向再议;设计模式参考 Claude Code,后补成本低) |

### 未决设计问题(仅记录,不定论)

- **preset-skills 部署语义**:安装脚本向用户目录部署 skill 时,拷贝/更新覆盖/用户已改动的冲突处理如何设计?——依赖 setup 脚本的整体形态,而 setup 脚本方案未定,故此问题挂起,不做定论。
- **setup 脚本现状**:skill 安装无任何机制——插件走 `opencode.json` 的 `plugin` 数组(oh-my-openagent/superpowers),`$CONFIG_DIR/skills/` 只建空目录。预设 skill 的部署机制属于上述未决问题。
- **MCP 双层注册(2026-08-23 记录)**:codegraph 同时被 omo 内置白名单(McpNameSchema 枚举,omo 源码硬编码,含自动下载逻辑)与 opencode.json(我们 setup 脚本注册)注册。preset 管理 MCP 时必须**两侧同步处理**——只动一边会出"幽灵工具"(一边禁了另一边还活着)。禁 omo 侧走 `disabled_mcps` 官方开关(已用此法移除 grep_app);摘 opencode.json 侧需同步。此坑同样适用于 codegraph 将来替换(graphify)。
- **subagent 模型路由:动态跟随 vs provider 白名单(2026-08-24 记录,含定案)**:
  - **设计原则(定案)**:agents 段**不写 override**——subagent 动态跟随主模型是正确默认(用户换主模型全家生效,零维护;显式写全会把动态机制焊死+配置漂移)。
  - **系统性风险**:omo 的 AGENT_MODEL_REQUIREMENTS fallbackChain 是**隐性 provider 白名单**——`zhipuai-coding-plan` 不在 librarian/explore 等任何 agent 的链上;当主模型为白名单外 provider 时,"跟随主模型"路径断裂,动态路由落到链上(选中欠费/未配的 deepseek 即死循环,本会话 8-23/8-24 亲历四轮)。
  - **setup 三层对策(定案,随 setup 形态落地)**:① agents 留空(保持动态跟随);② **装后路由自检**:跑一次微型任务,验证 librarian 实际模型==用户主模型,不一致即报警(此自检并入 E 方向"安全自检"模块);③ **fallbackChain patch 作为 preset 一等公民**(非兜底):检测到白名单外 provider 时自动应用 patch(将 provider 注入相关 agent 链首环)+备份+可回滚,并注明 omo 升级后需重跑。patch 已在两处验证有效(config 副本+runtime cache 副本,后者才是生效位置:/root/.cache/opencode/packages/oh-my-openagent@latest/.../dist/index.js)。
  - **通用教训**:第三方插件的隐性 provider 白名单/schema 约束是配置层项目的系统性风险——对策 = 装后自检实际行为(而非只验配置文件)+ 可选 patch 库。

### 会话级上下文压缩选型(2026-08-24 定案,六工具全景+omo 自带兜底)

**核心事实:omo 自带上下文管理,第三方插件是增强非必需**
- omo 内置 22 个 hook,其中上下文相关:**preemptive-compaction**(预防性压缩+降级监控:120s 超时/会话级去重/恢复上限/空尾部检测)、**anthropic-context-window-limit-recovery**(超限自动恢复:解析 token 超限→指数退避重试→自动截断至 50%)、**tool-output-truncator**(工具输出截断)——**"上下文爆了不崩"已被 omo 兜底,零新依赖**
- omo 不做的是"高保真技术摘要压缩"(它是截断/恢复,不是智能摘要)——这是第三方插件的价值位

**六工具生态全景(zread 复搜确认,DCP 非主流)**

| 工具 | 形态 | 关键差异 | 判定 |
|---|---|---|---|
| DCP(4066★) | 插件 | compress 工具模型自主触发;缓存命中 85% | 停更(作者转 Sleev),AGPL,不装 |
| **ACP**(opencode-acp) | 插件 | **模型 100% 负责压缩;三层 LSM(T1捕获→T2蒸馏→T3凝练);缓存 91%**;50 会话 3 万调用 97%<200K token | **选装候选①**(工程成熟+缓存最优) |
| **Magic Context**(cortexkit) | 插件 | **historian 用廉价/本地模型分层压缩(不烧主模型);跨会话跨 harness 记忆;检测到与 omo/其他压缩插件冲突自动禁用自身(fail-safe)** | **选装候选②**(本地模型分层+omo 兼容意识) |
| opencode-lcm | 插件 | 无损记忆,旧会话存外+检索召回,SQLite FTS5 | 社区早期,参考 |
| context-bank | 插件 | 语义检索记忆库,进程内嵌入,本地优先 | 参考 |
| ACM(opencode-acm) | 插件 | 主动管理(pin/剪枝/知识包/守护) | 参考 |
| Sleev / ContextOS | 代理 | 见下 | 不装 |

**生态共识**:所有插件都强调 **cache-aware**(压缩不破坏缓存)= 第一优化维度。

**分层记忆架构钩子**(延续):回答级 dense-output skill → 会话级压缩(omo 兜底 + ACP/Magic Context 增强,二选一待生态实测)→ 项目级 graphify。执行层不绑死单一项目(生态仍在震荡:一周内 DCP 停更/Sleev 转向/ContextOS 夭折)。

**判定**:默认不装第三方(omo 兜底已够);选装池 = ACP、Magic Context(生态实测裁决);Sleev 因"网关形态绕 harness 内权限/审计 + 闭源计费 + 遥测"与 E 方向结构性冲突,不装;ContextOS 因"3★ 一周停更+无许可证+不支持 OpenCode"仅留设计理念参考(本地小模型摘要+零遥测+append-only ledger)。

## 方向 A:联网认知(2026-08-24 定稿:自研 webmap + 3S 护栏)

### A-0 选型原则(2026-08-24 新增,由用户约束确立)
- **项目 MIT License → 不推荐付费项目、不捆绑第三方 key/配额、版权干净**。
- 由此排除:付费/带 key 门槛/抓取版权不清的 MCP 服务、Sleev(闭源付费)、ContextOS(死胎+无许可)。DCP(AGPL 免费)仅留选装池。
- 自研 webmap 成为 A 方向唯一完全符合的载体:纯 curl+本地解析,零依赖零费用,只抓站点授权给机器人的数据(llms.txt/sitemap/robots.txt),MIT 下无版权负担。

### A-1 自研三件套 + 3S 护栏(定稿,2026-08-24 参考设计版)
**授权核查结论**:webmap 生态无干净 MIT 轮子(firecrawl 无许可/已弃用、llms-txt-hub NOASSERTION、seo-audits 无许可、python-sitemap GPL-3.0)→ **跟 llms.txt 开放标准自研**(llmstxt.org 规范本身 MIT),参考轮子设计但不抄代码。
**参考设计来源**(不抄代码,仅借设计/API 形态):
- llmstxt-cli(npm,无许可):**"llms.txt 即 skill"成熟模式**——`install <名>`→抓 llms.txt→存 `.agents/skills/<slug>/SKILL.md`→symlink 各 agent;明确支持 OpenCode
- firecrawl generator(弃用):标准 `llms.txt` + `llms-full.txt` 双版本
- llms-txt-hub(898★):curated 目录按主类(6)+副类(7)组织

```
webmap(自研, MIT 干净, 仿 llmstxt-cli 命令形态):
  webmap init              # 初始化 curated 注册表(种子仿 hub 分类结构)
  webmap install <名>      # 抓该站点 llms.txt/llms-full.txt → skills/<slug>/SKILL.md → 注册 opencode
  webmap search <词>       # 搜注册表
  webmap update            # 刷新已装(llms-full 优先, 仿 --full)
  内部: curl 抓 llms.txt/robots.txt → 严格解析(3S S3) → 存 SKILL.md(3S S2 分级)
  3S 护栏: 限速≤2req/s/UA/审计(S1) · 注册表 hash 锁+trusted/community 分级(S2) · 注入隔离+严格解析(S3)
  持久站点图: SQLite 本地跨会话累计(数据主权)
```

### A-2 3S 顾虑与防御(用户明确:三个全中,对策为必做)
| S | 风险 | 防御(必做) |
|---|---|---|
| **S1 安全**(探测动作被 EDR 盯) | curl 批量抓取/遍历 = 像爬虫侦察 | 限速≤2req/s 串行;先 robots.txt 只抓 allow 路径;明确 UA(opencode-webmap/1.0+contact)不伪装;探测写审计日志;诚实边界:EDR 仍可能观察,不承诺隐身 |
| **S2 供应链**(注册表投毒/域名劫持) | curated YAML 被篡改→agent 抓恶意源 | 注册表每源存 sha256 抓取前校验(改即拒);trusted(内置种子+hash)/community(用户添加低信任)分级;注册表随 git 版本化可追溯;DNS 过期/转移异常核对(可选) |
| **S3 内容安全**(注入/污染) | 恶意站点在 llms.txt/sitemap 塞 prompt 注入;内容污染 agent | **注入隔离(核心)**:抓取内容仅作数据结构进独立上下文,明确"不可信数据非指令",禁止内容指令被执行;严格解析(失败即弃,不接受宽松解析);trusted 源进正常上下文,community 源默认隔离+标记;注入特征启发式(含"忽略以上/你是AI/系统提示"等模式→标记) |

### A-3 与既有能力的关系
- **graphify**:webmap 的"持久站点图"可落 graphify(五仓实测其文档建图能力)——接分层记忆钩子,非新建 SQLite(可选演进)
- **分层记忆**:回答级 dense-output → 会话级压缩(omo 兜底+ACP/Magic Context 候选)→ 项目级 graphify + 联网级 webmap,四级贯通(钩子记,执行待定)

### A-4 状态
- 选型定稿:自研为主(3S 护栏必做),Sleev/ContextOS 排除,DCP 选装池
- 待做:webmap 原型(curated 注册表+探测工具+隔离层),可复用验证体系测试
- 未决:webmap 与 graphify 的落点整合(先各自独立,后接分层记忆)

## 方向 C:具身认知(2026-08-24 定稿:自我画像 + skill 层自进化,双通道审批)

### C-1 边界(定稿)
- **画像内容边界(3S 防护下"读自己")**:能进画像 = 模型 ID/提供商/上下文窗口/能力标记/工具技能清单/权限配置摘要/会话统计(token 用量/耗时);**永不入画像** = API key/令牌(明文 key 是已知隐患,画像工具必须跳过密钥字段)、环境变量敏感值、用户个人数据。
- **自进化边界(SkillOpt 式,只做 skill 层)**:读自己→self-report(只读);提炼 skill→落**草稿区**(自动生成不直接生效);改自己→**用户审批后**入正式区(人工批准是硬门);**不做** = 权重更新/LoRA/自动改配置/自动启用新 skill。
- **与 3S 护栏对齐**:S1 画像读配置=本地只读+审计;S2 草稿区=供应链隔离(未审批不生效);S3 提炼读取的会话内容按不可信输入处理(历史会话可含恶意内容,防注入)。

### C-2 双通道审批(核心设计,2026-08-24 定稿)
"提炼经验"拆成两类,审批粒度分离——**不是自动分类,而是触发场景天然区分**:

| | ① 用户偏好/recall(类比 Claude Code /memory) | ② 流程改进(skill 内部更优流程) |
|---|---|---|
| 本质 | 事实记录(用户喜欢什么/项目约定) | 行为变更(agent 以后怎么做) |
| 通用性 | 低(绑定用户/项目) | 高(影响所有用该 skill 者) |
| 触发 | 用户显式说"记住/我喜欢/以后都这样" | 自动监测"流程与 skill 文档不一致/检索发现更优做法" |
| 写入 | **用户级 memory,直接写入(轻审批/可撤销)** | **草稿区 → 专门评审 → 批准才改 skill(重审批)** |
| 风险 | 低(记错顶多偏好不适用) | 高(改错影响所有后续行为) |

- **独立通道**:recall 通道(会话中 append,类 /memory)/ 改进通道(提炼→草稿→评审),互不混流。
- **审批不混淆**:用户不会被"改 skill"的重审批打断"记住偏好"的轻操作。

### C-3 与既有架构关系
- 画像复用方向 B 环境画像架构(读自己是读环境的姊妹,同一套探测/审计模式)
- 自进化接分层记忆钩子:skill 层自进化 = 记忆层的"改进回路"
- 参照实现:Claude Code /memory(通道①)、SkillOpt-Sleep 夜间管线(通道②的提炼器)、AutoSkill(add/merge/discard 决策)

### C-4 状态
- 边界与双通道定稿;待做:见 C-5 实施意见(用轮子版)
- 未决:改进通道的"更优流程"如何被可靠监测(需规则/检索配合,后续细化)

### omo 插件失效事故与修复(2026-08-29)
- **症状**: task 工具的 subagent_type 里 librarian/oracle/sisyphus-junior 消失(agent list 也无),但 `opencode run --agent librarian` 仍可跑(动态解析与注册分离)
- **根因**: `~/.config/opencode/node_modules` 里 omo 安装损坏(dist 8-24 时间戳但依赖树经多次 opencode 升级后不一致)
- **修复**: `cd ~/.config/opencode && npm install oh-my-openagent@latest --save`(重装一致化)→ agent 注册恢复;**重装会覆盖 fallbackChain patch,需重打**(librarian/explore/sisyphus-junior 三 agent 首环注入 zhipuai-coding-plan,两处副本: config node_modules + runtime cache)
- **教训**: opencode 自动更新会触碰插件依赖树;patch 后的插件在 opencode 大版本升级后应例行检查 agent list 健康度(可用 `opencode agent list | grep -c librarian` 当金丝雀)

### 生态替换记录(2026-08-28)
- **superpowers → superpowers-zh(jnMetaCode,7.9k★)**:benchmark 实测 zh 50/54 vs en 45/54(中文触发 2/0、debug 流程更严、翻译无损);setup 默认插件源已换 jnMetaCode/superpowers-zh;注意 zh 基于上游旧快照(brainstorming/executing-plans/subagent-driven-development 落后一次重写);英文环境用户可手动换回 obra/superpowers。报告: benchmarks/superpowers-zh-vs-en/

### C-5 实施意见(2026-08-24 定稿:集成而非自研)
**核心原则:不造轮子,优先集成成熟开源。**

| 子功能 | 方案 | 授权 | OpenCode 兼容 |
|---|---|---|---|
| 通道① 用户偏好/recall | **集成 mem0**(64k★,通用记忆层) | Apache-2.0 | ✅ 原生支持 OpenCode |
| 通道② 流程改进 | **集成 microsoft/SkillOpt**(16k★,text-space skill 优化器 + skillopt-sleep 夜间管线) | MIT | ⚠️ 核心 harness 无关,需 OpenCode 适配壳(几十行胶水) |
| 决策维护(add/merge/discard) | mem0 已含 | — | ✅ |
| 自我画像(读自己) | 复用方向 B 环境画像架构(同源探测/审计);读 opencode 运行时信息 + 审计聚合 | 自研薄壳 | ✅ |

**自研量**:仅 OpenCode 适配壳(SkillOpt 侧)+ 触发规则(何时走通道①②)+ 目录约定 + 审批提示 = 胶水层,不写核心逻辑。

### C-6 模型适配(2026-08-24 定稿:依赖 harness 内置,不造)
- **结论:模型适配无成熟独立开源轮子**(论文级 PromptBridge/MAPO 无官方实现,社区搜索全边缘项目);但**OpenCode 已内置解决大半**:
  - models.dev 元数据 → 模型能力/上下文/模态自动识别(agent 知道自己在跑什么 = C-1 画像的现成来源)
  - 能力 gate → 无 reasoning 能力的模型不生成推理变体
  - provider 协议注入 → 75+ provider 的 thinking/reasoning 字段自动适配
- **修正后方案**:
  - 能力感知(agent 认识自己跑的模型):零自研,画像工具读 OpenCode 运行时即可(与方向 B 同源)
  - prompt 适配(同一配置适应不同模型):零自研,models.dev+能力 gate+provider 注入已覆盖
  - 跨模型迁移优化(论文级):**不做不造**——研究级,个人用户无必要,harness 内置已覆盖 95% 场景
  - 可选增强:检测到用户换模型时,提示"是否用 ai-communication 风格校准"(纯提示,无核心逻辑)
- **经验教训**:先审视 spec 已有能力 + 搜轮子,再决定造不造——模型适配是"harness 已解决+无轮子"的典型案例,正确动作是依赖内置而非新起炉灶。

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
