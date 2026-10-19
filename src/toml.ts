/**
 * A deliberately small TOML reader for forge.toml. Pure, no dependency.
 *
 * Supported: comments, `[table]` and `[a.b]` headers (the dotted name is kept
 * as one literal key), bare and quoted keys, basic and literal strings,
 * integers, floats, booleans, and arrays of those (single or multi-line).
 * Anything else (inline tables, dates, multi-line strings, array-of-tables)
 * is an error naming the line, so a typo never silently drops a setting.
 */

export type TomlValue = string | number | boolean | TomlValue[]
export type TomlTables = Record<string, Record<string, TomlValue>>

export class TomlError extends Error {
  readonly line: number
  constructor(line: number, message: string) {
    super(`forge.toml line ${line}: ${message}`)
    this.name = 'TomlError'
    this.line = line
  }
}

class Cursor {
  pos = 0
  readonly text: string
  readonly lineOf: (pos: number) => number
  constructor(text: string, lineOf: (pos: number) => number) {
    this.text = text
    this.lineOf = lineOf
  }
  peek(): string { return this.text[this.pos] ?? '' }
  eof(): boolean { return this.pos >= this.text.length }
  fail(message: string): never { throw new TomlError(this.lineOf(this.pos), message) }

  /** Skip spaces and tabs; with `newlines`, also newlines and comments. */
  skip(newlines: boolean): void {
    for (;;) {
      const c = this.peek()
      if (c === ' ' || c === '\t' || c === '\r') { this.pos += 1; continue }
      if (newlines && c === '\n') { this.pos += 1; continue }
      if (newlines && c === '#') {
        const eol = this.text.indexOf('\n', this.pos)
        this.pos = eol < 0 ? this.text.length : eol
        continue
      }
      return
    }
  }
}

function parseBasicString(cur: Cursor): string {
  cur.pos += 1
  let out = ''
  for (;;) {
    const c = cur.peek()
    if (c === '' || c === '\n') cur.fail('unterminated string')
    cur.pos += 1
    if (c === '"') return out
    if (c !== '\\') { out += c; continue }
    const e = cur.peek()
    cur.pos += 1
    switch (e) {
      case '"': out += '"'; break
      case '\\': out += '\\'; break
      case 'n': out += '\n'; break
      case 't': out += '\t'; break
      case 'r': out += '\r'; break
      case 'u': {
        const hex = cur.text.slice(cur.pos, cur.pos + 4)
        if (!/^[0-9a-fA-F]{4}$/.test(hex)) cur.fail('bad \\u escape')
        out += String.fromCharCode(Number.parseInt(hex, 16))
        cur.pos += 4
        break
      }
      default: cur.fail(`unsupported escape \\${e}`)
    }
  }
}

function parseLiteralString(cur: Cursor): string {
  const start = cur.pos + 1
  const end = cur.text.indexOf("'", start)
  const eol = cur.text.indexOf('\n', start)
  if (end < 0 || (eol >= 0 && eol < end)) cur.fail('unterminated string')
  cur.pos = end + 1
  return cur.text.slice(start, end)
}

function parseValue(cur: Cursor): TomlValue {
  const c = cur.peek()
  if (c === '"') {
    if (cur.text.startsWith('"""', cur.pos)) cur.fail('multi-line strings are not supported')
    return parseBasicString(cur)
  }
  if (c === "'") {
    if (cur.text.startsWith("'''", cur.pos)) cur.fail('multi-line strings are not supported')
    return parseLiteralString(cur)
  }
  if (c === '[') {
    cur.pos += 1
    const items: TomlValue[] = []
    for (;;) {
      cur.skip(true)
      if (cur.peek() === ']') { cur.pos += 1; return items }
      items.push(parseValue(cur))
      cur.skip(true)
      if (cur.peek() === ',') { cur.pos += 1; continue }
      if (cur.peek() === ']') { cur.pos += 1; return items }
      cur.fail('expected , or ] in array')
    }
  }
  if (c === '{') cur.fail('inline tables are not supported; use a [table] header')
  const m = /^[^\s,\]#]+/.exec(cur.text.slice(cur.pos))
  if (!m) cur.fail('expected a value')
  const raw = m[0]
  cur.pos += raw.length
  if (raw === 'true') return true
  if (raw === 'false') return false
  const num = raw.replace(/_/g, '')
  if (/^[+-]?(0|[1-9][0-9]*)$/.test(num)) return Number.parseInt(num, 10)
  if (/^[+-]?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.test(num)) return Number.parseFloat(num)
  return cur.fail(`unsupported value "${raw}" (strings need quotes)`)
}

function parseKey(cur: Cursor): string {
  const c = cur.peek()
  if (c === '"') return parseBasicString(cur)
  if (c === "'") return parseLiteralString(cur)
  const m = /^[A-Za-z0-9_-]+/.exec(cur.text.slice(cur.pos))
  if (!m) cur.fail('expected a key')
  cur.pos += m[0].length
  return m[0]
}

/**
 * Parse TOML text into `{ table: { key: value } }`. Keys before the first
 * header land in the `""` table.
 */
export function parseToml(text: string): TomlTables {
  const lineStarts: number[] = [0]
  for (let i = 0; i < text.length; i += 1) if (text[i] === '\n') lineStarts.push(i + 1)
  const lineOf = (pos: number) => {
    let lo = 0
    let hi = lineStarts.length - 1
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1
      if (lineStarts[mid]! <= pos) lo = mid
      else hi = mid - 1
    }
    return lo + 1
  }
  const cur = new Cursor(text, lineOf)
  const tables: TomlTables = { '': {} }
  let table = ''
  for (;;) {
    cur.skip(true)
    if (cur.eof()) return tables
    if (cur.peek() === '[') {
      if (cur.text.startsWith('[[', cur.pos)) cur.fail('arrays of tables are not supported')
      cur.pos += 1
      cur.skip(false)
      const parts = [parseKey(cur)]
      cur.skip(false)
      while (cur.peek() === '.') {
        cur.pos += 1
        cur.skip(false)
        parts.push(parseKey(cur))
        cur.skip(false)
      }
      if (cur.peek() !== ']') cur.fail('expected ] after table name')
      cur.pos += 1
      table = parts.join('.')
      if (Object.hasOwn(tables, table) && table !== '') cur.fail(`table [${table}] defined twice`)
      tables[table] = {}
    } else {
      const key = parseKey(cur)
      cur.skip(false)
      if (cur.peek() === '.') cur.fail('dotted keys are not supported; use a [table] header')
      if (cur.peek() !== '=') cur.fail(`expected = after key "${key}"`)
      cur.pos += 1
      cur.skip(false)
      const value = parseValue(cur)
      const target = tables[table]!
      if (Object.hasOwn(target, key)) cur.fail(`key "${key}" defined twice`)
      target[key] = value
    }
    cur.skip(false)
    if (cur.peek() === '#') {
      const eol = cur.text.indexOf('\n', cur.pos)
      cur.pos = eol < 0 ? cur.text.length : eol
    }
    if (!cur.eof() && cur.peek() !== '\n') cur.fail('expected end of line')
  }
}
