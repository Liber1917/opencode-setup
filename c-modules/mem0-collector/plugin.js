/**
 * mem0-collector — 偏好自动收集插件(本地记忆版)
 *
 * 演进: mem0 三件套(CLI/MCP/collector 云端链)退役——云端外发违背零依赖零外发
 * 立场,改为直接写本地 docs/memory/memory-log.jsonl(murillovp/persistent-memory
 * 格式,MIT)。收集→存储→TUI 知会三环保留:
 *   收集(session.idle 启发式提取,逻辑不变)→ 存储(jsonl 冷追加)→
 *   TUI 可见(下次会话首条 user 消息注入知会,注入即消费)。
 * 同时承接 facts.md 50 行 fact-archive 轮换(照 murillovp 设计原样实现:
 * 超限时最旧事实搬入 jsonl(type:"fact-archive")并从 facts.md 删除)。
 *
 * 事件依据(opencode 1.18.30 二进制+plugin SDK 复核, 不猜): 无 session.end;
 * 最近事件 session.idle(schema {sessionID}), 每轮应答结束触发。
 *
 * 约束: 零依赖零外发(node 内置 fs,不出本机); 启发式宁缺勿滥(不做 NLP);
 * 密钥样文本一律不提取(隐私); 全链路 fail-open(插件永不抛)。
 * 本地插件形态: plugins/ 顶层 .ts 唯一正确(sp-router.ts/rtk.ts 先例)。
 * 数据位: 标记/通知 → ~/.local/share/opencode/(MEM0_COLLECTOR_DATA_DIR 可重定向);
 *         记忆  → ~/.config/opencode/docs/memory/(MEM0_COLLECTOR_MEMORY_DIR 可重定向)。
 */
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const WINDOW = 10        // 扫描窗口: 最后 N 条 user+assistant 消息
const CAP = 3            // 每会话收集上限(防爆)
const FACTS_MAX_LINES = 50 // facts.md 上限(murillovp 契约)

// 句级意图启发式(宁缺勿滥: 只认明确意图词, 不做语义猜测)
const PREFERENCE = /(我喜欢|我爱|我偏好|我讨厌|我不喜欢|我不爱|请?记住|记一下|以后[要请记得别不要总一直]|别再|不要再|不要|总是|每次都|一律)/
const ENV_FACT = /(用的是|装的是|目录在|路径是|环境变量|默认编辑器|默认终端|工作目录)/
const SECRET = /(sk-[A-Za-z0-9_-]{8,}|ghp_[A-Za-z0-9]{16,}|AKIA[A-Z0-9]{12,}|-----BEGIN|password|密钥|token\s*[:=]|Bearer )/i

const dataDir = () => process.env.MEM0_COLLECTOR_DATA_DIR
  || path.join(os.homedir(), '.local', 'share', 'opencode')

const memoryDir = () => process.env.MEM0_COLLECTOR_MEMORY_DIR
  || path.join(process.env.OPENCODE_CONFIG_DIR || path.join(os.homedir(), '.config', 'opencode'), 'docs', 'memory')

// murillovp 格式: {"date":"YYYY-MM-DD","type":"...","summary":"..."}(append-only)
const entry = (type, summary) =>
  JSON.stringify({ date: new Date().toISOString().slice(0, 10), type, summary })

// 冷追加: 先读旧文补尾换行再写(murillovp 实测坑——文件失尾换行时直接追加
// 会把新 JSON 粘上末行,静默腐蚀 JSONL)
const appendLog = (type, summary) => {
  const jsonl = path.join(memoryDir(), 'memory-log.jsonl')
  fs.mkdirSync(memoryDir(), { recursive: true })
  let prev = ''
  try { prev = fs.readFileSync(jsonl, 'utf8') } catch { /* 首建 */ }
  if (prev && !prev.endsWith('\n')) prev += '\n'
  fs.writeFileSync(jsonl, prev + entry(type, summary) + '\n')
}

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

// 轮换规划(纯函数, 单测入口): 超过 maxLines 时, 从最旧事实(文件序在最前)起
// 逐条搬出, 直到回到上限内; 标题/注释行不是事实, 永不搬。
// 返回 { keepLines: 轮换后保留的行数组, archives: 搬出的事实文本数组 }
export const planFactRotation = (content, maxLines = FACTS_MAX_LINES) => {
  const lines = content.split('\n')
  if (lines.length && lines[lines.length - 1] === '') lines.pop()
  if (lines.length <= maxLines) return { keepLines: lines, archives: [] }
  // 标记每行是否为"事实行": 非空、非标题、非注释(含跨行 <!-- --> 块内)
  const isFact = []
  let inComment = false
  for (const l of lines) {
    const opens = (l.match(/<!--/g) || []).length
    const closes = (l.match(/-->/g) || []).length
    if (inComment) { isFact.push(false); inComment = closes > opens ? false : inComment; continue }
    const stripped = l.trim()
    if (opens > 0) {
      if (closes < opens) inComment = true
      isFact.push(false)
      continue
    }
    isFact.push(stripped !== '' && !stripped.startsWith('#'))
  }
  // 从最旧(最前)事实行起搬,直到总行数回到上限内(null 占位不缩 keep.length,单独计数)
  const keep = [...lines]
  const archives = []
  let archived = 0
  for (let i = 0; i < keep.length && (keep.length - archived) > maxLines; i++) {
    if (!isFact[i]) continue
    archives.push(keep[i].trim().replace(/^[-*]\s+/, ''))
    keep[i] = null // 占位,循环末统一压掉(保持非事实行原位)
    archived++
  }
  return { keepLines: keep.filter((l) => l !== null), archives }
}

// 轮换执行(带副作用, fail-open): facts.md 超限时最旧事实搬入 jsonl 并从文件删除
const rotateFacts = () => {
  const factsPath = path.join(memoryDir(), 'facts.md')
  let content = ''
  try { content = fs.readFileSync(factsPath, 'utf8') } catch { return 0 }
  const { keepLines, archives } = planFactRotation(content)
  if (archives.length === 0) return 0
  for (const fact of archives) appendLog('fact-archive', fact)
  fs.writeFileSync(factsPath, keepLines.join('\n') + '\n')
  return archives.length
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
        // 增量收集: 首次命中后记录已提取句子,后续 idle 只提新增偏好句(同会话可多次,
        // 不同偏好各归各位——修"一次性封死丢早期偏好"缺陷)
        const res = await client?.session?.messages?.({ sessionID })
        const allItems = extractFromMessages(res?.data ?? res ?? [])
        // 先做 facts.md 轮换房务(与收集独立——文件超限就该搬,不等新偏好)
        rotateFacts()
        if (allItems.length === 0) return // 无匹配静默
        // 增量: 读已提取记录,只存新增偏好句(同会话可多次收集,不同偏好各归各位)
        const marker = path.join(markerDir, `${sessionID}.json`)
        let alreadyStored = []
        try { alreadyStored = JSON.parse(fs.readFileSync(marker, 'utf8')).stored ?? [] } catch {}
        const newItems = allItems.filter((s) => !alreadyStored.includes(s))
        if (newItems.length === 0) return // 本轮无新增
        const stored = []
        for (const s of newItems) {
          try { appendLog('user-preference', s); stored.push(s) } catch { /* 单条失败不阻断其余 */ }
        }
        if (stored.length === 0) return // 全败: 不写标记, 下次 idle 重试
        fs.mkdirSync(markerDir, { recursive: true })
        fs.writeFileSync(marker, JSON.stringify({ stored: [...alreadyStored, ...stored], at: Date.now() }))
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
            `(已存本地 ${path.join(memoryDir(), 'memory-log.jsonl')};检索: grep -i "词" 该文件)`,
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
