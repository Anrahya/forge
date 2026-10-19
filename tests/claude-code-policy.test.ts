/**
 * Parity between src/policy.ts and its shell port,
 * adapters/claude-code/scripts/hooks/policy.sh. Each case runs through both
 * and must reach the same allow/deny decision; most cases also pin the
 * expected decision. Skipped without bash and jq. Needs no DSH packages.
 */
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { after, describe, it } from 'node:test'
import { evaluateToolCall, type Phase } from '../src/policy.ts'

const here = dirname(fileURLToPath(import.meta.url))
const script = resolve(here, '..', 'adapters', 'claude-code', 'scripts', 'hooks', 'policy.sh')
const haveTools = spawnSync('bash', ['-c', 'command -v jq'], { encoding: 'utf8' }).status === 0

const root = realpathSync(mkdtempSync(join(tmpdir(), 'forge-cc-parity-')))
after(() => rmSync(root, { recursive: true, force: true }))
mkdirSync(join(root, '.forge', 't1'), { recursive: true })
mkdirSync(join(root, 'src'), { recursive: true })
writeFileSync(join(root, '.forge', 'current'), 't1\n')
const cargo = '[package]\nname = "x"\n\n[dependencies]\nserde = "1"\n\n[dev-dependencies]\nproptest = "1"\n'
writeFileSync(join(root, 'Cargo.toml'), cargo)

function setPhase(phase: Phase | 'none' | 'bogus'): void {
  const state = join(root, '.forge', 't1', 'state.json')
  if (phase === 'none') rmSync(state, { force: true })
  else writeFileSync(state, JSON.stringify({ phase }))
}

const scratch = [...new Set(['/tmp', '/private/tmp', tmpdir(), realpathSync(tmpdir())])]

type CcCall = { tool: 'Write' | 'Edit' | 'Bash'; input: Record<string, string> }

function viaShell(call: CcCall): { kind: 'allow' | 'deny'; reason: string } {
  const res = spawnSync('bash', [script], {
    input: JSON.stringify({ cwd: root, hook_event_name: 'PreToolUse', tool_name: call.tool, tool_input: call.input }),
    encoding: 'utf8',
    env: { ...process.env, TMPDIR: tmpdir() },
  })
  if (res.status !== 0 && res.status !== 2) throw new Error(`policy.sh exit ${res.status}: ${res.stderr}`)
  // Each harness names its own tools in the reason (Write vs write); compare the rest.
  const reason = res.stderr.trim().replace(/\b(Blocked: |forge: )(Write|Edit) /, (_m, lead: string, tool: string) => `${lead}${tool.toLowerCase()} `)
  return { kind: res.status === 2 ? 'deny' : 'allow', reason }
}

function viaTs(call: CcCall, phase: Phase | undefined, problem?: string) {
  const name = call.tool === 'Write' ? 'write' : call.tool === 'Edit' ? 'edit' : 'bash'
  const d = evaluateToolCall({ name, args: call.input }, {
    projectRoot: root,
    cwd: root,
    taskId: 't1',
    phase,
    ...problem === undefined ? {} : { stateProblem: problem },
    scratchDirs: scratch,
    readFile: p => (p === join(root, 'Cargo.toml') ? cargo : undefined),
  })
  return d.kind === 'ask' ? { kind: 'deny' as const, reason: d.reason } : d.kind === 'deny' ? d : { kind: 'allow' as const, reason: '' }
}

const W = (file_path: string, content = 'x'): CcCall => ({ tool: 'Write', input: { file_path, content } })
const E = (file_path: string, old_string: string, new_string: string): CcCall => ({ tool: 'Edit', input: { file_path, old_string, new_string } })
const B = (command: string): CcCall => ({ tool: 'Bash', input: { command } })

const CASES: { phases: Phase[]; call: CcCall; expect?: 'allow' | 'deny' }[] = [
  // read-only phases
  { phases: ['ground', 'scout', 'review', 'verify'], call: W('src/a.ts'), expect: 'deny' },
  { phases: ['ground', 'scout', 'review', 'verify'], call: W('.forge/t1/ground.md'), expect: 'allow' },
  { phases: ['ground', 'review'], call: E('src/a.ts', 'a', 'b'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('npm test 2>&1 | tee .forge/t1/repro.log'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('mkdir -p .forge/t1 && cargo test > .forge/t1/repro.log 2>&1'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('grep -rn foo src | head -20'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B("find . -name '*.ts' -exec grep -l foo {} +"), expect: 'allow' },
  { phases: ['ground', 'review'], call: B("find . -name '*.orig' -exec rm {} \\;"), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('echo "a > b" && ls 2>/dev/null'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('echo hi > src/a.ts'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('rm -rf dist'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('git commit -am wip'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('git status && git diff --stat'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('npm install left-pad'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B("sed -i 's/a/b/' src/a.ts"), expect: 'deny' },
  { phases: ['ground', 'review'], call: B("sed -n 's/a/b/p' src/a.ts"), expect: 'allow' },
  { phases: ['ground', 'review'], call: B("cat > .forge/t1/ground.md <<'EOF'\n# Gotchas\nrm -rf / is bad\nEOF"), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('mkdir -p /tmp/proto && echo x > /tmp/proto/a.ts'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('cd .forge/t1 && echo x > notes.md'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('cd src && echo x > notes.md'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('echo x > "$OUT"'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('bash -c "rm -rf build"'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('ls | xargs rm'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('ls | xargs grep foo'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B("python3 -c \"open('x.txt','w').write('1')\""), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('npx prettier --write .'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('npx tsc --noEmit'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('cargo fmt'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('cargo fmt --check && cargo clippy'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('timeout 60 sed -i s/a/b/ src/a.ts'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('FOO=1 env BAR=2 node -e "console.log(1)"'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('curl -sL https://example.com -o .forge/t1/page.html'), expect: 'allow' },
  { phases: ['ground', 'review'], call: B('curl -sL https://example.com -o page.html'), expect: 'deny' },
  { phases: ['ground', 'review'], call: B('tar xzf pkg.tgz'), expect: 'deny' },
  // guard-referee phases
  { phases: ['shape', 'build', 'report'], call: W('src/a.ts'), expect: 'allow' },
  { phases: ['shape', 'build', 'report'], call: B('git commit -am "fix: parse empty input"'), expect: 'allow' },
  { phases: ['build'], call: B('npm install zod'), expect: 'allow' },
  { phases: ['shape', 'build', 'report'], call: W('scripts/gates/g03-diff-hygiene.sh'), expect: 'deny' },
  { phases: ['build'], call: W('scripts/forge-verify.sh'), expect: 'deny' },
  { phases: ['build'], call: W('packages/web/vitest.config.mts'), expect: 'deny' },
  { phases: ['build'], call: W('jest.config.js'), expect: 'deny' },
  { phases: ['build'], call: W('eslint.config.mjs'), expect: 'deny' },
  { phases: ['build'], call: E('.eslintrc.json', 'a', 'b'), expect: 'deny' },
  { phases: ['build'], call: W('packages/api/tsconfig.build.json'), expect: 'deny' },
  { phases: ['build'], call: W('src/tsconfig-utils.ts'), expect: 'allow' },
  { phases: ['build'], call: W('clippy.toml'), expect: 'deny' },
  { phases: ['build'], call: W('.github/workflows/ci.yml'), expect: 'deny' },
  { phases: ['build', 'ground'], call: W('.forge/t1/verify.log', 'PASS'), expect: 'deny' },
  { phases: ['build'], call: B('echo x >> tsconfig.json'), expect: 'deny' },
  { phases: ['build'], call: B('git checkout -- scripts/gates/g07.sh'), expect: 'deny' },
  { phases: ['build'], call: B("sed -i 's/strict/loose/' tsconfig.json"), expect: 'deny' },
  { phases: ['build'], call: B('rm .forge/t1/verify.log'), expect: 'deny' },
  { phases: ['build'], call: B('cp /tmp/x .github/workflows/ci.yml'), expect: 'deny' },
  { phases: ['build'], call: B('cargo add --dev proptest'), expect: 'deny' },
  { phases: ['build'], call: B('cargo add serde'), expect: 'allow' },
  { phases: ['build'], call: B('npx eslint --fix src'), expect: 'allow' },
  { phases: ['build'], call: B('npx eslint --fix eslint.config.mjs'), expect: 'deny' },
  // Cargo.toml dev-dependencies
  { phases: ['build'], call: E('Cargo.toml', 'serde = "1"', 'serde = "1.0.200"'), expect: 'allow' },
  { phases: ['build'], call: E('Cargo.toml', 'proptest = "1"', 'proptest = "2"'), expect: 'deny' },
  { phases: ['build'], call: E('Cargo.toml', '[package]', '[dev-dependencies]\nfoo = "1"\n\n[package]'), expect: 'deny' },
  { phases: ['build'], call: W('Cargo.toml', cargo.replace('serde = "1"', 'serde = "2"')), expect: 'allow' },
  { phases: ['build'], call: W('Cargo.toml', cargo.replace('proptest = "1"', 'proptest = "1"\ninsta = "1"')), expect: 'deny' },
  { phases: ['build'], call: B("sed -i 's/1/2/' Cargo.toml"), expect: 'deny' },
]

describe('Claude Code policy.sh matches policy.ts', { skip: !haveTools && 'bash or jq missing' }, () => {
  for (const c of CASES) {
    for (const phase of c.phases) {
      const label = `${phase}: ${c.call.tool} ${JSON.stringify(c.call.input).slice(0, 90)}`
      it(label, () => {
        setPhase(phase)
        const sh = viaShell(c.call)
        const ts = viaTs(c.call, phase)
        assert.equal(sh.kind, ts.kind, `shell ${sh.kind} (${sh.reason}) vs ts ${ts.kind} (${ts.reason})`)
        if (c.expect !== undefined) assert.equal(ts.kind, c.expect)
        if (sh.kind === 'deny') assert.equal(sh.reason, ts.reason, 'same model-facing reason')
      })
    }
  }

  it('missing state fails closed in both, with .forge/ writable', () => {
    setPhase('none')
    const problem = '.forge/t1/state.json is missing'
    assert.equal(viaShell(W('src/a.ts')).kind, 'deny')
    assert.equal(viaTs(W('src/a.ts'), undefined, problem).kind, 'deny')
    assert.equal(viaShell(W('src/a.ts')).reason, viaTs(W('src/a.ts'), undefined, problem).reason)
    assert.equal(viaShell(W('.forge/t1/state.json', '{"phase":"ground"}')).kind, 'allow')
  })

  it('is silent when forge is inactive', () => {
    const elsewhere = realpathSync(mkdtempSync(join(tmpdir(), 'forge-cc-off-')))
    const res = spawnSync('bash', [script], { input: JSON.stringify({ cwd: elsewhere, tool_name: 'Write', tool_input: { file_path: 'a.ts', content: 'x' } }), encoding: 'utf8' })
    rmSync(elsewhere, { recursive: true, force: true })
    assert.equal(res.status, 0)
    assert.equal(res.stderr, '')
  })
})

describe('Claude Code stop.sh and inject.sh', { skip: !haveTools && 'bash or jq missing' }, () => {
  const hooks = dirname(script)
  const project = realpathSync(mkdtempSync(join(tmpdir(), 'forge-cc-hooks-')))
  const forgeDir = realpathSync(mkdtempSync(join(tmpdir(), 'forge-cc-dir-')))
  after(() => { rmSync(project, { recursive: true, force: true }); rmSync(forgeDir, { recursive: true, force: true }) })
  mkdirSync(join(project, '.forge', 't1'), { recursive: true })
  mkdirSync(join(project, 'scripts'), { recursive: true })
  writeFileSync(join(project, '.forge', 'current'), 't1\n')
  writeFileSync(join(project, '.forge', 't1', 'state.json'), '{"phase":"build"}')
  mkdirSync(join(forgeDir, 'skills', 'forge-build'), { recursive: true })
  writeFileSync(join(forgeDir, 'skills', 'forge-build', 'SKILL.md'), '---\nname: forge-build\ndescription: d\n---\n# Build loop body\n')
  writeFileSync(join(forgeDir, 'AGENTS.md'), '# forge\n\n## The contract\n\nx\n\n## Principle index\n\n- `prove-it-works`: verify.\n')

  const run = (hook: string, input: Record<string, unknown>) => spawnSync('bash', [join(hooks, hook)], {
    input: JSON.stringify({ cwd: project, session_id: 'parity', ...input }),
    encoding: 'utf8',
    env: { ...process.env, FORGE_DIR: forgeDir, TMPDIR: tmpdir() },
  })
  const verify = (code: number) => writeFileSync(join(project, 'scripts', 'forge-verify.sh'),
    `#!/usr/bin/env bash\n[ "$1 $2 $3 $4" = "--task-dir .forge/t1 --phase build" ] || exit 9\necho "G5 FAIL: diff 900 > budget 600" > .forge/t1/verify.log\nexit ${code}\n`)

  it('blocks the stop with the verify.log tail, then allows after the round cap', () => {
    verify(1)
    const first = run('stop.sh', { hook_event_name: 'Stop', stop_hook_active: false })
    assert.equal(first.status, 2)
    assert.match(first.stderr, /BUILD gates failed[\s\S]*G5 FAIL: diff 900 > budget 600[\s\S]*round 1 of 3/)
    assert.equal(run('stop.sh', { hook_event_name: 'Stop', stop_hook_active: true }).status, 2)
    assert.equal(run('stop.sh', { hook_event_name: 'Stop', stop_hook_active: true }).status, 2)
    const capped = run('stop.sh', { hook_event_name: 'Stop', stop_hook_active: true })
    assert.equal(capped.status, 0)
    assert.match(JSON.parse(capped.stdout).systemMessage, /still fail after 3 verify rounds/)
  })

  it('allows the stop when verification passes and reports other exits as errors', () => {
    verify(0)
    assert.equal(run('stop.sh', { hook_event_name: 'Stop', stop_hook_active: false }).status, 0)
    verify(7)
    const broken = run('stop.sh', { hook_event_name: 'Stop', stop_hook_active: false })
    assert.equal(broken.status, 2)
    assert.match(broken.stderr, /exit 7 \(expected 0 or 1\)/)
  })

  it('injects the phase skill body and the principle index only', () => {
    const out = run('inject.sh', { hook_event_name: 'UserPromptSubmit', prompt: 'go' })
    assert.equal(out.status, 0)
    assert.match(out.stdout, /^<forge-context task="t1" phase="build">/)
    assert.match(out.stdout, /# Build loop body/)
    assert.doesNotMatch(out.stdout, /name: forge-build/)
    assert.match(out.stdout, /## Principle index[\s\S]*prove-it-works/)
    assert.doesNotMatch(out.stdout, /The contract/)
  })
})
