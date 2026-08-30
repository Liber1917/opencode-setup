# Spec 分层索引(2026-08-28 拆分)

> 原 harness-env-awareness-spec.md(391 行)按方向拆分为可独立执行的工作规格。
> 设计原则/调研背景留在母文档;此处只放"要做什么"。

## 文件

| 文件 | 方向 | 当前状态(2026-08-30 双评审后) |
|---|---|---|
| B-environment.md | 环境感知(world-state/fragment/状态机) | ✅ 实装+部署接线(插件三Fragment/env-profile;§4 权限通道以直读fs折衷,无spawn) |
| A-webmap.md | 联网认知(webmap CLI+3S 护栏) | ✅ 实装+部署(限速/UA/robots遵守/审计日志/注入fail-closed/sha256指纹;注册表预锁hash未做→装后指纹) |
| C-embodiment.md | 具身认知(画像/双通道/模型适配) | ✅ 实装(双通道目录/模板/0600画像;mem0/SkillOpt 手动装已文档化) |
| D-control.md | 控制(skill 构成/协调/拓扑) | ✅ 机制实装+部署(opstate/preset-skills/fetch指引含grilling;skill内容按版权边界手动摘取) |
| E-security.md | 安全(E 六模块) | ✅ 实装+部署(59规则/审计+成本告警/AGENT-CARD/合规;escalation由ask通道承载,budget=调用量代理告警) |

## 实施任务清单(按优先级)

### 第一批(补核心闭环)
- [x] B: env-profile 探测脚本(b-modules/,实测通过)
- [x] D: preset-skills 部署步(步骤12⑦,幂等跳过已存在)
- [x] E: audit hook 自动接线(实测 event 四通道写入)
- [x] C: self-portrait 工具(c-modules/,0600,密钥不入)
- [x] subagent 路由自检步(步骤12⑧)
### 第二批(工具开发)
- [x] A: webmap CLI(a-modules/webmap,四命令+3S 实测通过)
- [x] A: 3S 护栏(限速0.5s/UA/严格解析/注入检测实测)
- [x] C: 双通道目录(c-modules-setup 初始化+模板,实测)
- [x] D: 上游单点指引(d-modules/fetch-skills,版权边界不自动拷)
- [x] D: opstate(d-modules/,声明式STATE.md+对账CLI,漂移检测/claim/done 实测)
### 第三批(Phase 2-4)
- [x] B: opencode-env 插件(b-modules/,三Fragment+注入+幂等,node 单测通过)
- [x] B: 状态机内嵌于 opstate/env-profile(失败也是信息;env status 由 profile 文件承载)

## 已知折衷(双评审确认,非隐藏缺口)
- escalation 无原生 justification 通道 → 由 ask 通道承载(人在场逐次授权)
- E-2⑤ 成本上限 → timeout 全链 + 单会话≥300事件告警(代理指标);原生 budget 待上游
- S2 注册表 sha256 → 装后指纹记录+update 校验(预锁内容hash会随上游更新误报)
- B §4 权限集成 → 插件直读文件系统(零 spawn,防EDR口径优先)
- D-1 grilling/discernment-nudge → fetch-skills 指引(上游MIT,用户自行摘取)
- D-2 "默认装 29" → 实装 SP 核心 8/16 + AG 0/8(版权边界,fetch-skills 指引覆盖;默认集合=仓库自有 preset + superpowers-zh 插件)
- E-2 "preset 锁版本" → 插件实际 @latest(锁版本需 pin 机制,未做;npm audit signatures 已做)
- E-2 审计延迟 → 实测 ~20ms/调用(spec 原文 <1ms 仅为设计目标;轮转上限 40MB≤50MB 达标)
