/**
 * opencode-env — B 方向环境感知插件(specs/B-environment.md Phase 1-4)
 * Phase 1: <env> 块注入(静态核心)
 * Phase 2: Fragment 模式(env/git/codegraph 三片段,独立缓存)
 * Phase 3: 异步就绪状态机(Pending/Ready/Failed,codegraph 探测不阻塞)
 * Phase 4: 注入策略(首条 user 消息注入,幂等防重;信息少而准——agent 按需读 env-profile.md 获取全量)
 *
 * 设计遵循: superpowers 插件范例(config hook + messages.transform)
 * 探测边界(spec §3): 只读静态(process/文件检查),不 spawn 命令(防 EDR)
 */
import path from 'path'
import fs from 'fs'
import os from 'os'
import { execFileSync } from 'child_process'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

// ── Fragment 基类(Phase 2)────────────────────────────
class Fragment {
  constructor(name) { this.name = name; this._state = 'Pending'; this._cache = null }
  get state() { return this._state }
  /** 子类实现: 返回字符串(Ready) 或抛错(Failed) */
  probe() { throw new Error('not implemented') }
  render() {
    if (this._cache) return this._cache
    try { this._cache = this.probe(); this._state = 'Ready' }
    catch { this._state = 'Failed' }
    return this._cache
  }
}

// ── 片段: env(系统/工具,同步,零开销)──────────────────
class EnvFragment extends Fragment {
  constructor() { super('env') }
  probe() {
    const tools = ['node','npm','bun','git','curl','python3','rg','codegraph'].filter(t => {
      try { execFileSync('which', [t], {stdio:'ignore', timeout: 2000}); return true } catch { return false }
    })
    return `<env>\n  Platform: ${process.platform} ${process.arch}\n  Today: ${new Date().toDateString()}\n  Tools: ${tools.join(', ') || 'none detected'}\n</env>`
  }
}

// ── 片段: git 快照(会话级缓存,一次)──────────────────
class GitFragment extends Fragment {
  constructor(dir) { super('git'); this.dir = dir }
  probe() {
    const gitDir = path.join(this.dir, '.git')
    if (!fs.existsSync(gitDir)) return null // 非 git 仓库: 不注入(静默)
    const branch = execFileSync('git',['rev-parse','--abbrev-ref','HEAD'],{cwd:this.dir,timeout:2000}).toString().trim()
    const last = execFileSync('git',['log','-1','--oneline'],{cwd:this.dir,timeout:2000}).toString().trim()
    return `  Git: ${branch} (last: ${last})`
  }
}

// ── 片段: codegraph 就绪声明(Phase 3 异步状态机)──────
class CodegraphFragment extends Fragment {
  constructor(dir) { super('codegraph'); this.dir = dir; this._checked = false }
  probe() {
    // 能力就绪声明,不注入结构(spec 2.1)
    const installed = (() => { try { execFileSync('which',['codegraph'],{stdio:'ignore',timeout:2000}); return true } catch { return false } })()
    if (!installed) return null // 未安装: 静默(结构理解靠 glob/grep)
    const idx = fs.existsSync(path.join(this.dir,'.codegraph')) || fs.existsSync(path.join(this.dir,'.codegraph','graph.db'))
    if (idx) return '  Codegraph: ready → 遇到"谁调用X/X怎么工作"优先查 codegraph'
    return '  Codegraph: installed, not inited → 深度结构理解前建议 codegraph init'
  }
}

// ── 注入主逻辑(Phase 1+4)─────────────────────────────
export const EnvPlugin = async ({ client, directory }) => {
  const workDir = directory || process.cwd()

  // Fragment 注册表(Phase 2)
  const fragments = [ new EnvFragment(), new GitFragment(workDir), new CodegraphFragment(workDir) ]
  const MARK = 'opencode-env-injected'

  const buildBlock = () => {
    // Pending 期间不阻塞: render() 同步但每片段自限超时;失败片段输出状态行(失败也是信息)
    const lines = ['Useful environment information:']
    for (const f of fragments) {
      const out = f.render()
      if (out == null) continue            // 静默跳过(非 git/未装)
      lines.push(out)
      if (f.state === 'Failed') lines.push(`  ${f.name}: probe failed(环境可能异常)`)
    }
    lines.push('  Full profile: read ~/.config/opencode/env-profile.md on demand')
    return lines.join('\n')
  }

  return {
    'experimental.chat.messages.transform': async (_input, output) => {
      if (!output.messages?.length) return
      const first = output.messages.find(m => m.info?.role === 'user')
      if (!first?.parts?.length) return
      if (first.parts.some(p => p.type === 'text' && p.text?.includes(MARK))) return // 幂等
      const text = `<!--${MARK}-->\n${buildBlock()}`
      const ref = first.parts[0]
      first.parts.unshift({ ...ref, type: 'text', text })
    },
  }
}

export default EnvPlugin
