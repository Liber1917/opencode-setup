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
