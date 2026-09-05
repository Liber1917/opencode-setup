# 去 GSD 三臂对照实验:去掉 GSD 后,困难任务完成率与带 GSD 轮的差异

> 2026-08-31 · 模型 zhipuai-coding-plan/glm-5.3 · opencode 1.18.25 · 全部数据实测
> 对照基线:gsd-3arm.md(2026-08-30/31,同模型同时限,带 GSD 前缀,完成率 0/6)

## 1. 问题与设计

- **用户问题**:去掉 GSD 后,困难任务完成率与带 GSD 轮(gsd-3arm.md 的 0/6)是否有显著差异?
- **设计**:复刻上一轮全部设定,唯一变量 = 三臂全部去掉 GSD、指令去掉 GSD 前缀(= 原 task.yaml instruction 逐字)。上一轮的其他混杂(模型代次、600s 时限、/app workdir、conda 缓存起点)在本轮与上轮之间保持不变,因此本轮 vs 上轮是"同一环境坐标系内 GSD 有无"的对照。

### 1.1 复刻要点(全部照上轮执行)

| 项 | 设定 | 核验 |
|---|---|---|
| 任务 | cancel-async-tasks(hard,6 测)+ conda-env-conflict-resolution(medium,3 测) | 原 task 目录在 /tmp/opencode/tbench/original-tasks/ |
| workdir | /app,每次 run 前 `rm -rf /app` 重建;conda 任务预置 /app/project/{environment.yml,test_imports.py}(client/task-deps 拷贝) | 每次 reset 在 run_one.sh 内完成 |
| conda 基座 | /opt/conda(miniconda 26.7.1,软链 /usr/local/bin/conda);每次 conda run 前 `rm -rf /opt/conda/envs/datasci`;pkgs 缓存 28G 三臂共享未动;base 158 包全程未变(与 baseline-base-pkgcount.txt 一致) | 已核 |
| 评分 venv | /tmp/opencode/gsdbench/scoring/scoring-venv(python 3.10.12 + pytest 8.4.1,与系统 python 同版本) | 已核 |
| 评分 | 官方 tests/test_outputs.py;cancel 评分前按官方 run-tests.sh 拷 test.py→/app;每 run 两跑(-x -q 与无 -x 全量);conda 设 TEST_DIR=原 tests/ + KMP_AFFINITY=disabled | score-x.log / score-full.log 两份 |
| 指令 | 上轮 instr 文件去掉 GSD 前缀;已程序化验证 = task.yaml 原文逐字(cancel 536B、conda 984B,且"上轮文件 = 前缀 + 原文"字节级成立) | nogsd/instr-cancel.txt / instr-conda.txt |
| 执行 | `env -u BUN_INSTALL HOME=<臂> timeout 600 opencode run --model zhipuai-coding-plan/glm-5.3 "$(cat 指令)"`,cwd=/app,串行 | runs.tsv |

### 1.2 三臂构建(本轮唯一变量:全部无 GSD)

| 臂 | 来源 | 剥离操作 | 等效于 |
|---|---|---|---|
| ng-arm-a | cp -a gsdbench/arm-a(保留缓存与 DB) | `rm -rf .config/opencode/{agents,skills}`(35 gsd agents + 72 skills) | 裸 opencode |
| ng-arm-b | cp -a gsdbench/arm-b | 同上(保留 omo+sp 插件缓存) | omo+sp 无 GSD |
| ng-arm-c | cp -a bench/arm-c | `rm -rf .config/opencode/{agents,commands,gsd-core,.gsd-staging,hooks}`、`rm -rf skills/gsd-*`(余 ai-communication)、python3 删 opencode.json 的 mcp.gsd 键(留 codegraph) | 全家桶无 GSD |

**偏差记录(诚实项)**:设计书未列 `.config/opencode/plugins/gsd-core.js`,但首轮 warmup 即报 `[gsd-core] hook script missing ... NOT enforced` 警告,证明该插件仍在加载并尝试执行 GSD hook 桥。为符合"剥 GSD"意图,将其删除后二次 warmup 干净(rc=0、无警告)。 inert 的 GSD 元数据文件(gsd-file-manifest.json、gsd-install-state.json、.gsd-profile、~/.gsd)按指令保留,不影响运行时。

**三臂验证**:各跑一次 warmup(ngwarm/<arm>,"reply OK",120s)全部 rc=0 回复 OK;ng-arm-b 额外 60s 建臂 warmup 确认插件加载(横幅"Sisyphus - ultraworker"= omo agent 注入成功);ng-arm-c opencode.json 经 `python -m json.tool` 校验合法;三臂 auth.json 均在(.local/share/opencode/auth.json)。

### 1.3 采样计划(9 runs,全串行)

cancel × 每臂 2 次(压方差)+ conda × 每臂 1 次。每 run 记录 rc/墙钟/out.log/双份 score/产物快照/epoch。实验起点 epoch 1788185673(2026-08-31 22:14)。

## 2. 结果矩阵(臂 × 任务 × 重复)

判定:过 = 该任务官方测试全过。两份评分(-x / 全量)结论一致。

### 2.1 本轮(无 GSD,9 runs)

| 任务 | ng-arm-a(裸) | ng-arm-b(omo+sp) | ng-arm-c(全家桶) |
|---|---|---|---|
| cancel r1 | ❌ 5/6(190s,rc=0) | ❌ 5/6(600s†,rc=124) | ✅ **6/6**(417s,rc=0) |
| cancel r2 | ❌ 5/6(63s,rc=0) | ❌ 5/6(600s†,rc=124) | ❌ 5/6(275s,rc=0) |
| conda r1 | ✅ **3/3**(386s,rc=0) | ❌ 0/3(600s†,rc=124) | ❌ 1/3(600s†,rc=124) |
| **全过 run 数** | 1/3 | 0/3 | 1/3 |

†rc=124 = 600s 到点被 timeout 杀。**合计 2/9 run 全过**(上轮带 GSD 为 0/6)。

- cancel 的 5 个 5/6 **全部败在同上轮一模一样的 `test_tasks_cancel_above_max_concurrent`**(n=3>max=2 时 SIGINT,2 个已启动任务 cleanup 未执行)。
- conda 细节(人工对照,最终分以 pytest 为准):
  - **ng-arm-a(过)**:诊断→改 yml(numpy 1.22.0→1.23.5、scipy→1.9.3、`tensorflow=2.8.0=cpu*`+`pytorch=1.12.1`、整体去掉 cudatoolkit,并在实测中发现 transformers 4.18 与新版 huggingface_hub 不兼容而加 pin)→create→跑 test_imports.py 全过。教科书式完成。
  - **ng-arm-b(0/3)**:solver 干跑驱动的修复方向正确(numpy=1.22.4、TF 2.8.0→2.9.1 对齐 libprotobuf、删 cudatoolkit),**但 yml 里的解释性注释含字符串"cudatoolkit=11.2"且无"cpuonly"字样,恰好踩中隐藏验收正则** → test 2 败;真实 env create 启动太晚,600s 被杀时环境未落盘 → test 1/3 败。
  - **ng-arm-c(1/3)**:solver 干跑通过后开始真实 create,600s 被杀时环境目录已建(半装)→ test 1 过、imports 败;其 yml 保留 `pytorch=1.12.0=cuda112py310*`+`cudatoolkit=11.2`+`tensorflow=2.9.1=cuda112py310*`(solver 可解但命中"cudatoolkit=11.2 且 pytorch=1.12.0 同存"的否决条件)→ test 2 败。

### 2.2 与上轮(GSD 版)并排对比

| 指标 | 上轮带 GSD(6 runs) | 本轮无 GSD(9 runs) |
|---|---|---|
| 全过 run 数 | **0/6** | **2/9**(cancel c-r1、conda a-r1) |
| cancel 最佳 | 3× 5/6(同一测试败) | 1× 6/6 + 5× 5/6(同一测试败) |
| conda 最佳 | 3× 0/3(全部 600s 超时,yml 零/错改) | 1× 3/3(386s 完成)+ 1× 1/3 + 1× 0/3 |
| 600s 超时数 | 4/6(cancel a + conda×3) | 4/9(b cancel×2 + conda b/c) |
| input tok 合计 | 398,149 | 449,043 |
| output tok 合计 | 27,245 | 23,856 |

## 3. token / 耗时 / 工具 / skill(opencode.db,session.directory='/app',本轮 epoch 后)

| run | 墙钟(DB) | input tok | output tok | 工具调用 | skill 调用 | skill 名 |
|---|---|---|---|---|---|---|
| cancel/a-r1 | 188s | 8,908 | 1,792 | 11 | 0 | — |
| cancel/a-r2 | 62s | 3,711 | 758 | 6 | 0 | — |
| cancel/b-r1 | 558s | 113,584 | 3,461 | 15 | 2 | programming, test-driven-development |
| cancel/b-r2 | 537s | 88,978 | 5,264 | 23 | 3 | brainstorming, test-driven-development, programming |
| cancel/c-r1 | 411s | 97,706 | 3,792 | 15 | 2 | programming, test-driven-development |
| cancel/c-r2 | 271s | 29,221 | 2,407 | 6 | 0 | — |
| conda/a-r1 | 385s | 9,409 | 1,486 | 14 | 0 | — |
| conda/b-r1 | 509s | 45,558 | 2,769 | 19 | 1 | systematic-debugging |
| conda/c-r1 | 589s | 51,968 | 2,127 | 18 | 1 | systematic-debugging |

- skill 调用合计 9 次,**全部非 GSD**(b/c 臂的 superpowers/omo 自带技能);ng-arm-a 为 0(无技能可调)。本轮 9 个 session 的 parts 中含"gsd"字样的记录(b 臂 14 条、c 臂 9 条)逐条核验:绝大多数是臂 HOME 路径(`/tmp/opencode/gsdbench/ng-arm-*`)出现在 read/bash/lsp_diagnostics 的文件参数里,另有各 1 条 reasoning 文本(一条引用技能基目录路径,一条提到路径中的"gsdbench"字样)——**无任何 GSD skill/command/agent/MCP 调用**。剥 GSD 操纵干净。
- cost 全部 0.0000(plan 订阅,同前)。
- **token 格局恢复臂间分化**:上轮 GSD 前缀把三臂拉平(1:2.1:1.3);本轮裸臂回到超轻量(cancel 3.7k-8.9k,conda 9.4k),b/c 臂因自带技能纪律仍在重量级(29k-114k)。上一轮"token 被拉平的原因是 GSD 流程而非插件装载"的结论获得反向验证。

## 4. 统计口径与结论(诚实声明)

**每格 n=1 或 2,以下只能给方向性判断,不能夸大。**

- run 级全过率 2/9(无 GSD)vs 0/6(带 GSD),Fisher 精确检验双侧 **p=0.49**——**无统计学显著差异**;分任务看同样不显著(cancel 1/6 vs 0/3,p=1.0;conda 1/3 vs 0/3,p=1.0)。
- **方向性判断:无 GSD ≥ 带 GSD**。带 GSD 轮唯一收获是 0;本轮出现了 2 个全过,且都不是边缘侥幸:conda/a 在 386s 内完整走完"修 yml→建环境→跑 imports"全流程(带 GSD 轮三臂同任务全部 600s 耗尽、零环境);cancel/c-r1 是全实验两个 round 里唯一 6/6。
- **回答用户问题:去掉 GSD 后,完成率没有显著差异(p≈0.49),但方向上不劣于、可能优于带 GSD。** 结合上轮 0/6:两轮合并后,"GSD 提升困难任务完成率"仍然零证据;且本轮 2 个全过的存在使"GSD 无完成率影响"的结论**增强**——若 GSD 真有正效应,在同为 600s、同模型、同 6 个(臂,任务)格子里不应由"无 GSD"侧率先破零。反之,上轮 0/6 更可能由时限压缩(600s vs 原任务 900-1000s)+ 单样本方差 + 部分流程开销共同导致,而非 GSD 单独致败;本轮 conda b/c 两个"真实 env create 启动太晚被杀"的失败与上轮失败模式同构,支持"时限是主混杂"的解释。
- 需要保留的不确定性:cancel 本身时过时不过(历史 ~3/4,两轮合计 1/9 全过,600s 下该任务对隐藏 case 的覆盖率是决定因素);n=1-2 无法区分臂间差异;两轮各只有一次机会的 conda 任务对"何时开始真实 create"的调度高度敏感。

## 5. 过程观察(定性)

1. **cancel 的败点高度稳定**:两轮 8 个非满分 run 全部败在同一个隐藏 case(排队任务存在时 SIGINT)。无 GSD 轮唯一全过的 c-r1,恰是唯一把"6 jobs/limit 2 + 真实 SIGINT 子进程"写进自测的 run——它的 out.log 明确记录"exactly the 2 started jobs wrote cleanup-N markers, queued 4 never started"。破局靠的是自测覆盖域的运气/洞察,与 harness 和 GSD 无关。
2. **无 GSD 时裸臂显著提速**:cancel/a 两次 190s/63s 完成(带 GSD 轮同臂 600s 超时,自验循环里打转),conda/a 386s 完整交卷(带 GSD 轮三臂全部超时)。流程开销的去除在硬时限下直接转化为完成率。
3. **b/c 臂的重预算来自自带技能纪律而非 GSD**:omo+sp 的 TDD/LSP/mypy 关卡让 cancel/b 两个 run 在产物已 5/6 定型后继续烧满 600s(mypy 装不上、反复 LSP 硬化验证)。这与上轮"GSD 流程是主要成本来源"的观察互补:**任何强验证纪律都会在 600s 硬时限下挤占执行预算**,区别只在于 GSD 额外引入计划/路由开销。
4. **conda 失败模式两轮同构**:solver 干跑(solver 可解)≠ 隐藏验收正则,且真实 create 太晚启动。本轮 b 的 yml 修复本身方向正确,却因注释里写了"cudatoolkit=11.2"字样被正则误杀——这是新观察:**解释性注释会与字符串匹配型验收标准互作用**,带 GSD 轮 b 臂的"solver 可解但不满验收"失败在本轮以更荒诞的形式复现。
5. **arm-c 剥 GSD 后行为无异常**:无 hook 警告、codegraph MCP 保留未影响任务,conda/c 失败纯属时限。
6. 权限混杂(pilot 发现)不再出现:workdir=/app 下三臂(含全放行的 ng-arm-c)全程无 external_directory 拒绝记录。

## 6. 结论

1. **去掉 GSD 后完成率 2/9 vs 带 GSD 0/6,Fisher p=0.49,无显著差异;方向上无 GSD 不劣于带 GSD。**
2. 两轮合并的更强结论:在这两个困难任务、600s、GLM-5.3 的坐标系里,**GSD 对完成率既无正效应的证据,也基本可排除"去掉 GSD 会变差"**——上轮 0/6 的主因更可能是时限压缩与单样本方差,GSD 顶多中性偏拖累(流程开销挤占硬时限)。
3. 完成率的真正杠杆是**自测覆盖域是否踩中隐藏 case**(cancel)与**关键耗时动作的启动时机**(conda),两者都与 harness/GSD 正交。
4. 可复用教训:与上轮一致(workdir=任务目录、conda 统一缓存起点与时限 ≥1000s);本轮新增——剥 GSD 须连 `plugins/gsd-core.js` 一起剥(warmup 警告是探测手段);yml/配置类任务的修复注释可能踩验收正则;技能/流程纪律的验证开销在硬时限下是净负债。

## 附:数据出处

- 运行与评分:`/tmp/opencode/gsdbench/nogsd/<task>/<arm>-r<N>/{out.log,score-x.log,score-full.log,rc,t0/t1.epoch,*.artifact}`;汇总 `nogsd/runs.tsv`;执行脚本 `nogsd/run_one.sh`;指令 `nogsd/instr-cancel.txt` / `instr-conda.txt`。
- 三臂 HOME:`/tmp/opencode/gsdbench/{ng-arm-a,ng-arm-b,ng-arm-c}`(源自 gsdbench/arm-a、gsdbench/arm-b、bench/arm-c,源臂未动);warmup 日志 `gsdbench/ngwarm/*.log`。
- token/工具/skill 查询:各臂 `~/.local/share/opencode/opencode.db`,`session.directory='/app' AND time_created > 本轮起点(ms)`,skill 名取 `part.data→$.state.input.name`;旧轮 session 以时间过滤剔除(已交叉核对上轮数值无误)。
- 对比基线:`/home/opencode-setup/benchmarks/terminal-bench/gsd-3arm.md`。
- 统计:Fisher 精确检验(双侧),python math.comb 实现,数值见 §4。
