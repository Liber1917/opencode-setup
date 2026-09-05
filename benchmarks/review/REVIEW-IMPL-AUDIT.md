# Spec 贯彻审查(第三只眼)——实现级逐条核对报告

- 日期: 2026-08-30 · 审查者: 独立审计 pass(opencode, GLM-5.3)
- 范围: `docs/design/specs/{A,B,C,D,E}*.md` 全部"要做/必做"条目 + `specs/README.md` 五项"已知折衷"
- 方法: 纸面宣称≠实现。每条判定给 文件:行号 证据;可执行项在 `/tmp/opencode` 隔离 HOME 实测复现;宣称有测试的必查测试文件并复跑
- 纪律: 只读审查,除本报告外未改任何仓库文件;全部实验在 /tmp/opencode

---

## 0. 结论速览

| 项 | 结果 |
|---|---|
| 应做条目总数(可判定) | **80** |
| 实现(严格) | 45(56.2%) |
| 实现+部分 | 68(85.0%) |
| 虚假折衷 | **1 项**(折衷③"update 校验");另有 1 处生成文档失实句(AGENT-CARD"审计写 30s") |
| 重大发现 | ① `webmap update` 功能性损坏(实测);② omo 路由 patch 未打到 runtime 生效副本(本机实测 0 标记);③ D-2"默认装 29"大部分未落地且未列入折衷;④ 路由自检⑧验证对象错位 |
| 终裁 | **REQUEST_CHANGES** |

---

## 1. A-webmap.md 逐条(a-modules/webmap)

| # | 条目 | 判定 | 证据(文件:行号 / 实测) |
|---|---|---|---|
| A-1 | `webmap init` | 实现 | webmap:44-62;实测两跑幂等("已存在(种子跳过)") |
| A-2 | `webmap install`(抓 llms.txt→skills/<slug>/SKILL.md) | 实现* | webmap:69-134;实测 nodejs.org 真装成功,信任级 yes 正确。*偏差:spec 形态为 `install <名>`(注册表名),实现只认域名——实测 `install python-docs` 探测 `https://python-docs/` 失败(webmap:7 用法定义即域名) |
| A-3 | `webmap search` | 实现 | webmap:64-67;实测 `search python` 命中 |
| A-4 | `webmap update`(刷新,llms-full 优先) | **未做(损坏)** | webmap:136-142 `read -r domain name ts` 未设 `IFS='\|'`,整行 4 字段被当作 domain;**实测**:update 输出 `→ 探测 https://nodejs.org\|nodejs-docs\|ec5c.../llms.txt`→必失败,任何已装项均无法刷新。另 `llms-full.txt` 抓取不存在(全文仅 :94 llms.txt);"llms-full 优先"未做 |
| A-5 | S1 限速≤2req/s 串行 | 实现 | webmap:16-19(`RATE=0.5` 秒/请求,每次 fetch 前 sleep);实测 2 次抓取 2.7s(含网络) |
| A-6 | S1 先 robots.txt 只抓 allow | 实现 | webmap:78-88(Disallow 覆盖 /llms.txt 即拒+写审计);awk 判定逻辑单测命中。注:覆盖面=llms.txt 路径(与作业面一致);:81-83 有一段无操作死代码 |
| A-7 | S1 明确 UA 不伪装 | 实现 | webmap:15(`opencode-webmap/1.0 (+repo)`)、:22(-A) |
| A-8 | S1 探测写审计日志 | 实现 | webmap:24-30(写 E 审计目录,缺目录静默不阻塞)、调用点 :86/:91 |
| A-9 | S1 诚实边界(不承诺隐身) | 实现 | spec/README 表述与实现一致(无隐身宣称) |
| A-10 | S2 注册表每源 sha256 抓取前校验(改即拒) | 未做→折衷③披露 | registry 种子无 hash 字段(webmap:47-55);以装后指纹替代(webmap:129-132);折衷宣称的"update 校验"不存在(见 A-4/§6) |
| A-11 | S2 trusted/community 分级 | 部分 | trusted 判定 webmap:75-76,标记 :116/:121;community 无添加通道、无差异化隔离(统一围栏) |
| A-12 | S2 注册表 git 版本化 | 部分 | 种子定义随仓库(webmap:47-55);用户注册表在 ~/.config 不随 git |
| A-13 | S3 注入隔离(检出即拒+不可信标记) | 实现 | webmap:100-104(检出拒装)+ :122-126(围栏+"视为数据而非指令");实测中英注入样文均拒、干净文放行 |
| A-14 | S3 严格解析失败即弃 | 实现 | webmap:106-108(首行 `#` + ≥3 行) |
| A-15 | S3 注入特征启发式 | 实现 | webmap:33-42(`ignore all/previous/above`、`忽略(以上\|之前\|上述)`、`you are an AI`、`你是AI`、`system prompt`、`系统提示`、`disregard`);grep 异常 fail-closed(:40) |
| A-16 | S3 trusted 正常上下文/community 隔离 | 部分 | 仅有信任级字段区分(webmap:116,121),无上下文隔离差异 |
| A-17 | 持久站点图 SQLite | 未做 | 仅 installed.list 平面清单(webmap:132);spec A-3 自标"可选演进/非新建 SQLite",判轻度 |
| A-18 | A-4 webmap 原型(注册表+探测+隔离层) | 实现 | 上述 A-1..A-16 综合 |

小计:实现 12 / 部分 3 / 未做 3(共 18)

---

## 2. B-environment.md 逐条(b-modules/)

| # | 条目 | 判定 | 证据 |
|---|---|---|---|
| B-1 | Phase1 静态核心 `<env>` 注入 | 实现 | plugin.js:47-55, 109-116(首条 user 消息 unshift) |
| B-2 | Phase2 Fragment 六类(OS/Git/Tool/Network/Resource/Codegraph) | 部分 | 实现 3/6:env(合并 OS+Tool)/git/codegraph,plugin.js:92;Network/Resource 片段无 |
| B-3 | render_diff 增量注入 | 未做 | 仅 MARK 幂等防重(plugin.js:113),无 diff/变更检测 |
| B-4 | snapshot/probe/validate 方法族 | 部分 | probe/render 有(plugin.js:35-43);validate 无 |
| B-5 | Phase3 状态机 Pending/Ready/Failed/Stale | 部分 | Pending/Ready/Failed/Skipped 有(plugin.js:32-43);Stale 无;实现为同步(:96 注释自称"同步",无实际超时机制) |
| B-6 | 失败也是信息 | 实现 | plugin.js:102(Failed 片段注入状态行) |
| B-7 | CodegraphFragment 能力就绪三态 | 实现 | plugin.js:75-85(ready/未 init 返回文案;未装静默);env-profile.sh:39-46 同款三态 |
| B-8 | §3 探测零 spawn(防 EDR) | 实现 | plugin.js:11-28 仅 fs/process;全文无 child_process/spawn(import 及调用均无,已核) |
| B-9 | §3 隐私面不探测 | 实现 | plugin/git 探测无凭据路径读取;且不读 commit subject(注入面,plugin.js:63) |
| B-10 | §4 权限集成(deny/ask/allow+PreToolUse) | 未做→折衷④披露 | 插件直读 fs,无权限通道对接(与折衷④描述一致,披露诚实) |
| B-11 | §5 `env status` 查看入口 | 部分 | 以指针行承载(plugin.js:104"Full profile: read ... on demand");无命令入口;specs/README:32 已声明"env status 由 profile 文件承载"(任务清单内披露) |
| B-12 | 插件部署接线 | 实现 | setup:895-911(拷贝至 plugins/opencode-env/ + opencode.json plugin 数组追加相对路径) |
| B-13 | env-profile 探测脚本 | 实现 | env-profile.sh 全文;实测生成 md(含 codegraph 就绪三态);setup:920-924 部署并执行。注:该脚本探测用 `--version` spawn(env-profile.sh:17-19)——非会话内探测,setup 期一次性,与 §3"运行时探测"口径不冲突但需知悉 |
| B-14 | 插件单测 | 实现 | test-plugin.mjs:11-35;**本审计复跑通过**("2 组断言全过":非 git 注入/幂等/part 纯净 + branch+sha) |
| B-15 | 路由对策① agents 留空(动态跟随) | 实现 | setup:161-187(agents 全空对象) |
| B-16 | 路由对策② 装后路由自检(librarian 实际模型==主模型) | 部分 | setup:947-959 步骤存在(60s 超时+失败⚠);**但实测逻辑是 `opencode run --model <主模型>`(setup:951),跑的是主模型冒烟,不触发任何 subagent,无法验证 librarian 路由**——验证对象错位,恰好检不出 B-17 的失效 |
| B-17 | 路由对策③ fallbackChain patch(生效位置+备份+可回滚) | **未做(关键)** | setup:558-638 patch 脚本存在且幂等,但**只打 `$CONFIG_DIR/node_modules/oh-my-openagent/dist/index.js`(setup:633)**;spec B:157 明言生效位置是 `/root/.cache/opencode/packages/oh-my-openagent@latest/.../dist/index.js`——**本机实测该 runtime 副本含 0 个 patch 标记、原版 fallbackChain 仍在 5 处**。setup 全文无 `.cache` 引用(grep 0 命中)→ 打补丁的位置 opencode 不加载。另:无备份逻辑(spec ③ 要求"+备份+可回滚") |
| B-18 | README 第三批"状态机内嵌" | 实现 | env-profile 三态承载(说法成立;opstate 属 D) |
| B-19 | superpowers→zh 替换落地 | 实现 | setup:142(jnMetaCode/superpowers-zh git 源) |

小计:实现 11 / 部分 5 / 未做 3(共 19)

---

## 3. C-embodiment.md 逐条(c-modules/)

| # | 条目 | 判定 | 证据 |
|---|---|---|---|
| C-1 | 画像边界:密钥/敏感值永不入 | 实现 | self-portrait.sh:10-56(只读 models 列表/agent 路由/mcp 名单 keys/权限摘要/skills 计数);**实测**:配置含 `apiKey: sk-ant-SUPERSECRET...`,产出 json 0 命中该串 |
| C-2 | 输出 0600 | 实现 | self-portrait.sh:63;实测 `-rw-------`(600) |
| C-3 | C-2 双通道目录+模板 | 实现 | c-modules-setup.sh:50-56(memory/ + skill-drafts/ + 模板 cp -n);实测两目录+两模板就位 |
| C-4 | 两通道互不混流/审批分离 | 实现 | 目录物理分离+模板分别声明轻/重语义(memory-preferences.md:1-10、skill-draft-README.md:1-5,含"不生效直到人工评审") |
| C-5 | mem0 集成(通道①) | 部分 | 安装器 c-modules-setup.sh:17-31;实测 CLI 真实存在(Mem0 CLI v0.2.13);spec 自定"触发规则"胶水无;setup 不接线——根 README:129-136 已明示"手动运行"(文档化折衷) |
| C-6 | SkillOpt 集成(通道②) | 部分 | c-modules-setup.sh:33-48(pip 安装+夜间管线说明+草稿区硬门说明);"几十行适配壳"仅目录约定+README 模板,无实际管线壳 |
| C-7 | C-6 模型适配(零自研,依赖内置) | 实现(按定案) | spec 定案即"不做不造/依赖 harness 内置";无可做项。可选项"换模型提示"未做(spec 标可选,不计) |
| C-8 | C-3 复用 B 架构 | 实现 | self-portrait 与 env-profile 同源探测模式 |

小计:实现 6 / 部分 2 / 未做 0(共 8)

---

## 4. D-control.md 逐条(d-modules/、preset-skills/、benchmarks/)

| # | 条目 | 判定 | 证据 |
|---|---|---|---|
| D-1 | D-1 默认装 grilling+discernment-nudge | 未做→折衷⑤披露 | preset-skills/ 无此二项;仅 fetch-skills.sh:9-10 指引(obra/superpowers 为 MIT 可直接拷)。折衷⑤描述属实(见 §6) |
| D-2 | D-1 选装 sycophancy-challenger+deep-interview | 未做 | 全仓无载体(指引亦无)——选装项零落地,未披露 |
| D-3 | D-2 默认装 29(核心16:SP8+AG8;增强13) | **未做(大部分)** | SP 侧:superpowers-zh 插件整包覆盖 SP 核心 8(setup:142)✓;**AG 侧 17 个(核心8+增强里 AG 项):零部署**——setup 无任何 AG 套件安装路径,fetch-skills.sh:5-10 也未列 AG 套件(用户无从按指引获取);preset-skills/ 仅 1 个(ai-communication,属管线外补充项)。specs/README D 行以"skill内容按版权边界手动摘取"概括,但 AG 17 项缺失未列入五折衷 |
| D-4 | D-2 按需 4(writing-skills/context-engineering/deprecation-and-migration/performance-optimization) | 未做 | 无部署、无指引(fetch-skills.sh 列的是 skill-creator,非此四项) |
| D-5 | D-2 验证体系四关(独立成文) | 部分 | VERIFICATION-PIPELINE.md 存在;静态/动态/泛化/碰撞(单装臂)有报告;"生态对照臂 ⏳ 待跑"(PIPELINE:4、:73-77 如实标注) |
| D-6 | G3 实测改判记录(9/7/9) | 实现 | collision-bench/report.md:94-101(base 9/SP 7/AG 9,加采样 3/3 中位数)——与 spec 记载一致 |
| D-7 | D-3 opstate(声明式状态+对账循环) | 实现 | opstate:13-131;**实测**:init✓/claim 不存在 id 正确报错 exit1(:96-102 假成功防线)/claim→done 流转✓/reconcile 检出"active 无 owner→pending"+"依赖未完成→blocked"双漂移✓ |
| D-8 | 子块② 默认装 mece+prd-writing | 未做 | 仅 fetch-skills.sh:6-7 指引(无 LICENSE 不自动拷,版权边界理由成立);未列入五折衷 |
| D-9 | ai-communication 入 preset+部署机制 | 实现 | preset-skills/ai-communication/SKILL.md(frontmatter 完整);setup:932-945 部署步(已存在则跳过,幂等 setup:937-938) |
| D-10 | D-5 防护移交 E | 实现 | e-modules 含 bwrap-setup.sh + devcontainer/(E 侧承接) |

小计:实现 4 / 部分 1 / 未做 5(共 10;D-4 拓扑跟踪项按 spec 为观察项,不计数)

---

## 5. E-security.md 逐条(e-modules/、setup:807-967)

| # | 条目 | 判定 | 证据 |
|---|---|---|---|
| E-1 | E-1 token 开销=0 | 实现 | 全部为静态规则/一次性脚本/事件 hook,无常驻模型调用(全仓核) |
| E-2 | E-1 延迟≤10ms/工具调用 | 部分 | 规则表为 opencode 原生(近零);但 E-2 审计行宣称"每调用<1ms"**实测不成立**:hook 每事件 spawn python3,5 次采样均 ~0.02s(20ms)。无任何延迟基准佐证 ≤10ms/<1ms 数字 |
| E-3 | E-1 大部分会话零弹窗 | 部分 | 39 条常用 allow 宽带(gen-permissions.sh:87-125);但 `webfetch:"ask"`(:66)与未知命令 `*:"ask"`(:126)使 web/非常规任务会话有弹窗——定性设计主张,非实证 |
| E-4 | E-1 审计≤50MB+轮转+30天 | 部分 | 上限成立:10MB×4=40MB(audit-init.sh:7 KEEP=3)+30 天删除(:80);**实测 rotate 生效**(伪造 11MB→轮转 .1)。但 rotate 仅 `--rotate` 手动触发,setup/ cron 均无调度(setup 全文 grep "rotate" 0 命中)——上界依赖人手 |
| E-5 | E-2① 权限红线 bash deny-list+只读白名单 | 实现 | gen-permissions.sh:67-127;**实测计数:交互版 bash 59 条=14 deny/6 ask/39 allow,与根 README:75 口径一致**;setup:832-871 merge 进 opencode.json(deny 不可被既有 allow 稀释 :850-852) |
| E-6 | E-2① edit 限 workspace(堵 Tier2) | 部分 | 敏感面 deny 齐(:58-64);但 `~/.config/opencode/**`、`~/.claude/**` allow(:56-57)已越出 workspace |
| E-7 | E-2① escalation(单次/授权永不持久) | 实现→折衷①披露 | ask 通道承载(webfetch/git push ask);AGENT-CARD:98 如实披露"无独立通道——由 ask 通道承载(人在场逐次授权,授权不持久)" |
| E-8 | E-2① 熔断器(连续拒绝→中止升级给人) | 部分 | 连续 5 deny→circuit-breaker 告警(audit-init.sh:29-40)**实测触发**;observe-only 架构无"中止"能力,仅告警(AGENT-CARD:99 如实写"告警") |
| E-9 | E-2① 硬 deny 位(自保护) | 部分 | opencode.json/oh-my-openagent.json/settings.json edit-deny(gen-permissions.sh:62-64);"用户级 allow 不可覆盖"依赖 opencode 合并语义,本审计无法独立验证 |
| E-10 | E-2② 密钥治理(.gitignore+0600+明文 key 迁移) | 部分 | .gitignore 补全 security-check.sh:29-31✓;auth.json 0600 校验+自修 :25-27✓;明文 key **实测检出**(:16-22,埋入 sk-ant-... 报 FAIL exit≠0)——但仅"建议迁移",迁移动作未做 |
| E-11 | E-2③ offline 开关(配置一行) | 实现 | security-check.sh:40-48(--offline 写入 offline:true) |
| E-12 | E-2⑤ AGENT-CARD 装完生成 | 部分 | security-check.sh:81-110,setup:880-883 接线;实测生成(含能力/自主度/审计/数据流向四段)——**但独立运行 bug**:无 skills/ 目录时死于 :85 `ls\|wc -l`(set -o pipefail),实测 exit2 且 AGENT-CARD 未生成(setup 路径有 skills/ 不受影响) |
| E-13 | E-2⑤ 成本上限 | 实现→折衷②披露 | timeout 链:codegraph 装 120s(setup:681)/路由自检 60s(setup:951)/工具版本 10s(env-profile.sh:18)/npm audit 30s+扫描 30s(security-check.sh:59,76)/models 20s(self-portrait.sh:12);≥300 事件/会话告警(audit-init.sh:41-51)**实测触发**(补 300 事件→cost-ceiling alert events:300) |
| E-14 | E-2 审计 JSONL+审批来源记录 | 实现 | hook.sh JSON 组装 audit-init.sh:18-28;四通道 event 接线 :57-66(**实测 opencode.json 生成 ask/deny/allow/reject 四键**);审批来源=src 字段通道语义;**实测脱敏**:`Bearer abcdefgh***`、`sk-abcdefgh***` |
| E-15 | E-2 供应链(npm audit signatures+锁版本+来源清单) | 部分 | npm audit signatures 一次装时(security-check.sh:58-69)✓;**"preset 锁版本"未做且反向**:setup:141 `oh-my-openagent@latest`(明示 latest);来源清单=AGENT-CARD 插件/MCP 列表(部分) |
| E-16 | E-2 注入自检(AgentSec npx) | 部分 | 以自写静态扫描替代(security-check.sh:71-79,curl\|sh/eval(atob/sk- 三模式)——非 spec 指定 AgentSec 工具,替换未披露 |
| E-17 | E-2 bwrap B 档一键选装+诚实边界 | 实现 | bwrap-setup.sh:14-31(clavinculis 优先/降级 opencode-bwrap)、:33-52 包装器、:6-7/:76-77 诚实边界文案与 spec E-0 一致 |
| E-18 | E-2 高开销不装(分类器/hash 链) | 实现 | 全仓无分类器/hash 链 |
| E-19 | E-3Ⅱ fail-loudly 异常告警 | 部分 | alerts.jsonl 载体(熔断/成本);无主动通知机制 |
| E-20 | E-3Ⅲ 可复现哈希 | 未做 | 全仓无环境/build 哈希产物;AGENT-CARD/COMPLIANCE 无 hash 段 |
| E-21 | E-3Ⅳ 日志脱敏(占位符) | 实现 | audit-init.sh:25-26(sk-/Bearer 打码);实测(见 E-14)。"执行前还原"不适用(审计 append-only) |
| E-22 | E-3Ⅳ session 30 天清理 | 部分 | rotate 的 -mtime +30 -delete(audit-init.sh:80);随 rotate 手动触发 |
| E-23 | E-3Ⅳ offline(数据主权) | 实现 | 同 E-11 |
| E-24 | E-0 B/C 档诚实边界向用户写明 | 实现 | bwrap-setup.sh:6-7,76-77;devcontainer/README.md |
| E-25 | E-3Ⅲ 合规文档(按地区+provider 清单) | 实现 | gen-compliance.sh:17-25(地区检测)、:29-44(provider 清单含 omo 路由)、:72-111(CN/EU 双模板);**实测 --region cn 生成**,provider 正确列出 |
| E-26 | 审计接线"实测四通道写入"(README 第一批宣称) | 实现 | 本审计独立复现(四通道+脱敏+熔断+成本告警全过)——宣称属实 |

小计:实现 12 / 部分 12 / 未做 1(共 25)

---

## 6. 五项"已知折衷"核验(specs/README.md:34-39)

| # | 折衷宣称 | 核验 | 判定 |
|---|---|---|---|
| ① | escalation 无原生 justification 通道→由 ask 通道承载(人在场逐次授权) | opencode 配置面确无 justification 承载机制;交互模板以 ask 承载高危项(gen-permissions.sh:66,82-86);AGENT-CARD:98 披露一致 | **属实** |
| ② | E-2⑤ 成本上限→timeout 全链+单会话≥300事件告警(代理指标);原生 budget 待上游 | timeout 抽查 6 处实在(见 E-13);300 事件告警实测触发(audit-init.sh:41-51) | **属实**(注:AGENT-CARD:100"审计写 30s"一句失实——audit-init.sh 全文无 timeout,grep 0 命中;该生成文档句子与事实不符) |
| ③ | S2 注册表 sha256→装后指纹记录**+update 校验**(预锁内容hash会随上游更新误报) | 装后指纹记录:属实(webmap:129-132,实测 installed.list 含 sha);**"update 校验":虚假**——webmap:136-142 无任何比较逻辑,且 update 因 IFS 解析缺陷整体损坏(实测 §1 A-4),"校验"从未存在 | **半虚假:后半句无实现支撑** |
| ④ | B §4 权限集成→插件直读文件系统(零 spawn,防EDR口径优先) | plugin.js 零 spawn 属实(无 child_process);直读 fs 属实;§4 确未做,折衷如实描述了取舍 | **属实** |
| ⑤ | D-1 grilling/discernment-nudge→fetch-skills 指引(上游MIT,用户自行摘取) | fetch-skills.sh:9-10 指引存在,版权边界理由与仓库 LICENSE 状态一致;注:该脚本 setup 不部署、装后用户不可见(仅仓库内可达)——描述未宣称部署,判属实(可达性弱) | **属实(弱交付)** |

---

## 7. 虚假/失实清单(纸面宣称 ≠ 实现)

1. **【虚假折衷】折衷③"update 校验"**(specs/README.md:37):webmap update 无校验代码且命令本身损坏(实测)。装后指纹的"记录"半句属实,"校验"半句无实现。
2. **【失实句】AGENT-CARD:100"审计写 30s"**(security-check.sh:100 生成):audit-init.sh/hook.sh 全文无 timeout。同句"路由自检 60s"属实(setup:951)。
3. **【宣称-实现错位】"subagent 路由自检"**(README specs 第一批 [x],setup:947-959):步骤存在,但跑的是主模型 `opencode run`,不触发 subagent,检不出路由失效——恰与下条复合成盲区。
4. **【运行时未生效】"子代理模型跟随主配置"**(根 README:30):patch 只打 config 副本(setup:633);runtime 生效副本(spec B:157 明示 ~/.cache/opencode/packages/...)实测 0 标记、原链 5 处仍在。本机即真实现场。
5. **【未披露缺口】D-2"默认装 29"**:AG 侧 17 项零部署零指引;按需 4 项零部署;D-1 选装 2 项零载体——均未列入五折衷(specs/README D 行"skill内容按版权边界手动摘取"仅可覆盖有指引的 mece/prd/grilling 等,覆盖不了"无指引亦无部署"的 AG 套件)。
6. **【数字无据】E-1"≤10ms/工具调用"与 E-2"每调用<1ms"**:无基准测量;hook 实测 ~20ms/事件(python3 spawn)。异步事件架构下未必阻塞工具调用,但数字宣称无实证且 <1ms 与实测差 20 倍。
7. **【轻度文档漂移】根 README:74-75 步骤表**:称"11. omo 模型路由补丁;12. 安全增强"——实际 patch 在步骤 8 内(setup:558-638),步骤 11 是 RTK。

---

## 8. 实测记录摘要(全部于 /tmp/opencode 隔离 HOME)

| 实验 | 结果 |
|---|---|
| node test-plugin.mjs | ✓ 2 组断言全过 |
| webmap init/search/install nodejs.org | ✓(2.7s/2 抓取,限速生效;sha 入 installed.list;信任级 yes) |
| webmap update | ✗ 整行作 domain,必失败(损坏复现) |
| webmap install python-docs(按名) | ✗ 只认域名 |
| scan_injection 单测 | ✓ 中英注入样文均拒、干净放行、grep 异常 fail-closed |
| robots awk 判定 | ✓ Disallow /llms.txt 命中 |
| audit-init init + 四通道事件 | ✓ event 四键写入 opencode.json |
| hook 脱敏 | ✓ Bearer/sk- 打码 |
| 熔断 | ✓ 5 连 deny→circuit-breaker alert |
| 成本告警 | ✓ 300 事件→cost-ceiling alert(events:300) |
| hook 延迟 | ~0.02s×5 次 |
| rotate | ✓ 11MB→.1 轮转(40MB 上界≤50MB) |
| opstate init/claim(不存在 id)/claim/done/reconcile | ✓ 全过(含假成功防线 exit1、双漂移修正) |
| self-portrait(埋 apiKey) | ✓ 0 泄漏、权限 600 |
| c-modules-setup --mem0 | ✓ 双通道目录+模板;mem0 CLI v0.2.13 真实存在 |
| security-check(埋明文 key) | ✓ 检出并 FAIL;无 skills/ 时独立运行死于 :85(exit2,AGENT-CARD 缺生成) |
| gen-compliance --region cn | ✓ 生成,provider 清单正确 |
| gen-permissions 计数 | ✓ bash 59=14d/6a/39al;headless JSON 合法 |
| runtime cache patch 标记 | ✗ 0 标记/原链 5 处(/root/.cache/opencode/packages/oh-my-openagent@latest/.../dist/index.js) |

---

## 9. 兑现率与终裁

### 真实兑现率

| 方向 | 实现 | 部分 | 未做 | 小计 |
|---|---|---|---|---|
| A | 12 | 3 | 3 | 18 |
| B | 11 | 5 | 3 | 19 |
| C | 6 | 2 | 0 | 8 |
| D | 4 | 1 | 5 | 10 |
| E | 12 | 12 | 1 | 25 |
| **合计** | **45** | **23** | **12** | **80** |

- **真实兑现率(严格,仅"实现"):45/80 = 56.2%**
- 宽口径(实现+部分):68/80 = 85.0%
- 已披露折衷覆盖的未做项(B-10、E-7、E-13、A-10、D-1)剔除后再算严格率:45/75 = 60.0%(D-2/D-1 选装/按需等未披露缺口仍计入分母)

### 虚假折衷清单

1. specs/README.md:37 折衷③后半句"**update 校验**"——无实现且 update 损坏(唯一判定"虚假"项)
2. (关联失实,非折衷)AGENT-CARD 模板"审计写 30s"句、路由自检名义与实效错位、README"子代理跟随"运行时未生效

### 终裁:REQUEST_CHANGES

阻断理由(按严重度):
1. **B-17**:omo 路由 patch 未打 runtime 生效副本——"子代理跟随主模型"这一根 README 一级卖点在运行时无效,且 B-16 自检验不出(双重失效);
2. **A-4+折衷③**:webmap update 功能损坏 + 折衷宣称不存在的"update 校验";
3. **D-3**:spec D-2 核心定案"默认装 29"落地不足半(SP 8/16 核心,AG 0/8),未列入折衷清单;
4. E-2 审计延迟数字宣称(<1ms)与实测(~20ms)无实证支撑,E-2"preset 锁版本"反向使用 @latest。

修复建议(最小集):webmap update 修 IFS 解析+实现 sha 比对或改折衷措辞;setup patch 补打 `~/.cache/opencode/packages/oh-my-openagent*/node_modules/oh-my-openagent/dist/index.js`(+备份);路由自检改为实际派发 librarian 微任务并核对模型;specs/README 补 AG 套件与按需 4 项的处置(装/指引/折衷三选一);AGENT-CARD 删"审计写 30s"或给 hook 加 timeout。

*——审计工具自身质量注记:审计链路(四通道/脱敏/熔断/成本告警/轮转)与 opstate/self-portrait 质量良好,前两轮评审(REVIEW.md/REVIEW-SPEC-UX.md)所列 U-1/W-1/W-2/O-1/O-2 等项经本次复核均已修复;security-check 独立运行 pipefail bug(:85)为新发现。*
