/**
 * Static write detection for shell commands. Pure: no DSH imports, no I/O.
 *
 * This is a heuristic, not a sandbox. It answers one question for the policy:
 * which paths might this command write, and is there a write whose target we
 * cannot name? The rules are listed in README.md ("Shell write heuristic").
 * Anything a command can do through a program we do not model (make, npm run,
 * a script file) is invisible here; the gates are the backstop.
 */
import { posix } from 'node:path'

/** One write found in a command. */
export type ShellWrite =
  | {
    /** A write to a path we could resolve. */
    readonly kind: 'path'
    readonly path: string
    /** The command word or redirect that writes it, for the denial reason. */
    readonly via: string
  }
  | {
    /** A write whose target we cannot resolve (git commit, npm install, a variable path). */
    readonly kind: 'opaque'
    readonly via: string
    /** Absolute forms of every path-like argument, for referee matching. */
    readonly mentions: readonly string[]
    /** `cargo add --dev` and friends: edits Cargo.toml dev-dependencies. */
    readonly cargoDevDeps?: true
  }

type Token =
  | { readonly t: 'word'; readonly v: string; readonly unresolved: boolean }
  | { readonly t: 'sep' }
  | { readonly t: 'redir'; readonly op: string }

const SEPARATORS = new Set([';', '&&', '||', '|', '&', '\n', '|&'])
const HARMLESS_TARGETS = new Set(['/dev/null', '/dev/stdout', '/dev/stderr', '/dev/tty'])

/**
 * Split a command into words, separators, and redirect operators. Quotes are
 * honored, heredoc bodies are dropped (they are data, not commands), and a
 * word containing `$`, a backtick, a glob, or a leading `~` is marked
 * unresolved because its path is not knowable statically.
 */
export function tokenize(command: string): Token[] {
  const out: Token[] = []
  const heredocs: { delim: string; strip: boolean }[] = []
  let i = 0
  const n = command.length
  let word = ''
  let inWord = false
  let unresolved = false
  let expectHeredocDelim: { strip: boolean } | undefined

  const flush = () => {
    if (!inWord) return
    if (expectHeredocDelim !== undefined) {
      heredocs.push({ delim: word, strip: expectHeredocDelim.strip })
      expectHeredocDelim = undefined
    } else {
      out.push({ t: 'word', v: word, unresolved })
    }
    word = ''
    inWord = false
    unresolved = false
  }

  while (i < n) {
    const c = command[i]!
    if (c === '\\' && i + 1 < n) {
      if (command[i + 1] === '\n') { i += 2; continue }
      word += command[i + 1]
      inWord = true
      i += 2
      continue
    }
    if (c === "'") {
      const end = command.indexOf("'", i + 1)
      const stop = end < 0 ? n : end
      word += command.slice(i + 1, stop)
      inWord = true
      i = stop + 1
      continue
    }
    if (c === '"') {
      let j = i + 1
      while (j < n && command[j] !== '"') {
        if (command[j] === '\\' && j + 1 < n) { word += command[j + 1]; j += 2; continue }
        if (command[j] === '$' || command[j] === '`') unresolved = true
        word += command[j]
        j += 1
      }
      inWord = true
      i = j + 1
      continue
    }
    if (c === '$' && command[i + 1] === '(') {
      // Command substitution: keep it inside the word, unresolved.
      let depth = 0
      let j = i + 1
      for (; j < n; j += 1) {
        if (command[j] === '(') depth += 1
        else if (command[j] === ')') { depth -= 1; if (depth === 0) break }
      }
      word += command.slice(i, j + 1)
      inWord = true
      unresolved = true
      i = j + 1
      continue
    }
    if (c === '`') {
      const end = command.indexOf('`', i + 1)
      const stop = end < 0 ? n : end
      word += command.slice(i, stop + 1)
      inWord = true
      unresolved = true
      i = stop + 1
      continue
    }
    if (c === '\n') {
      flush()
      out.push({ t: 'sep' })
      i += 1
      // Drop heredoc bodies that start on the next line.
      while (heredocs.length > 0) {
        const doc = heredocs.shift()!
        while (i < n) {
          const eol = command.indexOf('\n', i)
          const lineEnd = eol < 0 ? n : eol
          const line = command.slice(i, lineEnd)
          i = lineEnd + 1
          if ((doc.strip ? line.replace(/^\t+/, '') : line) === doc.delim) break
        }
      }
      continue
    }
    if (c === ' ' || c === '\t') { flush(); i += 1; continue }
    if (c === '#' && !inWord) {
      const eol = command.indexOf('\n', i)
      i = eol < 0 ? n : eol
      continue
    }
    // Operators.
    const rest = command.slice(i, i + 3)
    if (rest.startsWith('<<')) {
      flush()
      const strip = rest[2] === '-'
      i += strip ? 3 : 2
      if (command[i] === '<') { i += 1; continue } // here-string <<<: next word is data
      expectHeredocDelim = { strip }
      continue
    }
    if (rest.startsWith('&>')) {
      flush()
      const op = rest.startsWith('&>>') ? '&>>' : '&>'
      out.push({ t: 'redir', op })
      i += op.length
      continue
    }
    if (c === '>' || (/[0-9]/.test(c) && !inWord && command[i + 1] === '>')) {
      // A digit is a file-descriptor prefix only at the start of a word.
      flush()
      let j = i
      if (c !== '>') j += 1
      let op = '>'
      if (command[j + 1] === '>') op = '>>'
      else if (command[j + 1] === '|') op = '>|'
      j += op.length
      if (command[j] === '&') {
        // >&2, 2>&1: descriptor duplication, not a file.
        j += 1
        while (j < n && /[0-9-]/.test(command[j]!)) j += 1
        i = j
        continue
      }
      out.push({ t: 'redir', op })
      i = j
      continue
    }
    if (c === '<') { flush(); out.push({ t: 'redir', op: '<' }); i += 1; continue }
    if (c === ';' || c === '|' || c === '&' || c === '(' || c === ')') {
      flush()
      const two = command.slice(i, i + 2)
      if (two === '&&' || two === '||' || two === '|&' || two === ';;') i += 2
      else i += 1
      out.push({ t: 'sep' })
      continue
    }
    if (c === '$' || c === '*' || c === '?' || c === '[' || c === '{' || (c === '~' && !inWord)) unresolved = true
    word += c
    inWord = true
    i += 1
  }
  flush()
  return out
}

type Word = { readonly v: string; readonly unresolved: boolean }

interface Segment {
  readonly words: Word[]
  readonly redirects: { op: string; target?: Word }[]
}

function segments(tokens: Token[]): Segment[] {
  const segs: Segment[] = []
  let cur: Segment = { words: [], redirects: [] }
  for (let k = 0; k < tokens.length; k += 1) {
    const tok = tokens[k]!
    if (tok.t === 'sep') {
      if (cur.words.length > 0 || cur.redirects.length > 0) segs.push(cur)
      cur = { words: [], redirects: [] }
      continue
    }
    if (tok.t === 'redir') {
      const next = tokens[k + 1]
      if (next !== undefined && next.t === 'word') {
        cur.redirects.push({ op: tok.op, target: { v: next.v, unresolved: next.unresolved } })
        k += 1
      } else {
        cur.redirects.push({ op: tok.op })
      }
      continue
    }
    cur.words.push({ v: tok.v, unresolved: tok.unresolved })
  }
  if (cur.words.length > 0 || cur.redirects.length > 0) segs.push(cur)
  return segs
}

const WRAPPERS = new Set(['sudo', 'command', 'builtin', 'nice', 'nohup', 'time', 'exec', 'doas', 'stdbuf', 'timeout'])
const GIT_MUTATING = new Set([
  'add', 'am', 'apply', 'checkout', 'cherry-pick', 'clean', 'commit', 'init', 'merge', 'mv', 'pull',
  'push', 'rebase', 'reset', 'restore', 'revert', 'rm', 'stash', 'switch', 'tag', 'worktree', 'submodule',
])
const PM_MUTATING = new Set([
  'install', 'i', 'ci', 'add', 'remove', 'rm', 'uninstall', 'un', 'update', 'up', 'upgrade', 'link',
  'unlink', 'dedupe', 'prune', 'init', 'version', 'publish', 'patch', 'import',
])
const CARGO_MUTATING = new Set(['add', 'remove', 'rm', 'update', 'fix', 'install', 'new', 'init', 'generate-lockfile', 'vendor'])
const INLINE_WRITE_API = /writeFile|appendFile|createWriteStream|\bunlink|rmSync|rmdir|mkdir|rename|copyFile|truncate|open\([^)]*['"][wax]\+?['"]|write_text|write_bytes|os\.remove|shutil\.|File\.write|IO\.write/

/** Basename of a command word, so `/usr/bin/rm` reads as `rm`. */
function commandName(word: string): string {
  const slash = word.lastIndexOf('/')
  return slash < 0 ? word : word.slice(slash + 1)
}

function isOption(v: string): boolean {
  return v.startsWith('-') && v !== '-'
}

/** Short-option cluster containing the given flag letter, such as `-pi` for `i`. */
function hasShortFlag(words: readonly Word[], letter: string): boolean {
  return words.some(w => /^-[A-Za-z]+/.test(w.v) && !w.v.startsWith('--') && w.v.slice(1).split(/[^A-Za-z]/)[0]!.includes(letter))
}

function hasLong(words: readonly Word[], ...names: string[]): boolean {
  return words.some(w => names.some(name => w.v === name || w.v.startsWith(`${name}=`)))
}

class Collector {
  readonly writes: ShellWrite[] = []
  private base: string
  constructor(base: string) {
    this.base = base
  }

  get cwd(): string { return this.base }

  cd(target: Word | undefined): void {
    if (target === undefined || target.unresolved || target.v === '-') return
    this.base = posix.resolve(this.base, target.v)
  }

  path(word: Word, via: string): void {
    if (word.unresolved) {
      this.writes.push({ kind: 'opaque', via, mentions: [] })
      return
    }
    this.writes.push({ kind: 'path', path: posix.resolve(this.base, word.v), via })
  }

  opaque(via: string, words: readonly Word[], cargoDevDeps = false): void {
    const mentions = words
      .filter(w => !w.unresolved && !isOption(w.v) && w.v.length > 0)
      .map(w => posix.resolve(this.base, w.v.replace(/^[A-Za-z_][\w-]*=/, '')))
    this.writes.push({ kind: 'opaque', via, mentions, ...cargoDevDeps ? { cargoDevDeps: true as const } : {} })
  }
}

/** Non-option operands, skipping the values of options that take one. */
function operands(words: readonly Word[], valued: readonly string[] = []): Word[] {
  const out: Word[] = []
  let skip = false
  let endOfOptions = false
  for (const w of words) {
    if (skip) { skip = false; continue }
    if (!endOfOptions && w.v === '--') { endOfOptions = true; continue }
    if (!endOfOptions && isOption(w.v)) {
      if (valued.includes(w.v)) skip = true
      continue
    }
    out.push(w)
  }
  return out
}

/** Words from the first operand on, keeping that command's own options intact. */
function afterLeadingOptions(words: readonly Word[], valued: readonly string[]): Word[] {
  let k = 0
  while (k < words.length && isOption(words[k]!.v)) k += valued.includes(words[k]!.v) ? 2 : 1
  return words.slice(k)
}

function analyzeSegment(seg: Segment, out: Collector, depth: number): void {
  for (const r of seg.redirects) {
    if (r.op === '<') continue
    if (r.target === undefined) { out.opaque(r.op, []); continue }
    if (HARMLESS_TARGETS.has(r.target.v)) continue
    out.path(r.target, `redirect ${r.op}`)
  }

  let words = seg.words
  // Strip env assignments and wrapper commands.
  for (;;) {
    const first = words[0]
    if (first === undefined) return
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(first.v)) { words = words.slice(1); continue }
    const name = commandName(first.v)
    if (name === 'env') {
      words = words.slice(1)
      while (words[0] !== undefined && (isOption(words[0].v) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0].v))) words = words.slice(1)
      continue
    }
    if (name === 'timeout') { words = afterLeadingOptions(words.slice(1), ['-s', '-k', '--signal', '--kill-after']).slice(1); continue }
    if (WRAPPERS.has(name)) { words = words.slice(1); while (words[0] !== undefined && isOption(words[0].v)) words = words.slice(1); continue }
    if (name === 'xargs') {
      // xargs appends stdin words as arguments: model them as one unknown operand.
      const rest = operands(words.slice(1), ['-I', '-n', '-P', '-L', '-d', '-E', '-s'])
      if (rest.length > 0 && writesWithUnknownOperand(rest, out.cwd, depth)) out.opaque(`xargs ${commandName(rest[0]!.v)}`, rest)
      return
    }
    break
  }

  const cmdWord = words[0]!
  const cmd = commandName(cmdWord.v)
  const args = words.slice(1)

  switch (cmd) {
    case 'cd':
    case 'pushd':
      out.cd(operands(args)[0])
      return
    case 'rm': case 'rmdir': case 'unlink': case 'touch': case 'mkdir': case 'shred':
      for (const w of operands(args, ['-m'])) out.path(w, cmd)
      return
    case 'truncate':
      for (const w of operands(args, ['-s', '-r'])) out.path(w, cmd)
      return
    case 'chmod': case 'chown': case 'chgrp':
      for (const w of operands(args, ['--reference']).slice(1)) out.path(w, cmd)
      return
    case 'mv':
      for (const w of operands(args, ['-t', '-S'])) out.path(w, cmd)
      return
    case 'cp': case 'ln': case 'install': case 'rsync': {
      const tIdx = args.findIndex(w => w.v === '-t' || w.v === '--target-directory')
      if (tIdx >= 0 && args[tIdx + 1] !== undefined) { out.path(args[tIdx + 1]!, cmd); return }
      const ops = operands(args, ['-m', '-o', '-g', '-S', '-e', '--exclude', '--include'])
      const dest = ops[ops.length - 1]
      if (dest !== undefined) out.path(dest, cmd)
      return
    }
    case 'tee':
      for (const w of operands(args)) out.path(w, cmd)
      return
    case 'dd':
      for (const w of args) if (w.v.startsWith('of=')) out.path({ v: w.v.slice(3), unresolved: w.unresolved }, 'dd')
      return
    case 'sed': case 'perl': case 'ruby': {
      const inPlace = hasShortFlag(args, 'i') || hasLong(args, '--in-place')
      if (inPlace) {
        const scriptGiven = args.some(w => w.v === '-e' || w.v === '-f' || w.v.startsWith('--expression') || w.v.startsWith('--file'))
        const files = operands(args, ['-e', '-f', '--expression', '--file'])
        for (const w of scriptGiven ? files : files.slice(1)) out.path(w, `${cmd} -i`)
        return
      }
      if (cmd !== 'sed') inlineInterpreter(cmd, args, out)
      return
    }
    case 'node': case 'python': case 'python3': case 'deno':
      inlineInterpreter(cmd, args, out)
      return
    case 'bash': case 'sh': case 'zsh': case 'dash': {
      const cIdx = args.findIndex(w => w.v === '-c' || (/^-[a-z]*c$/.test(w.v)))
      const body = cIdx >= 0 ? args[cIdx + 1] : undefined
      if (body !== undefined && depth < 4) analyzeInto(body.v, out, depth + 1)
      return
    }
    case 'eval':
      if (depth < 4) analyzeInto(args.map(w => w.v).join(' '), out, depth + 1)
      return
    case 'find': {
      if (args.some(w => ['-delete', '-fprint', '-fprintf', '-fls'].includes(w.v))) { out.opaque('find -delete', args); return }
      for (let k = 0; k < args.length; k += 1) {
        if (!['-exec', '-execdir', '-ok', '-okdir'].includes(args[k]!.v)) continue
        const end = args.findIndex((w, idx) => idx > k && (w.v === ';' || w.v === '+'))
        const inner = args.slice(k + 1, end < 0 ? args.length : end).map(w => (w.v === '{}' ? UNKNOWN_OPERAND : w))
        if (inner.length > 0 && writesWithUnknownOperand(inner, out.cwd, depth, false)) out.opaque(`find ${args[k]!.v} ${commandName(inner[0]!.v)}`, args)
      }
      return
    }
    case 'curl': {
      const oIdx = args.findIndex(w => w.v === '-o' || w.v === '--output')
      if (oIdx >= 0 && args[oIdx + 1] !== undefined) out.path(args[oIdx + 1]!, 'curl -o')
      if (args.some(w => w.v === '-O' || w.v === '--remote-name' || w.v === '--remote-name-all')) out.opaque('curl -O', [])
      return
    }
    case 'wget': {
      const oIdx = args.findIndex(w => w.v === '-O' || w.v === '--output-document')
      if (oIdx >= 0 && args[oIdx + 1] !== undefined) { if (args[oIdx + 1]!.v !== '-') out.path(args[oIdx + 1]!, 'wget -O') }
      else out.opaque('wget', args)
      return
    }
    case 'tar':
      if (hasShortFlag(args, 'x') || /^[a-z]*x/.test(args[0]?.v ?? '') || hasLong(args, '--extract', '--get')) out.opaque('tar -x', args)
      return
    case 'unzip': case 'gunzip': case 'bunzip2': case 'unxz':
      if (!hasShortFlag(args, 'l') && !hasShortFlag(args, 't')) out.opaque(cmd, args)
      return
    case 'patch':
      out.opaque('patch', args)
      return
    case 'git': {
      const rest = operands(args, ['-C', '-c', '--git-dir', '--work-tree', '--namespace'])
      const sub = rest[0]?.v
      if (sub === undefined) return
      if (GIT_MUTATING.has(sub) || (sub === 'branch' && rest.length > 1) || (sub === 'stash' && rest.length >= 1)) out.opaque(`git ${sub}`, rest.slice(1))
      return
    }
    case 'npx': case 'bunx': case 'pnpx': {
      const inner = afterLeadingOptions(args, ['-p', '--package', '-c'])
      if (inner.length > 0) analyzeSegment({ words: inner, redirects: [] }, out, depth + 1)
      return
    }
    case 'npm': case 'pnpm': case 'yarn': case 'bun': {
      const ops = operands(args, ['--prefix', '-C', '--filter', '--dir', '-w', '--cwd'])
      const sub = ops[0]?.v
      if (sub === undefined) { if (cmd === 'bun') inlineInterpreter(cmd, args, out); return }
      if (['exec', 'dlx', 'x'].includes(sub)) {
        const subIdx = args.findIndex(w => w.v === sub)
        const inner = afterLeadingOptions(args.slice(subIdx + 1), ['-p', '--package', '-c'])
        if (inner.length > 0) analyzeSegment({ words: inner, redirects: [] }, out, depth + 1)
        return
      }
      if (PM_MUTATING.has(sub)) { out.opaque(`${cmd} ${sub}`, args); return }
      if (cmd === 'bun') inlineInterpreter(cmd, args, out)
      return
    }
    case 'pip': case 'pip3': case 'uv': case 'poetry': case 'pipx': {
      const sub = operands(args)[0]?.v
      if (sub !== undefined && ['install', 'uninstall', 'add', 'remove', 'sync', 'lock', 'update', 'init'].includes(sub)) out.opaque(`${cmd} ${sub}`, args)
      return
    }
    case 'cargo': {
      const ops = operands(args, ['--manifest-path', '-p', '--package', '-Z', '--config'])
      const sub = ops[0]?.v
      if (sub === undefined) return
      const dev = hasLong(args, '--dev') || args.some(w => w.v === '-D')
      if ((sub === 'add' || sub === 'remove' || sub === 'rm') && dev) { out.opaque(`cargo ${sub} --dev`, args, true); return }
      if (CARGO_MUTATING.has(sub)) { out.opaque(`cargo ${sub}`, args); return }
      if (sub === 'fmt' && !hasLong(args, '--check')) { out.opaque('cargo fmt', args); return }
      if (sub === 'clippy' && hasLong(args, '--fix')) out.opaque('cargo clippy --fix', args)
      return
    }
    case 'rustfmt': case 'black':
      if (!hasLong(args, '--check')) out.opaque(cmd, args)
      return
    case 'gofmt': case 'goimports':
      if (hasShortFlag(args, 'w')) out.opaque(`${cmd} -w`, args)
      return
    case 'prettier':
      if (hasLong(args, '--write') || args.some(w => w.v === '-w')) out.opaque('prettier --write', args)
      return
    case 'eslint':
      if (hasLong(args, '--fix')) out.opaque('eslint --fix', args)
      return
    case 'biome':
      if (hasLong(args, '--write', '--apply', '--apply-unsafe', '--fix')) out.opaque('biome --write', args)
      return
    case 'ruff':
      if (hasLong(args, '--fix') || (args[0]?.v === 'format' && !hasLong(args, '--check'))) out.opaque('ruff --fix', args)
      return
    default:
      return
  }
}

const UNKNOWN_OPERAND: Word = { v: '<input>', unresolved: true }

/**
 * Whether a command would write when one more argument of unknown value is
 * appended (xargs) or substituted (find -exec {}).
 */
function writesWithUnknownOperand(words: readonly Word[], cwd: string, depth: number, append = true): boolean {
  const probe = new Collector(cwd)
  analyzeSegment({ words: append ? [...words, UNKNOWN_OPERAND] : [...words], redirects: [] }, probe, depth + 1)
  return probe.writes.length > 0
}

function inlineInterpreter(cmd: string, args: readonly Word[], out: Collector): void {
  const flagIdx = args.findIndex(w => ['-e', '--eval', '-p', '--print', '-c', '-E'].includes(w.v) || (cmd === 'deno' && w.v === 'eval'))
  if (flagIdx < 0) return
  const code = args[flagIdx + 1]?.v ?? ''
  if (INLINE_WRITE_API.test(code)) out.opaque(`${cmd} inline code`, [...args.slice(flagIdx + 2), ...pathLikeLiterals(code)])
}

/** Quoted string literals inside inline code that look like relative or absolute paths. */
function pathLikeLiterals(code: string): Word[] {
  const found: Word[] = []
  for (const m of code.matchAll(/['"]([^'"\s]+\/[^'"\s]*|[^'"\s]+\.[A-Za-z]{1,5})['"]/g)) found.push({ v: m[1]!, unresolved: false })
  return found
}

function analyzeInto(command: string, out: Collector, depth: number): void {
  for (const seg of segments(tokenize(command))) analyzeSegment(seg, out, depth)
}

/**
 * Every write a bash command might perform.
 * @param command - the command text as the model sent it.
 * @param cwd - absolute directory relative paths resolve against.
 */
export function analyzeShell(command: string, cwd: string): ShellWrite[] {
  const out = new Collector(cwd)
  analyzeInto(command, out, 0)
  return out.writes
}

const PWSH_WRITERS = new Set([
  'set-content', 'add-content', 'out-file', 'new-item', 'remove-item', 'move-item', 'copy-item', 'rename-item',
  'clear-content', 'set-item', 'export-csv', 'export-clixml', 'expand-archive',
  'ni', 'ri', 'rm', 'del', 'erase', 'rd', 'rmdir', 'mi', 'mv', 'move', 'cpi', 'cp', 'copy', 'rni', 'ren', 'sc', 'ac', 'mkdir', 'md',
])

/**
 * Every write a PowerShell command might perform. Cmdlet targets are reported
 * as opaque writes with their path-like arguments; redirects resolve normally.
 * Coarser than the bash analysis; see README.md.
 */
export function analyzePwsh(command: string, cwd: string): ShellWrite[] {
  const out = new Collector(cwd)
  for (const seg of segments(tokenize(command))) {
    for (const r of seg.redirects) {
      if (r.op === '<') continue
      if (r.target === undefined) { out.opaque(r.op, []); continue }
      if (r.target.v.toLowerCase() === '$null') continue
      out.path(r.target, `redirect ${r.op}`)
    }
    const first = seg.words[0]
    if (first === undefined) continue
    const name = first.v.toLowerCase()
    if (name === 'cd' || name === 'set-location' || name === 'sl') { out.cd(operands(seg.words.slice(1))[0]); continue }
    if (PWSH_WRITERS.has(name)) out.opaque(first.v, seg.words.slice(1))
  }
  return out.writes
}
