/**
 * Discovers forge's SKILL.md files and parses their frontmatter. Node fs
 * only. The DSH provider object is built in `src/index.ts` from these records.
 *
 * Frontmatter keys follow DSH (`packages/skill/skill-filesystem/README.md`,
 * summarized in pstack-dsh HARNESS.md): `name` (kebab-case, the
 * `isSkillName` grammar `^[a-z0-9]+(?:-[a-z0-9]+)*$`), `description`,
 * optional `whenToUse`, `disable-model-invocation`, `user-invocable`.
 */
import { readdir, readFile } from 'node:fs/promises'
import { join, relative } from 'node:path'

export const SKILL_NAME = /^[a-z0-9]+(?:-[a-z0-9]+)*$/

export interface SkillRecord {
  readonly name: string
  readonly description: string
  readonly whenToUse?: string
  readonly modelInvocable: boolean
  readonly userInvocable: boolean
  /** Markdown body after the frontmatter. */
  readonly content: string
  /** Absolute directory holding SKILL.md (resource base for playbooks). */
  readonly dir: string
  /** Absolute SKILL.md path. */
  readonly path: string
}

export interface ParsedFrontmatter {
  readonly fields: Readonly<Record<string, string>>
  readonly body: string
}

function unquote(value: string): string {
  const t = value.trim()
  if (t.length >= 2 && ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'")))) {
    const inner = t.slice(1, -1)
    return t.startsWith('"') ? inner.replace(/\\"/g, '"').replace(/\\\\/g, '\\') : inner.replace(/''/g, "'")
  }
  return t
}

/**
 * Minimal YAML frontmatter reader: `key: value` lines plus `|` and `>` block
 * scalars (indented continuation lines). Nested maps and lists are skipped.
 */
export function parseFrontmatter(text: string): ParsedFrontmatter | undefined {
  const normalized = text.replace(/^﻿/, '').replace(/\r\n/g, '\n')
  if (!normalized.startsWith('---\n')) return undefined
  const end = normalized.indexOf('\n---', 3)
  if (end < 0) return undefined
  const lines = normalized.slice(4, end).split('\n')
  const afterFence = normalized.indexOf('\n', end + 4)
  const body = afterFence < 0 ? '' : normalized.slice(afterFence + 1).replace(/^\s*\n/, '')
  const fields: Record<string, string> = {}
  for (let i = 0; i < lines.length; i += 1) {
    const m = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(lines[i]!)
    if (!m) continue
    const key = m[1]!
    const rest = m[2]!.trim()
    if (rest === '|' || rest === '>' || rest === '|-' || rest === '>-' || rest === '|+' || rest === '>+') {
      const block: string[] = []
      while (i + 1 < lines.length && (/^\s+\S/.test(lines[i + 1]!) || lines[i + 1]!.trim() === '')) {
        block.push(lines[i + 1]!.trim())
        i += 1
      }
      fields[key] = rest.startsWith('>') ? block.join(' ').replace(/\s+/g, ' ').trim() : block.join('\n').trim()
      continue
    }
    fields[key] = unquote(rest)
  }
  return { fields, body }
}

function parseBool(value: string | undefined, fallback: boolean): boolean | undefined {
  if (value === undefined || value === '') return fallback
  const v = value.trim().toLowerCase()
  if (['true', 'yes', 'on'].includes(v)) return true
  if (['false', 'no', 'off'].includes(v)) return false
  return undefined
}

/** Parse one SKILL.md. Returns a problem string instead of a record when invalid. */
export function toSkillRecord(path: string, dir: string, text: string): SkillRecord | { problem: string } {
  const parsed = parseFrontmatter(text)
  if (parsed === undefined) return { problem: `${path}: no YAML frontmatter` }
  const name = parsed.fields.name ?? ''
  if (!SKILL_NAME.test(name)) return { problem: `${path}: name "${name}" is not kebab-case (${SKILL_NAME.source})` }
  const description = parsed.fields.description ?? ''
  if (description === '') return { problem: `${path}: description is required` }
  const disable = parseBool(parsed.fields['disable-model-invocation'], false)
  const user = parseBool(parsed.fields['user-invocable'], true)
  if (disable === undefined || user === undefined) return { problem: `${path}: invocation flags must be true or false` }
  const whenToUse = parsed.fields.whenToUse ?? parsed.fields['when-to-use'] ?? parsed.fields.when_to_use
  return {
    name,
    description,
    ...whenToUse ? { whenToUse } : {},
    modelInvocable: !disable,
    userInvocable: user,
    content: parsed.body,
    dir,
    path,
  }
}

async function walk(dir: string, found: string[], depth: number): Promise<void> {
  if (depth > 6) return
  let entries
  try {
    entries = await readdir(dir, { withFileTypes: true })
  } catch {
    return
  }
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name.startsWith('.') || entry.name === 'node_modules') continue
    const full = join(dir, entry.name)
    if (entry.isDirectory()) await walk(full, found, depth + 1)
    else if (entry.isFile() && entry.name === 'SKILL.md') found.push(full)
  }
}

/**
 * Every valid SKILL.md under `root`, sorted by name. Invalid files and
 * duplicate names are returned as problems; the first path in sorted order
 * wins a duplicate.
 */
/** Replace `$FORGE_HOME` with the install directory so skills can name scripts by absolute path. */
export function substituteForgeHome(text: string, forgeHome: string | undefined): string {
  return forgeHome === undefined ? text : text.split('$FORGE_HOME').join(forgeHome)
}

export async function scanSkills(root: string, forgeHome?: string): Promise<{ skills: SkillRecord[]; problems: string[] }> {
  const paths: string[] = []
  await walk(root, paths, 0)
  const skills: SkillRecord[] = []
  const problems: string[] = []
  const seen = new Map<string, string>()
  for (const path of paths) {
    let text: string
    try {
      text = await readFile(path, 'utf8')
    } catch (error) {
      problems.push(`${path}: ${(error as Error).message}`)
      continue
    }
    const dir = path.slice(0, -'/SKILL.md'.length)
    const record = toSkillRecord(path, dir, substituteForgeHome(text, forgeHome))
    if ('problem' in record) { problems.push(record.problem); continue }
    const prior = seen.get(record.name)
    if (prior !== undefined) {
      problems.push(`${relative(root, path)}: duplicate skill name "${record.name}" (kept ${relative(root, prior)})`)
      continue
    }
    seen.set(record.name, path)
    skills.push(record)
  }
  skills.sort((a, b) => a.name.localeCompare(b.name))
  return { skills, problems }
}
