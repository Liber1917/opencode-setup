#!/usr/bin/env node
/**
 * seed.mjs — sp-router v2 种子生成器(零依赖,纯 Node)
 *
 * 用法:
 *   node seed.mjs <vault绝对路径> <index.yaml> [--dry-run]
 *
 * 职责(计划流程图 2「启动对账」): 扫描 vault 下全部 SKILL.md(深度 1: <name>/SKILL.md;
 * 深度 2: <桶>/<name>/SKILL.md,如 superpowers 包的 skills/<name>/),
 * 找「vault 有、索引无」的技能 → 提取 frontmatter(name/description)→ 生成种子条目:
 *   - signals 初值 = description 分词(≥2 字符 ASCII 词,小写化 + 中文整词=连续汉字段≥2)
 *     全部进 weak(未人审,保守降权);strong 留空待人批
 *   - relations 空 / weight 0.5 初始降权 / tier basic / domain meta / _seed: true
 *   - 幂等: 索引中已存在(按 name 或 path 匹配,含已有 _seed 条目)的跳过
 *   - --dry-run 只打印不写入;不带则**追加**到 index.yaml 尾部(保留原内容)
 *   - fail-open: index.yaml 不存在 → 从空索引创建;SKILL.md 无 frontmatter → name 回退目录名
 */
import fs from 'node:fs'
import path from 'node:path'

const USAGE = '用法: node seed.mjs <vault绝对路径> <index.yaml> [--dry-run]'

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
      const sameList = nxt && nxt.dash === indent
      out[key] = child || sameList ? parseBlock(p) : null
    } else {
      out[key] = parseScalar(rest, `line ${nd.n}`)
    }
  }
  return out
}

// ---------------------------------------------------------------------------
// 种子逻辑
// ---------------------------------------------------------------------------

const FM_RE = /^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/

function parseFrontmatter(text, file) {
  const m = FM_RE.exec(text)
  if (!m) return null
  try {
    return parseYaml(m[1])
  } catch (e) {
    console.log(`WARN ${file}: frontmatter 无法解析(${e.message}),按无 frontmatter 处理`)
    return null
  }
}

// signals 初值: ≥2 字符 ASCII 词(小写化) + 中文整词(连续汉字段 ≥2)
function extractSignals(desc) {
  const sigs = []
  const seen = new Set()
  for (const w of desc.match(/[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*/g) || []) {
    const t = w.toLowerCase()
    if (t.length >= 2 && !seen.has(t)) { seen.add(t); sigs.push(t) }
  }
  for (const w of desc.match(/[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+/g) || []) {
    if (w.length >= 2 && !seen.has(w)) { seen.add(w); sigs.push(w) }
  }
  return sigs
}

const normPath = (p) => String(p).replace(/\\/g, '/').replace(/^\.\//, '')

function yquote(s) {
  if (s === '') return '""'
  // 呈现为数字/布尔/null 的字符串、含 YAML 特殊字符/空白、以 "- " 开头的 → 加引号
  if (/^[-+.]?[\d.]+([eE][-+]?\d+)?$/.test(s) || s === 'true' || s === 'false' || s === 'null') {
    return JSON.stringify(s)
  }
  if (/[:#\[\]{},&*!|>'"%@`\s]/.test(s) || /^- /.test(s)) return JSON.stringify(s)
  return s
}

function serializeEntry(e, li) {
  const a = ' '.repeat(li)
  const b = ' '.repeat(li + 2)
  const c = ' '.repeat(li + 4)
  const arr = (xs) => (xs.length > 0 ? `[${xs.map(yquote).join(', ')}]` : '[]')
  return [
    `${a}- name: ${yquote(e.name)}`,
    `${b}path: ${yquote(e.path)}`,
    `${b}tier: ${e.tier}`,
    `${b}domain: ${e.domain}`,
    `${b}signals:`,
    `${c}strong: ${arr(e.signals.strong)}`,
    `${c}weak: ${arr(e.signals.weak)}`,
    `${b}relations:`,
    `${c}co-requires: ${arr(e.relations['co-requires'])}`,
    `${c}supersedes: ${arr(e.relations.supersedes)}`,
    `${c}conflicts-with: ${arr(e.relations['conflicts-with'])}`,
    `${b}weight: ${e.weight}`,
    `${b}_seed: true`,
  ].join('\n')
}

function main() {
  const argv = process.argv.slice(2)
  const dryRun = argv.includes('--dry-run')
  const rest = argv.filter((a) => a !== '--dry-run')
  if (rest.length !== 2 || argv.includes('--help') || argv.includes('-h')) { console.error(USAGE); process.exit(2) }
  const [vaultArg, indexPath] = rest
  const vault = path.resolve(vaultArg)

  let vst = null
  try { vst = fs.statSync(vault) } catch { /* 不存在 */ }
  if (!vst || !vst.isDirectory()) {
    console.error(`ERROR vault 不是目录: ${vaultArg}`)
    process.exit(1)
  }

  // 读索引(不存在 → 空索引;语法坏 → 拒绝动它)
  let raw = null
  let skills = []
  try {
    raw = fs.readFileSync(indexPath, 'utf8')
  } catch {
    console.log(`WARN 索引不存在,将从空索引创建: ${indexPath}`)
  }
  if (raw !== null) {
    try {
      skills = parseYaml(raw)?.skills ?? []
    } catch (e) {
      console.error(`ERROR YAML 解析失败,拒绝追加: ${e.message}`)
      process.exit(1)
    }
    if (!Array.isArray(skills)) {
      console.error('ERROR 索引缺少顶层 skills 列表,拒绝追加')
      process.exit(1)
    }
  }

  const byName = new Set()
  const byPath = new Set()
  for (const e of skills) {
    if (!e || typeof e !== 'object') continue
    if (typeof e.name === 'string' && e.name.trim() !== '') byName.add(e.name.trim())
    if (typeof e.path === 'string' && e.path.trim() !== '') byPath.add(normPath(e.path.trim()))
  }

  // 扫描 vault 下的 SKILL.md: 深度 1(vault/<name>/SKILL.md)与深度 2(vault/<桶>/<name>/SKILL.md,
  // 如 superpowers 包的 skills/<name>/)。rel 路径保留桶前缀,与 index.yaml 的 path 约定一致。
  const seeds = []
  const seenDirs = new Set()
  const isSkillFile = (p) => { try { return fs.statSync(p).isFile() } catch { return false } }
  const candidates = []
  for (const d of fs.readdirSync(vault, { withFileTypes: true })) {
    if (!d.isDirectory() || d.name.startsWith('.') || d.name === 'node_modules') continue
    const sub = path.join(vault, d.name)
    if (isSkillFile(path.join(sub, 'SKILL.md'))) {
      candidates.push({ dir: d.name, rel: `${d.name}/SKILL.md` })
    } else {
      for (const d2 of fs.readdirSync(sub, { withFileTypes: true })) {
        if (!d2.isDirectory() || d2.name.startsWith('.') || d2.name === 'node_modules') continue
        const f2 = path.join(sub, d2.name, 'SKILL.md')
        if (isSkillFile(f2)) candidates.push({ dir: d2.name, rel: `${d.name}/${d2.name}/SKILL.md` })
      }
    }
  }
  for (const { dir, rel } of candidates) {
    if (seenDirs.has(dir)) { console.log(`WARN 目录名重复,仅取第一个: ${dir}`); continue }
    seenDirs.add(dir)
    const skillFile = path.join(vault, rel)
    let text = ''
    try {
      text = fs.readFileSync(skillFile, 'utf8')
    } catch (e) {
      console.log(`WARN 无法读取 ${skillFile}: ${e.message},跳过`)
      continue
    }
    const fm = parseFrontmatter(text, rel)
    const fmName = fm && typeof fm.name === 'string' && fm.name.trim() !== '' ? fm.name.trim() : null
    const name = fmName ?? dir
    // 幂等: name(目录名或 frontmatter 名)或 path 任一命中即跳过(含已有 _seed 条目)
    if (byName.has(name) || byName.has(dir) || byPath.has(normPath(rel))) {
      console.log(`SKIP ${dir}: 已在索引(name=${name})`)
      continue
    }
    const desc = fm && typeof fm.description === 'string' ? fm.description : ''
    if (!fm) console.log(`WARN ${rel}: 无 frontmatter,name 回退目录名,signals 为空`)
    const weak = extractSignals(desc)
    seeds.push({
      name,
      path: rel,
      tier: 'basic',
      domain: 'meta',
      signals: { strong: [], weak },
      relations: { 'co-requires': [], supersedes: [], 'conflicts-with': [] },
      weight: 0.5,
      _seed: true,
    })
    console.log(`SEED ${name}  path=${rel}  signals(${weak.length}): ${weak.join(' ') || '(空)'}`)
  }

  if (seeds.length === 0) {
    console.log('无新增,vault 与索引已对齐')
    process.exit(0)
  }

  if (dryRun) {
    console.log(`--dry-run: 未写入,将追加 ${seeds.length} 条到 ${indexPath}:`)
    console.log(seedText(seeds, raw === null ? 2 : detectListIndent(raw)).trimEnd())
    process.exit(0)
  }

  // 追加(保留原内容)
  if (raw !== null) {
    if (/skills:\s*\[\s*\]/.test(raw)) {
      console.error('ERROR skills: [] 内联空列表无法追加,请改为块式列表')
      process.exit(1)
    }
    // 安全闸: skills 列表之后不得再出现其他顶级 key,否则追加会挂错位置
    let seenList = false
    for (const lineRaw of raw.split(/\r?\n/)) {
      const s = stripComment(lineRaw)
      if (s.trim() === '') continue
      const ind = s.length - s.trimStart().length
      if (/^ *- /.test(s)) { seenList = true; continue }
      if (ind === 0 && seenList) {
        console.error(`ERROR 索引在 skills 列表之后还有顶级结构(${s.trim()}),拒绝盲追加`)
        process.exit(1)
      }
    }
  }
  if (raw === null) {
    // fail-open: 索引不存在 → 新建,先写 skills: 头
    fs.writeFileSync(indexPath, `skills:\n${seedText(seeds, 2)}`)
  } else {
    // 追加: 原内容字节级不动;原文末尾无换行时补一个再接种子块
    const prefix = raw.endsWith('\n') ? '' : '\n'
    fs.appendFileSync(indexPath, prefix + seedText(seeds, detectListIndent(raw)))
  }
  console.log(`已追加 ${seeds.length} 条种子 → ${indexPath}`)
}

function detectListIndent(raw) {
  const m = raw.match(/^( *)- /m)
  return m ? m[1].length : 2
}

function seedText(seeds, li) {
  return seeds.map((e) => serializeEntry(e, li)).join('\n') + '\n'
}

main()
