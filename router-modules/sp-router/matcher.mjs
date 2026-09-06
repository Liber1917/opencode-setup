/**
 * matcher.mjs — sp-router v2 路由匹配器(零依赖, ESM)
 *
 * 三个导出:
 *   tokenize(text)   文本 → 去重 token 数组(首现序)。ASCII: lowercase 后 /[a-z0-9]+/;
 *                    CJK 连续段: 长度 1 → 该单字, ≥2 → 二字滑窗 bigram。
 *   parseIndex(text) 极简 YAML 子集解析(解析器抄自同目录 validate.mjs, 不 import——其顶层有 main 副作用),
 *                    返回 {skills:[{name,path,tier,domain,signals,relations,weight}]}, 缺省字段给默认。
 *   route(query, index) 撒种(name+3/strong+2/weak+1) → 一层传播(co-requires ×0.5 /
 *                    supersedes 转移 ×0.7 清零 / conflicts-with 低者清零) → ×weight 取 top-3。
 */
// ---------------------------------------------------------------------------
// tokenize
// ---------------------------------------------------------------------------

const ASCII_WORD = /[a-z0-9]+/g
const CJK_RUN = /[\u3400-\u4dbf\u4e00-\u9fff]+/g

export function tokenize(text) {
  if (text == null) return []
  const s = String(text).toLowerCase()
  const spans = []
  for (const m of s.matchAll(ASCII_WORD)) spans.push({ pos: m.index, cjk: false, text: m[0] })
  for (const m of s.matchAll(CJK_RUN)) spans.push({ pos: m.index, cjk: true, text: m[0] })
  spans.sort((a, b) => a.pos - b.pos)
  const seen = new Set()
  const out = []
  const push = (t) => { if (!seen.has(t)) { seen.add(t); out.push(t) } }
  for (const sp of spans) {
    if (!sp.cjk || sp.text.length === 1) push(sp.text)
    else for (let i = 0; i + 1 < sp.text.length; i++) push(sp.text.slice(i, i + 2))
  }
  return out
}

// ---------------------------------------------------------------------------
// 极简 YAML 子集解析器(与 validate.mjs 同款: 2 空格缩进 / "- " 列表 / 行内 [a, b] 数组
// 与 {k: v} flow map / # 注释;块式与单行 flow 式条目均可)
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
      p.nodes[p.i] = { ...nd, dash: null, indent: indent + 2 }
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
// parseIndex: 解析 + 规整(缺省容错)
// ---------------------------------------------------------------------------

const strArr = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === 'string') : [])

export function parseIndex(text) {
  const data = parseYaml(String(text ?? ''))
  const raw = Array.isArray(data?.skills) ? data.skills : []
  const skills = raw
    .filter((e) => e && typeof e === 'object' && !Array.isArray(e) && typeof e.name === 'string' && e.name.trim() !== '')
    .map((e) => ({
      name: e.name,
      path: typeof e.path === 'string' ? e.path : '',
      tier: e.tier,
      domain: e.domain,
      signals: {
        strong: strArr(e.signals?.strong),
        weak: strArr(e.signals?.weak),
      },
      relations: {
        'co-requires': strArr(e.relations?.['co-requires']),
        supersedes: strArr(e.relations?.supersedes),
        'conflicts-with': strArr(e.relations?.['conflicts-with']),
      },
      weight: typeof e.weight === 'number' && Number.isFinite(e.weight) && e.weight > 0 ? e.weight : 1,
    }))
  return { skills }
}

// ---------------------------------------------------------------------------
// route: 撒种 → 一层传播 → 终分排序 top-3
// ---------------------------------------------------------------------------

export function route(query, index) {
  const qt = new Set(tokenize(query))
  if (qt.size === 0) return []
  const skills = Array.isArray(index?.skills) ? index.skills : []

  const seed = new Map()
  const score = new Map()
  const hitsMap = new Map()
  for (const s of skills) {
    seed.set(s.name, 0)
    score.set(s.name, 0)
    hitsMap.set(s.name, [])
  }
  const overlaps = (tokens) => tokens.some((t) => qt.has(t))
  const addHit = (name, raw) => {
    const h = hitsMap.get(name)
    if (!h.includes(raw)) h.push(raw)
  }
  // 撒分: seed 记撒种分(传播的源), score 同步累加(即当前总分)
  const bump = (name, pts) => {
    seed.set(name, seed.get(name) + pts)
    score.set(name, score.get(name) + pts)
  }

  // 撒种: name +3 / strong +2 / weak +1, hits 记原串(去重保持序)
  for (const s of skills) {
    if (overlaps(tokenize(s.name))) {
      bump(s.name, 3)
      addHit(s.name, s.name)
    }
    for (const sig of s.signals?.strong ?? []) {
      if (overlaps(tokenize(sig))) {
        bump(s.name, 2)
        addHit(s.name, sig)
      }
    }
    for (const sig of s.signals?.weak ?? []) {
      if (overlaps(tokenize(sig))) {
        bump(s.name, 1)
        addHit(s.name, sig)
      }
    }
  }

  // 传播 a) co-requires: 种子分>0 的 A 给每个 B 加 seed[A]×0.5
  for (const s of skills) {
    const sa = seed.get(s.name)
    if (sa <= 0) continue
    for (const b of s.relations?.['co-requires'] ?? []) {
      if (!score.has(b)) continue
      score.set(b, score.get(b) + sa * 0.5)
    }
  }

  // 传播 b) supersedes: 双方种子分均>0 才转移, B 分×0.7 给 A, B 清零(含已得增益)
  for (const s of skills) {
    const sa = seed.get(s.name)
    for (const b of s.relations?.supersedes ?? []) {
      if (!seed.has(b)) continue
      const sb = seed.get(b)
      if (sa > 0 && sb > 0) {
        score.set(s.name, score.get(s.name) + sb * 0.7)
        score.set(b, 0)
      }
    }
  }

  // 传播 c) conflicts-with: 双方分>0 时低分者=0; 平局 B(被引用方)=0
  for (const s of skills) {
    for (const b of s.relations?.['conflicts-with'] ?? []) {
      if (!score.has(b)) continue
      const fa = score.get(s.name)
      const fb = score.get(b)
      if (fa > 0 && fb > 0) {
        if (fb <= fa) score.set(b, 0)
        else score.set(s.name, 0)
      }
    }
  }

  // 终分 = score × weight, 四舍五入 2 位; 过滤 0; 分降序, 平局 name 升序; top-3
  const round2 = (x) => Math.round(x * 100) / 100
  const ranked = []
  for (const s of skills) {
    const w = typeof s.weight === 'number' && Number.isFinite(s.weight) && s.weight > 0 ? s.weight : 1
    const finalScore = round2(score.get(s.name) * w)
    if (finalScore > 0) ranked.push({ name: s.name, score: finalScore, hits: hitsMap.get(s.name) })
  }
  ranked.sort((a, b) => (b.score - a.score) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
  return ranked.slice(0, 3)
}
