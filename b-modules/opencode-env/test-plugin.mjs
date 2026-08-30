// opencode-env 插件行为测试: node --test b-modules/opencode-env/test-plugin.mjs
// 或直接: node b-modules/opencode-env/test-plugin.mjs
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'

const mod = await import(new URL('./.opencode/plugin.js', import.meta.url).href)
const plugin = mod.default

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
console.log('✓ test-plugin: 2 组断言全过')
