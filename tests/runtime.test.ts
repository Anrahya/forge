/**
 * Filesystem-backed modules: state, skills, injection, verify, spawn. Uses
 * temp dirs and fakes; needs no DSH packages.
 */
import assert from 'node:assert/strict'
import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, describe, it } from 'node:test'
import { buildInjection, InjectionTracker, loadPhaseContext, principleIndex } from '../src/inject.ts'
import { parseForgeToml } from '../src/roles.ts'
import { parseFrontmatter, scanSkills } from '../src/skills.ts'
import { executeSpawn, parseSpawnArgs, planSpawn, type ActivationLike, type SubagentsLike } from '../src/spawn.ts'
import { ForgeTomlCache, readForgeState } from '../src/state.ts'
import { runVerify, tailText, verifyFeedback, VerifyRounds } from '../src/verify.ts'

const dirs: string[] = []
function tmp(): string {
  const d = realpathSync(mkdtempSync(join(tmpdir(), 'forge-dsh-test-')))
  dirs.push(d)
  return d
}
function put(path: string, text: string): void {
  mkdirSync(join(path, '..'), { recursive: true })
  writeFileSync(path, text)
}
after(() => { for (const d of dirs) rmSync(d, { recursive: true, force: true }) })

describe('readForgeState', () => {
  it('is inactive without .forge/current, or with an empty one', () => {
    const root = tmp()
    assert.deepEqual(readForgeState(root), { active: false })
    put(join(root, '.forge', 'current'), '\n')
    assert.deepEqual(readForgeState(root), { active: false })
    assert.deepEqual(readForgeState(undefined), { active: false })
  })

  it('finds the task from a subdirectory and reads the phase', () => {
    const root = tmp()
    put(join(root, '.forge', 'current'), 'fix-parser\n')
    put(join(root, '.forge', 'fix-parser', 'state.json'), '{"phase":"build","loops":1}')
    mkdirSync(join(root, 'src', 'deep'), { recursive: true })
    const state = readForgeState(join(root, 'src', 'deep'))
    assert.deepEqual(state, { active: true, root, taskId: 'fix-parser', taskDir: '.forge/fix-parser', phase: 'build' })
  })

  it('stays active with no phase when state.json is missing, malformed, or wrong', () => {
    const root = tmp()
    put(join(root, '.forge', 'current'), 't1')
    const missing = readForgeState(root)
    assert.equal(missing.active && missing.phase, undefined)
    assert.match(missing.active ? missing.problem ?? '' : '', /missing/)
    put(join(root, '.forge', 't1', 'state.json'), '{nope')
    const bad = readForgeState(root)
    assert.match(bad.active ? bad.problem ?? '' : '', /not valid JSON/)
    put(join(root, '.forge', 't1', 'state.json'), '{"phase":"plan"}')
    const wrong = readForgeState(root)
    assert.match(wrong.active ? wrong.problem ?? '' : '', /"plan" is not one of/)
  })

  it('rejects path traversal in .forge/current', () => {
    const root = tmp()
    put(join(root, '.forge', 'current'), '../../etc')
    const state = readForgeState(root)
    assert.equal(state.active, true)
    assert.equal(state.active && state.phase, undefined)
  })
})

describe('ForgeTomlCache', () => {
  it('loads the nearest forge.toml and reloads after an edit', () => {
    const root = tmp()
    put(join(root, 'forge.toml'), '[roles]\nbuild = "a/b"\n')
    mkdirSync(join(root, 'pkg'))
    const cache = new ForgeTomlCache()
    assert.deepEqual(cache.load(join(root, 'pkg')).config.roles.build, [{ provider: 'a', model: 'b' }])
    writeFileSync(join(root, 'forge.toml'), '[roles]\nbuild = "c/d"\n')
    const later = new Date(Date.now() + 5000)
    utimesSync(join(root, 'forge.toml'), later, later)
    assert.deepEqual(cache.load(root).config.roles.build, [{ provider: 'c', model: 'd' }])
  })

  it('returns an empty config when no forge.toml exists', () => {
    assert.deepEqual(new ForgeTomlCache().load(tmp()).config.roles, {})
  })
})

describe('skills', () => {
  it('parses block scalars and quoted values', () => {
    const fm = parseFrontmatter('---\nname: forge-build\ndescription: >\n  Build one unit,\n  then check it.\nwhenToUse: "after SHAPE"\n---\n\n# Build\n')
    assert.equal(fm?.fields.description, 'Build one unit, then check it.')
    assert.equal(fm?.fields.whenToUse, 'after SHAPE')
    assert.equal(fm?.body, '# Build\n')
  })

  it('finds nested SKILL.md files, rejects bad names, and reports duplicates', async () => {
    const root = tmp()
    put(join(root, 'forge', 'SKILL.md'), '---\nname: forge\ndescription: router\n---\nRoute.\n')
    put(join(root, 'forge', 'playbooks', 'bug.md'), '# not a skill')
    put(join(root, 'principles', 'prove-it-works', 'SKILL.md'), '---\nname: prove-it-works\ndescription: verify the real artifact\ndisable-model-invocation: false\nuser-invocable: false\n---\nBody\n')
    put(join(root, 'micro', 'unslop', 'SKILL.md'), '---\nname: Unslop Mode\ndescription: bad name\n---\n')
    put(join(root, 'micro', 'zz-dupe', 'SKILL.md'), '---\nname: forge\ndescription: duplicate\n---\n')
    put(join(root, 'micro', 'no-desc', 'SKILL.md'), '---\nname: no-desc\n---\n')
    const { skills, problems } = await scanSkills(root)
    assert.deepEqual(skills.map(s => s.name), ['forge', 'prove-it-works'])
    const prove = skills.find(s => s.name === 'prove-it-works')!
    assert.equal(prove.userInvocable, false)
    assert.equal(prove.modelInvocable, true)
    assert.equal(prove.dir, join(root, 'principles', 'prove-it-works'))
    assert.equal(problems.length, 3)
    assert.ok(problems.some(p => /not kebab-case/.test(p)))
    assert.ok(problems.some(p => /duplicate skill name "forge"/.test(p)))
    assert.ok(problems.some(p => /description is required/.test(p)))
  })

  it('returns nothing for a missing root', async () => {
    assert.deepEqual(await scanSkills(join(tmp(), 'nope')), { skills: [], problems: [] })
  })
})

describe('injection', () => {
  const agents = '# forge contract\n\n## The contract\n\n1. x\n\n## Principle index\n\n**Core**\n- `laziness-protocol`: smallest change.\n\n### Notes\nstill index\n'

  it('extracts the principle index section', () => {
    const idx = principleIndex(agents)
    assert.ok(idx?.startsWith('## Principle index'))
    assert.match(idx ?? '', /still index/)
    assert.doesNotMatch(idx ?? '', /The contract/)
    assert.equal(principleIndex('# nothing'), undefined)
  })

  it('prefers the project skill copy and strips frontmatter', async () => {
    const project = tmp()
    const forge = tmp()
    put(join(forge, 'AGENTS.md'), agents)
    put(join(forge, 'skills', 'forge-build', 'SKILL.md'), '---\nname: forge-build\ndescription: d\n---\nBundled body\n')
    let ctx = await loadPhaseContext(project, forge, 'build')
    assert.equal(ctx.skill, 'Bundled body')
    assert.equal(ctx.skillPath, 'skills/forge-build/SKILL.md')
    put(join(project, '.agents', 'skills', 'forge-build', 'SKILL.md'), '---\nname: forge-build\ndescription: d\n---\nProject body\n')
    ctx = await loadPhaseContext(project, forge, 'build')
    assert.equal(ctx.skill, 'Project body')
    const text = buildInjection({ taskId: 't1', phase: 'build', forgeHome: '/opt/forge', ...ctx, maxChars: 10_000 })
    assert.match(text, /FORGE_HOME=\/opt\/forge/)
    assert.match(text, /^<forge-context task="t1" phase="build">/)
    assert.match(text, /Project body/)
    assert.match(text, /## Principle index/)
  })

  it('truncates to the character budget and keeps the closing tag', () => {
    const text = buildInjection({ taskId: 't', phase: 'scout', skill: 'x'.repeat(5000), maxChars: 1000 })
    assert.equal(text.length <= 1000, true)
    assert.match(text, /truncated[\s\S]*<\/forge-context>$/)
  })

  it('re-enters on a new turn, on change, and every N steps', () => {
    const t = new InjectionTracker()
    assert.equal(t.shouldEnter('a', 'h1', 1, 1, 3), true)
    assert.equal(t.shouldEnter('a', 'h1', 1, 2, 3), false)
    assert.equal(t.shouldEnter('a', 'h1', 1, 3, 3), false)
    assert.equal(t.shouldEnter('a', 'h1', 1, 4, 3), true)
    assert.equal(t.shouldEnter('a', 'h2', 1, 5, 3), true)
    assert.equal(t.shouldEnter('a', 'h2', 2, 1, 3), true)
    assert.equal(t.shouldEnter('b', 'h2', 2, 1, 3), true)
    assert.equal(t.shouldEnter('c', 'h', 1, 1, 1), true)
    assert.equal(t.shouldEnter('c', 'h', 1, 2, 1), true)
  })
})

describe('verify', () => {
  function project(script: string): string {
    const root = tmp()
    put(join(root, 'scripts', 'forge-verify.sh'), script)
    chmodSync(join(root, 'scripts', 'forge-verify.sh'), 0o755)
    mkdirSync(join(root, '.forge', 't1'), { recursive: true })
    return root
  }
  const base = { taskDir: '.forge/t1', phase: 'build' as const, timeoutMs: 10_000, tailLines: 5, tailChars: 2000 }

  it('passes on exit 0 and receives the documented arguments', async () => {
    const root = project('#!/usr/bin/env bash\n[ "$1" = --task-dir ] && [ "$2" = .forge/t1 ] && [ "$3" = --phase ] && [ "$4" = build ] || exit 3\necho ok > .forge/t1/verify.log\nexit 0\n')
    assert.deepEqual(await runVerify({ script: join(root, 'scripts', 'forge-verify.sh'), projectRoot: root, ...base }), { kind: 'pass' })
  })

  it('returns the verify.log tail on exit 1', async () => {
    const root = project('#!/usr/bin/env bash\nfor i in $(seq 1 20); do echo "line $i"; done > .forge/t1/verify.log\necho "G2 FAIL: tests failed" >> .forge/t1/verify.log\nexit 1\n')
    const outcome = await runVerify({ script: join(root, 'scripts', 'forge-verify.sh'), projectRoot: root, ...base })
    assert.equal(outcome.kind, 'fail')
    assert.match(outcome.kind === 'fail' ? outcome.logTail : '', /G2 FAIL: tests failed$/)
    assert.doesNotMatch(outcome.kind === 'fail' ? outcome.logTail : '', /line 1\n/)
  })

  it('ignores a stale verify.log and reports other exit codes as errors', async () => {
    const root = project('#!/usr/bin/env bash\necho "crashed before logging" >&2\nexit 2\n')
    put(join(root, '.forge', 't1', 'verify.log'), 'PASS from last week\n')
    const outcome = await runVerify({ script: join(root, 'scripts', 'forge-verify.sh'), projectRoot: root, ...base })
    assert.equal(outcome.kind, 'error')
    assert.match(outcome.kind === 'error' ? outcome.message : '', /exit 2/)
    assert.match(outcome.kind === 'error' ? outcome.logTail ?? '' : '', /crashed before logging/)
    assert.doesNotMatch(outcome.kind === 'error' ? outcome.logTail ?? '' : '', /last week/)
  })

  it('reports a missing script and a timeout', async () => {
    const missing = await runVerify({ script: undefined, projectRoot: tmp(), ...base })
    assert.equal(missing.kind, 'error')
    const root = project('#!/usr/bin/env bash\nsleep 5\n')
    const started = Date.now()
    const slow = await runVerify({ script: join(root, 'scripts', 'forge-verify.sh'), projectRoot: root, ...base, timeoutMs: 300 })
    assert.match(slow.kind === 'error' ? slow.message : '', /did not finish/)
    assert.ok(Date.now() - started < 4000, 'the process group is killed, not just bash')
  })

  it('stops the script when the turn is cancelled', async () => {
    const root = project('#!/usr/bin/env bash\nsleep 5\n')
    const controller = new AbortController()
    setTimeout(() => controller.abort(), 100)
    const started = Date.now()
    await runVerify({ script: join(root, 'scripts', 'forge-verify.sh'), projectRoot: root, ...base, signal: controller.signal })
    assert.ok(Date.now() - started < 4000)
  })

  it('feedback tells the model the turn is not done and never to edit the referee', () => {
    const text = verifyFeedback({ kind: 'fail', exitCode: 1, logTail: 'G7 FAIL' }, 't1', 'build', 2, 3)
    assert.match(text, /not done/)
    assert.match(text, /Do not edit gate scripts/)
    assert.match(text, /round 2 of 3/)
    assert.match(text, /G7 FAIL/)
  })

  it('tails by lines then characters', () => {
    assert.equal(tailText('a\nb\nc', 5, 100), 'a\nb\nc')
    assert.equal(tailText('a\nb\nc\nd', 2, 100), '[... earlier lines omitted ...]\nc\nd')
  })

  it('counts rounds per agent and turn', () => {
    const r = new VerifyRounds()
    assert.equal(r.next('a', 1), 1)
    assert.equal(r.next('a', 1), 2)
    assert.equal(r.next('a', 2), 1)
    r.reset('a')
    assert.equal(r.next('a', 2), 1)
  })
})

describe('forge_spawn', () => {
  type Parent = { id: string }
  const parent: Parent = { id: 'parent' }

  function fakeSubagents() {
    const calls: { kind: string; arg: unknown }[] = []
    const subagents: SubagentsLike<Parent, string> = {
      async startActivation(spec) {
        calls.push({ kind: 'activation', arg: spec })
        const activation: ActivationLike = {
          childId: spec.childId ?? 'allocated-1',
          result: Promise.resolve({ output: [{ type: 'text', text: 'review.md written' }], stopReason: 'completed' }),
          async dispose() { calls.push({ kind: 'dispose', arg: null }) },
        }
        return activation
      },
      getProvider() { return {} },
    }
    return { subagents, calls }
  }

  it('validates arguments', () => {
    assert.throws(() => parseSpawnArgs({ description: 'x', prompt: 'y', role: 'planner' }), /role must be one of/)
    assert.throws(() => parseSpawnArgs({ description: '', prompt: 'y', role: 'build' }), /description is required/)
    assert.equal(parseSpawnArgs({ description: 'd', prompt: 'p', role: 'review' }).runInBackground, true)
  })

  it('routes a mapped role through agentOptions and registers the role before start', async () => {
    const { config } = parseForgeToml('[roles]\nbuild = "deepseek-official/deepseek-chat"\nreview = ["deepseek-official/deepseek-reasoner", "openrouter/qwen/qwen3-coder"]\n')
    const { subagents, calls } = fakeSubagents()
    const roles = new Map<string, string>()
    const result = await executeSpawn(
      parseSpawnArgs({ description: 'review diff', prompt: 'Review .forge/t1', role: 'review' }),
      planSpawn(config, 'review'),
      {
        subagents,
        providerName: 'spawn',
        parent,
        signal: new AbortController().signal,
        newChildId: () => 'child-1',
        remember: (id, role) => {
          assert.equal(calls.length, 0, 'role registered before startActivation')
          roles.set(id, role)
        },
        forget: id => { roles.delete(id) },
      },
    )
    assert.deepEqual(result, { kind: 'activation', subagentId: 'child-1', role: 'review', route: 'openrouter/qwen/qwen3-coder', family: 'qwen' })
    assert.equal(roles.get('child-1'), 'review')
    const spec = calls[0]!.arg as { childId: string; label: string; delivery: string; request: { agentOptions?: unknown; prompt: unknown } }
    assert.equal(spec.childId, 'child-1')
    assert.equal(spec.delivery, 'parent')
    assert.equal(spec.label, 'review diff')
    assert.deepEqual(spec.request.agentOptions, { provider: 'openrouter', model: 'qwen/qwen3-coder' })
    assert.deepEqual(spec.request.prompt, [{ type: 'text', text: 'Review .forge/t1' }])
  })

  it('inherits when the role is unmapped and waits for the result when run_in_background is false', async () => {
    const { subagents, calls } = fakeSubagents()
    const result = await executeSpawn(
      parseSpawnArgs({ description: 'ground', prompt: 'Explain the parser', role: 'ground', run_in_background: false }),
      planSpawn(parseForgeToml('').config, 'ground'),
      { subagents, providerName: 'spawn', parent, signal: new AbortController().signal, newChildId: () => 'unused', remember: () => {}, forget: () => {} },
    )
    assert.equal(result.kind, 'foreground')
    assert.equal(result.route, 'inherit')
    assert.match(result.note ?? '', /not mapped/)
    assert.equal(result.kind === 'foreground' && result.output, 'review.md written')
    const start = calls[0]!.arg as { delivery: string; request: Record<string, unknown> }
    assert.equal('agentOptions' in start.request, false)
    assert.equal(start.delivery, 'caller')
    assert.equal(calls.at(-1)!.kind, 'dispose')
  })

  it('avoid_family picks the next candidate from another family and reports the family', async () => {
    const { config } = parseForgeToml('[roles]\nbuild = "deepseek-official/deepseek-chat"\nreview = ["openrouter/z-ai/glm-5", "deepseek-official/deepseek-reasoner", "openrouter/qwen/qwen3-coder"]\n[families]\n"glm-5" = "glm"\n')
    const first = planSpawn(config, 'review')
    assert.equal(first.family, 'glm')
    const second = planSpawn(config, 'review', 'glm')
    assert.deepEqual(second.route, { provider: 'deepseek-official', model: 'deepseek-reasoner' })
    assert.equal(second.family, 'deepseek')
    const none = planSpawn(parseForgeToml('[roles]\nreview = "openrouter/z-ai/glm-5"\n[families]\n"glm-5" = "glm"\n').config, 'review', 'glm')
    assert.match(none.note ?? '', /no review candidate outside the glm family/)
    assert.equal(parseSpawnArgs({ description: 'd', prompt: 'p', role: 'review', avoid_family: ' glm ' }).avoidFamily, 'glm')
    const { subagents } = fakeSubagents()
    const result = await executeSpawn(parseSpawnArgs({ description: 'd', prompt: 'p', role: 'review' }), first, { subagents, providerName: 'spawn', parent, signal: new AbortController().signal, newChildId: () => 'c1', remember: () => {}, forget: () => {} })
    assert.equal(result.family, 'glm')
  })

  it('forgets the reserved id when start fails', async () => {
    const { subagents } = fakeSubagents()
    subagents.startActivation = async () => { throw new Error('boom') }
    const roles = new Map<string, string>()
    await assert.rejects(executeSpawn(
      parseSpawnArgs({ description: 'd', prompt: 'p', role: 'build' }),
      planSpawn(parseForgeToml('').config, 'build'),
      { subagents, providerName: 'spawn', parent, signal: new AbortController().signal, newChildId: () => 'c', remember: (id, r) => { roles.set(id, r) }, forget: id => { roles.delete(id) } },
    ), /boom/)
    assert.equal(roles.size, 0)
  })

  it('fails clearly without the subagent service or provider', async () => {
    const args = parseSpawnArgs({ description: 'd', prompt: 'p', role: 'build' })
    const plan = planSpawn(parseForgeToml('').config, 'build')
    const deps = { providerName: 'spawn', parent, signal: new AbortController().signal, newChildId: () => 'c', remember: () => {}, forget: () => {} }
    await assert.rejects(executeSpawn(args, plan, { ...deps, subagents: undefined }), /subagent service/)
    const { subagents } = fakeSubagents()
    subagents.getProvider = () => undefined
    await assert.rejects(executeSpawn(args, plan, { ...deps, subagents }), /provider "spawn" is not registered/)
  })
})
