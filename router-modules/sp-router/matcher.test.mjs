/**
 * matcher.test.mjs — sp-router v2 匹配器测试(node:test + node:assert/strict, 零依赖)
 *
 * 覆盖: tokenize 分词 / 空 query / 撒种 / 三种传播边 / weight / 排序截断 /
 *       parseIndex 容错 / 真实 index.yaml 隐性路由用例。
 * 运行: node --test matcher.test.mjs
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

import { tokenize, parseIndex, route } from './matcher.mjs'

// 真实索引: 启动时读文件 parseIndex(隐性路由用例依赖真数据)
const realIndexPath = fileURLToPath(new URL('./index.yaml', import.meta.url))
const realIdx = parseIndex(fs.readFileSync(realIndexPath, 'utf8'))

// 合成索引构造器: entries 每项 {name, strong, weak, co, sup, conf, weight}
const mk = (entries) => ({
  skills: entries.map((e) => ({
    name: e.name,
    path: `skills/${e.name}/SKILL.md`,
    tier: 'basic',
    domain: 'meta',
    signals: { strong: e.strong ?? [], weak: e.weak ?? [] },
    relations: {
      'co-requires': e.co ?? [],
      supersedes: e.sup ?? [],
      'conflicts-with': e.conf ?? [],
    },
    weight: e.weight ?? 1,
  })),
})

// ---- tokenize ----

test('tokenize: CJK 二字滑窗 bigram', () => {
  assert.deepEqual(tokenize('返回值'), ['返回', '回值'])
  assert.deepEqual(tokenize('修'), ['修']) // 单字段 → 该单字
})

test('tokenize: ASCII 小写化 + 中英混排去重(首现序)', () => {
  const toks = tokenize('用TDD写测试')
  assert.ok(toks.includes('tdd'), `应含小写 tdd: ${JSON.stringify(toks)}`)
  assert.ok(toks.includes('写测'), `应含 bigram 写测: ${JSON.stringify(toks)}`)
  assert.deepEqual(tokenize('abc abc'), ['abc']) // 去重
})

// ---- 空 query ----

test('route: 空/无 token query 返回 []', () => {
  const idx = mk([{ name: 'alpha', strong: ['崩溃'] }])
  assert.deepEqual(route('', idx), [])
  assert.deepEqual(route('   ', idx), [])
  assert.deepEqual(route(undefined, idx), [])
  assert.deepEqual(route('今天天气很好', mk([{ name: 'x' }])), []) // 无信号命中
})

// ---- 撒种 ----

test('撒种: strong 命中 +2, hits 记信号原串', () => {
  const idx = mk([{ name: 'alpha', strong: ['崩溃'] }])
  assert.deepEqual(route('崩溃', idx), [{ name: 'alpha', score: 2, hits: ['崩溃'] }])
})

test('撒种: name 命中 +3, hits 去重保持序', () => {
  const idx = mk([{ name: '修复', strong: ['修复'] }])
  // name+3, strong+2, hits 只记一次 '修复'
  assert.deepEqual(route('修复', idx), [{ name: '修复', score: 5, hits: ['修复'] }])
})

// ---- 传播: co-requires ----

test('传播: co-requires 一层, B 得 seed[A]×0.5', () => {
  const idx = mk([
    { name: 'a', strong: ['崩溃'], co: ['b'] },
    { name: 'b' },
  ])
  assert.deepEqual(route('崩溃', idx), [
    { name: 'a', score: 2, hits: ['崩溃'] },
    { name: 'b', score: 1, hits: [] },
  ])
})

// ---- 传播: supersedes ----

test('传播: supersedes 双分转移, B 分×0.7 给 A 且 B 清零', () => {
  const idx = mk([
    { name: 'a', strong: ['崩溃'], sup: ['b'] },
    { name: 'b', strong: ['修复'] },
  ])
  // a: seed 2 + 2×0.7 = 3.4; b: 清零
  assert.deepEqual(route('崩溃 修复', idx), [{ name: 'a', score: 3.4, hits: ['崩溃'] }])
})

test('传播: supersedes 仅 B 有分不转移', () => {
  const idx = mk([
    { name: 'a', sup: ['b'] },
    { name: 'b', strong: ['修复'] },
  ])
  assert.deepEqual(route('修复', idx), [{ name: 'b', score: 2, hits: ['修复'] }])
})

// ---- 传播: conflicts-with ----

test('传播: conflicts-with 双分低者归零, 平局被引用方归零', () => {
  const tie = mk([
    { name: 'a', strong: ['崩溃'], conf: ['b'] },
    { name: 'b', strong: ['修复'] },
  ])
  // 平局 2:2 → b(被引用方)=0
  assert.deepEqual(route('崩溃 修复', tie), [{ name: 'a', score: 2, hits: ['崩溃'] }])

  const lower = mk([
    { name: 'a', strong: ['崩溃'], conf: ['b'] },
    { name: 'b', strong: ['修复'], weak: ['修弱'] },
  ])
  // a=2 < b=3 → a 归零
  assert.deepEqual(route('崩溃 修复 修弱', lower), [{ name: 'b', score: 3, hits: ['修复', '修弱'] }])
})

// ---- weight ----

test('weight: 终分 = score × weight(2 分 × 2 = 4)', () => {
  const idx = mk([{ name: 'w', strong: ['崩溃'], weight: 2 }])
  assert.deepEqual(route('崩溃', idx), [{ name: 'w', score: 4, hits: ['崩溃'] }])
})

// ---- 排序与截断 ----

test('排序: 分降序, 平局 name 升序, 最多返回 3 个', () => {
  const idx = mk([
    { name: 'd', strong: ['崩溃'] },
    { name: 'c', strong: ['崩溃'] },
    { name: 'b', strong: ['崩溃'] },
    { name: 'a', strong: ['崩溃'] },
  ])
  const res = route('崩溃', idx)
  assert.equal(res.length, 3)
  assert.deepEqual(res.map((r) => r.name), ['a', 'b', 'c'])
  for (const r of res) assert.equal(r.score, 2)
})

// ---- parseIndex ----

test('parseIndex: 真实 index.yaml 解析 20 技能且字段规整', () => {
  assert.equal(realIdx.skills.length, 20)
  const sd = realIdx.skills.find((s) => s.name === 'systematic-debugging')
  assert.ok(sd.signals.strong.includes('崩溃'))
  assert.deepEqual(sd.relations['co-requires'], ['verification-before-completion'])
})

test('parseIndex: 缺省容错(signals/relations 默认空, weight 默认 1)', () => {
  const idx = parseIndex('skills:\n  - {name: solo}\n')
  assert.equal(idx.skills.length, 1)
  const s = idx.skills[0]
  assert.equal(s.name, 'solo')
  assert.deepEqual(s.signals, { strong: [], weak: [] })
  assert.deepEqual(s.relations, { 'co-requires': [], supersedes: [], 'conflicts-with': [] })
  assert.equal(s.weight, 1)
})

// ---- 真实隐性路由用例(真 index.yaml) ----

test('真实索引: "这个函数返回值不对,修完提交" → 含 debugging 与 verification', () => {
  const top = route('这个函数返回值不对,修完提交', realIdx)
  const names = top.map((r) => r.name)
  assert.ok(names.includes('systematic-debugging'), `top-3=${JSON.stringify(top)}`)
  assert.ok(names.includes('verification-before-completion'), `top-3=${JSON.stringify(top)}`)
})

test('真实索引: "改完了可以提交了吧" → verification-before-completion 置顶', () => {
  const top = route('改完了可以提交了吧', realIdx)
  assert.equal(top[0].name, 'verification-before-completion')
})

test('真实索引: "为什么结果错了" → systematic-debugging 置顶', () => {
  const top = route('为什么结果错了', realIdx)
  assert.equal(top[0].name, 'systematic-debugging')
})

// ---- 信号两级命中(full/partial)+ 黑名单整串降权(语义修复) ----

test('两级: full=信号全部 token ∈ query → strong +2; 单 bigram 交叠不再命中', () => {
  const idx = mk([{ name: 'a', strong: ['崩溃修复'] }])
  // '崩溃修复' 3 个 bigram 全在 query → full +2
  assert.deepEqual(route('崩溃修复', idx), [{ name: 'a', score: 2, hits: ['崩溃修复'] }])
  // 仅 '崩溃' 一个 bigram 交叠(命中 1 < 2, 且非全部) → 零命中
  assert.deepEqual(route('崩溃日志堆栈', idx), [])
})

test('两级: full 对 weak → +1', () => {
  const idx = mk([{ name: 'a', weak: ['返回值'] }])
  assert.deepEqual(route('函数返回值', idx), [{ name: 'a', score: 1, hits: ['返回值'] }])
})

test('两级: partial=命中 token≥2 且 ≥信号 token 数 60% → strong +1; 不足 60% 不命中', () => {
  // '崩溃修复堆栈' 5 token, query 命中 崩溃/修复/堆栈 = 3(=60%) → partial +1
  const idx = mk([{ name: 'a', strong: ['崩溃修复堆栈'] }])
  assert.deepEqual(route('崩溃和修复和堆栈', idx), [{ name: 'a', score: 1, hits: ['崩溃修复堆栈'] }])
  // 命中 2/5 = 40% < 60% → 不命中
  assert.deepEqual(route('崩溃 修复', idx), [])
})

test('两级: partial 对 weak → +0.5', () => {
  // '错误堆栈' 3 token, 命中 错误/堆栈 = 2(66.7% ≥ 60%) → partial +0.5
  const idx = mk([{ name: 'a', weak: ['错误堆栈'] }])
  assert.deepEqual(route('错误和堆栈', idx), [{ name: 'a', score: 0.5, hits: ['错误堆栈'] }])
})

test('黑名单: 信号串与 GENERIC_WORDS 完全相等 → 该信号得分 ×0.25', () => {
  const idx = mk([{ name: 'a', weak: ['技能'] }, { name: 'b', strong: ['继续'] }])
  // '技能' weak full 本应 +1 → ×0.25 = 0.25
  assert.deepEqual(route('技能', idx), [{ name: 'a', score: 0.25, hits: ['技能'] }])
  // '继续' strong full 本应 +2 → ×0.25 = 0.5
  assert.deepEqual(route('继续', idx), [{ name: 'b', score: 0.5, hits: ['继续'] }])
})

test('黑名单: 仅整串完全相等才 ×0.25; 含泛化词的长信号不降权', () => {
  const idx = mk([
    { name: 'a', strong: ['继续'] },     // 黑名单整串 → 降权
    { name: 'b', strong: ['继续开发'] }, // 非整串相等 → 不降权
  ])
  // query '继续 开发': a full 2×0.25=0.5; b 命中 2/3 ≥60% → partial +1 → b 胜 a
  const res = route('继续 开发', idx)
  assert.deepEqual(res.map((r) => r.name), ['b', 'a'])
  assert.deepEqual(res.map((r) => r.score), [1, 0.5])
})

// ---- wrapper 回归(仲裁修正版) ----

test('wrapper 回归 A(污染不垄断): 真实报错句 top-3 中 debugging 高于 writing-skills', () => {
  const top = route('根据下方技能指引,这个函数返回值不对,帮我看看', realIdx)
  const names = top.map((r) => r.name)
  const dbg = names.indexOf('systematic-debugging')
  const wsk = names.indexOf('writing-skills')
  assert.ok(dbg >= 0, `systematic-debugging 应在 top-3: ${JSON.stringify(top)}`)
  assert.ok(wsk < 0 || wsk > dbg, `writing-skills 不应高于 systematic-debugging: ${JSON.stringify(top)}`)
})

test('wrapper 回归 B(纯技能句正确路由): 技能元问句允许 writing-skills 在列', () => {
  const top = route('根据下方技能指引,你会先读哪一个技能的 SKILL.md?只回答技能名', realIdx)
  assert.ok(top.map((r) => r.name).includes('writing-skills'), `top-3=${JSON.stringify(top)}`)
})
