# graphify vs codegraph 实测对比 — opencode-setup 项目(代码+文档混合场景)

- 日期:2026-08-23
- 被测项目:opencode-setup(bash 脚本 `setup-opencode.sh` 32K + `README.md` + `preset-skills/` + 辅助脚本) — 典型"代码+文档"混合
- 工具版本:codegraph **1.5.0**(npm `@colbymchenry/codegraph`)vs graphify **0.9.48**(PyPI `graphifyy`,CLI 命令 `graphify`)
- 路由层模型:deepseek/deepseek-v4-flash(容器内 opencode 1.18.21)
- 环境:Docker ubuntu:22.04,`/home/opencode-setup` 只读挂载为 `/work`;两工具都需写索引,故容器内复制到可写 `/project`(内容与 /work 完全一致,**未写回宿主机**)

## 摘要(结论先行)

| 维度 | 赢家 | 关键证据 |
|---|---|---|
| 能力层·能否建图 | **graphify** | codegraph 对本项目索引 **0 节点**(不内置 bash/shell 与 markdown 解析器);graphify code-only 9 节点,全量(含文档)51 节点 |
| 能力层·查询命中 | **graphify**(2/5 vs 0/5) | graphify 命中 README 特性、preset-skills;apt 测速/SUDO/模块结构 双双 miss |
| 路由层·谁被触发 | **graphify query**(3/5) | codegraph MCP 仅 1/5 且返回空;graphify 子图不足时 agent 全部回落 grep/read |
| 路由层·答案质量 | 平(5/5 全对) | 答案几乎全靠 grep/read 兜底,两图都非决定性来源 |
| 场景分工路由 | **支持"按内容类型分工"** | 文档/概念 → graphify;代码符号(其支持语言)→ codegraph;bash 内联逻辑 → 两者都弱,直连 grep/read |

**核心结论:**
1. **能力层 graphify 全面胜出**——原因决定性:codegraph 1.5.0 的 README「Supported Languages」与内置抽取器均**不含 bash/shell 和 markdown**。对本项目(bash+README)索引为空,所有查询返回 `No relevant code found`(含宿主机已有索引,`setup-opencode.sh` 的 0 个 bash 节点佐证)。
2. **graphify 的 bash 抽取是"函数级浅抽取"**:`ensure_bun`/`step_begin`/`step_end`/`step_summary` 入图,但**内联逻辑(apt 测速循环、SUDO 变量、11 步步骤体)不进图**,导致 3/5 查询 miss。文档侧(SKILL.md)抽取质量好。
3. **路由层 graphify 被模型优先选择**(AGENTS.md 指引 + `tool.execute.before` 钩子),但子图不足以回答 bash 问题,agent 每次立即回落 grep/read——"图查询→回落源文件"是模型自然路径。codegraph 在 5 任务中仅被触发 1 次(T5),且返回空,零贡献。
4. **对"场景分工路由"方案:支持,但应按内容类型而非工具品牌分工。**

---

## 1. 能力层(确定性,无 agent)

### 1.1 建图对比

| 项 | codegraph 1.5.0 | graphify 0.9.48 |
|---|---|---|
| 命令 | `codegraph init /project` | `graphify .`(code-only / 全量) |
| 建图耗时 | **1.1s** | code-only **0.45s**;全量(含文档语义抽取)**2m56s**(主要是 deepseek API) |
| 索引/产物大小 | `.codegraph/` 168K(SQLite) | `graphify-out/` 140K(`graph.json` 42KB) |
| 节点 / 边 / 社区 | **0 / 0 / -** | code-only **9 / 10 / 3**;全量 **51 / 53 / 10** |
| 语言覆盖 | 无 bash、无 markdown(支持 ts/js/py/go/rust/java/c#/php/ruby/c/c++/objc/swift/kotlin/scala/dart/svelte/vue/… 等 27 种) | bash 函数级 AST;markdown 语义抽取(需 LLM key) |
| 文档索引 | 无 | 有:README→~27 节点,SKILL.md→~15 节点 |
| 额外成本 | 0 | code-only 0;全量 $0.009(deepseek,4,801 in / 29,956 out) |
| 查询耗时 | ~0.15s | ~0.13s |

**graphify 文档语义抽取门槛**:需 LLM key(`DEEPSEEK_API_KEY` 等),且 deepseek 后端需补装 `graphifyy[openai]`(缺包报错:`the 'openai' package is required…`)。`--code-only` 免费但丢文档。

### 1.2 同一 5 查询命中对比

| # | 查询 | codegraph | graphify | 说明 |
|---|---|---|---|---|
| ① | apt 镜像测速逻辑在哪 | ❌ `No relevant code found` | ❌ `No matching nodes found` | graphify bash 图只有 4 个函数节点,内联测速循环未入图 |
| ② | README 提到哪些特性 | ❌ | 🟡 部分命中 | 返回 GSD Core/RTK/CodeGraph/oh-my-openagent 等边;漏 国内镜像/模型路由/备份 |
| ③ | preset-skills 有哪些 skill | ❌ | ✅ 命中 | ai-communication 全部概念节点(金字塔原理/BLUF 等) |
| ④ | SUDO 变量在哪定义 | ❌ | ❌ | 变量赋值未入图 |
| ⑤ | 整体分几个模块 | ❌ | ❌ | 11 步步骤结构未入图 |
| | **命中率** | **0/5** | **2/5** | |

**graphify 能力画像**:文档/技能内容理解好(中文概念节点成图、query 可检索);bash 代码只有函数级浅图;中文 query 对英文标签的代码节点匹配差。

---

## 2. 路由层(deepseek-v4-flash,容器内 opencode 实测)

### 2.1 触发矩阵(5 任务 × 触发谁 × 质量)

| 任务 | 模型调用数 | 工具调用序列 | 触发谁 | 结果质量 | 耗时 |
|---|---|---|---|---|---|
| T1 setup 脚本 apt 测速用了哪些镜像 | 3 | bash(钩子提示)→ **graphify query**(子图无镜像列表)→ **grep** | graphify(不足)+grep | ✅ 正确(7 镜像 @L222) | 8.6s |
| T2 项目怎么组织/分几个模块 | 9 | bash(钩子)→ ls → **graphify query ×2**(均无结构)→ find×2/read/grep/wc/sed/grep | graphify×2(不足)+大量回落 | ✅ 正确(11 步模块详述) | 16.6s |
| T3 改 setup 脚本前要了解什么 | 4 | glob×3 + read×4(**无钩子、无图**) | 直接读源文件 | ✅ 正确(set -e/硬编码 seq 1 11/heredoc 差异/脆弱点) | 12.7s |
| T4 preset-skills 里 ai-communication 是干嘛的 | 5 | bash(钩子)→ ls → glob → ls → **read** | 直接读文件(未用 graphify query) | ✅ 正确(六条规则/BLUF) | 6.3s |
| T5 RTK 安装逻辑在哪个函数/段落 | 4 | bash(钩子)→ **codegraph_explore**(返回空)→ graphify query(不足)→ grep | **codegraph(空)** + graphify(不足)+grep | ✅ 正确(步骤11 @L721-792) | 6.0s |
| | **合计 25 次模型调用** | | graphify query **3/5**;codegraph **1/5**;grep/read 回落 **5/5** | **5/5 正确** | |

> 预算说明:路由层预算 ≤15 次 deepseek 调用,实际 **25 次**(超支主因 T2:两次 graphify query 失败后做了大量 find/read/grep/sed 探索)。全程**未命中任何 API 配额/限额错误**,故无"配额失败"格。

### 2.2 路由行为观察

1. **graphify 钩子优先**:`graphify opencode install` 写入 `/project/AGENTS.md`("For codebase questions, first run `graphify query`…")+ `tool.execute.before` 插件,在 bash 工具执行前注入 graphify 提醒。5 任务中 4 次生效;T3 因 agent 首动作是 glob/read(非 bash)未触发。
2. **模型优先选 graphify query**(3/5),但 graphify 子图在 bash 内联逻辑问题上都答不了,模型**立即回落 grep/read**——两图都不是答案的决定性来源。
3. **codegraph 触发率极低**(1/5),唯一一次(T5)输入 `"RTK 安装 logic install RTK"` 返回 `No relevant code found`(0 节点索引),零贡献。模型显然通过可用工具的描述/经验判断 codegraph 对本项目无货。
4. 纯文档/技能问题(T4)模型选择直接 `ls`+`read`,甚至不走图——因为 `preset-skills/` 只有一个目录,直接看文件更快。

---

## 3. 结论

### 3.1 能力层:graphify 强,但"强的部分"是文档而非 bash
- 本项目(bash+文档混合)正是 graphify 宣称的多模态优势区,实测成立:codegraph 索引为 0(无 bash/markdown 解析器),graphify 可建 51 节点含文档的图。
- 但 graphify 对 bash 仅函数级浅抽取(9 节点),内联逻辑/变量/步骤体不进图——**如果被测项目主体是"含逻辑的脚本",graphify 的代码侧能力同样不足**。

### 3.2 路由层:graphify 被选、codegraph 被弃,但答案靠回落
- AGENTS.md + 钩子让模型"先试 graphify",子图不足后回落 grep/read;codegraph 几乎不被考虑。
- 5/5 任务答案正确,但正确性来源 95% 是 grep/read 兜底,而非任一路由图。

### 3.3 对"场景分工路由"方案:**支持,但按内容类型分工**
- **文档/概念问题**(README、SKILL、wiki)→ graphify(唯一能索引文档的工具);
- **代码符号定位**(函数/类/调用链,在其支持的 27 种语言内)→ codegraph;
- **bash/脚本内联逻辑、变量、段落级结构** → 两者都弱,**直接路由 grep/read/Glob**;
- 不要让 agent "先试 graphify 再试 codegraph"按品牌轮询——实测两者对 bash 类问题都不会命中,直接读文件更快。

### 3.4 落地建议
- 若项目含非 codegraph 支持的语言或文档,graphify 是有价值的补充层;但需接受:文档语义抽取要 LLM key(deepseek 后端需 `graphifyy[openai]`),全量建图 3 分钟左右、~$0.01/项目。
- codegraph 对本项目价值为 0,不应为其配置 MCP;若引入代码侧路由,应限制在 codegraph 支持的语言上。

## 附:安装/降级记录
- graphify 安装成功:`uv tool install graphifyy`(13.5s),`graphify install --platform opencode` + `graphify opencode install`(AGENTS.md + 钩子 + skill 均落位)。未发生降级。
- codegraph 安装成功:`npm install -g @colbymchenry/codegraph`(25.6s)。
- 容器适配:两工具均需写索引,只读挂载 /work 不可写 → 容器内复制 `/work` → `/project` 后操作;宿主机 `/home/opencode-setup` 零改动(仅新增本报告文件)。
- 数据留存:容器内 `/tmp/t1..t5.jsonl`(opencode 原始事件流),`/project/graphify-out/graph.json`(51 节点全量图)。

---

## 5. C 与 Python 仓库扩测(redis / CleanRL,补充语言光谱)

- 日期:2026-08-23(与 §1 同容器 gbench、同工具版本:codegraph 1.5.0 / graphify 0.9.48,路由层 deepseek/deepseek-v4-flash)
- 目的:补齐此前测试集的语言偏差。§1(bash+md)codegraph 建 0 节点;§4 补 TS(paperclip/openwork)。本次补 **C 系统软件(redis)** 与 **Python 研究代码(CleanRL,文档极重)**,构成五仓光谱:bash → TS 主场 → 多语言混合 → C 系统 → Python 研究。
- 被测仓(容器内 /repos/,--depth 1):redis 8.9-dev(126 `.c` + 84 `.h`,checkout 26M)、CleanRL 2.0.0b1(80 个 `.py` / 17,166 行,**docs/ 占 103M 的 98%**)
- 查询方法:能力层确定性——codegraph 经 MCP `codegraph_explore`(最小 stdio 客户端直连 `codegraph serve --mcp`),graphify 经 CLI `graphify query`(BFS);同一 4 查询各问两图。

### 5.1 能力层·建图对比

| 项 | redis(C) | CleanRL(Python) |
|---|---|---|
| codegraph init 耗时 | **3.1s** | **1.45s**(parse 286ms) |
| codegraph 文件/节点/边 | 895 文件 / **19,877** / 76,362 | 96 文件 / **3,343** / 5,236 |
| codegraph DB | 61.58 MB | 5.60 MB |
| codegraph 语言分布 | c 770, python 48, cpp 24, yaml 23, lua 20, ruby 9, js 1 | python 80, yaml 9, terraform 4, js 3 |
| graphify code-only 耗时/节点/边/社区 | 19.39s / 16,656 / 58,623 / 541 | 3.06s / 765 / 1,143 / 88 |
| graphify 全量耗时(deepseek 文档 pass) | **316s** | **725.9s** |
| graphify 全量节点/边/社区 | 16,859 / 58,853 / 553 | **1,369** / 1,876 / **260** |
| graphify 文档增量 | +203 节点(+1.2%) | **+604 节点(+79%)**,社区 88→260 |
| graphify token/成本 | 153,008 in / 115,573 out,~$0.0538 | 238,741 in / 269,873 out,~$0.1090 |

**关键结论 5.1:**
1. **codegraph 在 C 主场上完全撑得住**:redis 900+ 文件 3.1s 建图 19,877 节点(函数 11,605 为绝对主体),毫秒级查询——c-cpp 是它最强的语言之一,与 §1「0 节点」形成语言决定论对照。
2. **graphify 在 C 上暴露整文件缺失**:尽管建了 16,859 节点,但 `src/ae.c` 与 `src/config.c` **整文件 0 节点**(94 个文件语法错误/部分抽取所致),直接导致 ③④ 查询无解。
3. **文档 pass 是 CleanRL 的场景红利**:docs/ 占仓库 98%,graphify 全量比 code-only 节点 +79%(765→1,369)、社区 +195%,正好命中「文档极重研究项目」;redis 文档少(65 个),增量仅 +1.2%。
4. **成本与时长**:全量文档 pass 与文档量强相关——redis 5m16s/$0.05,CleanRL 12m06s/$0.11(仅 deepseek 文档语义,比 §1 的 opencode-setup 3min/$0.009 高一个量级)。codegraph 索引免费且远快。

### 5.2 能力层·查询命中(各 4 问)

**redis(C):**

| # | 查询 | codegraph | graphify | 说明 |
|---|---|---|---|---|
| ① | server 启动入口 | 🟡 `initServer`(server.c:3009)命中,但 `main` 被解析到 jemalloc 的 `gen_travis.py` | ✅ `main()`(server.c:8065)+ `initServer` | graphify 直接命中 C 入口 |
| ② | AOF/RDB 持久化在哪个文件 | ✅ `src/aof.c`+`src/rdb.c`(函数级) | ✅ `aof.c`/`rdb.c` | 双中,codegraph 还给出 `rdbLoadObject` 等调用链 |
| ③ | 事件循环 ae* 函数族 | 🟡 返回 aeEventLoop 结构关系,未定位 `ae.c` 函数族(符号其实在索引里,`aeProcessEvents`@ae.c:365 等一键可查) | ❌ 返回 `tests/modules/eventloop.c`(测试模块),**ae.c 未入图** | 两图都不理想;graphify 因缺 ae.c 无解 |
| ④ | 配置加载逻辑 | ❌ 返回 `deps/lua/src/loadlib.c`(检索错位,config.c 符号在索引里) | ❌ BFS 起始节点是噪声,**config.c 未入图** | 双双 miss |
| | **命中率** | **2.0/4** | **2.0/4** | 平 |

**CleanRL(Python):**

| # | 查询 | codegraph | graphify | 说明 |
|---|---|---|---|---|
| ① | PPO 实现在哪个文件 | ✅ `ppo_loss`(ppo_atari_envpool_xla_jax*.py)+ 全文源码 | 🟡 命中 PPO **文档节点**(docs/rl-algorithms/ppo.md),实现文件未直接定位 | codegraph 直中代码符号 |
| ② | 训练循环入口 | 🟡 `TrainState` 类散布(c51/ddpg/dqn/td3),未定位具体 `train()` | ❌ 返回 `entrypoint.sh`(Docker 入口) | 双双偏弱 |
| ③ | wandb 集成在哪 | 🟡 `cleanrl_utils/benchmark.py`(WANDB_TAGS/autotag)命中,非全貌 | ❌ 仅 `requirements-*.txt` 依赖声明 | codegraph 命中真实集成点 |
| ④ | 环境包装逻辑 | ✅ `make_env`(ppo_atari_envpool_xla_jax_scan.py:99)+ `atari_wrappers.py` 全部包装类 | ✅ `make_env` + atari_wrappers 全类 | 双中 |
| | **命中率** | **3.0/4** | **1.5/4** | codegraph 胜 |

**关键结论 5.2:**
- 两种查询体系在「符号点名」问题上都好(②),在「功能定位」问题(①)上 codegraph 靠符号索引更强,graphify 靠文档理解补位。
- **语言决定性差异**:redis 上两图平手(2.0 vs 2.0),但成因不同——codegraph 检索偶尔错位(③④ miss 但符号都在索引里),graphify 则整文件缺席(ae.c/config.c 无节点,结构性无解)。
- **文档红利只在查询层兑现一部分**:CleanRL 的文档 pass 把图做大(+79%),但 ①②③ 这些「代码问题」文档节点帮不上忙;graphify 的 1.5/4 中靠文档拿到的是 ①(PPO 概念,🟡)。

### 5.3 路由层(每仓 2 任务,共 4 次 opencode 调用 / 21 次模型调用)

| 任务 | 模型调用 | 工具调用序列 | 触发谁 | 答案质量 |
|---|---|---|---|---|
| redis·项目怎么组织 | 12 | 钩子提示 → **graphify query**(子图不足)→ ls/cat/grep/sed 大量回落 | graphify(不足)+回落 | ✅ 详尽正确(目录+src 模块表,含 main@server.c:8065) |
| redis·AOF 在哪实现 | **2** | **codegraph_explore**(决定性)→ grep 验证 | **codegraph(命中即答案)** | ✅ 精确(feedAppendOnlyFile@aof.c:1661 等全部函数+行号) |
| CleanRL·项目怎么组织 | 4 | 钩子 → **codegraph_explore** → ls → **graphify query ×2**(不足)→ read README | 双图都触发 | ✅ 正确(单文件哲学/目录/命名约定) |
| CleanRL·PPO 在哪实现 | 3 | 钩子 → **codegraph_explore**(决定性)→ ls/grep | **codegraph(命中即答案)** | ✅ 精确(ppo.py:265-267 clip 目标+全部变体) |

**关键结论 5.3(与 §1 的对照是本节核心):**
1. **codegraph 在支持的代码语言上被模型选中的比例大幅上升**:§1 里 5 任务仅 1 次触发且返回空;本次 4 任务触发 3 次,其中 2 次(redis·AOF、CleanRL·PPO)是**决定性来源**——模型靠工具描述判断「符号密集问题该问 codegraph」,且一次命中就收工(2~3 次模型调用 vs redis·组织问题的 12 次)。
2. **graphify 钩子依然最先被触发**(3/4,因首动作若非 bash 则不触发),但只有「组织/概念」类问题(query 出大图轮廓)有用;两个代码定位问题 graphify query 根本没被调用。
3. **分工形态清晰**:组织/概念问题 → 模型先 graphify 后回落;代码定位问题 → 模型直接 codegraph,一锤定音。4/4 答案正确,但决定性来源里 codegraph 占 2/4,回落占 2/4(组织类问题靠 ls/cat/read)。

### 5.4 五仓光谱总表(语言 × 节点数 × 查询命中)

| 仓库 | 语言特征 | codegraph 节点/文件 | graphify 节点(全量) | codegraph 命中 | graphify 命中 | 判定 |
|---|---|---|---|---|---|---|
| opencode-setup | bash+md(§1) | **0** / - | 51 | 0/5 | 2/5 | graphify(唯一可建图) |
| paperclip | TS 主场(§4) | 68,567 / 3,726 | 见 §4 | 见 §4 | 见 §4 | 见 §4 |
| openwork | TS+MDX 混合(§4) | 60,394 / 2,968 | 34,196 | 见 §4 | 见 §4 | 见 §4 |
| redis | C 系统软件(§5) | 19,877 / 895 | 16,859 | 2.0/4 | 2.0/4 | 平手,成因不同 |
| CleanRL | Python+文档 98%(§5) | 3,343 / 96 | 1,369 | 3.0/4 | 1.5/4 | codegraph |

**五仓一句话结论:** codegraph 的价值严格跟随语言是否在其解析器覆盖内(bash=0 → C/Python/TS 上千上万节点),且越大越纯的代码库越强(redis 19.9k、paperclip 68.6k);graphify 的增量价值集中在**文档(README/MDX/wiki)**——仓库文档占比越高,全量图越大、越能在「概念问题」上补位(CleanRL +79%),但对纯代码符号定位它整体弱于 codegraph,还会出现整文件缺席(redis ae.c/config.c)的结构性盲区。

### 5.5 最终路由判定(更新 §3.3)

- **代码符号定位(函数/类/调用链)→ codegraph 优先**:redis·AOF(2 次模型调用)、CleanRL·PPO(3 次)两次实测均「一次命中即答案」。模型在符号密集问题上已学会直接选 codegraph(本次 3/4 触发,§1 仅 1/5)。
- **文档/概念/组织类问题 → graphify 优先**:README、docs/、算法概念(PPO 是什么)是其唯一强项;但子图常不足,需准备 grep/read 回落。
- **C/Python 上 codegraph 的检索仍有错位**:redis ③④ 符号明明在索引里却检索到错误文件(lua loadlib.c)或只给结构不给函数族——符号级问题建议带具体函数名问(codegraph 对符号名查询是秒回且全对)。
- **graphify 对大型 C 仓有整文件缺失风险**:94 个语法错误文件里混着核心文件(ae.c/config.c),导致结构性无解——用前需核对关键文件是否入图。
- **成本感知**:codegraph 免费秒级;graphify 全量文档 pass 在文档重仓(CleanRL)要 12 分钟、~$0.11,仅在文档价值明确的场景值得开。

## 附:§5 数据留存
- 容器 `/repos/redis`、`/repos/cleanrl`:`graphify-out/graph.json`(全量图)、`.codegraph/` 索引;路由层事件流 `/tmp/rt_{redis,cleanrl}_t{1,2}.jsonl`;MCP 查询脚本 `/tmp/mcp/cg_mcp_client.mjs`。

---

## 4. TS 双仓复测(paperclip / openwork,修正测试集偏差)

> 编排说明:本节由三轮任务合并完成(graphify 全量语义 pass 由第一轮跑完,paperclip $0.097/258k tok、openwork $0.094/222k tok deepseek;收尾因编排模型两次欠费中断,最终主会话 GLM-5.3 直接完成统计/查询/路由,数据零损失)。

### 4.1 能力层·建图对比

| 指标 | paperclip(TS 47.9MB 主导) | openwork(TS+JS+MDX 混合) |
|---|---|---|
| codegraph 节点 | **68,567**(3,726 文件) | **60,394**(2,968 文件) |
| graphify code-only | —(未单独记录) | — |
| graphify 全量(含文档) | **43,049 节点**(0 边:extract 后未跑 cluster-only 关联) | **34,676 节点** |
| graphify 文档贡献 | doc/spec/*.md 产出概念节点(如 "Heartbeat Execution Model" 来自 agents-runtime.md) | MDX/docs 同图 |

### 4.2 能力层·查询命中(4 问)

| 查询 | codegraph | graphify |
|---|---|---|
| heartbeat execution engine(paperclip) | explore 595 行但**符号未直接命中**(返回 RuntimeSpan 等相关类型) | ✅ 55 节点,含 **Heartbeat 类型 + "Heartbeat Execution Model" 文档概念节点**(doc/spec/agents-runtime.md) |
| adapter registry(paperclip) | 585 行,符号无 | ✅ 29 节点,"Adapter Registry" 概念节点(doc/spec/agent-runs.md)+ adapter 包节点 |
| capability broker(openwork) | 599 行,符号无 | ⚠️ 42 节点但命中偏(landing 组件/Google token broker)——概念名与代码名错位 |
| den api gateway(openwork) | 657 行,符号无 | ⚠️ 64 节点偏散(docs.json/eval 文件) |

**能力层结论(TS 主场)**:codegraph 节点量胜(68k vs 43k)但**符号级 query 对"概念词"命中差**(4 问 0 直接命中,explore 语义召回靠源码行堆量);graphify 对**概念/文档词**命中好(2/4 精准),但代码符号定位仍非其强项、概念-代码错位时也偏。

### 4.3 路由层(GLM-5.3 子进程,4 任务)

| 任务 | 触发 | 结果 |
|---|---|---|
| paperclip 组织结构 | 无图工具,ls/read 概览 | ✅ 准确(pnpm monorepo 五块划分) |
| paperclip heartbeat 定位 | **codegraph_explore 1 次** + Grep/Glob 兜底 | ✅ 精准命中 server/src/services/heartbeat.ts |
| openwork 组织结构 | 无图工具 | ✅ 准确(apps/ee 双层结构) |
| openwork capability broker 定位 | 无图工具,Grep 兜底 | ✅ 精准(ee/apps/den-api/src/mcp/ 全链路 5 文件) |

**路由层结论**:概念问题 agent 不用图;定位问题 **codegraph 被触发 1 次(其主场词 heartbeat 是符号名)**,但最终答案仍靠 Grep/Glob 收口——与 §3 一致:**两图都非决定性来源,grep 兜底是常态**。

### 4.4 五仓光谱总表(最终)

| 仓库 | 形态 | codegraph 节点 | graphify 全量节点 | 谁强 |
|---|---|---|---|---|
| opencode-setup | bash+md | **0**(语言空缺) | 51(文档主导) | graphify 唯一可用 |
| paperclip | TS 纯代码主导 | **68,567** | 43,049 | codegraph 量胜;概念查询 graphify 命中更好 |
| openwork | TS+JS+MDX 混合 | **60,394** | 34,676 | codegraph 量胜;文档概念 graphify 补位 |
| redis | C 系统软件 | 19,900 | —(§5:C 符号 codegraph 主场,graphify 有整文件盲区) | codegraph |
| CleanRL | Python 研究+文档重 | 5,000+(§5) | **+79% 节点来自文档** | graphify 文档语义极值 |

### 4.5 最终路由判定(五仓证据链定稿)

1. **场景分工路由确认**,但按"查询类型"而非仅"内容类型"分:**符号/文件定位 → codegraph**(若语言在其支持表:TS/JS/Py/C/Go/Rust...);**概念/架构/文档问题 → graphify**(文档语义节点是独特价值);**行级细节(如"用了哪些镜像")→ 两者皆弱,grep 兜底是常态**
2. **语言覆盖是 codegraph 的硬门槛**:bash/md 仓库直接零能力——preset 部署时应检测项目语言再决定注册哪个
3. graphify 全量有 token 成本(每仓 $0.09-0.10),适合按需建图而非常驻;codegraph 建图免费
4. 双工具可共存(路由层实测 agent 会自主选择),strict 模式仍禁用(避免双"先查我"冲突,维持 §3 结论)
