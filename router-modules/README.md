# sp-router — superpowers 路由模式(渐进披露移植)

## 问题

superpowers-zh 官方 OpenCode 插件两层急加载,实测 **9,158 token/对话起步税**(arm-sp 微任务基线,2026-08-30):

1. `config` 钩子把 20 个 skill 目录注册进 opencode 扫描路径 → 全部 name+description 进 system prompt
2. `messages.transform` 把 using-superpowers **全文**注进首条消息(`<EXTREMELY_IMPORTANT>` 块)

本插件替代急加载:**不注册**扫描路径(描述税归零);首条用户消息只注入路由块;agent 命中场景 → `Read <vault>/<name>/SKILL.md` 按需加载正文(等价 Claude Code 渐进披露)。

## 组件清单

| 文件 | 职责 |
|---|---|
| `plugin.js` | 注入插件(v2)。启动时动态 import `matcher.mjs` 并读 `index.yaml`(候选: 插件同目录 → vault);首条 user 消息经 `route()` 取 top-3 注入精简块;幂等标记 `<!-- sp-router:superpowers_router vN -->`,transform 前先剥离旧标记再路由 |
| `matcher.mjs` | 路由匹配器(零依赖 ESM)。`tokenize`(ASCII 词 + CJK 二字 bigram)/`parseIndex`(极简 YAML 子集解析,缺省容错)/`route`(撒种 → 一层传播 → ×weight 取 top-3) |
| `index.yaml` | 20 技能信号索引(与 superpowers-zh v7.9 目录同步): strong/weak 触发词、co-requires/supersedes/conflicts-with 关系、weight |
| `validate.mjs` | 索引校验器。8 项 ERROR 检查(YAML 可解析/name 唯一/path 非空/relations 引用闭合/`--vault` 时文件存在/weight 为正/tier·domain 枚举/disabled 不被引用)+ WARN 质量提示(无 weak 信号、strong<3、已停用) |
| `seed.mjs` | 种子生成器。扫 vault 找「vault 有、索引无」的技能 → frontmatter 分词全进 weak(待人批)+ weight 0.5 + `_seed: true`,幂等追加到 index.yaml 尾部,`--dry-run` 先看后写 |
| `matcher.test.mjs` | 24 条断言(node:test): 分词/撒种/三种传播边/weight/排序截断/parseIndex 容错/真实索引隐性用例 + B 轮新增的两级命中、黑名单、wrapper 回归。运行: `node --test matcher.test.mjs` |

## 行为矩阵

| 条件 | 注入形态 | 行为 |
|---|---|---|
| 默认(matcher+index 就绪,未设 `SP_ROUTER_V1`) | v2 精简块 | 强制扫描纪律两行 + top-3 候选(命中词 + vault 路径)+ 兜底行「以上不覆盖时 Read `<index.yaml 路径>` 全量匹配(N 技能)」 |
| `SP_ROUTER_V1=1` | v1 全量目录 | 同一段纪律两行 + 20 技能一行清单 + using-superpowers 兜底指路 |
| 加载失败(matcher import 失败/索引缺失或为空/route 抛错/无 top-3) | fail-open 回退 v1 | `console.error` 一行,不抛,会话照常,能力零丢失 |

撒种语义(B 轮修复后): name 整词命中 +3;信号两级命中——full(信号全部 token ∈ query)strong×2/weak×1,partial(命中 token≥2 且 ≥信号 token 数 60%)strong×1/weak×0.5;泛化词黑名单(GENERIC_WORDS 16 词)整串相等 ×0.25。传播: co-requires 种子分×0.5,supersedes 双活时转移 ×0.7 且被超者清零,conflicts-with 低分者清零;终分 = score×weight 取 top-3。

**部署现状(如实)**: `setup-opencode.sh` 只 sed 单文件 `plugin.js` → `~/.config/opencode/plugins/sp-router.ts`,**不随附 `matcher.mjs`/`index.yaml`**——setup 部署后 import 失败,实际运行 v1 全量目录形态。要激活 v2 top-3:

```bash
cp router-modules/sp-router/{matcher.mjs,index.yaml} ~/.config/opencode/plugins/
```

(B 轮实验的部署方式即「复刻 setup sed + 同目录补 matcher/index」。)

## 启用

```bash
SUPERPOWERS_ROUTER=1 ./setup-opencode.sh
```

默认不启用(保持官方急加载)。已装用户手动切换:

```bash
git clone --depth 1 https://github.com/jnMetaCode/superpowers-zh.git ~/.config/opencode/sp-vault/superpowers
# opencode.json: plugin 数组移除 superpowers@git+...
sed "s|__SP_VAULT__|$HOME/.config/opencode/sp-vault/superpowers/skills|g" \
  router-modules/sp-router/plugin.js > ~/.config/opencode/plugins/sp-router.ts
cp router-modules/sp-router/{matcher.mjs,index.yaml} ~/.config/opencode/plugins/   # v2 需要
```

vault 需在盘,更新 = `git pull`;克隆失败时插件无技能可读(装完重跑脚本补克隆)。

## 三轮实验终局

完整报告: `benchmarks/terminal-bench/sp-router-ab.md`(A/B 轮均预注册判据,独立执行)。

| 轮 | v2 形态 | 端到端准确率 | 检索层(实况注入) | 会话输入 token | 判定 |
|---|---|---|---|---|---|
| 初版 v1(2026-08-30) | —(全量目录) | — | — | 微任务基线 936 vs 官方 9,158(−90%) | 保留为默认部署形态 |
| A 轮(2026-09-06) | 首版撒种: 任一 token 重叠即整条信号命中 | v2 9/10 vs v1 **10/10** | **0/10**(wrapper 元词污染 + 单 bigram 交叠引爆弱信号,十句注入候选几乎全同) | v2 均值 ~17.1k vs v1 ~7.8k(9/10 触发兜底 Read index.yaml,会话变两轮放大) | **FAIL**(v2 不优于 v1,计划就地停) |
| B 轮(2026-09-06) | 两级命中 + 黑名单整串×0.25 + transform 剥离标记 | **v2 10/10** vs v1 9/10 | **10/10**(9 句 top-1;兜底 Read 0/10) | v2 均值 11.4k vs v1 8.9k;中位数 v2 7,391 vs v1 7,832(v2 便宜 5.6%) | **FAIL**(判据②结构性不可达),永久停 |

- **检索修复被端到端证实**: A 轮诊断的两个根因(wrapper 元词污染、单 bigram 引爆)被 B 轮语义修复消除;v2 端到端首次超过 v1(#8 changelog/commit 规范句,v1 全量目录反而误路由到 brainstorming)。
- **判据②为何结构性不可达**: 预注册门槛「v2 逐句会话输入 < 0.6×v1」≈4.7k,而本轮实测无插件共享基座(系统提示+工具 schema)本身 ≈7.0k(opencode 1.18.29)——任何插件方案(含零开销)都过不了。按预注册规则不允许赛后改口径,如实 FAIL,无 C 轮;Wave 3(routing.jsonl 路由日志)/SkillOpt 夜审随终局搁置(见 `docs/design/specs/C-embodiment-phase2-routing.md` 状态注记)。
- **token 的真实口径**: 注入块本身 v1 ≈0.75k / v2 ≈0.3k(省约 60%);端到端因 v2 设计内行为(按纪律先 Read 候选 SKILL.md 正文再作答,实测 4/10 句触发、每句约 +9k)单句总量可能反超 v1 的全量目录。渐进披露是把目录税换成按需正文税,不是单向省。
- **方差**: 每句单次采样,v1 两轮分别 10/10、9/10(同句波动已有记录),±1 句级别的差异不作信号解读。

## 维护指南

- **补信号词**: 编辑 `index.yaml` 对应技能的 strong/weak 数组 → `node validate.mjs index.yaml`(ERROR 拦截,WARN 提示)→ 部署侧把 index.yaml 同步拷到 `~/.config/opencode/plugins/`。B 轮教训: 真实人话与触发词存在词汇空缺(如「高峰超时/间歇」对「时好时坏」),补词是第一修复手段。
- **触发词不压缩原则**: 信号写用户会说的原话(「改完了」「时好时坏」「想做一个」),不做同义归并成抽象词——泛化词(「怎么做」「工具」「文档」)会跨技能引爆,黑名单只兜整串,兜不住含泛化词的长信号;补词宁多具体短语,不补抽象词。
- **上游新增技能**: `node seed.mjs <vault绝对路径> index.yaml`——幂等(已存在按 name/path 跳过),种子全进 weak 待人批,strong 留空;`--dry-run` 先看后写。批完跑 validate。
- **CATALOG 同步**: `plugin.js` 内 CATALOG 是 v1 清单快照(20 技能一行时机),上游演进后需重新生成(见 plugin.js 头部注释);v2 侧对应维护 index.yaml + seed。
- **测试**: 改 matcher/索引后跑 `node --test matcher.test.mjs`(24 条,B 轮后全绿)。

## 已知问题

- **泛化词长尾**: 黑名单(GENERIC_WORDS 16 词)只整串匹配,含泛化词的长信号不降权;B 轮实况 top-3 中 writing-skills 仍稳定在场(SKILL.md 字面命中 ~3.5 分),靠期望技能更高分压住,未再垄断——「怎么做」类表达的长尾污染窗口仍在,靠补信号词收窄。
- **单 bigram 交叠的残余面**: partial 档要求命中 token≥2 且 ≥60%,单 bigram 交叠已不命中;但 2-bigram 巧合交叠在极端短句上仍可能误撒种(A 轮 #4「文档」、#9「检查一下」型病理的弱化版)。
- **上游竞态**: `opencode run` 短命服务器存在插件加载竞态——同配置随机出现「插件生效/不生效」双峰。交互式 TUI(常驻进程)不受影响;基准与无头批量任务需多轮取样(A/B 两轮 23+ 次运行未复现)。

## OpenCode 本地插件加载规则(踩坑实录,2026-08-30)

| 方式 | 结果 |
|---|---|
| `plugins/` 顶层 `.ts`(import 语法) | ✓ 加载(rtk.ts 同款,TS 转译无视 package.json type) |
| `plugins/` 顶层 `.js`(ESM import) | ✗ 静默失败(最近 package.json 无 type:module 按 CJS 解析) |
| `plugins/` 顶层 `.mjs` | ✗✗ **毒丸**:整个插件管线崩,连 npm 插件都不加载 |
| plugin 数组放文件路径(相对/绝对) | ✗ 数组只认 npm 包,文件路径被忽略 |
| `plugins/子目录/plugin.js` | ✗ 不发现(只扫顶层) |

## 安全注意

vault 里的 SKILL.md 是第三方内容: 读取走 Read 工具(受权限系统管辖), 不自动执行其中脚本; 与 webmap 的 S3 注入隔离原则一致。`index.yaml` 兜底行给出的也是 vault 内路径,不含任何联网动作。
