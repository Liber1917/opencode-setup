// opencode-env 插件行为测试: node --test b-modules/opencode-env/test-plugin.mjs
// 或直接: node b-modules/opencode-env/test-plugin.mjs
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'

const mod = await import(new URL('./.opencode/plugin.js', import.meta.url).href)
const plugin = mod.default

// 环境隔离: 用户级 facts.md 探测重定向到空 tmp(真机 ~/.config/opencode 可能已部署)
const _cfgSandbox = mkdtempSync(path.join(tmpdir(), 'plg-cfg-'))
const _prevCfg = process.env.OPENCODE_CONFIG_DIR
process.env.OPENCODE_CONFIG_DIR = _cfgSandbox

// ① 非 git 目录: 注入但无 Git 行 + 幂等 + part 纯净
{
  const api = await plugin({ directory: tmpdir() })
  const msgs = [{ info: { role: 'user' }, parts: [{ type: 'text', text: 'hi' }] }]
  await api['experimental.chat.messages.transform']({}, { messages: msgs })
  const t = msgs[0].parts[0].text
  assert.ok(t.includes('opencode-env-injected'), 'MARK 存在')
  assert.ok(!t.includes('Git:'), '非 git 目录不注 Git 行')
  await api['experimental.chat.messages.transform']({}, { messages: msgs })
  assert.equal(msgs[0].parts.length, 2, '幂等')
  assert.deepEqual(Object.keys(msgs[0].parts[0]), ['type', 'text'], 'part 字段纯净')
}
// ② git 仓库: branch+sha 注入,不含 commit message(注入面)
{
  const d = mkdtempSync(path.join(tmpdir(), 'plg-'))
  mkdirSync(path.join(d, '.git', 'refs', 'heads'), { recursive: true })
  writeFileSync(path.join(d, '.git', 'HEAD'), 'ref: refs/heads/main\n')
  writeFileSync(path.join(d, '.git', 'refs', 'heads', 'main'), 'abcdef1234567890\n')
  const api = await plugin({ directory: d })
  const msgs = [{ info: { role: 'user' }, parts: [{ type: 'text', text: 'hi' }] }]
  await api['experimental.chat.messages.transform']({}, { messages: msgs })
  const gitLine = msgs[0].parts[0].text.split('\n').find(l => l.startsWith('  Git:'))
  assert.ok(gitLine.includes('main') && gitLine.includes('abcdef'), 'branch+sha')
  rmSync(d, { recursive: true, force: true })
}
// ③ GSD Fragment: 非 GSD 目录静默;有 .planning 注入 phase 状态(C2 判决机制)
{
  const d = mkdtempSync(path.join(tmpdir(), 'plg-'))
  const api = await plugin({ directory: d })
  let msgs = [{ info: { role: 'user' }, parts: [{ type: 'text', text: 'hi' }] }]
  await api['experimental.chat.messages.transform']({}, { messages: msgs })
  assert.ok(!msgs[0].parts[0].text.includes('GSD:'), '无 .planning 不注 GSD 行')
  mkdirSync(path.join(d, '.planning'), { recursive: true })
  writeFileSync(path.join(d, '.planning', 'ROADMAP.md'), '# Roadmap\n## Phase 1: MVP — In Progress ✅\n- [x] step\n')
  writeFileSync(path.join(d, '.planning', 'STATE.md'), '---\nstatus: executing\n---\nCurrent Position: Ready to plan Phase 1 tasks\n')
  const api2 = await plugin({ directory: d })
  msgs = [{ info: { role: 'user' }, parts: [{ type: 'text', text: 'hi' }] }]
  await api2['experimental.chat.messages.transform']({}, { messages: msgs })
  const gsdLine = msgs[0].parts[0].text.split('\n').find(l => l.includes('GSD:'))
  assert.ok(gsdLine && gsdLine.includes('Phase'), '有 .planning 注入 phase: ' + gsdLine)
  rmSync(d, { recursive: true, force: true })
}
// ④ MemoryFragment: 无 facts.md 静默;项目级注入预览行;超 50 行截断提醒;用户级兜底
{
  const d = mkdtempSync(path.join(tmpdir(), 'plg-'))
  // ④a 无任何 facts.md → 静默
  let api = await plugin({ directory: d })
  let msgs = [{ info: { role: 'user' }, parts: [{ type: 'text', text: 'hi' }] }]
  await api['experimental.chat.messages.transform']({}, { messages: msgs })
  assert.ok(!msgs[0].parts[0].text.includes('Memory:'), '无 facts.md 不注 Memory 行')
  // ④b 项目级 facts.md → 注入一行预览(剥模板注释取实际事实)
  mkdirSync(path.join(d, 'docs', 'memory'), { recursive: true })
  writeFileSync(path.join(d, 'docs', 'memory', 'facts.md'), '# Facts\n<!-- 模板注释 -->\n- 用户偏好 bun 打包\n- 输出用中文\n')
  api = await plugin({ directory: d }) // 新实例避开片段缓存
  msgs = [{ info: { role: 'user' }, parts: [{ type: 'text', text: 'hi' }] }]
  await api['experimental.chat.messages.transform']({}, { messages: msgs })
  const memLine = msgs[0].parts[0].text.split('\n').find(l => l.includes('Memory:'))
  assert.ok(memLine && memLine.includes('用户偏好 bun 打包'), '预览含首条事实: ' + memLine)
  assert.ok(memLine.includes('全量: 读 docs/memory/facts.md'), '全量指引在场')
  assert.ok(!memLine.includes('⚠'), '50 行内无截断提醒')
  // ④c 超 50 行 → 截断提醒
  writeFileSync(path.join(d, 'docs', 'memory', 'facts.md'), '# Facts\n' + Array.from({ length: 55 }, (_, i) => `- 事实 ${i}`).join('\n') + '\n')
  api = await plugin({ directory: d })
  msgs = [{ info: { role: 'user' }, parts: [{ type: 'text', text: 'hi' }] }]
  await api['experimental.chat.messages.transform']({}, { messages: msgs })
  const warnLine = msgs[0].parts[0].text.split('\n').find(l => l.includes('Memory:'))
  assert.ok(warnLine && warnLine.includes('超 50 上限'), '超限截断提醒在场: ' + warnLine)
  // ④d 项目级缺席 → 用户级兜底
  rmSync(path.join(d, 'docs'), { recursive: true, force: true })
  mkdirSync(path.join(_cfgSandbox, 'docs', 'memory'), { recursive: true })
  writeFileSync(path.join(_cfgSandbox, 'docs', 'memory', 'facts.md'), '# Facts\n- 用户级事实一条\n')
  api = await plugin({ directory: d })
  msgs = [{ info: { role: 'user' }, parts: [{ type: 'text', text: 'hi' }] }]
  await api['experimental.chat.messages.transform']({}, { messages: msgs })
  const userLine = msgs[0].parts[0].text.split('\n').find(l => l.includes('Memory:'))
  assert.ok(userLine && userLine.includes('用户级事实一条'), '用户级 facts.md 兜底注入')
  rmSync(d, { recursive: true, force: true })
}
if (_prevCfg === undefined) delete process.env.OPENCODE_CONFIG_DIR
else process.env.OPENCODE_CONFIG_DIR = _prevCfg
rmSync(_cfgSandbox, { recursive: true, force: true })
console.log('✓ test-plugin: 4 组断言全过')
