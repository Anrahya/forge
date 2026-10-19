/**
 * Loads the real plugin entry (src/index.ts) with the published DSH
 * 0.2.0-rc.2 packages from devDependencies and drives each registration
 * through a fake Cordis context. This checks wiring, not DSH dispatch: the
 * fake calls listeners the way the event declarations describe. Skipped
 * when the DSH packages are not installed.
 */
import assert from 'node:assert/strict'
import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, describe, it } from 'node:test'

const require = createRequire(import.meta.url)
let haveDsh = true
try { require.resolve('@deepseek-ai/dsh-tools') } catch { haveDsh = false }

type Listener = (...args: any[]) => any

function fakeContext(extra: Record<string, unknown> = {}) {
  const listeners = new Map<string, Listener>()
  const tools = new Map<string, any>()
  const providers: any[] = []
  const effects: string[] = []
  const ctx = {
    on(name: string, listener: Listener) { listeners.set(name, listener); return () => listeners.delete(name) },
    effect(run: () => () => void, label?: string) { effects.push(label ?? ''); return run() },
    tools: { register(def: any) { tools.set(def.name, def); return () => tools.delete(def.name) } },
    skills: { registerProvider(create: any) { providers.push(create({ signal: new AbortController().signal, invalidate() {} })); return () => {} } },
    get(name: string) { return extra[name] },
  }
  return { ctx, listeners, tools, providers, effects }
}

function fakeAgent(cwd: string, opts: { origin?: 'subagent' } = {}) {
  const steered: any[] = []
  const injected: any[] = []
  return {
    agent: {
      id: `agent-${Math.random()}`,
      session: { header: { cwd, ...opts.origin ? { origin: opts.origin } : {} } },
      steer(m: any) { steered.push(m) },
      inject(m: any) { injected.push(m) },
    },
    steered,
    injected,
  }
}

const dirs: string[] = []
after(() => { for (const d of dirs) rmSync(d, { recursive: true, force: true }) })

function forgeProject(phase: string, verifyExit: number): { root: string; forgeRoot: string } {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'forge-dsh-smoke-')))
  const forgeRoot = realpathSync(mkdtempSync(join(tmpdir(), 'forge-dsh-root-')))
  dirs.push(root, forgeRoot)
  mkdirSync(join(root, '.forge', 't1'), { recursive: true })
  writeFileSync(join(root, '.forge', 'current'), 't1\n')
  writeFileSync(join(root, '.forge', 't1', 'state.json'), JSON.stringify({ phase }))
  writeFileSync(join(root, 'forge.toml'), '[roles]\nbuild = "deepseek-official/deepseek-chat"\n[effort]\nbuild = "high"\nreview = "max"\n')
  mkdirSync(join(forgeRoot, 'skills', `forge-${phase}`), { recursive: true })
  writeFileSync(join(forgeRoot, 'skills', `forge-${phase}`, 'SKILL.md'), `---\nname: forge-${phase}\ndescription: ${phase} phase\n---\n# ${phase} playbook body\n`)
  writeFileSync(join(forgeRoot, 'AGENTS.md'), '# forge\n\n## Principle index\n\n- `prove-it-works`: verify the real artifact.\n')
  mkdirSync(join(forgeRoot, 'scripts'), { recursive: true })
  writeFileSync(join(forgeRoot, 'scripts', 'forge-verify.sh'), `#!/usr/bin/env bash\necho "G2 FAIL: 3 tests failed" > "$2/verify.log"\nexit ${verifyExit}\n`)
  chmodSync(join(forgeRoot, 'scripts', 'forge-verify.sh'), 0o755)
  return { root, forgeRoot }
}

describe('plugin wiring', { skip: !haveDsh && 'DSH packages not installed' }, () => {
  it('registers every hook, the tool, and the skills provider', async () => {
    const plugin = await import('../src/index.ts')
    assert.equal(plugin.name, 'forge-dsh')
    assert.deepEqual(plugin.inject, ['tools', 'skills'])
    const { ctx, listeners, tools, providers } = fakeContext()
    const { forgeRoot } = forgeProject('build', 0)
    plugin.apply(ctx as any, { forgeRoot })
    assert.deepEqual([...listeners.keys()].sort(), ['agent/disposed', 'agent/pre-step', 'agent/request', 'agent/turn-stopping', 'tools/pre-execute'])
    assert.ok(tools.has('forge_spawn'))
    const skills = await providers[0].list({})
    assert.deepEqual(skills.map((s: any) => s.name), ['forge-build'])
    const def = await providers[0].get(skills[0], {})
    assert.match(def.content, /build playbook body/)
  })

  it('pre-execute denies a read-only phase write and passes when forge is inactive', async () => {
    const plugin = await import('../src/index.ts')
    const { ctx, listeners } = fakeContext()
    const { root, forgeRoot } = forgeProject('ground', 0)
    plugin.apply(ctx as any, { forgeRoot })
    const pre = listeners.get('tools/pre-execute')!
    const allow = async () => ({ kind: 'allow' })
    const { agent } = fakeAgent(root)
    const denied = await pre({ name: 'write', arguments: { file_path: 'src/a.ts', content: 'x' }, agent }, allow)
    assert.equal(denied.kind, 'deny')
    assert.match(denied.reason, /read-only/)
    const ok = await pre({ name: 'write', arguments: { file_path: '.forge/t1/ground.md', content: 'x' }, agent }, allow)
    assert.equal(ok.kind, 'allow')
    const elsewhere = fakeAgent(realpathSync(tmpdir())).agent
    assert.equal((await pre({ name: 'write', arguments: { file_path: 'a.ts', content: 'x' }, agent: elsewhere }, allow)).kind, 'allow')
  })

  it('pre-step appends one forge context message and skips identical re-entry', async () => {
    const plugin = await import('../src/index.ts')
    const { ctx, listeners } = fakeContext()
    const { root, forgeRoot } = forgeProject('build', 0)
    plugin.apply(ctx as any, { forgeRoot, reinjectEverySteps: 4 })
    const preStep = listeners.get('agent/pre-step')!
    const { agent } = fakeAgent(root)
    const signal = new AbortController().signal
    const userMsg = { id: 'm1', role: 'user', content: [{ type: 'text', text: 'go' }], source: { kind: 'user' } }
    const first = await preStep({ agent, messages: [userMsg], turn: 1, step: 1, signal }, async () => ({ kind: 'enter', messages: [userMsg] }))
    assert.equal(first.messages.length, 2)
    assert.equal(first.messages[1].source.kind, 'forge')
    assert.equal(first.messages[1].source.form, 'instructions')
    assert.match(first.messages[1].content[0].text, /build playbook body[\s\S]*Principle index/)
    const second = await preStep({ agent, messages: [], turn: 1, step: 2, signal }, async () => ({ kind: 'enter', messages: [] }))
    assert.equal(second.messages.length, 0)
    const empty = await preStep({ agent, messages: [], turn: 2, step: 1, signal }, async () => ({ kind: 'enter', messages: [] }))
    assert.equal(empty.messages.length, 0, 'an empty first step stays empty')
    const rejected = await preStep({ agent, messages: [userMsg], turn: 3, step: 1, signal }, async () => ({ kind: 'reject' }))
    assert.equal(rejected.kind, 'reject')
  })

  it('turn-stopping steers on a failed gate and stays quiet on pass or for subagents', async () => {
    const plugin = await import('../src/index.ts')
    const failing = forgeProject('build', 1)
    const f = fakeContext()
    plugin.apply(f.ctx as any, { forgeRoot: failing.forgeRoot, maxVerifyRounds: 2 })
    const stop = f.listeners.get('agent/turn-stopping')!
    const top = fakeAgent(failing.root)
    const signal = new AbortController().signal
    await stop({ agent: top.agent, turn: 1, signal })
    assert.equal(top.steered.length, 1)
    assert.equal(top.steered[0].source.kind, 'forge')
    assert.equal(top.steered[0].source.form, 'notice')
    assert.match(top.steered[0].content[0].text, /G2 FAIL: 3 tests failed/)
    await stop({ agent: top.agent, turn: 1, signal })
    await stop({ agent: top.agent, turn: 1, signal })
    assert.equal(top.steered.length, 2, 'no more steering after maxVerifyRounds')
    assert.equal(top.injected.length, 1, 'a notice is left for the next turn')

    const child = fakeAgent(failing.root, { origin: 'subagent' })
    await stop({ agent: child.agent, turn: 1, signal })
    assert.equal(child.steered.length, 0)

    const passing = forgeProject('build', 0)
    const p = fakeContext()
    plugin.apply(p.ctx as any, { forgeRoot: passing.forgeRoot })
    const ok = fakeAgent(passing.root)
    await p.listeners.get('agent/turn-stopping')!({ agent: ok.agent, turn: 1, signal })
    assert.equal(ok.steered.length, 0)
  })

  it('agent/request applies phase effort only when the route lists it', async () => {
    const plugin = await import('../src/index.ts')
    const llm = {
      async resolveModelInfo(provider: string, model: string) {
        return { provider, id: model, name: model, reasoning: { efforts: model === 'deepseek-chat' ? [{ id: 'high', name: 'High' }] : [] } }
      },
    }
    const { ctx, listeners } = fakeContext({ llm })
    const { root, forgeRoot } = forgeProject('build', 0)
    plugin.apply(ctx as any, { forgeRoot })
    const request = listeners.get('agent/request')!
    const { agent } = fakeAgent(root)
    const signal = new AbortController().signal
    const listed = await request({ agent, turn: 1, step: 1, signal }, async () => ({ provider: 'deepseek-official', model: 'deepseek-chat' }))
    assert.equal(listed.reasoningEffort, 'high')
    const unlisted = await request({ agent, turn: 1, step: 1, signal }, async () => ({ provider: 'other', model: 'tiny' }))
    assert.equal(unlisted.reasoningEffort, undefined)
  })

  it('forge_spawn routes the role and the child inherits the role policy', async () => {
    const plugin = await import('../src/index.ts')
    const started: any[] = []
    const subagents = {
      getProvider() { return {} },
      async startActivation(spec: any) {
        started.push(spec)
        return { childId: spec.childId, result: new Promise(() => {}), async dispose() {} }
      },
    }
    const { ctx, listeners, tools } = fakeContext({ subagents })
    const { root, forgeRoot } = forgeProject('build', 0)
    plugin.apply(ctx as any, { forgeRoot })
    const { agent } = fakeAgent(root)
    const tool = tools.get('forge_spawn')
    const value = await tool.execute({ description: 'review diff', prompt: 'Review .forge/t1', role: 'review' }, { agent, signal: new AbortController().signal })
    assert.equal(value.kind, 'activation')
    assert.equal(value.route, 'inherit')
    const childId = started[0].childId
    const child = { ...fakeAgent(root).agent, id: childId }
    const pre = listeners.get('tools/pre-execute')!
    const denied = await pre({ name: 'edit', arguments: { file_path: 'src/a.ts', old_string: 'a', new_string: 'b' }, agent: child }, async () => ({ kind: 'allow' }))
    assert.equal(denied.kind, 'deny', 'a review child is read-only while the task is in build')
  })
})
