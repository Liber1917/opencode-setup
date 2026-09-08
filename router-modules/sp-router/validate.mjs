#!/usr/bin/env node
/**
 * validate.mjs — sp-router v2 index.yaml 校验器(零依赖,纯 Node)
 *
 * 用法:
 *   node validate.mjs <index.yaml> [--vault <vault绝对路径>]
 *
 * 检查项(ERROR 拦截 / WARN 只提示):
 *   ① YAML 可解析 —— 内置极简子集解析器(2 空格缩进 / "- " 列表 / 行内 [a, b] 数组与
 *      {k: v} flow map / # 注释;块式与单行 flow 式条目均可),不依赖 PyYAML / js-yaml
 *   ② name 唯一且非空                       ⑥ weight 为正数
 *   ③ path 非空字符串                       ⑦ tier ∈ {basic,pro} / domain 枚举合法
 *   ④ --vault 给定时逐个检查 path 文件存在    ⑧ disabled: true 不被他人 co-requires/supersedes 引用
 *   ⑤ relations 引用的 name 都在索引里
 *   WARN 质量提示(不拦): 无 weak 信号 / strong 信号 <3 / 技能已停用
 *
 * 输出: 每项一行(WARN/ERROR 前缀);exit code = ERROR 数 > 0 ? 1 : 0
 */
import fs from 'node:fs'
import path from 'node:path'

const TIERS = new Set(['basic', 'pro'])
// domain 枚举(与 index.yaml 编目实际词表对齐;需要扩展时改这里)
const DOMAINS = new Set(['process', 'writing', 'review', 'testing', 'tooling', 'meta'])
const REL_KEYS = ['co-requires', 'supersedes', 'conflicts-with']

// ---------------------------------------------------------------------------
// 极简 YAML 子集解析器(schema 限定: 2 空格缩进 / "- " 列表项 / 行内 [a, b] / # 注释)
// ---------------------------------------------------------------------------

function stripComment(raw) {
  let q = null
  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i]
    if (q) { if (ch === q) q = null } else if (ch === '"' || ch === "'") q = ch
    else if (ch === '#' && (i === 0 || raw[i - 1] === ' ' || raw[i - 1] === '\t')) return raw.slice(0, i)
  }
  return raw
}

function splitTopLevel(s) {
  const out = []
  let cur = ''
  let q = null
  let depth = 0
  for (const ch of s) {
    if (q) { cur += ch; if (ch === q) q = null; continue }
    if (ch === '"' || ch === "'") { q = ch; cur += ch; continue }
    if (ch === '[' || ch === '{') depth++
    else if (ch === ']' || ch === '}') depth--
    if (ch === ',' && depth === 0) { out.push(cur); cur = '' } else cur += ch
  }
  out.push(cur)
  return out
}

function unquote(s) {
  const t = s.trim()
  if (t.length >= 2 && ((t[0] === '"' && t[t.length - 1] === '"') || (t[0] === "'" && t[t.length - 1] === "'"))) {
    return t.slice(1, -1)
  }
  return t
}

function parseScalar(raw, where) {
  const v = raw.trim()
  if (v.startsWith('[')) {
    if (!v.endsWith(']')) throw new SyntaxError(`${where}: 行内数组未闭合: ${v.slice(0, 40)}`)
    const inner = v.slice(1, -1).trim()
    if (inner === '') return []
    return splitTopLevel(inner).map((s) => s.trim()).filter((s) => s !== '').map((s) => parseScalar(s, where))
  }
  if (v.startsWith('{')) {
    // 行内映射(flow map): {k: v, k2: [a, b]} —— index.yaml 单行条目用
    if (!v.endsWith('}')) throw new SyntaxError(`${where}: 行内映射未闭合: ${v.slice(0, 40)}`)
    const inner = v.slice(1, -1).trim()
    const out = {}
    if (inner === '') return out
    for (const pair of splitTopLevel(inner)) {
      const t = pair.trim()
      if (t === '') continue
      const ci = t.indexOf(':')
      if (ci < 0) throw new SyntaxError(`${where}: 行内映射缺少冒号: ${t.slice(0, 40)}`)
      const key = unquote(t.slice(0, ci))
      const rest = t.slice(ci + 1).trim()
      out[key] = rest === '' ? null : parseScalar(rest, where)
    }
    return out
  }
  if (v.length >= 2 && ((v[0] === '"' && v[v.length - 1] === '"') || (v[0] === "'" && v[v.length - 1] === "'"))) {
    return v.slice(1, -1)
  }
  if (v === 'true') return true
  if (v === 'false') return false
  if (v === 'null' || v === '~') return null
  if (/^-?\d+$/.test(v)) return parseInt(v, 10)
  if (/^-?\d+\.\d+$/.test(v)) return parseFloat(v)
  return v
}

function parseYaml(text) {
  const nodes = []
  const lines = text.replace(/^\uFEFF/, '').split(/\r?\n/)
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes('\t')) throw new SyntaxError(`line ${i + 1}: tab 字符不支持(子集仅空格缩进)`)
    const s = stripComment(lines[i])
    if (s.trim() === '') continue
    const indent = s.length - s.trimStart().length
    const body = s.trim()
    if (body === '-' || body.startsWith('- ')) {
      nodes.push({ n: i + 1, dash: indent, indent: indent + 2, text: body.slice(1).trim() })
    } else {
      nodes.push({ n: i + 1, dash: null, indent, text: body })
    }
  }
  const p = { nodes, i: 0 }
  if (p.nodes.length === 0) return {}
  const value = parseBlock(p)
  if (p.i < p.nodes.length) {
    throw new SyntaxError(`line ${p.nodes[p.i].n}: 意外的内容(缩进与上下文不匹配)`)
  }
  return value
}

function parseBlock(p) {
  const nd = p.nodes[p.i]
  return nd.dash !== null ? parseList(p, nd.dash) : parseMap(p, nd.indent)
}

// "- xxx: yyy" 形式: 列表项的 map 首行落在 dash 上;行首 { / [ 视为行内集合交 parseScalar
const MAP_START = /^(?:"[^"]*"|'[^']*'|[^:\s"{[][^:]*):(?:\s|$)/

function parseList(p, indent) {
  const out = []
  while (p.i < p.nodes.length && p.nodes[p.i].dash === indent) {
    const nd = p.nodes[p.i]
    if (nd.text === '') {
      p.i++
      const nxt = p.nodes[p.i]
      if (nxt && (nxt.dash !== null ? nxt.dash > indent : nxt.indent > indent)) out.push(parseBlock(p))
      else out.push(null)
    } else if (MAP_START.test(nd.text)) {
      p.nodes[p.i] = { ...nd, dash: null, indent: indent + 2 } // 视作 indent+2 的普通 key 行
      out.push(parseMap(p, indent + 2))
    } else {
      p.i++
      out.push(parseScalar(nd.text, `line ${nd.n}`))
    }
  }
  return out
}

function parseMap(p, indent) {
  const out = {}
  while (p.i < p.nodes.length) {
    const nd = p.nodes[p.i]
    if (nd.indent !== indent || nd.dash !== null) break
    p.i++
    const m = nd.text.match(/^((?:"[^"]*")|(?:'[^']*')|[^:]+):\s*(.*)$/)
    if (!m) throw new SyntaxError(`line ${nd.n}: 无法解析 "key: value" 行: ${nd.text}`)
    const key = unquote(m[1])
    const rest = m[2].trim()
    if (rest === '') {
      const nxt = p.nodes[p.i]
      const child = nxt && (nxt.dash !== null ? nxt.dash > indent : nxt.indent > indent)
      const sameList = nxt && nxt.dash === indent // YAML 允许列表与 key 同缩进
      out[key] = child || sameList ? parseBlock(p) : null
    } else {
      out[key] = parseScalar(rest, `line ${nd.n}`)
    }
  }
  return out
}

// ---------------------------------------------------------------------------
// 校验
// ---------------------------------------------------------------------------

const USAGE = '用法: node validate.mjs <index.yaml> [--vault <vault绝对路径>]'

function main() {
  const argv = process.argv.slice(2)
  let indexPath = null
  let vault = null
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--vault') {
      vault = argv[++i]
      if (!vault) { console.error(USAGE); process.exit(2) }
    } else if (argv[i] === '--help' || argv[i] === '-h') {
      console.log(USAGE); process.exit(0)
    } else if (indexPath === null) indexPath = argv[i]
    else { console.error(USAGE); process.exit(2) }
  }
  if (indexPath === null) { console.error(USAGE); process.exit(2) }

  const errors = []
  const warns = []
  const E = (msg) => errors.push(msg)
  const W = (msg) => warns.push(msg)

  // ① YAML 可解析
  let data
  try {
    data = parseYaml(fs.readFileSync(indexPath, 'utf8'))
  } catch (e) {
    if (e.code === 'ENOENT') { console.error(`ERROR 无法读取索引文件: ${indexPath}`); process.exit(1) }
    console.error(`ERROR YAML 解析失败: ${e.message}`)
    process.exit(1)
  }

  const skills = data?.skills
  if (!Array.isArray(skills)) {
    console.error('ERROR 索引缺少顶层 skills 列表(skills: [...])')
    process.exit(1)
  }

  // 第一遍: 单条目字段 + 收集 name / disabled
  const names = new Set()
  const disabledNames = new Set()
  const entries = skills.map((e, i) => {
    const tag = e && typeof e === 'object' && !Array.isArray(e) && typeof e.name === 'string' && e.name.trim() !== ''
      ? e.name.trim()
      : `#${i}`
    if (!e || typeof e !== 'object' || Array.isArray(e)) { E(`[${tag}] 条目不是对象`); return null }
    // ② name 唯一且非空
    if (typeof e.name !== 'string' || e.name.trim() === '') E(`[${tag}] name 缺失或为空`)
    else if (names.has(tag)) E(`[${tag}] name 重复`)
    else names.add(tag)
    // ③ path 非空字符串
    if (typeof e.path !== 'string' || e.path.trim() === '') E(`[${tag}] path 缺失或非字符串`)
    // ⑦ tier / domain 枚举
    if (!TIERS.has(e.tier)) E(`[${tag}] tier 非法: ${JSON.stringify(e.tier) ?? 'undefined'} (合法: ${[...TIERS].join('|')})`)
    if (!DOMAINS.has(e.domain)) {
      E(`[${tag}] domain 非法: ${JSON.stringify(e.domain) ?? 'undefined'} (合法: ${[...DOMAINS].join('|')})`)
    }
    // ⑥ weight 为正数
    if (typeof e.weight !== 'number' || !Number.isFinite(e.weight) || e.weight <= 0) {
      E(`[${tag}] weight 非法: ${JSON.stringify(e.weight) ?? 'undefined'} (须为正数)`)
    }
    // signals: 类型检查 + 质量提示
    if (e.signals != null) {
      if (typeof e.signals !== 'object' || Array.isArray(e.signals)) E(`[${tag}] signals 须为对象`)
      else for (const k of ['strong', 'weak']) {
        if (e.signals[k] != null && !Array.isArray(e.signals[k])) E(`[${tag}] signals.${k} 须为数组`)
      }
    }
    const strongCount = Array.isArray(e.signals?.strong) ? e.signals.strong.length : 0
    const hasWeak = Array.isArray(e.signals?.weak) && e.signals.weak.length > 0
    if (strongCount < 3) W(`[${tag}] strong 信号 ${strongCount}/3 —— 建议补足(质量提示)`)
    if (!hasWeak) W(`[${tag}] 无 weak 信号(质量提示)`)
    // 停用标记
    if (e.disabled === true) { disabledNames.add(tag); W(`[${tag}] 已停用(disabled: true),不参与路由`) }
    return { e, tag }
  })

  // 第二遍: ⑤ relations 闭合 + ⑧ 停用不被引用 + ④ path 文件存在
  for (const { e, tag } of entries) {
    if (!e) continue
    if (e.relations != null && (typeof e.relations !== 'object' || Array.isArray(e.relations))) {
      E(`[${tag}] relations 须为对象`)
      continue
    }
    for (const k of REL_KEYS) {
      const refs = e.relations?.[k]
      if (refs == null) continue
      if (!Array.isArray(refs)) { E(`[${tag}] relations.${k} 须为数组`); continue }
      for (const r of refs) {
        if (typeof r !== 'string' || r.trim() === '') { E(`[${tag}] relations.${k} 含非字符串引用: ${JSON.stringify(r)}`); continue }
        // ⑤ 引用闭合
        if (!names.has(r)) E(`[${tag}] relations.${k} 引用不存在的技能: ${r}`)
        // ⑧ 停用技能不被 co-requires/supersedes 引用(conflicts-with 豁免)
        if (disabledNames.has(r) && (k === 'co-requires' || k === 'supersedes')) {
          E(`[${tag}] relations.${k} 引用了停用技能: ${r}`)
        }
      }
    }
  }
  if (vault) {
    for (const { e, tag } of entries) {
      if (!e || typeof e.path !== 'string' || e.path.trim() === '') continue
      const full = path.join(vault, e.path.replace(/^\.\//, ''))
      let st = null
      try { st = fs.statSync(full) } catch { /* 不存在 */ }
      if (!st || !st.isFile()) E(`[${tag}] path 文件不存在: ${full}`)
    }
  }

  for (const msg of errors) console.log(`ERROR ${msg}`)
  for (const msg of warns) console.log(`WARN ${msg}`)
  console.log(`# 校验完成: skills=${skills.length} errors=${errors.length} warnings=${warns.length}${vault ? ` vault=${vault}` : ''}`)
  process.exit(errors.length > 0 ? 1 : 0)
}

main()
