# opencode-setup

一键配置 [OpenCode](https://opencode.ai) 环境，集成 oh-my-openagent、CodeGraph MCP 和完整的 Agent 生态（GSD 工作流等按需选装）。

```bash
# 国内网络优先走镜像（gh-proxy.com → ghfast.top → 官方直连 自动回退）
curl -fsSL "https://gh-proxy.com/https://raw.githubusercontent.com/Liber1917/opencode-setup/main/setup-opencode.sh" | bash
```

> ⚠ **管道安装与克隆安装的差异**：安全增强模块（步骤 12：权限红线/审计/AGENT-CARD/合规/webmap 等）**随仓库分发**，管道安装拿不到。需要完整安全增强请用下方克隆方式。

> **开发者**：仓库自带 `.opencode/skills/docker-test-setup` skill——修改脚本后用它跑 Docker 容器矩阵回归（22.04/24.04 全流程、断网降级、幂等）。在 OpenCode 中执行 `/docker-test-setup` 获取完整测试命令与断言清单。

或克隆后运行：

```bash
git clone https://github.com/Liber1917/opencode-setup.git
cd opencode-setup
./setup-opencode.sh
```

用 `sh` 运行也没问题——脚本检测到非 bash 环境会自动以 bash 重新执行。

## 特性

- **Bun 运行时** — 自动安装（npm 镜像优先 → npmmirror 二进制 → 官方脚本三级回退），检测损坏自愈，避免跨平台 PATH 问题
- **环节计时** — 每步结束显示耗时，结束时输出各环节耗时汇总表（含总耗时），定位安装瓶颈一目了然
- **npm 镜像加速** — 默认 npmmirror，国内网络下安装飞快，可用环境变量覆盖
- **oh-my-openagent** — 10 个 Agent + 8 个 Category 的模型路由
- **子代理模型显式路由** — oh-my-openagent.json 为全部 10 agent + 8 category 写显式 model（堵死内置回退链的 claude 路由 403；`OMO_MODEL=<provider/model>` 可换），另有 fallbackChain 补丁双保险
- **RTK 命令输出压缩** — 安装 [Rust Token Killer](https://github.com/rtk-ai/rtk) 并集成 OpenCode 插件，bash 命令输出进 LLM 前被智能压缩，节省 60-90% Token（零认证镜像源下载，国内网络友好）
- **apt 源自动测速** — 对 6 个国内镜像 + 官方源真实下载测速，自动切换最快源（官方最快则不动，已自定义则跳过）
- **node/pip 国内源** — node 优先走 npmmirror 二进制（失败回退 nodesource）；pip 自动 ensurepip 引导 + 中科大 PyPI 源
- **GSD Core 工作流（选装）** — 项目全生命周期管理；默认不装（实测零完成率收益、~4k tok/会话常驻成本），`INSTALL_GSD=1` 启用
- **DCP 上下文压缩（选装）** — `INSTALL_DCP=1`（AGPL-3.0 需双重知会确认）；长会话上下文锯齿式回落，实测末态 -82%、计费当量 -43%
- **MinerU 文档解析（选装）** — `INSTALL_MINERU=1` 本地档免费无限量（PDF/图片 → Markdown/JSON），选装即自动接线 mineru-local skill + Flash MCP（agent 即刻可调用）；轻量走 Flash MCP 免装
- **superpowers 路由模式（选装）** — `SUPERPOWERS_ROUTER=1` 渐进披露替代官方急加载（v1 全量目录 / v2 top-3 检索双形态）
- **记忆/自进化（选装）** — `INSTALL_CMODULES=1` 或菜单选 `5`：mem0 偏好记忆 + SkillOpt 夜间提炼双通道；提炼产物只落草稿区，人工批准才生效（无自动生效路径）
- **CodeGraph MCP** — 代码图索引工具（`codegraph_*` 工具族，项目内 `codegraph init` 后生效）
- **零假设** — 除 curl 和 git 外不依赖任何预装工具（node/bun 均自动安装）

## 安装效果

```
~/.config/opencode/
├── opencode.json           ←  MCP（codegraph，安装成功时自动注册）+ 插件配置（oh-my-openagent；路由模式下 superpowers 不进 plugin 数组）
├── oh-my-openagent.json    ←  Agent 模型路由
├── dcp.jsonc               ←  DCP 配置（INSTALL_DCP=1 时生成；阈值实测加速值，见文件内注释）
├── node_modules/           ←  oh-my-openagent（官方模式下另有 superpowers 插件）
├── plugins/                ←  rtk.ts（命令输出压缩）/ opencode-env.ts（步骤 12）/ sp-router.ts（SUPERPOWERS_ROUTER=1）
├── command/                ←  GSD Core 命令（INSTALL_GSD=1 时存在）
├── memory/                 ←  mem0 偏好记忆（INSTALL_CMODULES=1 时创建）
├── skill-drafts/           ←  SkillOpt 夜间提炼草稿区（INSTALL_CMODULES=1 时创建；人工批准后移入 skills/）
├── skills/                 ←  技能目录（步骤 12 部署 preset-skills）
├── sp-vault/               ←  superpowers-zh 克隆（SUPERPOWERS_ROUTER=1 时存在，更新 = git pull）
├── AGENT-CARD.md           ←  Agent 环境披露（步骤 12 生成）
├── compliance/             ←  合规文档 CN/EU（步骤 12 生成）
└── opencode-setup-modules/ ←  E 模块（权限红线/审计/自检/合规 + env-profile/self-portrait）

~/.claude/
└── settings.json           ←  Hooks 配置

~/.local/bin/               ←  webmap / opstate / heartbeat（步骤 12 部署；rtk 非 root 回退时也在此）
~/.npmrc                    ←  npm 镜像源（npmmirror）
~/.bunfig.toml              ←  Bun registry 镜像
~/.bashrc                   ←  Bun/npm 路径；INSTALL_MINERU=1 时追加 MINERU_MODEL_SOURCE=modelscope
```

## 使用方式

安装脚本按 12 步执行（`sh` 运行会在开始前自动切换 bash；交互终端上步骤 1 之后会弹出选装菜单，见下文「交互式选装菜单」）：

1. 检测已有配置（发现现存配置时可选备份后重生成，非交互默认保留现有配置）
2. 创建配置目录
3. 生成 opencode.json（有 python3 时校验 JSON，损坏即中止）/ oh-my-openagent.json / Claude settings
4. apt 源测速优化（6 国内镜像 + 官方测速，最快者自动切换，失败自动还原）
5. 检查前置依赖：unzip、node（npmmirror 二进制优先，回退 nodesource）+ 配置 npm/PyPI 镜像源
6. 安装 Bun 运行时（npm 镜像 → npmmirror 二进制 → 官方脚本三级回退）+ Bun registry 配置
7. 通过 Bun 安装 OpenCode
8. 安装 oh-my-openagent 插件 + omo 模型路由补丁（子代理跟随主配置，双副本补打）；`SUPERPOWERS_ROUTER=1` 时另行克隆 vault 并部署 sp-router 插件
9. GSD Core 工作流（默认跳过，`INSTALL_GSD=1` 选装）
10. 安装 CodeGraph CLI 并注册 MCP（绝对路径，安装失败自动跳过注册）
11. 安装 RTK（镜像链下载，集成 OpenCode 插件，自动关闭遥测）

    步骤 11 与 12 之间另有三个**不占步骤号**的选装段：DCP 上下文压缩（`INSTALL_DCP=1`，AGPL-3.0 安装前后双重知会 + 确认门，非交互需 `CONFIRM_AGPL=1`）、MinerU 文档解析（`INSTALL_MINERU=1`，Apache-2.0）与记忆/自进化双通道（`INSTALL_CMODULES=1`，装完交互问是否开启夜间自进化定时任务）。三者默认跳过，见下文对应小节。

12. 安全与能力增强（可选，`SKIP_SECURITY=1` 跳过，随仓库分发）——部署权限红线（交互版 59 条：14 deny / 6 ask / 39 allow）/ 审计模块（脱敏+熔断+成本告警+30 天轮转）/ 实时心跳（`heartbeat` 命令：读审计流算调用/速率/子代理，查询式零常驻税）/ 出环硬门控（`/completion-gate` 斜杠命令：宣称完成前独立复核，check 阻断/report 报告）/ 安全自检 + AGENT-CARD / 合规文档（CN/EU）/ webmap / opencode-env 插件（env/git/codegraph/GSD 四片段）/ opstate / env-profile / self-portrait / preset-skills / 路由自检

### 交互式选装菜单

在交互终端直接运行（且未设置任何选装环境变量）时，步骤 1 之后会弹出安装向导式选装菜单，把 GSD/DCP/MinerU/superpowers 路由/记忆自进化五个选装项一次选完：

```text
═══════════════════════════════════
 可选组件(全免费,默认都不装)
═══════════════════════════════════
 1. GSD 工作流        [ ] 多阶段项目管理(/gsd-* 命令,用户显式驱动)
 2. DCP 上下文压缩     [ ] 长会话自动压缩(AGPL-3.0,装前需确认)
 3. MinerU 文档解析    [ ] PDF→Markdown 本地版(免费无限量,磁盘 20GB+)
 4. superpowers 路由   [ ] 技能清单渐进披露(默认官方急加载)
 5. 记忆/自进化     [ ] mem0 偏好记忆+SkillOpt 夜间提炼(草稿区审批制)
───────────────────────────────────
 输入要启用的编号(空格分隔,如 "1 3";直接回车=全不装):
```

- 输入编号**空格分隔**（`1 3` = GSD + MinerU，`5` = 记忆/自进化），回车确认；**直接回车 = 全不装**（与历史默认一致）
- 非法输入提示重输，最多 3 次，超限自动按全不装继续（不会卡死安装）
- 选中 `2`（DCP）只代表进入安装段，**AGPL-3.0 确认门仍在安装时进行**——菜单不绕过 `CONFIRM_AGPL`
- 选中 `5`（记忆/自进化）装完后会交互问是否开启夜间自进化定时任务（答 `y` 才写 crontab；见「记忆/自进化」小节）
- 选中后回显（如 `→ 将安装: GSD, MinerU`），收尾汇总输出「已装组件(选装)」行；菜单与环境变量设的是同一组开关，无第二套状态

**菜单跳过条件**（优先级从高到低，任一命中即不出现菜单，直接走环境变量语义）：

1. `SETUP_INTERACTIVE=0` —— 强制关闭菜单（最高优先级，交互终端也不弹）
2. 已显式设置任一 `INSTALL_GSD` / `INSTALL_DCP` / `INSTALL_MINERU` / `SUPERPOWERS_ROUTER` / `INSTALL_CMODULES` / `CONFIRM_AGPL` —— 用户已给定路径，不打扰
3. 非交互终端（`curl | bash` 管道、CI、`docker exec -i` 等 `[ -t 0 ]` 为假的环境）—— 自动跳过，**非交互行为与历史版本完全一致**

调试/回归：`SETUP_FORCE_MENU=1` 可在无 TTY 时强制弹出菜单（输入改从 stdin 管道读取），用于测试菜单代码路径。

### 自定义路径

```bash
export OPENCODE_CONFIG_DIR=/custom/path/opencode
export CLAUDE_CONFIG_DIR=/custom/path/claude
./setup-opencode.sh
```

### 自定义 npm 镜像源

默认 `https://registry.npmmirror.com`。如需其他镜像或恢复官方源：

```bash
export NPM_REGISTRY=https://registry.npmjs.org
./setup-opencode.sh
```

脚本不会覆盖已有的 `~/.npmrc` 和 `~/.bunfig.toml` 中的 registry 配置。pip 同样不覆盖已有 `index-url` 的配置。

node 缺失时优先从 npmmirror 下载官方二进制（LTS v24 → v22，按架构自动选择），下载失败自动回退 nodesource 系统包。pip 缺失时用 `ensurepip` 引导（失败则提示手动安装，不写入配置），仅当 pip 可用时才写入中科大 PyPI 源（`~/.config/pip/pip.conf`，兼容 `~/.pip/pip.conf`）。

### 安装选项与环境变量

全部开关一览（默认值均为关闭）：

```bash
export INSTALL_GSD=1          # 选装 GSD 工作流（默认跳过，见下文选装说明）
export INSTALL_DCP=1          # 选装 DCP 上下文压缩插件（AGPL-3.0，需知情确认，见「DCP 上下文压缩」小节；非交互另需 CONFIRM_AGPL=1）
export INSTALL_MINERU=1       # 选装 MinerU 文档解析·本地档（免费无限量，Apache-2.0，见「MinerU 文档解析」小节；轻量可用 Flash MCP 免装）
export INSTALL_CMODULES=1     # 选装记忆/自进化双通道（mem0+SkillOpt，见「记忆/自进化」小节；非交互不问定时，默认不开启）
export SUPERPOWERS_ROUTER=1   # 启用 superpowers 路由模式（渐进披露替代官方急加载，见「superpowers 路由模式」小节）
export SETUP_INTERACTIVE=0    # 强制关闭交互式选装菜单（设置任一上面的选装变量时菜单本就不出现，见「交互式选装菜单」小节）
export SKIP_SECURITY=1        # 跳过步骤 12 安全与能力增强
export SKIP_APT_MIRROR=1      # 完全跳过 apt 源优化
export FORCE_APT_MIRROR=1     # 强制重新测速并切换（即使已自定义）
./setup-opencode.sh
```

apt 源测速默认执行：官方源最快则保持不动；若源文件已自定义（非官方域名）则跳过，避免覆盖手动配置。切换前自动备份原文件为 `sources.list.bak`；`apt-get update` 失败时提示还原命令。另有 `OPENCODE_CONFIG_DIR`/`CLAUDE_CONFIG_DIR`/`NPM_REGISTRY`（见「自定义路径」「自定义 npm 镜像源」小节）与 `OMO_MODEL`（覆盖子代理默认模型）不在上表，按需单独设置。

### 备份

```bash
./backup-opencode-config.sh
```

## 升级

**管道安装用户**（curl|bash，无本地仓库）的升级方式——管道本身就是自更新（拉到的即 main 最新）：

```bash
curl -fsSL "https://gh-proxy.com/https://raw.githubusercontent.com/Liber1917/opencode-setup/main/setup-opencode.sh" | bash -s -- --upgrade
```

> `-s` 让 bash 从 stdin 读脚本；`--` 之后的内容归脚本（防止 bash 把 `--upgrade` 当自己的选项）。


`./setup-opencode.sh --upgrade` 一条命令（克隆用户自动 git pull；curl 用户自动重下载替换）：

- **自更新先行**：升级第一步先把脚本自身更到最新，再以新版执行升级。git 克隆用户自动 `git pull --ff-only`（本地有改动无法快进时黄警跳过，以当前版本继续）；curl 安装用户自动重下载 main 最新脚本，经 `bash -n` 语法 + 大小双校验后替换自身。已是最新则直接继续——同版本不会重启，天然无循环
- **状态清单还原选装上下文**：安装/升级收尾把在场组件实测写入 `~/.config/opencode/.setup-state.json`（升级账本）；`--upgrade` 读它自动恢复 `INSTALL_DCP` / `INSTALL_MINERU` / `INSTALL_GSD` 等选装开关——忘带环境变量重跑不会再走「未选」路径误剥已装接线（如 mcp.gsd）
- **考古模式**：v1.0 之前安装的机器没有状态清单，`--upgrade` 现场探测在场组件重建清单后照常升级，不报错不阻断
- **失败续传（幂等）**：脚本是加法，任何一步失败直接重跑 `--upgrade` 即续传——已装组件由既有幂等跳过自动略过，变更段（omo 补丁 / 路由三件套 / 安全检查）正常更新，不回滚
- 升级完成收尾按新旧状态清单 diff 打印本次新装组件；DCP 等已确认过的许可不重新询问（首次确认已在清单留档，知会文本仍打印）

查看当前版本：`./setup-opencode.sh --version`。

## 安全与能力增强（步骤 12）

安装脚本最后一步部署可选的安全/能力模块到 `~/.config/opencode/opencode-setup-modules/`：

| 模块 | 功能 | 用法 |
|---|---|---|
| `gen-permissions.sh` | 权限红线（三档模板：交互版 59 条 bash 规则：14 deny / 6 ask / 39 常用 allow；无头版 7 条红线；沙箱版网络红线，见下小节） | 重新生成：`bash gen-permissions.sh`（终端上问标准/沙箱档；无头：`--headless`；沙箱：`--sandbox`） |
| `audit-init.sh` | 审计模块（JSONL + 密钥脱敏 + 熔断器 + 30 天轮转） | 初始化：`bash audit-init.sh`；轮转：`bash audit-init.sh --rotate` |
| `heartbeat.sh` | 实时心跳（读审计流尾部算最近会话调用/事件速率/子代理状态，一行输出；不碰 opencode.db，审计流无 token 字段故无 token 数） | 查询：`heartbeat [窗口行数]`（默认 50，装后 `~/.local/bin/heartbeat`） |
| `completion-gate.sh` | 出环硬门控（evidence-gated completion，`/completion-gate` 斜杠命令） | 阻断：`bash completion-gate.sh check [workdir]`；报告：`report` 子命令 |
| `security-check.sh` | 安全自检（密钥治理/offline/provenance/注入扫描）+ AGENT-CARD 生成 | 装完跑一次：`bash security-check.sh`；开 offline：`bash security-check.sh --offline` |
| `gen-compliance.sh` | 合规文档（CN/EU 双地区，provider 数据流向清单） | `bash gen-compliance.sh --region cn` |
| `bwrap-setup.sh` | B 档沙箱一键脚本（clavinculis 优先，降级 opencode-bwrap） | `bash bwrap-setup.sh` |
| `devcontainer/` | C 档容器隔离模板（非 root + cap-drop） | 见 `devcontainer/README.md` |

### 出环硬门控（completion-gate，完成时双控）

完成时幻觉调研（arXiv 2606.09863）实测：agent 宣称"完成"时，单靠推理环内自评假成功率 44-52%；加一道**独立于推理环的机器复核**（双控）可压到 3%。`completion-gate.sh` 是 AGENTS.md 在场守则的机器执行层——宣称完成前，由环外脚本按退出码阻断/放行：

| 检查项 | 判定 |
|---|---|
| git 卫生 | 有未提交变更且会话有 edit/write 工具记录（查 opencode 会话 DB）→ 未过（需 commit 或说明） |
| 测试通过 | 检出 `package.json` test / Makefile test / pytest 痕迹即跑（`timeout -s KILL 300`），退出非零 → 未过 |
| 声明-在场一致 | 扫会话最后一条 assistant 消息的完成声明（`已安装/已配置/…`+名词、`✓` 行、`已生成`+文件名），逐项 `command -v` / 文件存在复核；声明了不在场的东西 → 未过 |
| 明文密钥 | 扫暂存/未提交文件有无 `sk-` 开头 20+ 位密钥，命中 → 未过（输出掩码） |

- **阻断模式**：`bash completion-gate.sh check [workdir]`——任一未过退出码 1；`/completion-gate` 斜杠命令（部署于 `~/.config/opencode/commands/`）即调它，退出码 1 前不得宣称完成
- **报告模式**：`bash completion-gate.sh report [workdir]`——同样输出，恒退出 0，不阻断人工收尾
- **诚实覆盖**：声明复核的名词映射硬编码一小批（opencode/mineru/skillopt/mem0/rtk/codegraph/bun/node + `*.sh`/`*.json` 等文件名模式），映射外不覆盖，输出如实说明
- **挂载形态**：opencode 1.18.29 的 config schema 无 `event` 键，TUI 与 `opencode run` 双实测 event 命令均不触发（无 Stop/session.idle 等价事件），故挂斜杠命令形态；单测见 `tests/test-completion-gate.sh`（四夹具场景断言退出码与输出）


### 权限模板三档（交互 / 无头 / 沙箱）

`gen-permissions.sh` 支持三档权限模板，deny 面与适用场景各不相同。默认调用（不带 flag）在交互终端上会先问权限档位（`1 标准` / `2 沙箱`，回车=标准，详见小节末）：

| 档位 | 生成参数 | deny 面 | ask 面 | 适用场景 |
|---|---|---|---|---|
| 交互版（默认） | `bash gen-permissions.sh`（终端问档位，回车=标准） | 14 条：本机破坏类（`rm -rf`/`mkfs`/`dd`/`chmod 777`/`git reset --hard`/`crontab -r`/`sudo rm` 等）+ 网络不可逆类（force-push/`curl\|sh`/authorized_keys 持久化） | 6 条（`git push`/`npm publish`/`docker push`/`gh release create`/`gh pr merge`/webfetch） | 本机日常开发，高风险操作弹窗确认 |
| 无头版 | `--headless` | 7 条红线（本机破坏类 + 网络不可逆类子集） | 0（其余全 allow） | benchmark/CI 无头跑，红线外全放行 |
| 沙箱版 | `--sandbox` | 6 条网络不可逆类：force-push ×2、`curl\|sh`、`wget\|sh`、authorized_keys 凭据持久化、`gh release create` | 0（docker/pip/npm 等全走 `"*": "allow"` 兜底） | 一次性容器/VM 等本机破坏可复原的隔离环境，免手动点弹窗 |

沙箱档设计裁定：**隔离挡得住本机破坏，挡不住网络不可逆**——本机破坏类 deny 被删（容器/VM 边界已覆盖，可复原），网络不可逆类 deny 保留。`gh release create` 归 deny 而非 ask：沙箱档 ask 归零无中间态，而发布一旦触发通知/外部镜像抓取，事后删除收不回已分发产物，按"网络不可逆"标准与 force-push 同类。**沙箱档不是全 bypass**——网络红线仍在。

默认调用（无 flag、无环境变量）在交互终端上会先问权限档位：选 `1` 或回车=标准档（交互版 59 条），选 `2`=沙箱档（与 `--sandbox` 产物等价）；非法输入提示重输，连续 3 次后按标准档继续。非交互调用（管道、`curl | bash`、无头 CI 等 `[ -t 0 ]` 为假的环境）不问不读，直接标准档，行为与历史版本零差异。setup 步骤 12 经命令替换调用本脚本（stdout/stderr 重定向 `/dev/null`、stdin 未重定向）：交互装机时问句照常出现（提示走 `/dev/tty`，重定向下仍可见），管道装机不触发。

容器/CI 中可免改脚本直选档位：`PERMISSION_MODE=sandbox bash setup-opencode.sh`（`PERMISSION_MODE=headless` 同理，经 `gen-permissions.sh` 生效，与对应 flag 等价）。

### DCP 上下文压缩（选装，`INSTALL_DCP=1`，AGPL-3.0 需知情确认）

[DCP](https://github.com/Opencode-DCP/opencode-dynamic-context-pruning)（opencode-dynamic-context-pruning，npm 包 `@tarquinen/opencode-dcp`）为 OpenCode 注入 `compress` 工具与阈值 nudge，长会话上下文呈锯齿式回落而不是单调爬升。**默认不装**，原因见下方许可证知会。

> **许可证知会（AGPL-3.0-or-later，脚本安装前后各提示一次）**
>
> 该插件为 AGPL-3.0 许可证：未修改使用无义务；修改并（哪怕服务器）部署需公开修改源码；部分企业禁用 AGPL。继续安装即视为你知情并自行决定。
>
> 合规背景（详见 `benchmarks/terminal-bench/dcp-verify.md`「AGPL 合规注记」）：AGPL 网络条款（§13）使"将其作为网络服务一部分提供"可能触发整体源码披露义务；opencode 插件与主进程同进程加载（bun import），属"合并工作"解释的灰色地带。组织合规策略通常将 AGPL 列为默认禁用、需法务逐案豁免的许可证——**实验/个人沙箱可用，团队默认不装**。另注：上游开发重心已转移至 Sleev，DCP 处于维护模式，选型时需考虑上游活跃度。

安装方式（交互终端会逐字显示上述知会并要求确认：默认 n、10 秒超时自动跳过；非交互管道必须双变量显式确认，防 `curl | bash` 误触）：

```bash
INSTALL_DCP=1 ./setup-opencode.sh                        # 交互确认（y 继续）
INSTALL_DCP=1 CONFIRM_AGPL=1 ./setup-opencode.sh         # 非交互/CI 双变量显式确认
opencode plugin @tarquinen/opencode-dcp@latest --global  # 或手动安装（官方装法）
```

实测数据（单会话 9 轮真实任务，glm-5.3，阈值调低加速触发；完整报告 `benchmarks/terminal-bench/dcp-verify.md`）：

| 指标 | DCP 实验组 | `--pure` 对照 | 差异 |
|---|---|---|---|
| 每 fetch 上下文均值 | 15.7K | 50.2K | **-69%** |
| 末段上下文（末 3 fetch） | ~13K | ~69K | **-82%** |
| 计费当量（input + cacheRead/10） | 127K | 223K | **-43%** |
| 累计未缓存 input | 76.6K | 63.5K | +21%（压缩改写历史→缓存失效的代价） |

模型自主触发已实测证实（9 轮内 4 次自主调用 compress，机制为 nudge 注入 + 工具可用 + 阈值到达的合力）；`/dcp-compress` 命令可手动兜底。装后脚本写入默认 `~/.config/opencode/dcp.jsonc`（compress 阈值 8K/16K 为实测加速值，上游默认 50K/100K，按模型上下文窗口调整，见文件内注释）。安装为官方全局装法，唯一配置改动是 `opencode.json` plugin 数组新增一行，卸载即逆操作。重启 OpenCode 后生效。

### MinerU 文档解析（选装，`INSTALL_MINERU=1`，Apache-2.0）

[MinerU](https://github.com/opendatalab/MinerU)（opendatalab 出品）把 PDF/图片解析为 Markdown/JSON，中文文档解析的主力开源工具。官方共三条路径，免费/付费情况如实如下：

| 档位 | 费用 | 限制 | 适合 |
|---|---|---|---|
| Flash 云 API（MCP，免装） | **免费**，免装免 key | 单文件 ≤20 页 / ≤10MB，IP 限速 | 轻量、偶发的文档解析 |
| 本地部署（`INSTALL_MINERU=1`） | **完全免费**，无限量 | 磁盘 20GB+ / 内存 16GB+（CPU pipeline 可跑）；模型数 GB 首次运行下载 | 大批量、隐私敏感、离线 |
| 云 API token | 免费额度后按量付费 | 需自行注册购买 token | 本脚本不接，自行评估 |

> **付费立场声明**：本脚本只接免费路径——轻量用 Flash MCP，大量用本地部署；云 token 档请自行评估，我们不推荐（也不会自动配置）。

**轻量路径（Flash MCP，零安装）**：在 `opencode.json` 的 `mcp` 段加入以下配置即可（不设 `MINERU_API_TOKEN` 即 Flash 免费档；`uvx` 需要 [uv](https://docs.astral.sh/uv/)，MCP 来自官方 [MinerU-Ecosystem](https://github.com/opendatalab/MinerU-Ecosystem)；选装 `INSTALL_MINERU=1` 时此合并由脚本自动完成，无需手动）：

```json
"mcp": {
  "mineru-flash": {
    "type": "local",
    "command": ["uvx", "mineru-open-mcp"],
    "enabled": true
  }
}
```

**大量路径（本地部署）**：

```bash
INSTALL_MINERU=1 ./setup-opencode.sh
```

脚本行为（各环节独立容错，失败仅黄警不阻断其余步骤）：

1. 打印许可证知会：**MinerU 为 Apache-2.0 + 附加条款——个人与常规商用免费；MAU>1 亿或月收入>$2000 万 需商业授权；对外在线服务需标注使用了 MinerU**（Apache-2.0 宽松，无需 AGPL 式确认门）
2. 资源前置检查：磁盘可用 <25GB 或内存 <15GB 打黄色警告，仍继续装包（模型首次运行才下载，装包本身不占大空间）
3. `pip install "mineru[core]"`（走脚本已配置的中科大 PyPI 源；PEP 668 系统自动加 `--break-system-packages` 重试；python3/pip 缺失则告警跳过并附手动指引）
4. 幂等写入 `~/.bashrc`：`export MINERU_MODEL_SOURCE=modelscope`（国内模型源，已存在不重复写）
5. 验证 `mineru --version` / `import magic_pdf`（容错三连），成功绿√失败黄⚠附手动安装指引
6. 提示模型下载时机：模型约数 GB，首次运行 `mineru` 时自动从 modelscope 下载
7. agent 侧接线（不留裸 CLI 零调用面——agent 不会自发使用裸 CLI，实测教训）：部署 `preset-skills/mineru-local` skill（本地解析用法：后端选择 `-b pipeline`/`-b vlm-engine`、输出目录读法、隐私与超时注意事项）到 `~/.config/opencode/skills/`；按「轻量路径」同款配置幂等合并 Flash MCP `mineru-flash` 进 `opencode.json` 的 `mcp` 段（既有 mcp 条目保留，重复跑不重复写）；打印隐私知会一行（**Flash MCP 走云端处理（文档传 mineru.net，处理后不保留）；本地隐私文档用 mineru CLI**）；未检出 `uvx` 时黄警附 `curl -LsSf https://astral.sh/uv/install.sh | sh` 指引，不阻断

> **选装后自动部署 mineru-local skill + Flash MCP（agent 即刻可调用）；隐私文档用本地 CLI，便捷任务用 Flash MCP。**

### superpowers 路由模式（可选，`SUPERPOWERS_ROUTER=1`）

官方 superpowers 插件急加载实测 **9.2k token/对话起步税**（20 技能描述进 system prompt + using-superpowers 全文进首条消息）。路由模式换为渐进披露：首条消息只注入路由块（强制扫描纪律两行 + 候选清单），agent 命中场景时 `Read` vault 里的技能正文。

```bash
SUPERPOWERS_ROUTER=1 ./setup-opencode.sh
```

插件有两种形态（组件与实验细节见 `router-modules/README.md`）：

- **v1 全量目录——setup 部署的实际形态**：注入纪律两行 + 20 技能一行清单 + using-superpowers 兜底指路。setup 只部署插件单文件（`sp-router.ts`），`matcher.mjs`/`index.yaml` 未随附，v2 检索层加载失败自动回退本形态（fail-open，能力零丢失）。旧环境实测微任务基线 936 token（−90%）。
- **v2 top-3 检索——组件齐备时的插件默认**：matcher 按信号词对首条消息撒种排序，注入 top-3 候选（含命中词）+ 兜底行（候选不覆盖时读全量索引匹配）。激活需手动把 `matcher.mjs`/`index.yaml` 拷到 `~/.config/opencode/plugins/`；`SP_ROUTER_V1=1` 可显式锁回 v1 纯目录。

**token 口径（B 轮实测，`benchmarks/terminal-bench/sp-router-ab.md`）**：注入块本身 v1 ≈0.75k / v2 ≈0.3k（省约 60%）；但端到端会话总量 v2 可能反超 v1——模型按纪律先 `Read` 候选技能正文再行动（实测 4/10 句触发，每句约 +9k），逐句均值 v2 11.4k vs v1 8.9k，中位数口径 v2 反而便宜 5.6%。渐进披露是把目录税换成按需正文税，不是单向省。

**实验终局**：预注册判决实验两轮（A 轮检索层缺陷致 FAIL；B 轮修复后 v2 端到端准确率 10/10 ≥ v1 的 9/10，但 token 判据结构性不可达——门槛低于无插件共享基座本身），终局 FAIL，路由日志/夜间审计等后续计划搁置。模式保留为选装，不再迭代；已装用户切换步骤见 `router-modules/README.md`。

### 记忆/自进化（选装，`INSTALL_CMODULES=1` 或菜单选 `5`）

装 **mem0 + SkillOpt 双通道**（复用 `c-modules/c-modules-setup.sh --all` 装器，不重复实现）：

- **通道① 用户偏好 recall** → [mem0](https://github.com/mem0ai/mem0)（Apache-2.0）：会话中 `mem0 add '记住X'` / `mem0 search '查询'`
- mem0 初始化免注册：`mem0 init --agent --agent-caller opencode`（免费档无卡；云端存储，自托管可设 `MEM0_BASE_URL`）
- **通道② 流程改进** → [SkillOpt-Sleep](https://github.com/microsoft/SkillOpt)（MIT）：`skillopt-sleep` 扫 OpenCode 会话 → 提炼 → 验证门控 → 落草稿区待审

```bash
INSTALL_CMODULES=1 ./setup-opencode.sh              # 菜单选 5 同效;交互终端装完会问定时
bash c-modules/c-modules-setup.sh --all             # 或手动单独运行装器
```

**夜间自进化定时任务**（核心新增）：菜单选 `5` 的交互终端在装完后会问：

```text
是否开启夜间自进化定时任务? (每晚 03:00 扫当天会话→提炼→验证门控→落草稿区待审) [y/N]:
```

答 `y` 才写 crontab（幂等，已存在同命令不重复添加；crontab 不可用则打印手动 `crontab -e` 行）：

```cron
0 3 * * * skillopt-sleep >> ~/.config/opencode/skill-drafts/sleep.log 2>&1
```

**审批制契约（硬门）**：提炼产物只落 `skill-drafts/` 草稿区，人工批准（移入 `skills/`）才生效——**自进化无自动生效路径**。`INSTALL_CMODULES=1` 环境变量路径按非交互铁律不问定时问题、默认不开启，仅打印开启命令一行（防管道/CI 误写 crontab）。

### 仓库新增目录

```
router-modules/  ←  上下文优化（sp-router：superpowers 渐进披露路由插件 + 信号索引/校验器/种子生成器，见 router-modules/README.md）
a-modules/       ←  A 方向联网认知（webmap CLI：llms.txt 站点文档装成 skill，3S 护栏）
b-modules/       ←  B 方向环境感知（opencode-env 插件 + env-profile.sh）
c-modules/       ←  C 方向集成模块（mem0 + SkillOpt 装器 + self-portrait；经菜单第 5 项/INSTALL_CMODULES=1 接入）
d-modules/       ←  D 方向控制（opstate 声明式任务状态 + fetch-skills 指引）
e-modules/       ←  E 方向安全模块（6 个脚本 + devcontainer）
preset-skills/   ←  预设 skill（ai-communication 沟通协议）
benchmarks/      ←  验证体系与实测报告（terminal-bench / review / 对抗测试）
docs/design/     ←  设计资产（五方向规格 specs/ + 调研报告）
.opencode/skills/docker-test-setup/  ←  Docker 测试矩阵 skill
```

### 装后可用的新命令（克隆安装）

```bash
webmap install nodejs.org   # A-联网认知：站点 llms.txt → skill（限速/UA/注入隔离/robots 遵守）
opstate claim t1 alice      # D-控制：声明式任务状态流转（STATE.md 对账）
env-profile                 # B-环境感知：全量环境画像（env/git/codegraph 三态）
```
opencode-env 插件（自动接线）在每会话首条消息注入轻量 env 块，agent 按需读全量画像。

## 配置

### API 密钥

```bash
nano ~/.config/opencode/opencode.json
```

```json
{
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "sk-your-key-here",
        "baseURL": "https://api.anthropic.com"
      }
    }
  }
}
```

**使用 DeepSeek**（Anthropic 兼容接口）：

```json
{
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "sk-your-deepseek-key",
        "baseURL": "https://api.deepseek.com/anthropic"
      }
    }
  }
}
```

### 模型路由（可选）

oh-my-openagent 使用源码内置的默认模型 + 回退链，开箱即用。

如需自定义，编辑 `~/.config/opencode/oh-my-openagent.json`，为 agent 添加 `model` 字段：

```json
{
  "agents": {
    "oracle": {"model": "deepseek/deepseek-v4-flash"},
    "explore": {"model": "deepseek/deepseek-v4-flash"},
    "sisyphus-junior": {"model": "deepseek/deepseek-v4-flash"}
  }
}
```

不设 model = 使用内置默认，优先级：
```
agent model > category model > 用户 fallback_models > OpenCode 默认 model > 源码内置回退链
```

## Agent 一览

| Agent | 职责 |
|-------|------|
| **hephaestus** | 构建与实现 |
| **oracle** | 架构、调试、高难度推理 |
| **librarian** | 外部文档、OSS 代码搜索 |
| **explore** | 代码库模式发现 |
| **multimodal-looker** | PDF/图片分析 |
| **prometheus** | 规划与策略 |
| **metis** | 预规划顾问 |
| **momus** | 计划评审 |
| **atlas** | 知识管理 |
| **sisyphus-junior** | 专注任务执行 |

## Category 一览

| Category | 适用场景 |
|----------|---------|
| visual-engineering | 前端、UI/UX、CSS |
| ultrabrain | 复杂逻辑、算法 |
| deep | 自主问题解决 |
| artistry | 创意/非常规方案 |
| quick | 单文件简单修改 |
| unspecified-low | 低难度杂项 |
| unspecified-high | 高难度杂项 |
| writing | 文档、写作 |

## GSD Core 工作流（选装，`INSTALL_GSD=1`）

GSD Core（[open-gsd/gsd-core](https://github.com/open-gsd/gsd-core)）是 GSD 的官方继任项目，原生支持 OpenCode。

> **为什么默认不装**（三轮基准实测，`benchmarks/terminal-bench/gsd-*.md`）：任务完成率零收益（客场 0/6、主场三条件同分）；常驻菜单成本 ~4k token/会话；模型自发调用率 0%（必须用户显式敲命令）。**它的真实价值是多阶段项目的流程产物与提交规范**——需要时再装，不吃默认配置的 token。

```bash
INSTALL_GSD=1 ./setup-opencode.sh   # 装后 /gsd-* 命令可用
```

装后无需额外配置即可使用 `/gsd-*` 命令（opencode-env 插件会在 GSD 项目里自动注入当前 phase 状态）：

| 命令 | 功能 |
|------|------|
| `/gsd-new-project` | 初始化项目 |
| `/gsd-plan-phase` | 创建执行计划 |
| `/gsd-execute-phase` | 带原子提交的执行 |
| `/gsd-progress` | 进度跟踪 |
| `/gsd-help` | 全部命令列表 |

## CodeGraph

脚本会安装 codegraph CLI（`@colbymchenry/codegraph`），安装成功后才在 opencode.json 中注册 MCP（避免启动报 Executable not found）。MCP command 使用**绝对路径**（兼容脚本安装的官方二进制 node 布局，其 npm 全局 bin 不在 PATH）；安装失败会显示真实错误日志，装好后重新运行脚本即可。索引按项目启用：

```bash
cd your-project
codegraph init        # 生成 .codegraph/ 索引（之后自动增量同步）
```

重启 OpenCode 后 `codegraph_explore` 等工具生效。无索引的目录中 MCP 自动休眠，不影响其他工具。

## RTK（Token 节省）

脚本安装 RTK 并注册 OpenCode 插件（`~/.config/opencode/plugins/rtk.ts`）。插件在 bash 工具执行前拦截命令，重写为 `rtk` 等价命令，输出进入 LLM 前被压缩（git/test/build 等常见命令节省 60-90% Token）。

```bash
rtk gain          # 查看累计节省统计
rtk discover      # 发现未被覆盖的命令
rtk init --opencode -g   # 重装/修复 OpenCode 插件
```

RTK 安装走镜像链（gh-proxy.com → ghfast.top → 官方直连），无需 GitHub 认证。重启 OpenCode 后生效。内置工具（Read/Grep/Glob 等）不走 bash hook，不受影响；命令失败时完整原始输出保存在 `~/.local/share/rtk/tee/` 可追溯。

## 常见问题

### 国内网络安装慢

脚本已默认使用 npmmirror 镜像（npm/npx/bun 全部走镜像），apt 源自动测速切换最快国内镜像。Bun 安装优先走 npm 镜像，不再依赖 GitHub。node 安装仍走 nodesource，若也慢请手动安装 node 后重跑脚本。RTK 下载走 GitHub 代理镜像链（gh-proxy.com → ghfast.top → 官方直连），任一源可用即成功。

### RTK 未生效

重启 OpenCode 后插件才加载。验证：

```bash
rtk --version     # 应显示 rtk 0.45.x
ls ~/.config/opencode/plugins/rtk.ts   # 插件文件存在
```

若插件文件缺失，手动执行 `rtk init --opencode -g`。

### `node: not found`

**原因**：在 WSL 中运行了 Windows npm 安装的 opencode。

**解决**：用 Bun 在 **WSL 内**重新安装：

```bash
# 确保在 WSL 内执行
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
bun install -g opencode-ai
```

### 插件不生效

重启 OpenCode 会话后生效。

### GSD Core 安装失败

确保 Node.js 已安装，然后手动运行：

```bash
npx --yes @opengsd/gsd-core@latest --opencode --global
```

### "未检测到 OpenCode 环境"

在 OpenCode 终端会话内运行命令。

## 环境要求

- bash（用 `sh` 运行会自动切换）
- curl / git / 网络连接

node、Bun、OpenCode 由脚本自动安装。

## 文件清单

| 文件 | 说明 |
|------|------|
| `setup-opencode.sh` | 统一安装脚本（唯一入口） |
| `backup-opencode-config.sh` | 配置文件手动备份工具 |

## License

MIT
