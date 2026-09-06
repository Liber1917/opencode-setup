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
