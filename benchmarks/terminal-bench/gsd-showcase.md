# GSD 主场实验:多阶段项目型任务上,主动调用 / 环境态引导 / 无 GSD 三条件对照

> 2026-09-01(00:44-01:39 UTC)· 模型 zhipuai-coding-plan/glm-5.3 · opencode 1.18.25 · Docker ubuntu:24.04 · 全部数据实测
> 前轮:gsd-3arm.md(客场,0/6)、nogsd-3arm.md(去 GSD,2/9)。本轮为第三段:GSD 主场。

## 1. 问题与重做理由

- 前两轮用的是**一次性技术难题**(cancel-async 的 asyncio 取消边缘 case、conda 修环境),对 GSD 不利——多阶段计划纪律在"单发谜题"上没有发挥空间,且 600s 硬时限让流程开销直接挤占执行预算(两轮主结论之一)。
- 本轮换 **GSD 的设计场景**:多阶段项目型任务(从零建包:解析器→CLI→测试→文档→原子提交;遗留 C++ 库现代化:修构建→写转换器→转换全部模型→对格式规约),时限放宽到 900s,环境换 Docker 真容器。
- 核心问题:**三条件的完成质量是否有差异?**其中 C2 直接检验 Phase2 路由 spec(C-embodiment-phase2-routing.md §2.2)的状态注入假设——"GSD 项目的会话开始时模型看状态走流程"。本轮 C2 用的是该假设的**弱化版**:状态只作为文件存在于 repo(.planning/ 可见),没有 env 块注入。判决问题:状态文件可见时,模型会不会自然接手 GSD 工作流?

## 2. 实验设计

### 2.1 Docker 环境(全部真实执行)

- `docker run -d --name gsd-showcase ubuntu:24.04 sleep infinity`;容器内 apt 安装 curl/git/python3/pip/unzip + 任务所需构建链(build-essential、cmake 3.28.3、clang 系列、ninja-build、dos2unix,对齐 t2 官方 Dockerfile)+ python3.12-venv;系统级 pytest 8.4.1(同时充当 agent 可用的预装 pytest)。
- **偏差(容器网络)**:bun.sh 与 github.com 从容器内 TLS 握手失败(bun.sh SSL_ERROR_SYSCALL、github gnutls_handshake 错误),但 npm 源与 ubuntu 主仓可达。处置:bun 二进制与 opencode-ai 全局包(opencode 1.18.25,与前两轮同版本)从宿主 docker cp 进容器——功能等效,不影响单变量设计。apt security 源一次瞬时 502,重试成功。
- **三条件 HOME** `/root/homes/{c1,c2,c3}`,各含 `opencode.json = {"$schema":"https://opencode.ai/config.json","model":"zhipuai-coding-plan/glm-5.3"}` + auth.json 副本。基座统一为裸 opencode(隔离 GSD 单变量)。
- **GSD 注入**:C1/C2 `docker cp fresh-home/.config/opencode/{agents,skills}`(35 agents + 72 skills,与 gsdbench 轮同法);另将 `gsd-core/` 拷到容器内**同绝对路径** `/tmp/opencode/fresh-home/.config/opencode/gsd-core`——skills 的 SKILL.md 内嵌 `@/tmp/opencode/fresh-home/...` 绝对引用,gsdbench 轮在宿主跑时这些引用可解析,拷到同路径保持容器内行为等价。C3 不注入。
- 容器级 `git config --system`(user.name/email/init.defaultBranch),三条件等同,消除 git 身份摩擦噪声。

### 2.2 三条件(唯一变量 = GSD 的在场方式)

| 条件 | 指令 | GSD skills | 环境预置 |
|---|---|---|---|
| C1 主动调用 | GSD 前缀 + 任务原文 | 有 | 无 |
| C2 环境态引导 | 任务原文(无任何 GSD 字样) | 有 | repo 内预置 `.planning/` 项目状态 |
| C3 无 GSD | 任务原文 | 无 | 无 |

- C1 前缀与 gsd-3arm.md 逐字相同(197B,从上轮指令文件程序化切出并冻结):`Use the GSD workflow for this task: check available GSD commands with the skill tool (name='gsd-help' or list gsd-* skills), plan before executing, and follow GSD's plan→execute→verify discipline. `
- **C2 的 .planning 构造依据**:gsd-new-project SKILL.md 的 "Creates" 清单 + gsd-core/templates/{project,roadmap,state,requirements,config} 模板,手工构造同构最小集:`PROJECT.md / REQUIREMENTS.md(REQ 编号) / ROADMAP.md(该任务 = Phase 1,状态 In progress,0/3 plans,含 3 条建议 plan) / STATE.md(frontmatter status:executing + Current Position:Ready to plan Phase 1) / config.json(模板默认值)`。C2 的 repo 同时 `git init` 并做 1 个种子提交(`chore: initialize GSD planning state`),模拟真实 GSD 项目(GSD 会提交 .planning);评分时 commit 数按"总提交 − 1 种子"计。

### 2.3 两任务

**任务 1(自定义,GSD 主场核心):logparse**。在 /app/repo 从零建 Python 包:解析 apache common / nginx combined / BSD syslog 三种日志,CLI `logparse PATH [--format F] [--top N] [--json]`(exit code 1/2、JSON 输出 schema、tie-break 规则全部在指令中钉死);要求 pytest 套件覆盖三格式+自动检测+强制格式+top 排序+CLI 子进程冒烟、README 含用法、git ≥3 个有意义的原子提交。指令全文 2899B 冻结于 `task1-logparse.txt`。
**隐藏评分测试先写先冻结**:`hidden-tests/test_hidden.py` 12 测(help 冒烟、三格式 JSON 解析、skipped 计数、nginx/apache 互斥自动检测、强制格式、top 排序+tie-break+min(N,distinct)、syslog 主机 top、缺文件 rc=1、坏格式 rc=2、import),sha256 冻结于 FROZEN.sha256,**跑完 6 个 run 后校验未变**;且已核验 6 个 run 的 parts 数据中零条引用 `/opt/hidden-tests`(评分时才 docker cp 进容器;匹配到的 `/tests/test_` 均为 agent 自己的 /app/repo/tests 文件)。

**任务 2(terminal-bench 最难多阶段)**:从 241 个原任务里按"difficulty=hard + 指令含多步骤/建产物"筛选。候选判读:add-benchmark-lm-eval-harness 为 **medium** 且需 7200s 预算 + 93k 行外部数据集克隆,不适 900s;adaptive-rejection-sampler 为 medium(R 语言单文件);**选定 3d-model-format-legacy(hard,45 官方测试)**:2007 年 win32 遗留 C++ 库(MdfLib)——①修到本机可构建(cmake)②写 .mdf→JSON 转换器 ③转换全部模型到 /app/converted_models ④严格遵守 JSON_FORMAT.md。原任务 max_agent_timeout 1200s / 估计时长 600s,本轮按统一设计用 900s(介于两者之间,报告如实记录)。环境按官方 Dockerfile 复刻:宿主 clone MdfLib@de40bee → dos2unix(宿主无 dos2unix,用 python 等价去 CR,6 文件)→ test_models 只留 bunbun/dragon → 删 .git → 容器内 /opt/task2-pristine,每 run 重置拷回 /app。

### 2.4 执行

- 每 run 前 `rm -rf /app` 按任务重建(C2 追加 .planning + git 种子提交);`docker exec -e HOME=/root/homes/<c> -w /app gsd-showcase timeout 900 /root/.bun/bin/opencode run --model zhipuai-coding-plan/glm-5.3 "$(cat /tmp/instr-<t>-<c>.txt)"`。
- 三条件 warmup 全过("reply OK",rc=0,确认插件/模型/auth 通)。
- 顺序:t1c1→t1c2→t1c3→t2c1→t2c2→t2c3,串行。每 run 记录 rc/墙钟/out.log/t0/t1 epoch,run 后立即 tar 快照 /app + git log,再评分。
- **执行事故(诚实记录)**:①首次 t1/c1 启动指令的 `$(cat)` 在宿主侧展开(容器内文件不存在),2s 即败,无 agent 运行、无计入;修正引号后重跑。②t2/c1 首次评分把 additional_test_models 路径写错(实际在 tests/ 子目录),官方测试因找不到 /tests/additional_test_models 而假败;修正评分脚本、清掉本次评分产生的 converted_models/temp 后重评——**重评仅读快照态,不影响 agent 产物**。

## 3. 结果矩阵

**全部 6 run 无一超时**(最长 768s < 900s),rc 全 0。cost 全 0.0000(plan 订阅)。

### 3.1 任务 1:logparse(隐藏 12 测 + 工程质量维度)

| 维度 | C1 主动 GSD | C2 环境态 | C3 无 GSD |
|---|---|---|---|
| 隐藏 pytest | **12/12** | **12/12** | **12/12** |
| CLI 冒烟(--help rc=0) | ✓ | ✓ | ✓ |
| README 存在 + 含用法 | ✓(70 行) | ✓(69 行) | ✓(62 行) |
| 自带测试数 | 34 | 30 | 36 |
| agent 提交数(≥3 要求) | **6** | 5(另 1 种子) | 5 |
| 提交 body 非空占比 | **4/6(67%)** | 0/5(0%) | 2/5(40%) |
| 墙钟 | 353s | **301s** | 313s |
| input tok | 50,626 | 35,210 | **23,122** |
| output tok | 13,667 | **7,231** | 7,482 |
| 工具调用 | 43 | 22 | 25 |
| GSD skill 调用 | **2**(gsd-help, gsd-quick) | **0** | 0 |
| GSD 流程产物 | `.planning/quick/20260901-logparse/{PLAN,SUMMARY,VERIFICATION}.md` + STATE.md 更新 + 2 个 planning 提交 | .planning 原封未动 | — |

### 3.2 任务 2:3d-model-format-legacy(官方 45 测)

| 维度 | C1 主动 GSD | C2 环境态 | C3 无 GSD |
|---|---|---|---|
| test_cmake.py(构建/运行/字节一致) | **6/6** | **6/6** | **6/6** |
| test_outputs.py(39 产物断言) | **39/39** | **39/39** | **39/39** |
| **合计** | **45/45** | **45/45** | **45/45** |
| 墙钟 | **602s** | 740s | 768s |
| input tok | 73,795 | 80,567 | **56,360** |
| output tok | 20,313 | 21,662 | **18,691** |
| 工具调用 | 40 | 62 | 50 |
| GSD skill 调用 | **1**(gsd-help) | **0** | 0 |
| GSD 流程产物 | `/app/.planning/PLAN.md`(自拟轻量版) | .planning 原封未动 | — |

(三条件 converted_models 的 JSON 字节数不同——c1 152K/342K、c2 154K/344K、c3 271K/654K——是浮点序列化精度差异,字节一致性测试各自通过,不影响判分。)

## 4. C2 的 GSD 自发调用率(Phase2 假设的判决数据,单列)

**C2 两 run 的 gsd-* skill 调用数 = 0/2。**且不是"没看见"——parts 数据显示两个 agent 都明确注意到了 .planning:

- **t1/c2**(3 条 parts 涉及 .planning):`ls`/`git log` 列出了 .planning,reasoning 原文:*"The repo already has a git repo with one commit and a .planning directory. The task says 'the directory is currently empty; create ev…"* ——发现指令与环境矛盾后,**按指令文本行事,把 .planning 当既存事实绕开**,全程零读取内容、零调用、结束时不更新 STATE/ROADMAP。
- **t2/c2**(3 条 parts):目录列表看到 `.planning/`,reasoning 原文:*"Also check .planning directory — **probably GSD stuff, ignore.**"* 结尾再次确认:*"the .planning directory — ignore."*(同 run 还有一句 "git: user didn't ask to commit. Don't commit.")——**主动识别、主动分类、主动忽略**。

**判决:状态文件可见 ≠ 状态进入决策。**模型把 .planning 归类为"别人的流程元数据",与当前指令无关即绕行;两个 run 的 .planning 五个种子文件逐字节未动。这直接支持 Phase2 §2.2 的机制选择:**文件可见性不足以引发自发接管,必须有更强的注入机制(env 块把当前位置注入 system prompt 层)——spec 里"GSD Fragment 每会话读 .planning 注入当前位置"的设计方向得到判决性支持,而非文件可见这种弱形式。**附带发现:t1/c2 展示了注入状态的边界条件——**注入的状态还不能与指令文本矛盾,矛盾时指令文本胜出**(本轮 t1 恰好因种子状态与"directory is currently empty"措辞冲突而多了一个混杂;t2 无此冲突,结论主要立在 t2/c2 上)。

对照组核验:**C1 前缀 2/2 触发**(t1:gsd-help→gsd-quick,完整走 quick-task 流程产出 PLAN/SUMMARY/VERIFICATION;t2:gsd-help 后 reasoning 判断重型工作流不适合"无 .planning 结构的单会话 greenfield 任务",自拟轻量 `/app/.planning/PLAN.md` 并自述遵循 plan→execute→verify);**C3 = 0/2 且 parts 中零 gsd 痕迹**,剥净验证通过。

## 5. 过程观察

1. **任务天花板现象**:主场 + 900s 下,三条件在两任务的**全部客观判分维度上完全同分**(12/12 与 45/45 ×3)。质量差异只出现在指令未钉死的软维度:提交信息质量(body 占比 67% vs 0% vs 40%,C1 最高)与流程产物(C1 独有 PLAN/SUMMARY/VERIFICATION + STATE 更新)。
2. **C1 的 GSD 效果形态与前两轮一致:流程合规而非解题增强**。它没有让任何判分维度变好(本来就满分),但可靠地多产出了计划/验证文档与更规范的提交信息;代价是 token(t1:50.6k vs C3 的 23.1k,约 2.2×)。t2 上 GSD 反而没带来 token 膨胀(73.8k < C2 的 80.6k)——C1 在 t2 只调了一次 gsd-help 就自我裁剪了流程深度,单样本不足以归因。
3. **900s 下无人接近时限**(最长 768s):前两轮"流程开销撞死线"的主败因在本轮坐标系里被移除,这也解释了为何本轮 GSD 无害——它有害的形态(挤占硬时限)需要时限压力才显形。
4. **t2/c2 的工具调用最多(62)却零 GSD**:它把预算花在更多次的构建/试错循环上。环境态存在时模型不是"更省"也不是"更流程化",只是**当它不存在**。
5. **隐藏测试先冻结的流程价值得到验证**:12 测对三条件完全公平(同一 sha256),且事后核验无 run 窥见测试;评分全记录在 score.log。
6. t1 三条件都自发写了远超要求的测试(30-36 个)、README、原子提交——**当任务本身被写成多阶段交付物清单时,模型不需要 GSD 也会表现出计划纪律**(指令即计划)。GSD 的差异化空间被"写得足够好的任务指令"压缩了。

## 6. 三轮全景(客场 → 去 GSD → 主场)

| 轮 | 场景 | 时限 | GSD | 结果 |
|---|---|---|---|---|
| gsd-3arm | 客场:单发技术难题 ×2,三 harness | 600s | 显式前缀,6/6 触发 | **0/6** 全过;cancel 三臂败在同一隐藏 case;conda 三臂全超时零产出 |
| nogsd-3arm | 同上,去 GSD,三 harness | 600s | 无 | **2/9** 全过(conda/a 386s 教科书式、cancel/c 6/6);Fisher p=0.49 vs 0/6 |
| **本轮(主场)** | 多阶段项目型 ×2(Docker 真环境),裸基座三条件 | **900s** | C1 显式 2/2 触发 / C2 环境态 0/2 / C3 无 | **6/6 全过(三条件同分)**;差异仅在流程产物与提交质量 |

三轮合并的结论链:
1. **完成率维度**:GSD 在三种在场方式下都**没有**提升完成率的证据(客场 0/6 是最低分;主场三条件同分)。主场同分的解释不是"GSD 无用"而是"任务-时限坐标系里模型本身够得着天花板"——GSD 的价值空间只剩流程质量,而流程质量在指令写得足够好时也可被裸模型达到。
2. **流程质量维度**:GSD 显式调用**稳定地**产出计划/验证/状态文档与更规范的提交(body 占比 67%),token 代价约 0-2.2× 不定。这是三轮中 GSD 唯一可复现的正效应。
3. **激活机制维度(对 Phase2 最重要)**:三轮一致——**模型从不自发调 GSD**(客场 5 次零、本轮 C2 环境态 0/2);**显式一句前缀 100% 触发**(客场 6/6、本轮 C1 2/2);**纯文件可见 0%**(本轮 C2 判决)。Phase2 的菜单压缩+env 块状态注入设计同时回应了这两端:菜单不进 system prompt(省税),状态靠注入进 system prompt(补触发)。

## 7. 诚实结论

1. **单样本警告**:每格 n=1,2 任务 × 3 条件 = 6 run;以下均为方向性判断。
2. **主场三条件完成质量无差异**(12/12、45/45 全同分);GSD 主场没有兑现"多阶段任务上质量更优"的假设——至少在本模型、本两任务、900s 内,任务指令本身已携带足够的计划结构。
3. **C2 判决(Phase2 §2.2 假设的弱化版被证伪)**:.planning 状态文件可见时,模型看见、正确分类("GSD stuff")、然后忽略,0/2 自发调用、0 状态更新。**需要 env 块级的注入(进 system prompt),文件可见性不够;且注入内容须与指令文本一致,否则指令胜出。**
4. C1 前缀继续 100% 触发;C3 剥净验证通过(0 gsd 痕迹)。本轮实验操控的三臂边界干净。
5. 可复用教训:容器网络可能 selectively 阻断 bun.sh/github——预拷二进制是稳妥路径;隐藏测试冻结+事后 parts 核验是公平性保障;评分脚本自身的 bug(路径写错)会假败,重评只读快照即可修复;t2 官方 agent 时限 1200s vs 本轮 900s,若复现请对齐。

## 附:数据出处(宿主 /tmp/opencode/gsdshowcase/)

- 指令与冻结:`instr-t{1,2}-c{1,2,3}.txt`、`prefix-c1.txt`、`task1-logparse.txt`、`task2-3dmodel.txt`、`hidden-tests/test_hidden.py`、`FROZEN.sha256`(跑后校验 OK)
- 每 run:`runs/<task>/<cond>/{out.log,rc,t0/t1.epoch,reset.log,app-snapshot.tar,git-repo.log,git-repo-bodies.log,score.log}`;warmup:`warm/*.log`
- C2 种子状态:`planning-task{1,2}/.planning/`(五文件,构造依据见 §2.2)
- DB 指标:`db-metrics.json`(token/工具/skill 调用,提取脚本 `extract_db.py`,DB 副本 `dbdump/`);.planning 感知探针输出见本报告 §4(源:`dbdump/` parts 查询)
- 执行/评分脚本:`run_one.sh`、`score_one.sh`
- 对比基线:`gsd-3arm.md`、`nogsd-3arm.md`、`/home/opencode-setup/docs/design/specs/C-embodiment-phase2-routing.md` §2.2
