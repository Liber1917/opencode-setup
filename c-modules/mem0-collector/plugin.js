/**
 * mem0-collector — 自研偏好自动收集插件(替代 npm mem0-collector@0.7.0 半成品)
 *
 * 退役依据(源码审计): npm 包三环断裂——①TUI 完全静默(event hook 仅写本地文件)
 * ②不写 mem0(storeMemory 只落 pending_sync/*.json 队列)③声称 repo 404。
 * 自研闭合三环: 收集(session.idle 启发式提取)→ 存储(mem0 add)→ TUI 可见
 * (下次会话首条 user 消息注入知会——event hook 无输出面, 延迟通知)。
 *
 * 事件依据(opencode 1.18.30 二进制+plugin SDK 复核, 不猜): 无 session.end;
 * 最近事件 session.idle(schema {sessionID}), 每轮应答结束触发。收集策略:
 * 每次 idle 扫最后 10 条 user/assistant、仅提取 user 句; 首次命中即写会话标记
 * (每会话至多收集一次, 上限 3 条); 无命中不写标记——晚出偏好在后续 idle 续捕。
 *
 * 约束: 零 npm 依赖(node 内置); 启发式宁缺勿滥(不做 NLP); 密钥样文本一律
 * 不提取(隐私); 全链路 fail-open(插件永不抛)。
 * 本地插件形态: plugins/ 顶层 .ts 唯一正确(sp-router.ts/rtk.ts 先例), 不进
 * plugin 数组。数据位 ~/.local/share/opencode/(MEM0_COLLECTOR_DATA_DIR 可重定向)。
 */
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const WINDOW = 10        // 扫描窗口: 最后 N 条 user+assistant 消息
const CAP = 3            // 每会话收集上限(防爆)
const MEM0_TIMEOUT = 10_000

// 句级意图启发式(宁缺勿滥: 只认明确意图词, 不做语义猜测)
const PREFERENCE = /(我喜欢|我爱|我偏好|我讨厌|我不喜欢|我不爱|请?记住|记一下|以后[要请记得别不要总一直]|别再|不要再|不要|总是|每次都|一律)/
const ENV_FACT = /(用的是|装的是|目录在|路径是|环境变量|默认编辑器|默认终端|工作目录)/
const SECRET = /(sk-[A-Za-z0-9_-]{8,}|ghp_[A-Za-z0-9]{16,}|AKIA[A-Z0-9]{12,}|-----BEGIN|password|密钥|token\s*[:=]|Bearer )/i

const dataDir = () => process.env.MEM0_COLLECTOR_DATA_DIR
  || path.join(os.homedir(), '.local', 'share', 'opencode')

// 剥除插件注入注释块(本插件知会/env/router 等)后按中英句读切分
const splitSentences = (text) => String(text ?? '')
  .replace(/<!--[\s\S]*?-->/g, ' ')
  .split(/[。！？!?;\n]+|\.(?=\s)/)
  .map((s) => s.trim())
  .filter(Boolean)

// 从消息列表提取候选句(纯函数, 单测入口): 仅 user 角色、窗口内、句长 6..120、
// 非密钥样、命中偏好/环境事实模式; 去重后封顶 CAP
export const extractFromMessages = (messages = []) => {
  const seen = new Set()
  const out = []
  for (const m of (Array.isArray(messages) ? messages : []).slice(-WINDOW)) {
    if ((m?.info?.role ?? m?.role) !== 'user') continue
    const text = (m?.parts ?? []).filter((p) => p?.type === 'text').map((p) => p?.text ?? '').join('\n')
    for (const s of splitSentences(text)) {
      if (s.length < 6 || s.length > 120) continue
      if (SECRET.test(s) || !(PREFERENCE.test(s) || ENV_FACT.test(s))) continue
      if (!seen.has(s)) { seen.add(s); out.push(s) }
      if (out.length >= CAP) return out
    }
  }
  return out
}

let mem0Path = null, mem0Checked = false
const mem0Available = () => {
  if (!mem0Checked) {
    mem0Checked = true
    for (const p of (process.env.PATH || '').split(path.delimiter).filter(Boolean)) {
      try {
        const full = path.join(p, 'mem0')
        if (fs.existsSync(full) && fs.accessSync(full, fs.constants.X_OK) === undefined) { mem0Path = full; break }
      } catch { /* 不可读目录跳过 */ }
    }
    if (!mem0Path) console.error('[mem0-collector] mem0 CLI 不在 PATH, 插件休眠(装后自动恢复)')
  }
  return mem0Path !== null
}

const addMemory = (text) => {
  try {
    execFileSync('mem0', ['add', text], { timeout: MEM0_TIMEOUT, stdio: 'ignore' })
    return true
  } catch (e) {
    console.error(`[mem0-collector] mem0 add 失败(fail-open): ${e?.message ?? e}`)
    return false
  }
}

export const Mem0CollectorPlugin = async ({ client }) => {
  const markerDir = path.join(dataDir(), 'mem0-collector-markers')
  const noticeFile = path.join(dataDir(), 'mem0-collector-notice.json')
  const MARK = 'mem0-collector:notice'

  return {
    event: async ({ event }) => {
      try {
        if (event?.type !== 'session.idle') return
        const sessionID = event?.properties?.sessionID
        if (!sessionID) return
        const marker = path.join(markerDir, `${sessionID}.json`)
        if (fs.existsSync(marker)) return // 幂等: 每会话至多收集一次
        const res = await client?.session?.messages?.({ sessionID })
        const items = extractFromMessages(res?.data ?? res ?? [])
        if (items.length === 0 || !mem0Available()) return // 无匹配静默; CLI 缺席休眠
        const stored = items.filter(addMemory)
        if (stored.length === 0) return // mem0 全败: 不写标记, 下次 idle 重试
        fs.mkdirSync(markerDir, { recursive: true })
        fs.writeFileSync(marker, JSON.stringify({ stored, at: Date.now() }))
        fs.writeFileSync(noticeFile, JSON.stringify({ sessionID, items: stored, at: Date.now() }))
      } catch (e) {
        console.error(`[mem0-collector] 收集失败(fail-open): ${e?.message ?? e}`)
      }
    },

    // TUI 可见(延迟通知): 下次会话首条 user 消息注入一行知会, 注入即消费
    'experimental.chat.messages.transform': async (_input, output) => {
      try {
        let notice = null
        try { notice = JSON.parse(fs.readFileSync(noticeFile, 'utf8')) } catch { return }
        if (!notice?.items?.length) return
        const first = output?.messages?.find((m) => m.info?.role === 'user')
        if (!first?.parts?.length) return
        if (first.parts.some((p) => p.type === 'text' && p.text?.includes(MARK))) return // 幂等
        first.parts.unshift({
          type: 'text',
          text: [
            `<!--${MARK}-->`,
            `📝 mem0-collector: 上次会话(${String(notice.sessionID ?? '').slice(-8)})自动收集了 ${notice.items.length} 条记忆:`,
            ...notice.items.map((s) => `- ${s}`),
            '(管理: mem0 search \'查询\' / 删除: mem0 delete <id>)',
          ].join('\n'),
        })
        fs.unlinkSync(noticeFile)
      } catch (e) {
        console.error(`[mem0-collector] 知会注入失败(fail-open): ${e?.message ?? e}`)
      }
    },
  }
}

export default Mem0CollectorPlugin
