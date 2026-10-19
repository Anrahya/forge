import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { cargoDevDepsReason, devDepsText, evaluateToolCall, isRefereePath, type Phase, type PolicyContext } from '../src/policy.ts'
import { analyzeShell } from '../src/shell.ts'

const ROOT = '/repo'

function ctx(phase: Phase | undefined, extra: Partial<PolicyContext> = {}): PolicyContext {
  return { projectRoot: ROOT, cwd: ROOT, taskId: 't1', phase, scratchDirs: ['/tmp'], ...extra }
}

function decide(phase: Phase | undefined, name: string, args: Record<string, unknown>, extra: Partial<PolicyContext> = {}) {
  return evaluateToolCall({ name, args }, ctx(phase, extra))
}

const bash = (command: string) => ({ command, description: 'x' })

describe('read-only phases (ground, scout, review, verify)', () => {
  for (const phase of ['ground', 'scout', 'review', 'verify'] as const) {
    it(`${phase}: denies source writes through every write tool`, () => {
      assert.equal(decide(phase, 'write', { file_path: 'src/a.ts', content: 'x' }).kind, 'deny')
      assert.equal(decide(phase, 'edit', { file_path: '/repo/src/a.ts', old_string: 'a', new_string: 'b' }).kind, 'deny')
      assert.equal(decide(phase, 'str_replace_editor', { command: 'create', path: '/repo/src/new.ts', file_text: 'x' }).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash('echo hi > src/a.ts')).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash('rm -rf dist')).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash('git commit -am wip')).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash('npm install left-pad')).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash("sed -i 's/a/b/' src/a.ts")).kind, 'deny')
      assert.equal(decide(phase, 'pwsh', { command: 'Set-Content -Path src/a.ts -Value x' }).kind, 'deny')
    })

    it(`${phase}: allows reads, tests, and writes under .forge/`, () => {
      assert.equal(decide(phase, 'read', { file_path: 'src/a.ts' }).kind, 'allow')
      assert.equal(decide(phase, 'str_replace_editor', { command: 'view', path: '/repo/src' }).kind, 'allow')
      assert.equal(decide(phase, 'write', { file_path: '.forge/t1/ground.md', content: '# Overview' }).kind, 'allow')
      assert.equal(decide(phase, 'bash', bash('npm test 2>&1 | tee .forge/t1/repro.log')).kind, 'allow')
      assert.equal(decide(phase, 'bash', bash('mkdir -p .forge/t1 && cargo test > .forge/t1/repro.log 2>&1')).kind, 'allow')
      assert.equal(decide(phase, 'bash', bash('grep -rn foo src | head -20')).kind, 'allow')
      assert.equal(decide(phase, 'bash', bash('git status && git diff --stat')).kind, 'allow')
      assert.equal(decide(phase, 'bash', bash("find . -name '*.ts' -exec grep -l foo {} +")).kind, 'allow')
      assert.equal(decide(phase, 'bash', bash('echo "a > b" && ls 2>/dev/null')).kind, 'allow')
    })
  }

  it('the deny reason names the phase, the target, and where writes go', () => {
    const d = decide('ground', 'edit', { file_path: 'src/a.ts', old_string: 'a', new_string: 'b' })
    assert.equal(d.kind, 'deny')
    assert.match(d.kind === 'deny' ? d.reason : '', /phase "ground" is read-only/)
    assert.match(d.kind === 'deny' ? d.reason : '', /edit src\/a\.ts/)
    assert.match(d.kind === 'deny' ? d.reason : '', /\.forge\/t1\/ground\.md/)
  })

  it('heredoc bodies are data: writing an artifact with a heredoc is allowed', () => {
    const cmd = "cat > .forge/t1/ground.md <<'EOF'\n# Gotchas\nrm -rf / would be bad\ngit commit is not run here\nEOF"
    assert.equal(decide('ground', 'bash', bash(cmd)).kind, 'allow')
  })

  it('scratch directories stay writable for prototypes', () => {
    assert.equal(decide('scout', 'bash', bash('mkdir -p /tmp/proto && echo x > /tmp/proto/a.ts')).kind, 'allow')
    assert.equal(decide('scout', 'write', { file_path: '/home/me/notes.md', content: 'x' }).kind, 'deny')
  })

  it('cd inside the command moves the base for relative targets', () => {
    assert.equal(decide('ground', 'bash', bash('cd .forge/t1 && echo x > notes.md')).kind, 'allow')
    assert.equal(decide('ground', 'bash', bash('cd src && echo x > notes.md')).kind, 'deny')
    assert.equal(decide('ground', 'bash', { command: 'echo x > notes.md', workdir: '.forge/t1' }).kind, 'allow')
  })

  it('variable targets and nested shells are treated as unknown writes', () => {
    assert.equal(decide('review', 'bash', bash('echo x > "$OUT"')).kind, 'deny')
    assert.equal(decide('review', 'bash', bash('bash -c "rm -rf build"')).kind, 'deny')
    assert.equal(decide('review', 'bash', bash('ls | xargs rm')).kind, 'deny')
    assert.equal(decide('review', 'bash', bash("python3 -c \"open('x.txt','w').write('1')\"")).kind, 'deny')
    assert.equal(decide('review', 'bash', bash('npx prettier --write .')).kind, 'deny')
    assert.equal(decide('review', 'bash', bash('cargo fmt')).kind, 'deny')
    assert.equal(decide('review', 'bash', bash('cargo fmt --check')).kind, 'allow')
  })
})

describe('build, shape, and report guard referee paths', () => {
  for (const phase of ['shape', 'build', 'report'] as const) {
    it(`${phase}: allows ordinary writes`, () => {
      assert.equal(decide(phase, 'write', { file_path: 'src/a.ts', content: 'x' }).kind, 'allow')
      assert.equal(decide(phase, 'bash', bash('git commit -am "fix: parse empty input"')).kind, 'allow')
      assert.equal(decide(phase, 'bash', bash('npm install zod')).kind, 'allow')
    })

    it(`${phase}: denies referee files through every write tool`, () => {
      const referees = [
        'scripts/gates/g03-diff-hygiene.sh',
        'scripts/forge-verify.sh',
        'vitest.config.ts',
        'packages/web/vitest.config.mts',
        'jest.config.js',
        'eslint.config.mjs',
        '.eslintrc.json',
        'tsconfig.json',
        'packages/api/tsconfig.build.json',
        'clippy.toml',
        '.github/workflows/ci.yml',
        '.forge/t1/verify.log',
      ]
      for (const path of referees) {
        const write = decide(phase, 'write', { file_path: path, content: 'x' })
        assert.equal(write.kind, 'deny', `write ${path}`)
        assert.equal(decide(phase, 'edit', { file_path: path, old_string: 'a', new_string: 'b' }).kind, 'deny', `edit ${path}`)
        assert.equal(decide(phase, 'bash', bash(`echo x >> ${path}`)).kind, 'deny', `bash >> ${path}`)
      }
    })

    it(`${phase}: catches referee paths in opaque shell writes`, () => {
      assert.equal(decide(phase, 'bash', bash('git checkout -- scripts/gates/g07.sh')).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash("sed -i 's/strict/loose/' tsconfig.json")).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash('rm .forge/t1/verify.log')).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash('cp /tmp/x .github/workflows/ci.yml')).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash('cargo add --dev proptest')).kind, 'deny')
      assert.equal(decide(phase, 'bash', bash('cargo add serde')).kind, 'allow')
    })
  }

  it('the referee reason points at S5 instead of a workaround', () => {
    const d = decide('build', 'write', { file_path: 'vitest.config.ts', content: '' })
    assert.equal(d.kind, 'deny')
    assert.match(d.kind === 'deny' ? d.reason : '', /S5/)
  })

  it('verify.log is referee even in read-only phases', () => {
    const d = decide('ground', 'write', { file_path: '.forge/t1/verify.log', content: 'PASS' })
    assert.equal(d.kind, 'deny')
    assert.match(d.kind === 'deny' ? d.reason : '', /forge-verify\.sh/)
  })
})

describe('Cargo.toml dev-dependencies', () => {
  const cargo = '[package]\nname = "x"\n\n[dependencies]\nserde = "1"\n\n[dev-dependencies]\nproptest = "1"\n'
  const readFile = (p: string) => (p === '/repo/Cargo.toml' ? cargo : undefined)

  it('allows edits to [dependencies]', () => {
    assert.equal(decide('build', 'edit', { file_path: 'Cargo.toml', old_string: 'serde = "1"', new_string: 'serde = "1.0.200"' }, { readFile }).kind, 'allow')
  })

  it('denies edits inside [dev-dependencies]', () => {
    assert.equal(decide('build', 'edit', { file_path: 'Cargo.toml', old_string: 'proptest = "1"', new_string: 'proptest = "2"' }, { readFile }).kind, 'deny')
  })

  it('denies edits that add a dev-dependencies header', () => {
    const d = decide('build', 'edit', { file_path: 'Cargo.toml', old_string: '[package]', new_string: '[dev-dependencies]\nfoo = "1"\n\n[package]' }, { readFile })
    assert.equal(d.kind, 'deny')
  })

  it('full rewrites pass only when the dev-dependencies section is unchanged', () => {
    const same = cargo.replace('serde = "1"', 'serde = "1.0.200"')
    assert.equal(decide('build', 'write', { file_path: 'Cargo.toml', content: same }, { readFile }).kind, 'allow')
    const changed = cargo.replace('proptest = "1"', 'proptest = "1"\nquickcheck = "1"')
    assert.equal(decide('build', 'write', { file_path: 'Cargo.toml', content: changed }, { readFile }).kind, 'deny')
  })

  it('target-specific dev-dependencies count too', () => {
    assert.equal(devDepsText('[target.\'cfg(unix)\'.dev-dependencies]\nnix = "1"\n'), 'nix = "1"')
  })

  it('a shell write to Cargo.toml cannot be checked and is denied in build', () => {
    assert.equal(decide('build', 'bash', bash("sed -i 's/1/2/' Cargo.toml"), { readFile }).kind, 'deny')
    assert.equal(cargoDevDepsReason({ kind: 'path', path: '/repo/Cargo.toml', via: 'tee' }, cargo)?.includes('cannot be checked'), true)
  })

  it('str_replace_editor insert checks the target line section', () => {
    assert.equal(decide('build', 'str_replace_editor', { command: 'insert', path: '/repo/Cargo.toml', insert_line: 5, new_str: 'anyhow = "1"' }, { readFile }).kind, 'allow')
    assert.equal(decide('build', 'str_replace_editor', { command: 'insert', path: '/repo/Cargo.toml', insert_line: 8, new_str: 'insta = "1"' }, { readFile }).kind, 'deny')
  })
})

describe('state and role handling', () => {
  it('a missing phase fails closed but keeps .forge/ writable', () => {
    const extra = { stateProblem: '.forge/t1/state.json is missing' }
    const d = decide(undefined, 'write', { file_path: 'src/a.ts', content: 'x' }, extra)
    assert.equal(d.kind, 'deny')
    assert.match(d.kind === 'deny' ? d.reason : '', /state\.json is missing/)
    assert.equal(decide(undefined, 'write', { file_path: '.forge/t1/state.json', content: '{"phase":"ground"}' }, extra).kind, 'allow')
  })

  it('a review child is read-only even while the task is in build', () => {
    assert.equal(decide('build', 'write', { file_path: 'src/a.ts', content: 'x' }, { rolePhase: 'review' }).kind, 'deny')
    assert.equal(decide('build', 'write', { file_path: 'src/a.ts', content: 'x' }, { rolePhase: 'build' }).kind, 'allow')
  })

  it('a build child cannot write while the task is in a read-only phase', () => {
    assert.equal(decide('review', 'write', { file_path: 'src/a.ts', content: 'x' }, { rolePhase: 'build' }).kind, 'deny')
  })

  it('forge_spawn with the escalation role asks the human', () => {
    assert.equal(decide('build', 'forge_spawn', { role: 'escalation', description: 'x', prompt: 'y' }).kind, 'ask')
    assert.equal(decide('build', 'forge_spawn', { role: 'review', description: 'x', prompt: 'y' }).kind, 'allow')
  })

  it('unknown tools pass through', () => {
    assert.equal(decide('ground', 'web_fetch', { url: 'https://example.com' }).kind, 'allow')
    assert.equal(decide('ground', 'run_code', { code: 'await tools.write({})', description: 'x' }).kind, 'allow')
  })
})

describe('isRefereePath', () => {
  it('matches config basenames at any depth and nothing outside the project', () => {
    assert.equal(isRefereePath('a/b/tsconfig.app.json'), true)
    assert.equal(isRefereePath('src/tsconfig-utils.ts'), false)
    assert.equal(isRefereePath('../other/tsconfig.json'), false)
    assert.equal(isRefereePath('scripts/gates'), true)
    assert.equal(isRefereePath('scripts/gatesy.sh'), false)
  })
})

describe('analyzeShell', () => {
  it('resolves redirect targets and ignores descriptor duplication', () => {
    const writes = analyzeShell('make 2>&1 >/dev/null; cmd > out.txt 2> err.txt', '/w')
    assert.deepEqual(writes.map(w => (w.kind === 'path' ? w.path : w.via)), ['/w/out.txt', '/w/err.txt'])
  })

  it('treats quoted operators as text', () => {
    assert.deepEqual(analyzeShell("echo 'a; rm -rf x' && grep '>' f", '/w'), [])
  })

  it('records mv sources and destinations', () => {
    const writes = analyzeShell('mv a.ts b.ts', '/w')
    assert.deepEqual(writes.map(w => (w.kind === 'path' ? w.path : '')), ['/w/a.ts', '/w/b.ts'])
  })

  it('skips the mode operand of chmod', () => {
    const writes = analyzeShell('chmod +x scripts/run.sh', '/w')
    assert.deepEqual(writes.map(w => (w.kind === 'path' ? w.path : '')), ['/w/scripts/run.sh'])
  })
})
