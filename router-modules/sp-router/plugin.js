/**
 * sp-router — superpowers-zh 路由模式插件(渐进披露移植)
 *
 * 替代 superpowers 官方插件的急加载(20 skill 描述进 system prompt + using-superpowers 全文进首消息 ≈9.2k token):
 *   ① 不把 skills 目录注册进 opencode 扫描路径(描述税归零)
 *   ② 首条用户消息只注入精简路由块(v2: 纪律两行 + top-3 候选 + 兜底)
 *   ③ agent 命中场景 → Read <vault>/<name>/SKILL.md 按需加载正文(等价 Claude Code 渐进披露)
 *
 * v2: 启动时动态 import matcher.mjs 并读 index.yaml(候选: 插件同目录 → vault);
 *     首条 user 消息经 route() 得 top-3 注入 v2 块。SP_ROUTER_V1=1 / 无 top-3 /
 *     任何加载失败 → 回退 v1 全量清单, 不抛。幂等: 注入块末尾带
 *     <!-- sp-router:superpowers_router vN --> 标记, includes('superpowers_router') 检查。
 *
 * 用法: opencode.json plugin 数组移除 superpowers@..., 加入本插件路径;
 *       superpowers skills 克隆/留在 vault 路径(本插件只读, 不安装不更新)。
 */
import fs from 'node:fs'
import path from 'path'
import { fileURLToPath } from 'node:url'

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

// 纪律两行(v1 与 v2 块共用, 逐字保留)
const DISCIPLINE = [
  `每次回复前(包括澄清性提问)必须先扫描下方技能清单。命中(含隐性命中——用户描述症状而非点名流程)→ 立即 Read ${vault}/<name>/SKILL.md,先读正文再行动,未读前不要凭记忆模仿流程。`,
  `合理化跳过的红旗信号(出现即视为命中): "这是简单问题" / "不需要正式流程" / "我先做这一件事" / "我记得流程大概是什么"。`,
]

const routerBlock = `<EXTREMELY_IMPORTANT>
${DISCIPLINE[0]}
${DISCIPLINE[1]}
清单: ${CATALOG.map(([n]) => n).join(', ')}
vault: ${vault}/<name>/SKILL.md
命中多个取最相关的一个;疑似有流程但清单对不上 → Read ${vault}/using-superpowers/SKILL.md 查方法论。
</EXTREMELY_IMPORTANT>
<skill_catalog>
${CATALOG.map(([n, d]) => `- ${n}: ${d}`).join('\n')}
</skill_catalog>
<!-- sp-router:superpowers_router v1 -->`

// v2 精简块: 纪律两行 + top-3 候选(命中词至多 3 个)+ 兜底行
const v2Block = (top, indexPathUsed, skillCount) => `<EXTREMELY_IMPORTANT>
${DISCIPLINE[0]}
${DISCIPLINE[1]}
候选(按路由分):
${top.map((r, i) => `${i + 1}. ${r.name} [${r.hits.slice(0, 3).join(' ')}] — Read ${vault}/${r.name}/SKILL.md`).join('\n')}
以上不覆盖时 Read ${indexPathUsed} 全量匹配(${skillCount} 技能)。
</EXTREMELY_IMPORTANT>
<!-- sp-router:superpowers_router v2 -->`

export const SpRouterPlugin = async () => {
  // 启动: 动态引 matcher + 读 index.yaml(候选: 插件同目录 → vault);任何失败 → console.error 一行, v1 兜底
  let routeFn = null
  let loadedIndex = null
  let loadedIndexPath = null
  try {
    const matcher = await import(new URL('./matcher.mjs', import.meta.url).href)
    const pluginDir = path.dirname(fileURLToPath(import.meta.url))
    const candidates = [path.join(pluginDir, 'index.yaml'), path.join(vault, 'index.yaml')]
    for (const cand of candidates) {
      let raw
      try { raw = fs.readFileSync(cand, 'utf8') } catch { continue }
      const idx = matcher.parseIndex(raw)
      if (!Array.isArray(idx?.skills) || idx.skills.length === 0) continue
      routeFn = matcher.route
      loadedIndex = idx
      loadedIndexPath = cand
      break
    }
    if (!loadedIndex) console.error(`[sp-router] v2 索引未就绪(候选均不可用: ${candidates.join(' | ')}),回退 v1 清单`)
  } catch (e) {
    console.error(`[sp-router] v2 加载失败(${e?.message ?? e}),回退 v1 清单`)
  }

  return {
    'experimental.chat.messages.transform': async (_input, output) => {
      if (!output.messages?.length) return
      const first = output.messages.find(m => m.info?.role === 'user')
      if (!first?.parts?.length) return
      if (first.parts.some(p => p.type === 'text' && p.text.includes('superpowers_router'))) return // 幂等
      let block = routerBlock // v1 兜底
      if (process.env.SP_ROUTER_V1 !== '1' && routeFn) {
        try {
          let text = first.parts.filter(p => p.type === 'text').map(p => p.text).join('')
          text = text.replace(/<!-- sp-router:[^>]*-->/g, '')
          const top = routeFn(text, loadedIndex)
          if (top.length > 0) block = v2Block(top, loadedIndexPath, loadedIndex.skills.length)
        } catch (e) {
          console.error(`[sp-router] v2 路由失败(${e?.message ?? e}),回退 v1 清单`)
        }
      }
      first.parts.unshift({ type: 'text', text: block })
    },
  }
}

export default SpRouterPlugin
