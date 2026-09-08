# GSD 三臂对照实验:显式 GSD 指令对困难任务完成率的影响

> 2026-08-30/31 · 模型 zhipuai-coding-plan/glm-5.3 · opencode 1.18.25 · 全部数据实测

## 1. 问题与假设

- 前轮结论回顾:裸 / omo+sp / 全家桶三臂在 4 任务上成功率无差异,input token 差 25-34x(bx3 实测:a=719 / b=27,512 / c=42,757);困难任务历史(无 GSD,GLM-5.1,900-1000s 时限):cancel-async-tasks 时过时不过(R1-R2 合计约 3/4)、conda-env-conflict 时过时不过(约 3/4)、broken-networking 双败(环境性)。
- 已实测前提:模型从不**主动**调 gsd-help/progress,必须显式指令。
- 本实验问题:①任务指令显式要求 GSD 工作流,能否提升困难任务完成率?②三种 harness 下 GSD 效果是否不同?

## 2. 实验设计(执行情况)

### 2.1 三臂 HOME(全部注入 GSD:71 个 gsd-* skills + 35 个 gsd-* agents,来自 fresh-home 干净版)

| 臂 | 配置 | GSD 注入方式 |
|---|---|---|
| arm-a-gsd | 裸 opencode(schema+model) | cp agents/ + skills/ |
| arm-b-gsd | + plugin: oh-my-openagent@latest, superpowers-zh | 同上 |
| arm-c | 全家桶(cp -r bench/arm-c:权限全放行、审计 hook、无头模板、gsd+codegraph MCP) | 自带 |

三臂 auth.json 均为 /root 副本。统一 `timeout 600 opencode run --model zhipuai-coding-plan/glm-5.3`。

### 2.2 任务(2 个;broken-networking 按设计排除)

**排除原因**:broken-networking 在历史两轮四跑全败且归因宿主网络不稳——本机无法复现其容器网络故障语境,跑出来也只是重复环境噪声,无信息量。

- **cancel-async-tasks(hard)**:写 `/app/run.py` 的 `run_tasks`(有界并发 + SIGINT 后 cleanup 仍执行)。
- **conda-env-conflict-resolution(medium)**:修 `/app/project/environment.yml` 冲突并建 `datasci` 环境。

### 2.3 指令

原 instruction 前加固定英文前缀(照设计书原文):
`Use the GSD workflow for this task: check available GSD commands with the skill tool (name='gsd-help' or list gsd-* skills), plan before executing, and follow GSD's plan→execute→verify discipline. ` + 原 instruction 逐字。

### 2.4 与设计书的偏差(均为预实验暴露的结构性问题,诚实记录)

1. **workdir 由 `.../<task>/<arm>/ws` 改为 `/app`**。预实验(pilot,保留数据:arm-a HOME 库中 session `ses_facde2a94f`,120s,in=35,437)证明:照原设计 cd 到 ws 后,裸臂对任务必需的 `/app/run.py` 写入触发 `external_directory` 无头 auto-reject,3 次写入全拒、运行当场终止、零产出——三臂比较会退化为权限策略比较(arm-c 配了全放行)而非 GSD 比较。改用任务本身的规范工作目录 `/app`(原 Dockerfile WORKDIR),每次 run 前 `rm -rf /app` 重建,隔离性等价;三臂配置零改动。session 过滤条件相应由 directory=ws 改为 directory='/app'。
2. **本地补装 conda 基座**(miniconda 26.7.1 → /opt/conda,软链 /usr/local/bin/conda,TUNA 镜像):对齐原任务 Dockerfile(任务前提是"已有 base conda"),否则三臂比的是"谁会装 conda"。
3. **conda pkgs 缓存预热**(用 solution 同构的未锁版 yml 建临时环境后删除,缓存 18G,三臂共享同一冷启动起点):消除顺序跑 a→b→c 的缓存先后偏差。每次 conda run 前删除 datasci 环境并重置 /app/project;base 环境 158 包全程未变(已核)。

## 3. 结果矩阵(臂 × 任务)

判定标准:过 = 该任务 tests 全部通过。评分用官方 test 文件(cancel:pytest test_outputs.py 6 测;conda:pytest test_outputs.py 3 测,TEST_DIR 指向原 tests/,conda 环境真实可跑,**判分客观,非人工**)。

| 任务 | arm-a(裸+GSD) | arm-b(omo+sp+GSD) | arm-c(全家桶+GSD) |
|---|---|---|---|
| cancel-async-tasks | ❌ 5/6 | ❌ 5/6 | ❌ 5/6 |
| conda-env-conflict | ❌ 0/3 | ❌ 0/3 | ❌ 0/3 |
| **合计** | **0/2** | **0/2** | **0/2** |

- cancel 三臂败在**同一个测试** `test_tasks_cancel_above_max_concurrent`(排队超过 max_concurrent 时 SIGINT,2 个已启动任务的 cleanup 未执行:stdout 有 2×"Task started."、0×"Cleaned up.")——正是该任务 historically 时过时不过的那个边缘 case。其余 5 测(并发、限流、at/below max 取消)三臂全过。
- conda 三臂细节(人工对照 task.yaml 验收描述的过程判读,最终分仍以上表 pytest 为准):
  - **arm-a**:600s 全部耗在 GSD 流程上——gsd-help→gsd-debug 路由→写 `.planning/debug/conda-env-conflict.md`→委派 Gsd-Debug-Session-Manager 子代理空转,**environment.yml 逐字节未动、无环境**。零实质产出。
  - **arm-b**:流程最完整(诊断→`.planning/quick/` PLAN.md→改 yml→conda env create),solver 干跑驱动的修复(tensorflow 2.8.0→2.9.1 对齐 pytorch 1.12+cudatoolkit 11.2),但**保留了 numpy=1.22.0+scipy=1.9.0 与 cudatoolkit=11.2+pytorch=1.12.0**——solver 可解 ≠ 隐藏验收标准(测试正则明确要求这两对之一被改掉),且 600s 到点时 env create 尚未落盘。
  - **arm-c**:拿原始 yml 直接 create 撞真 solver 错误(libprotobuf 区间互斥),诊断中被杀,yml 未动。

## 4. GSD 实际调用验证(核心前提)

显式前缀**可靠触发**了 GSD:6/6 run 首个 skill 调用均为 `gsd-help`(每臂 HOME opencode.db,`part WHERE json_extract(data,'$.tool')='skill' AND data LIKE '%gsd%'`,按 session 过滤 directory='/app'):

| run | gsd skill 调用 | 调用名 | gsd MCP 工具调用 |
|---|---|---|---|
| cancel/a | 2 | gsd-help, gsd-fast | 0 |
| cancel/b | 3 | gsd-help, gsd-quick, programming | 0 |
| cancel/c | 2 | gsd-help, gsd-fast | 0 |
| conda/a(主) | 2 | gsd-help, gsd-debug | 0 |
| conda/a(子代理会话) | 0 | —(Gsd-Debug-Session-Manager,25 次工具) | 0 |
| conda/b | 2 | gsd-help, gsd-quick | 0 |
| conda/c | 2 | gsd-help, gsd-quick | 0 |

值得注意:**gsd MCP 工具调用全程为 0,连已配 gsd MCP server 的 arm-c 也是**——GSD 在本实验里完全以"skills 即提示词"方式生效(读 skill markdown→照其纪律行事),没有走 MCP 后端。GSD 行为痕迹:b/cancel 产出 `.planning/quick/` 的 PLAN/SUMMARY + STATE 行 + 4 个 git 原子提交;a/conda 产出 debug 会话文件并派子代理;b/conda 产出 PLAN.md。

## 5. token / 耗时 / 工具数(opencode.db session 级汇总)

| run | 墙钟 | input tok | output tok | 工具调用 | 备注 |
|---|---|---|---|---|---|
| cancel/a | 600s(超时†) | 48,988 | 2,869 | 21 | 产物已写出,超时发生在自验循环 |
| cancel/b | 587s | 103,865 | 6,711 | 29 | 最贵 |
| cancel/c | 579s | 61,535 | 3,860 | 16 | |
| conda/a | 600s(超时) | 57,096(主 23,021+子代理 34,075) | 7,626 | 14+25 | 子代理吞掉大头 |
| conda/b | 600s(超时) | 58,232 | 3,479 | 25 | 死在 env create |
| conda/c | 600s(超时) | 68,433 | 2,700 | 14 | 死在诊断 |
| (pilot)cancel/a@ws | 120s | 35,437 | — | — | 权限混杂证据,保留 |

†conda 三臂全部 600s 超时被杀。cost 均 0.0000(plan 订阅,同前轮)。

## 6. 与前轮(无 GSD)对比

- **完成率**:前轮无 GSD 困难任务历史(GLM-5.1,900-1000s)cancel≈3/4、conda≈3/4;本轮带 GSD(GLM-5.3,600s)**0/6**。但存在三个混杂:模型代次不同、时限压缩 33-40%(conda 三臂全是"超时被杀"而非"做完了但错",arm-b 死时 env create 还在跑——原任务给 1000s)、单样本方差(cancel 本身时过时不过)。**不能断言 GSD 降完成率,但可以断言:没有任何证据支持 GSD 提升完成率。**
- **token**:前轮 3 臂差 25-34x 的格局被 GSD 前缀**抹平**:裸臂一旦真的执行 GSD 流程,token 即进入重臂量级(cancel:a 49k vs b 104k vs c 62k,比值 1 : 2.1 : 1.3;前轮 bx3 为 1 : 38 : 59)。GSD 的计划-验证纪律是主要成本来源,不是插件装载本身。
- **触发方式**:前轮"模型从不主动调 GSD"成立;本轮证明**显式一句前缀即 100% 触发**(6/6),且三臂触发行为高度一致(help→quick/fast/debug 路由)。

## 7. 过程观察(定性)

1. cancel 三臂各自写了不同设计的实现(gather+CancelledError / drain-with-return_exceptions / 文档化传播语义),却败在同一测试——GSD 的 plan→verify 纪律没有转化出 asyncio 取消语义的领域洞察,三臂的 verify 自测也都没覆盖"排队任务未启动时 SIGINT"这个隐藏 case(测试不可见)。
2. GSD 在**硬时限**下有可见的反噬风险:arm-a conda 把全部预算花在流程编排(debug 会话初始化+子代理委派)上,实质动作一个没做;而走 gsd-quick/fast 轻路由的臂至少完成了改 yml/写代码。GSD 自身的任务分级路由(quick/fast vs debug)在裸臂上选了最重的 debug 路径。
3. arm-b conda 的失败模式最有信息量:**"solver 可解"与"隐藏验收正则"错位**——它用 solver 干跑证据支撑了一个不满足测试断言的 yml。GSD 流程让它更严谨,但严谨的方向对着可解性而非验收标准。
4. 权限混杂(pilot)本身是个 harness 级发现:裸/omo 臂无头模式下对 cwd 外写入 auto-reject,一次拒绝即终止运行且模型不恢复——做跨目录任务的基准必须显式处理(改 workdir 或配 external_directory)。

## 8. 诚实结论

1. **GSD 显式指令 100% 触发(6/6),但 0/6 完成,没有任何完成率提升的证据**;三臂之间也无差异(完成率全 0,cancel 连失败测试都相同)。
2. **"哪种 harness 下 GSD 更有效"在本轮无解**:三臂 GSD 路径(skills-only、无 MCP)与结果完全同质。唯一臂间差是 token 与流程产物(b 产出最全:PLAN/SUMMARY/git 提交)。
3. **GSD 的真实效果是"流程合规"而非"解题增强"**:它可靠地产出计划/验证/提交物,并显著推高 token(裸臂被拉到重臂量级);对超时敏感的任务还引入流程空转风险(单侧样本:a/conda)。
4. **单样本方差警告**:每格 n=1,cancel 历史本身翻转不定(R1❌→R2✅);本轮 0/6 相对历史 ~3/4 的落差混着模型代次与 600s 压缩两个因子,任何归因都只是假设。要下 GSD 无效的强结论,需同配置同任务 N≥5 重复采样。
5. 可复用教训:显式前缀是激活 GSD 的可靠开关;跑这类基准须 workdir=任务目录(或配 external_directory)、conda 类任务须统一 pkgs 缓存起点与时限(≥原任务 1000s 才公平)。

## 附:数据出处

- 运行日志:`/tmp/opencode/gsdbench/<task>/<arm>/out.log`;分数:`.../<arm>/score.log`;产物快照:`run.py.artifact` / `environment.yml.artifact`;起止 epoch:`t0/t1.epoch`。
- GSD/token 查询:各臂 `~/.local/share/opencode/opencode.db`,`session.directory='/app'` 过滤(pilot/warmup 会话以 directory 区分)。
- 指令原文:`/tmp/opencode/gsdbench/instr-cancel-async.txt` / `instr-conda.txt`。
- 前轮数据:`/home/opencode-setup/benchmarks/terminal-bench/hard-tasks-round2.md`、`/tmp/opencode/bench/results.md`(bx3 行)。
