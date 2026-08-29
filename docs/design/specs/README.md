# Spec 分层索引(2026-08-28 拆分)

> 原 harness-env-awareness-spec.md(391 行)按方向拆分为可独立执行的工作规格。
> 设计原则/调研背景留在母文档;此处只放"要做什么"。

## 文件

| 文件 | 方向 | 当前状态 |
|---|---|---|
| B-environment.md | 环境感知(world-state/fragment/状态机) | ⚠️ 未实装(Phase1-4 待做) |
| A-webmap.md | 联网认知(webmap CLI+3S 护栏) | ❌ 未实装 |
| C-embodiment.md | 具身认知(画像/双通道/模型适配) | ⚠️ c-modules 仅装 CLI,画像/目录未落 |
| D-control.md | 控制(skill 构成/协调/拓扑) | ⚠️ 评审完,skill 集合未部署 |
| E-security.md | 安全(E 六模块) | ✅ e-modules/ 已实装+benchmark 验证 |

## 实施任务清单(按优先级)

### 第一批(补核心闭环)
- [ ] B: env-profile 探测脚本(Phase1 静态核心)
- [ ] D: preset-skills 部署步(29 skill 拷贝)
- [ ] E: audit hook 自动接线(写 opencode.json event 段)
- [ ] C: self-portrait 工具(复用 B 架构)
- [ ] subagent 路由自检步
### 第二批(工具开发)
- [ ] A: webmap CLI(init/install/search/update)
- [ ] A: 3S 护栏(限速/hash锁/注入隔离)
- [ ] C: 双通道目录(memory/ + skill-drafts/)
- [ ] D: skill-creator/mece/prd 集成
- [ ] D: 文件即状态 Operator 式对账
### 第三批(Phase 2-4)
- [ ] B: Fragment 抽象 + diff 注入
- [ ] B: 异步状态机 + env status
