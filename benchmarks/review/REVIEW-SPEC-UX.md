# Spec 一致性 + UX 评审 — opencode-setup

- 日期: 2026-08-30 · 评审人: opencode (glm-5.3) · 方法: 只读走查 + /tmp/opencode 沙箱实测
- 对照物: `docs/design/specs/` A/B/C/D/E 五份 spec + `specs/README.md` 任务清单(12 项全标 [x]) + `README.md` 对用户的承诺
- 代码基线: HEAD `dbdd4ac`(上轮 7H/22M/30L 修复提交之后,以当前工作树为准)
- 关键实测环境: 干净 HOME 两轮真实跑 `setup-opencode.sh`(139s 全流程 + 幂等二跑)、webmap/opstate/self-portrait/env-profile/c-modules/audit-hook 逐模块实测
- 姊妹篇: 上轮 `REVIEW.md`(Bug/安全维度)。本轮聚焦 **spec 兑现** 与 **新用户体验**,只读不改动

---

## 0. 结论速览

**REQUEST_CHANGES**

一句话: **代码层兑现率约 8 成,交付层兑现率接近 0**——上轮 TOP1(U-1)的修复只写了一半: 用法改成了 `$SCRIPT_DIR`,但**定义行从未添加**,导致步骤 12(E 权限红线/审计/自检/合规 + B 画像 + C 画像 + D preset-skills + 路由自检)在**包括仓库内运行在内的一切路径下静默跳过**,而脚本结尾照常打出"配置完成!"。实测修复(注入一行定义)后步骤 12 全链路通过——问题被精确隔离在缺失的一行上。

| 维度 | COVERED | PARTIAL | MISSING | N/A |
|---|---|---|---|---|
| A 联网认知(12 项) | 4 | 3 | 5 | — |
| B 环境感知(12 项) | 5 | 4 | 3 | — |
| C 具身认知(7 项) | 5 | 2 | 0 | — |
| D 控制(6 项) | 2 | 2 | 1 | 1 |
| E 安全(16 项) | 5 | 8 | 3 | — |
| README 任务清单(12 项) | 5 | 5 | 2 | — |
| **合计(65 项)** | **26 (40%)** | **24 (37%)** | **14 (22%)** | 1 |

> 兑现率口径: 纯 COVERED 40%;COVERED+PARTIAL 77%。但**"新用户跑一次 setup 实际拿到"口径下**: E 六模块 0/6 生效、B/C 画像 0/2、preset-skills 0/1、路由自检 0/1——增强层交付率 0%(全部经由死掉的步骤 12)。

### 上轮遗留核对(REVIEW.md TOP/次级项)

| 上轮编号 | 本轮状态 | 证据 |
|---|---|---|
| U-1(相对路径跳过安全模块) | **半修复→更糟**: 用法已改 `$SCRIPT_DIR` 但**未定义**,原先"相对路径调用"才触发,现在所有调用都触发 | setup-opencode.sh:811(用法) vs 全文无 `SCRIPT_DIR=`(grep 仅 811-878 八处用法);实测见 §3 UX-1 |
| W-1(webmap 注入扫描 fail-open) | **未修**: 仍 `rtk grep ... && return 1 \|\| return 0`,rtk 缺失→静默判"干净" | a-modules/webmap:26;实测无 rtk 时注入样文放行 |
| G-1(gen-permissions 零参自毁) | ✅ 已修(显式 for 解析 + /dev/stdout 兜底) | gen-permissions.sh:11-20 |
| U-2(固定 /tmp 路径) | ✅ 已修(mktemp) | setup-opencode.sh:549,806 |
| U-10(管道 read 自噬) | ✅ 已修([ -t 0 ] 守卫),实测"非交互模式: 保留现有配置" | setup-opencode.sh:87-94;uxrun2.log |
| A-1(审计 JSONL 损坏) | ✅ 已修(python json.dumps),实测含引号命令出合法 JSON | audit-init.sh:18-28 |
| A-2(熔断非连续) | ✅ 已修(末尾连续计数) | audit-init.sh:30-42 |
| W-2(name 路径穿越) | ✅ 已修(消毒+截断) | webmap:57 |
| O-2(opstate rtk 依赖) | ✅ 已修(系统 grep) | opstate:25 |
| P-2(plugin spawn 探测) | ✅ 已修(findInPath 纯 fs) | plugin.js:19-28 |

---

## 1. Spec 一致性逐项

### 1.1 A-webmap(联网认知 + 3S 护栏)

| spec 项 | 判定 | 证据(文件:行 / 实测) |
|---|---|---|
| A-1 webmap 四命令 init/search/install/update | **COVERED** | webmap:110-115;实测 init ✓ / search ✓ / install nodejs.org 真装 ✓(信任级 yes 正确) |
| A-2 S1 限速 ≤2req/s 串行 | **COVERED** | webmap:16-19(`RATE=0.5` 秒/请求,throttle 每次抓取前 sleep) |
| A-2 S1 明确 UA 不伪装 | **COVERED** | webmap:15(`opencode-webmap/1.0 (+repo 链接)`) |
| A-2 S1 先 robots.txt 只抓 allow 路径 | **MISSING** | webmap 全文无 robots.txt 抓取/解析;仅 :21 注释宣称"只碰 robots 协议区"(llms.txt 恰是协议区属于话术成立,但 spec 写明"先 robots.txt"未做) |
| A-2 S1 探测写审计日志 | **MISSING** | webmap 无任何审计写入(E 审计目录亦未打通) |
| A-2 S2 注册表每源 sha256 抓取前校验(改即拒) | **MISSING** | registry 种子仅 `域名\|名称\|分类`(webmap:33-40),无 hash 字段,install 前无校验 |
| A-2 S2 trusted/community 分级 | **PARTIAL** | trusted 判定有(webmap:60-61,85);community 添加通道无(`install <任意域名>` 默认 trusted=no 算隐式社区级,但无 add 子命令/低信任隔离区分) |
| A-2 S2 注册表随 git 版本化可追溯 | **COVERED** | 注册表由 init 生成种子于用户目录,种子定义随仓库版本化(webmap:32-40) |
| A-2 S3 注入隔离(核心) | **PARTIAL** | 产出标记"数据非指令"+代码围栏+信任级 ✓(webmap:85-95);**但注入特征检测 fail-open**: webmap:26 在无 rtk 环境(`rtk grep` 127)落入 `\|\| return 0` = 判干净(实测复现);README 清单宣称"3S 实测通过"未覆盖此边界 |
| A-2 S3 严格解析失败即弃 | **PARTIAL** | 仅校验首行 `#` 开头(webmap:77),非完整 llms.txt 规范;且该行也依赖 rtk——rtk 缺失时**一切安装**被误报"格式异常"(fail-closed 方向正确但行为误导) |
| A-1 持久站点图 SQLite | **MISSING(可选)** | 未实现;spec A-3 自身标注"可选演进,先各自独立"——不计入必做 |
| A 接线: setup 部署 webmap 到用户环境 | **MISSING** | setup-opencode.sh 无任何 `a-modules`/`webmap` 引用(grep 0 命中);README 正文亦零文档——CLI 只存在于仓库,克隆用户需自行发现 |

**小结**: 四命令骨架与 S1 限速/UA 兑现;S2 hash 锁、S1 robots/审计、部署接线缺位;S3 核心护栏带 fail-open 伤。

### 1.2 B-environment(重点: 三 Fragment)

| spec 项 | 判定 | 证据 |
|---|---|---|
| Phase1 env-profile 探测脚本 | **PARTIAL** | b-modules/env-profile.sh 独立可用(实测生成 md,codegraph 就绪三态 :39-46);setup 接线死于 SCRIPT_DIR(setup:865) |
| Phase2 三 Fragment(Env/Git/Codegraph) | **COVERED** | plugin.js:47-85 恰三类 Fragment,独立缓存/独立失效(Fragment 基类 :31-44) |
| Phase3 异步状态机 + 失败也是信息 | **PARTIAL** | Pending/Ready/Failed/Skipped 有,失败不缓存下轮重试(plugin.js:41),Failed 输出状态行(:102);**无 Stale/变更重探**(spec §2.3 四态少一态);探测实为同步 render(spec 异步不阻塞——fs 只读开销小,属可接受折衷但未按 spec) |
| Phase4 注入策略(首条 user 消息 + 幂等) | **COVERED** | plugin.js:109-116 MARK 注释防重,unshift 首条 user 消息 |
| Phase4 `env status` 查看入口 | **PARTIAL** | 以"按需读 env-profile.md"承载(plugin.js:104 指针行);无命令入口(spec §5)——specs/README 清单已认可该折衷("env status 由 profile 文件承载") |
| §4 权限集成(探测走 deny/ask/allow + hook) | **MISSING** | plugin 直读文件系统,无权限通道参与 |
| §3 探测不 spawn 命令(防 EDR) | **COVERED** | plugin.js:19-28 findInPath 纯 fs 遍历(上轮 P-2 修复),GitFragment 读 .git/HEAD 不调 git(:61-71) |
| subagent ① agents 不写 override | **COVERED** | setup:153-180 生成的 oh-my-openagent.json 全部 `{}`,model 留空 |
| subagent ③ fallbackChain patch 一等公民 | **COVERED** | setup:548-628;实测 uxrun1 `omo patch applied`,策略为"系统默认优先于硬编码链"(比 spec"注入链首"更彻底,含备份与 already-applied 幂等) |
| subagent ② 装后路由自检 | **PARTIAL** | setup:891-898 存在(60s 超时+graceful ⚠);死于 SCRIPT_DIR,实际装后从不执行 |
| B 接线: opencode-env 插件部署 | **MISSING** | setup/README 均无引用(grep 0);实测装后 `plugins/` 仅 gsd-core.js/rtk.ts——插件对用户不可达 |
| README 清单"node 单测通过" | **MISSING(不可验证)** | b-modules 全目录无任何 test 文件(find 0 命中);单测若为一次性脚本未入库,宣称无从复核 |

**小结**: 插件本体质量好(零 spawn/幂等/三 Fragment),但**未部署=不存在**;env-profile 双路(脚本+插件)一死一失联。

### 1.3 C-embodiment(重点: 双通道审批目录结构)

| spec 项 | 判定 | 证据 |
|---|---|---|
| C-1 画像边界: 密钥/敏感值永不入 | **COVERED** | self-portrait.sh:29-56 仅读 model 列表/agent 路由/mcp 名单(只取 keys)/权限摘要/skills 计数;实测输出无任何密钥字段 |
| C-1 输出 0600 | **COVERED** | self-portrait.sh:63;实测 `-rw-------`(600) |
| C-2 通道① 用户级 memory(轻审批/可撤销) | **COVERED** | c-modules-setup.sh:52 建 `memory/`;templates/memory-preferences.md 定义 append+日期+删行即撤销+敏感项禁写 |
| C-2 通道② skill-drafts 草稿区(重审批, 不生效) | **COVERED** | c-modules-setup.sh:52 建 `skill-drafts/`;templates/skill-draft-README.md:"**不生效**——直到人工评审通过后移入 ../skills/",评审四要点+拒绝处置 |
| C-2 两通道互不混流/审批不混淆 | **COVERED** | 目录物理分离 + 两份模板分别声明轻/重语义(c-modules-setup.sh:56,61-63) |
| C-5 mem0 集成(通道①) | **PARTIAL** | 安装器有(c-modules-setup.sh:17-31),`@mem0/cli` 在 npm 真实存在(0.2.13,实测查 registry);但 spec 自定的胶水"触发规则"未做,且 setup 不接线(README:127 明示"手动运行",算已文档化的折衷) |
| C-5 SkillOpt 集成(通道②) | **PARTIAL** | 安装器有(:33-48);实测 PyPI `skillopt` 确为 microsoft/SkillOpt 官方(project_urls 指向 microsoft.github.io/SkillOpt)——供应链归属干净;同样缺触发规则 |
| C-6 模型适配(零自研依赖 harness) | **COVERED** | 无任何自研适配代码 = 严格符合 spec 定案("依赖内置而非新起炉灶");可选项(换模型提示)未做属"纯提示可选" |

**小结**: C 是五方向兑现最扎实的: 双通道目录结构与 spec 表格逐条对齐,边界(密钥不入/0600)实测通过。短板仅在与 setup 的自动接线(画像生成在步骤 12 ⑥,已死)。

### 1.4 D-control(重点: 五定案)

| spec 项 | 判定 | 证据 |
|---|---|---|
| D-1 对人交互: 默认装 grilling + discernment-nudge | **MISSING** | preset-skills/ 仅 ai-communication 一个;d-modules/fetch-skills.sh:5-9 指引清单里也没有这两个(E-security.md:71-73"待部署机制"的机制已建成但未纳入) |
| D-2 skill 构成: 默认 29(核心 16 + 增强 13) | **PARTIAL** | 部署机制在(setup:877-889 遍历 preset-skills,幂等跳过)但死于 SCRIPT_DIR;仓库仅 1 个自有 skill;SP 侧由 superpowers-zh 插件部分覆盖(setup:132-135),AG 侧 8 核心全缺;按需 4 与选装无通道。版权边界"不自动拷"属有意折衷且有指引(fetch-skills.sh:3,8) |
| D-3 Operator 轻量实现(声明式+对账循环) | **COVERED** | d-modules/opstate 五命令齐全;实测: 孤儿 active→pending、死依赖→blocked 双漂移检出正确,python 原子重写 |
| D-3 claim/done 可靠性 | **PARTIAL** | 前置校验有(require_task, opstate:96-102, 不存在任务实测报错);**但"owner 空+有 depends"形态的行 sed 不匹配仍打印 ✓**(opstate:104-113,实测 t5 假成功: 提示 active、文件仍 pending)——上轮 O-1 只修了前置没修变更本体 |
| D-4 拓扑标定(跟踪观察) | **N/A** | spec 定案即"跟踪",无实施要求 |
| D-5 防护三层移交 E | **COVERED** | bwrap-setup.sh + devcontainer/ 均落位 e-modules,与 E-3 Ⅰ 预防域对齐 |

**小结**: D-3 的 Operator 模式兑现好(带一个边界 bug);D-1/D-2 的 skill 集合交付是五方向中缺口最大的——机制在、内容空、且机制本身死了。

### 1.5 E-security(重点: 六模块)

六模块实体: gen-permissions / audit-init / security-check / gen-compliance / bwrap-setup / devcontainer。

| spec 项 | 判定 | 证据 |
|---|---|---|
| ① 权限红线 bash deny-list + edit 限域 | **PARTIAL** | gen-permissions.sh:51-91 实测计数: 交互版 bash 14 deny+6 ask(含 `"*": "ask"` 兜底)、edit 7 deny+2 allow、webfetch ask,共 30 条;无头版 7 deny+11 allow(:23-49);deny 面覆盖 rm-rf/force-push/curl\|sh/authorized_keys 等 spec 点名项 ✓ |
| ① escalation 通道(deny 后 justification 单次升级) | **MISSING** | 全仓库无 escalation/justification 机制(grep 0);仅 AGENT-CARD.md 文案宣称"ask 通道单次放行"(security-check.sh:85)——文档说了,配置层没做 |
| ① 熔断器(连续拒绝→中止升级给人) | **PARTIAL** | audit-init.sh:30-42 真"末尾连续"计数 ≥5 → alerts.jsonl 告警 ✓;但止于告警,无"中止升级"动作(配置层可辩,文案与能力落差应写明) |
| ① 硬 deny 位(自保护, 用户 allow 不可覆盖) | **PARTIAL** | edit deny 三个配置文件(gen-permissions.sh:62-64)✓;但 setup 合并为**整体替换** `c["permission"]=perm`(setup:832)——实测用户已有 read/external_directory 段被清空,"自保护"以先清场为代价 |
| ② 密钥治理(.gitignore 补全+0600+明文 key 迁移) | **PARTIAL** | security-check.sh:16-34: 明文 key 检测 ✓、auth.json 0600 自动修复 ✓、.gitignore 补全 ✓;"迁移"仅提示不执行(spec 自身标"现行问题"级) |
| ③ offline 开关(配置一行) | **PARTIAL** | security-check.sh:38-41 仅检测+告警,从不写入该行——spec 归类"零开销必装"且成本一行,未兑现动作 |
| ④ AGENT-CARD.md 装完生成 | **COVERED** | security-check.sh:68-96;实测生成(能力/自主度/审计/数据流向四段,含审批来源口径) |
| ⑤ 成本上限(timeout+预算 ceiling, "4 控件"之二) | **MISSING** | 全仓库无 budget/ceiling 相关配置(grep 0)——零开销必装档,完全未做 |
| ⑥ 审计(JSONL+脱敏+轮转+审批来源) | **COVERED** | 实测端到端: 四通道 event 接线(ask/deny/allow/reject)、JSONL 合法、`sk-abcdefgh***` 脱敏命中、轮转 10MB×3+30 天(audit-init.sh:7,62-70);审批来源=事件类型即人批/规则/人拒 ✓ |
| ⑦ 供应链(audit signatures + preset 锁版本) | **PARTIAL** | npm audit signatures ✓(security-check.sh:45-56, 30s 超时);但安装全部 `@latest`(setup:133,542)——锁版本未做,与"preset 锁版本"spec 字面相反 |
| ⑧ 注入自检(AgentSec npx 冒烟) | **PARTIAL** | security-check.sh:59-65 以静态 grep 三模式(curl\|sh/eval(atob/sk-)替代——更轻但非 spec 指定;折衷可接受,应标注 |
| ⑨ bwrap B 档一键选装 | **COVERED** | bwrap-setup.sh: clavinculis→opencode-bwrap 降级链+opencode-sandbox 包装器;**诚实边界**两处声明(:6-7,76-77)精确对齐 spec E-0 "不给虚假安全感" |
| ⑩ devcontainer C 档 | **COVERED** | devcontainer.json: no-new-privileges+cap-drop=ALL+非 root 用户+卷挂载 |
| E-1 弹窗预算(大部分会话零弹窗) | **PARTIAL(冲突)** | 交互版 `"*": "ask"`(gen-permissions.sh:87)使**每条未匹配 bash 命令都弹窗**——与 E-1"宽带放行/零弹窗"直接冲突;E-0"默认对最不懂用户安全"支持保守,但两原则的张力无任何折衷说明(无头版是 allow 兜底,两版立场分裂) |
| E-1 审计存储 ≤50MB | **COVERED** | 10MB×3=30MB 上限(audit-init.sh:7);alerts.jsonl 无轮转(上轮 A-6 遗留,量小) |
| E 接线: setup 步骤 12 部署六模块 | **MISSING** | setup:811 `[ -d "$SCRIPT_DIR/e-modules" ]` 恒假(定义缺失)→ 恒走 :903 else 分支;实测干净环境跑完 setup,permission 仅剩步骤 3 的 read/external_directory、无 event 段、无 AGENT-CARD/compliance/modules 目录 |

### 1.6 specs/README.md 任务清单(12 项全标 [x])

| 清单项 | 判定 | 说明 |
|---|---|---|
| 第一批: B env-profile 探测脚本 | **PARTIAL** | 脚本✓(实测);setup 接线死 |
| 第一批: D preset-skills 部署步 | **PARTIAL** | 步骤存在(setup:877);死于 SCRIPT_DIR |
| 第一批: E audit hook 自动接线 | **PARTIAL** | 代码✓(实测四通道+脱敏);经死的步骤 12,自动接线实际不发生 |
| 第一批: C self-portrait | **COVERED** | 工具独立完整(0600/密钥不入实测);README 未承诺 setup 自动跑 |
| 第一批: subagent 路由自检步 | **PARTIAL** | 步骤存在且降级优雅;死 |
| 第二批: A webmap 四命令 | **COVERED** | 实测 init/search/install 全通 |
| 第二批: A 3S 护栏 | **PARTIAL** | 限速/UA/注入标记✓;robots/sha256/审计缺+fail-open |
| 第二批: C 双通道目录 | **COVERED** | 实测目录+模板+语义全对齐 |
| 第二批: D 上游单点指引 | **COVERED** | fetch-skills.sh 版权边界清晰 |
| 第二批: D opstate | **PARTIAL** | 对账实测✓;claim 一形态假成功 |
| 第三批: B opencode-env 插件 | **PARTIAL** | 代码✓;"单测通过"无测试文件可证;**未部署** |
| 第三批: B 状态机内嵌 | **PARTIAL** | env-profile/opstate 承载失败信息✓;无 Stale 态 |

清单 12 项勾选与现实的偏差模式一致: **"能力已写"≠"能力已接线"**。第一批 5 项里 4 项的死因是同一个 SCRIPT_DIR。

---

## 2. 实测验证记录(/tmp/opencode)

| # | 验证 | 结果 |
|---|---|---|
| V1 | 干净 HOME 真跑 setup(绝对路径调用,SKIP_APT_MIRROR=1) | exit 0,总 139s;步骤 12 仅"⚠ 未找到 e-modules(源码仓库外运行?)"一行,安全层全跳过;结尾"配置完成!" |
| V2 | 同环境注入 `SCRIPT_DIR=/home/opencode-setup` 再跑 | 步骤 12 全绿: 权限合并✓/审计✓/AGENT-CARD✓/合规✓/env-profile✓/self-portrait✓/preset-skill✓/路由自检 graceful ⚠(无 API key,符合预期)——**证明缺的只有定义行** |
| V3 | V1 产出的 opencode.json | permission 仅 read/external_directory(无红线),无 event 段——安全零落地实锤 |
| V4 | 审计 hook 喂事件 | deny/allow 两行 JSONL 合法;`sk-abcdefgh***` 脱敏命中 |
| V5 | webmap 无 rtk 注入样文 | "Ignore all previous instructions" 静默放行(fail-open);有 rtk 时检出✓ |
| V6 | webmap install docs.python.org | llms.txt 404 → 种子清单含无效源(docs.python.org/nodejs.org 中后者✓) |
| V7 | opstate reconcile/claim | 双漂移修正✓;`## t5 \| status: pending \| owner: \| depends: t4` claim 报 ✓ 但文件未变(假成功) |
| V8 | self-portrait / env-profile / c-modules-setup | 三个脚本独立全通(0600/降级警告/双通道目录+模板) |
| V9 | 幂等二跑 | 全程"已存在,跳过",omo patch "already applied",非交互保留配置✓ |
| V10 | gen-permissions 规则计数 | 交互版 21 deny/7 ask/2 allow=30 条(README:120 宣称 53 条=18/7/23,数字失真) |
| V11 | npm/PyPI 包归属 | `@mem0/cli` 0.2.13 存在;PyPI `skillopt` 官方归属 microsoft/SkillOpt ✓ |
| V12 | 权限合并副作用 | 合并后 read/external_directory 段消失(整体替换非合并) |

---

## 3. UX 评审(新用户视角: `bash setup-opencode.sh`)

### BLOCKER

- **UX-1 · 步骤 12 静默死亡且话术误导,结尾零红旗**。setup:811 的 bug 使增强步骤全跳过,提示语"源码仓库外运行?"在**标准姿势(克隆后仓库根运行)下是假话**;脚本以"配置完成!"+12/12 耗时表收尾,新用户对"安全增强其实没装"毫无感知。安全功能最危险的失败是"让用户以为它在"。(实测 V1/V3)

### HIGH

- **UX-2 · README 首推路径(curl \| bash)结构性拿不到步骤 12**。模块"随仓库分发"(setup:800 注释),管道安装无仓库——README:7 的主安装命令产出的环境永远缺权限红线/审计/AGENT-CARD,但 README:40-56"安装效果"图明确画了这些产物、:73 把步骤 12 列为安装内容。承诺与两条主路径的现实都不符。
- **UX-3 · 安全自检的警告内容被 `tail -4` 吞掉**。setup:858 只展示末 4 行(恰是 AGENT-CARD 段),实测"3 通过/3 警告"——哪 3 条警告用户看不到,警告不可读=不可行动,违背自检模块的存在意义。

### MEDIUM

- **UX-4 · 路由自检失败提示无抓手**。"⚠ 路由自检未确认(网络/配额?可手动验证)"(setup:897)——怎么验证?应给出可复制的命令(如 `opencode run --model X 'OK'`)。
- **UX-5 · "权限红线已合并"实为整体替换**。setup:821 注释写 merge,:832 实为 `c["permission"]=perm` 全量覆盖——存量用户的自定义 permission 静默清空(实测 V12)。对答了"y 备份重新生成"的用户也有中途手工改配置被清的风险。
- **UX-6 · 交互红线默认 `"*": "ask"` = 每条 bash 命令弹窗**。与 E-1 零弹窗目标冲突(§1.5),README 完全未向用户预告这一体验;新用户装完的第一个感受可能是"每一步都要按确认"。
- **UX-7 · security-check 的 .gitignore/.env 检查打在 CWD=CONFIG_DIR**。setup:540 `cd $CONFIG_DIR` 后不返回,步骤 12 全部相对路径检查作用在配置目录(非 git 仓库),用户真实项目目录永远查不到(上轮 S-8 遗留未修)。
- **UX-8 · README 步骤编号与脚本错位一位**。README:62-73 列"1. 检测非 bash 环境…"而脚本 [1/12] 是"检测已有配置"(非 bash 切换在步骤 0);对照排查时容易错位。

### LOW

- **UX-9 · apt 还原提示语歧义**:"⚠ apt update 失败,还原原源: sudo cp x y"(setup:259)读起来像"已还原",实际只打印命令未执行。
- **UX-10 ·"查看已安装的 skills: skill({name:…})"**(setup:934)是工具调用语法,终端里没法直接输入,对新用户是困惑项。
- **UX-11 · GSD 路径陈旧**:收尾清单写 `plugins/gsd`(setup:940),实测目录为 `gsd-core`(plugins/gsd-core.js)。
- **UX-12 · WSL 注意事项无条件打印**(setup:943-947),纯 Linux 环境也是 WSL 提示——噪音。
- **UX-13 · PERM_TMP 顶层 RETURN trap 永不触发**,每跑一次泄漏一个 /tmp 文件;:805-807 还有莫名缩进错位(setup:806-807)。
- **UX-14 · 中文一致性总体优秀**(全部状态输出统一中文+✓/⚠/✗ 图标体系),少量残留: env 注入块 "Useful environment information:" 为英文(面向模型,可接受);插件 MARK 注释英文(无碍)。
- **UX-15 · 权限规则数文案失真**: README:73,120 宣称"53 条(18 deny/7 ask/23 allow)",实测交互版 30 条(21/7/2)(V10)。

### 正面(值得保持)

- 12 步进度条 + 每步耗时 + 汇总表(实测 139s 明细)——定位安装瓶颈体验一流
- 失败提示普遍可操作: 手动命令、退出码、"重新运行脚本即可注册"级指引密度高
- 回退链完备(bun 三级/node 两级/RTK 镜像链)且每级失败都有出口
- 幂等体验好: 二跑全程"已存在,跳过"、patch already-applied(V9)
- 非交互管道模式正确降级不覆盖配置(U-10 修复实测生效)
- 收尾"下一步"5 条 + 配置文件位置清单,新手引导结构完整

---

## 4. 最终裁定

### REQUEST_CHANGES

**Spec 兑现率: COVERED 40%(26/64),含部分兑现 77%——但交付层(用户跑一次 setup 实得)增强模块兑现率 0%,全部阻塞于同一行缺失的 `SCRIPT_DIR=` 定义。**

### TOP 3(修复优先级)

1. **补一行 `SCRIPT_DIR` 定义,救活整个步骤 12**(setup-opencode.sh:811)。上轮 U-1 的修复只替换了用法漏了定义,使 E 权限红线/审计/自检/合规 + B/C 画像 + preset-skills + 路由自检在**所有**调用方式下静默跳过,且以"配置完成!"收尾误导用户。一行修复,已实测验证(注入定义后全链路通过,V2)。同时把 UX-1 的误导话术与 UX-3 的 tail -4 一并处理。
2. **让 README 的承诺与两条安装路径的现实对齐**(README.md:7 vs :40-73)。curl|bash 结构性拿不到步骤 12——要么把模块内联进脚本/改为装后 `curl` 拉取,要么在 README 明示"安全增强仅限克隆运行"并修正安装效果图、步骤编号(UX-8)与规则数文案(UX-15);顺带补 a/b/d-modules 的发现性文档(webmap/opencode-env/opstate 目前对用户不可见)。
3. **修 webmap S3 注入扫描 fail-open**(a-modules/webmap:26)。上轮 W-1 点名、本轮实测仍未修: 无 rtk 环境注入检测静默放行,而 webmap 的威胁模型恰是"不可信第三方内容"。按上轮建议改系统 grep + 工具失败=拒绝;同文件 :77 的 rtk 依赖一并清理。

次级必改(复审前): UX-5 权限段改真合并、UX-6 弹窗策略两版立场分裂需定案并写入 README、opstate claim 假成功(opstate:104-113)、UX-4 自检失败给验证命令、E-2⑤ 成本上限零开销档补齐。
