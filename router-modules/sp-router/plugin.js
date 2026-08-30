/**
 * sp-router — superpowers-zh 路由模式插件(渐进披露移植)
 *
 * 替代 superpowers 官方插件的急加载(20 skill 描述进 system prompt + using-superpowers 全文进首消息 ≈9.2k token):
 *   ① 不把 skills 目录注册进 opencode 扫描路径(描述税归零)
 *   ② 首条用户消息只注入 ~400 token 能力清单(名称+一行时机)
 *   ③ agent 命中场景 → Read <vault>/<name>/SKILL.md 按需加载正文(等价 Claude Code 渐进披露)
 *
 * 用法: opencode.json plugin 数组移除 superpowers@..., 加入本插件路径;
 *       superpowers skills 克隆/留在 vault 路径(本插件只读, 不安装不更新)。
 */
import path from 'path'

// vault 路径: 优先环境变量, 回退标准克隆位
const vault = "__SP_VAULT__"  // 部署时由 setup 注入绝对路径

// 能力清单(与 superpowers-zh v7.9 同步;改上游时重新生成)
const CATALOG = [
  ['brainstorming', '任何创造性工作之前(创建功能/组件/改行为)— 先探索意图与设计'],
  ['systematic-debugging', '遇到 bug/测试失败/异常行为时, 在提出修复方案之前'],
  ['test-driven-development', '实现任何功能或修 bug 时, 在写实现代码之前'],
  ['verification-before-completion', '宣称工作完成/已修复/测试通过之前— 先运行验证命令拿证据'],
  ['writing-plans', '有规格/需求用于多步骤任务时, 动手写代码之前'],
  ['executing-plans', '有书面实现计划需在单独会话执行且有审查检查点时'],
  ['subagent-driven-development', '在当前会话执行含独立任务的实现计划时'],
  ['dispatching-parallel-agents', '面对 2+ 个可独立进行、无共享状态的并行任务时'],
  ['using-git-worktrees', '需与当前工作区隔离的功能开发/执行计划前'],
  ['requesting-code-review', '完成任务/重要功能/合并前, 验证成果符合要求'],
  ['receiving-code-review', '收到 review 反馈后、实施建议前— 严谨验证而非盲从'],
  ['finishing-a-development-branch', '实现完成、测试全过、需决定如何集成时'],
  ['writing-skills', '创建/编辑技能或部署前验证技能有效性时'],
  ['mcp-builder', '系统化构建生产级 MCP 服务器/工具时'],
  ['workflow-runner', '运行 agency-orchestrator YAML 多角色工作流时'],
  ['chinese-code-review', '显式 /chinese-code-review 时— 中文 review 话术与分级'],
  ['chinese-commit-conventions', '显式 /chinese-commit-conventions 时— 中文提交规范'],
  ['chinese-documentation', '显式 /chinese-documentation 时— 中文排版规范'],
  ['chinese-git-workflow', '显式 /chinese-git-workflow 时— 国内 Git 平台配置'],
  ['using-superpowers', '(元技能)路由失效时的兜底: 完整技能使用方法论'],
]

const routerBlock = `<superpowers_router>
你有 20 个流程技能(superpowers),按渐进披露加载——只在命中场景时读取,平时零成本:
${CATALOG.map(([n, d]) => `- ${n}: ${d}`).join('\n')}
vault: ${vault}/<name>/SKILL.md

规则:
1. 任务开始前扫一遍清单,命中场景 → 立即 Read ${vault}/<name>/SKILL.md 并遵循(技能正文未加载前不要凭记忆模仿)
2. 多个命中按上表顺序取最相关的一个,用完即继续
3. 清单未覆盖但疑似有既有流程(创建/审查/计划/调试类工作)→ Read ${vault}/using-superpowers/SKILL.md 查方法论
</superpowers_router>`

export const SpRouterPlugin = async () => ({
  'experimental.chat.messages.transform': async (_input, output) => {
    if (!output.messages?.length) return
    const first = output.messages.find(m => m.info?.role === 'user')
    if (!first?.parts?.length) return
    if (first.parts.some(p => p.type === 'text' && p.text.includes('superpowers_router'))) return // 幂等
    first.parts.unshift({ type: 'text', text: routerBlock })
  },
})

export default SpRouterPlugin
