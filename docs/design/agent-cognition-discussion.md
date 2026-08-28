# Agent 认知升级 — 讨论材料(会话持久化副本)

> 关联文件:`/home/agent-cognition-report.html`(完整版 + TL;DR 报告)
> 状态:7 路 deep research 已完成(4 主方向 + 3 补充:模型自适应/SkillCoach/安全合规),报告已交付,讨论待用户选择切入点

## 待讨论项(唯一阻塞)

与用户由浅入深讨论五个方向,需用户回来选择切入点。已备齐全部材料。

---

## 方向速览

| 方向 | 本质 | 证据 | 难度 | 结论 |
|---|---|---|---|---|
| A 联网 | 给 agent 互联网地图而非盲搜 | 中(STORM/llms.txt/GraphRAG) | 中 | 值得(curated 注册表+站点图是空白) |
| B 环境 | agent 知道自己机器上有啥 | **强**(Terminal-Bench 24.1% 失败) | 低 | **最值得**,证据最硬成本最低;规格已评审完毕 |
| C 具身 | agent 认识自己+自评 | 中(原语齐备,自评不可靠) | 低 | 做"画像"别做重量级自进化 |
| D 控制 | 人审计划不审命令 + 对人交互/流程/拓扑 | **强**(97% 橡皮图章/39% 计划拒绝) | 低 | **已收口**:五定案(交互/skill构成32+/协调 Operator式/拓扑跟踪/防护移交E) |
| E 安全合规 | 给信任边界上锁 | **强**(OWASP Top10 2026 + EU AI Act 已执法) | 低 | **必做**;新承接防护三层(权限红线+审计默认/bwrap 一键选装/devcontainer 按需) |

## C 方向扩充(用户补充要求)

- **模型自适应**:PromptBridge(2512.01420) 跨模型 prompt 迁移 +27.4% SWE-Bench;MAPO(2407.04118) 按模型优化 prompt +20%;工程标杆 OpenCode models.dev 元数据 → 能力 gate → provider 协议注入
- **轻量自进化(SkillCoach 参考)**:SkillCoach(2607.01874) 演化评估 rubric;Skills-Coach GRPO(2604.27488) 文本空间优化 SKILL.md,成本 ~$20,严格"改指令不改权重";生产参考 Microsoft SkillOpt(-Sleep 夜间管线);**注意 SkillCoach 不在 rtk-ai/rtk 里**(那是 Rust Token Killer 压缩工具)

## E 方向核心(安全/可信/合规)

- 框架:OWASP Agentic Top 10 2026;注入基准 InjecAgent(ASR 24-47%)/ASB(84.3%)
- 可信:审计 hooks(PreToolUse/PostToolUse)、Agent Cards 可复现哈希、System Card 透明披露、overlay 回滚
- 合规:EU AI Act 2026-08-02 执法落地;中国 GB/T 45654-2025 可认证 + 不得留存可识别身份记录
- 落地:deny-first 权限 + 脱敏审计 + offline 数据主权 + AGENT-CARD 模板 + 安全自检

## 三件事今天就能做(ROI 排序)

1. **环境画像 skill(方向 B)** — &lt;1s 探测生成环境摘要,解决 24.1% 失败。脚本已有 55 处探测逻辑可复用。
2. **控制默认值模板(方向 D)** — 计划级确认+命令级白名单+角色权限,复刻 Codex --profile。零新代码纯配置。
3. **联网地图 skill(方向 A)** — curated 注册表+webmap 工具+持久站点图。

## 关键洞察(横跨四方向)

"注入信息"≠"agent 会用"——Agents Explore but Agents Ignore 实测:发现率 79-81%,利用率仅 37-50%。任何预置必须配套"探索-行动"提示规范。

---

## 方向 B「环境画像 skill」设计草案(讨论稿)

### 定位
安装完成后生成 agent 可读的环境画像 `~/.config/opencode/env-profile.md`,会话中按需读取。只读画像,不改行为。

### 数据来源:100% 复用现有探测逻辑
| 画像字段 | 来源 | 脚本行号 |
|---|---|---|
| OS/架构 | uname -m + 发行版判断 | ~L301 |
| 权限状态 | id -u + sudo 判定 | ~L60 |
| 工具清单 | command -v curl/node/bun/rtk/codegraph | 遍布 |
| 包管理器 | command -v apt-get/yum/brew/apk | ~L275-281 |
| 网络/镜像 | 步骤 4 测速结果 | ~L222-250 |
| PATH 概况 | .bashrc 注入内容 | ~L790 |

### 画像内容(1-2KB 高信号)
```markdown
# 环境画像 (生成于 YYYY-MM-DD, 删除后重跑脚本可重新生成)
- OS: Linux x86_64 (ubuntu)
- 包管理器: apt
- 工具: node 24.19.0, bun 1.3.14, curl, git, codegraph, rtk 0.45
- npm 镜像: npmmirror
- apt 源: archive.ubuntu.com (官方最快)
- 已装 harness: opencode (plugins: rtk.ts, gsd-core.js)
- 注意: 全局 npm bin 不在 PATH, 用 npx 或完整路径
```

### 三个待定设计点(讨论重点)
1. **注入方式**:会话开始自动注入 vs agent 主动按需读?(token 成本 vs 即时性)
2. **动态刷新**:哈希指纹比对(环境变了才重生成)vs 每次会话重跑探测(&lt;1s 很便宜)?
3. **形态**:纯 skill(引导读 md)vs skill+启动 hook(自动注入)?

### 与方向 D 联动(可选)
画像里追加"本机权限模板"段(explorer/reviewer/build 预设),一个文件同时服务认知与控制。
