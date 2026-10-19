/**
 * forge roles and their model routes, read from forge.toml. Pure.
 *
 * ```toml
 * [roles]
 * build  = "deepseek-official/deepseek-chat"
 * review = ["openrouter/qwen/qwen3-coder", "deepseek-official/deepseek-reasoner"]
 * escalation = "inherit"
 *
 * [effort]          # LlmCallConfig.reasoningEffort ids, applied only when the route lists them
 * review = "high"
 *
 * [families]       # optional; default family is the leading letters of the model id
 * "deepseek-reasoner" = "deepseek"
 * ```
 *
 * A route is `provider/model`; the first `/` splits, so model ids may contain
 * slashes. A list gives candidates in preference order.
 */
import type { Phase } from './policy.ts'
import { parseToml, type TomlValue } from './toml.ts'

export const ROLES = ['ground', 'scout', 'shape', 'build', 'review', 'report', 'escalation'] as const
export type Role = (typeof ROLES)[number]

export function isRole(value: unknown): value is Role {
  return typeof value === 'string' && (ROLES as readonly string[]).includes(value)
}

/** Policy phase a child spawned with this role runs under; escalation follows the task. */
export function rolePhase(role: Role): Phase | undefined {
  return role === 'escalation' ? undefined : role
}

/** A phase whose name is also a role, for phase-driven effort on the main agent. */
export function phaseRole(phase: Phase | undefined): Role | undefined {
  return isRole(phase) ? phase : undefined
}

export interface Route {
  readonly provider: string
  readonly model: string
}

export interface ForgeToml {
  readonly roles: Partial<Record<Role, readonly Route[]>>
  readonly effort: Partial<Record<Role, string>>
  readonly families: Readonly<Record<string, string>>
}

export const EMPTY_FORGE_TOML: ForgeToml = { roles: {}, effort: {}, families: {} }

export function parseRoute(spec: string): Route | undefined {
  const trimmed = spec.trim()
  const slash = trimmed.indexOf('/')
  if (slash <= 0 || slash === trimmed.length - 1) return undefined
  return { provider: trimmed.slice(0, slash), model: trimmed.slice(slash + 1) }
}

/**
 * Read the role tables of forge.toml. Unknown roles and malformed routes are
 * reported as warnings and skipped; TOML syntax errors throw `TomlError`.
 */
export function parseForgeToml(text: string): { config: ForgeToml; warnings: string[] } {
  const tables = parseToml(text)
  const warnings: string[] = []
  const roles: Partial<Record<Role, Route[]>> = {}
  for (const [key, value] of Object.entries(tables.roles ?? {})) {
    if (!isRole(key)) { warnings.push(`[roles] ${key}: unknown role (expected ${ROLES.join(', ')})`); continue }
    const specs: TomlValue[] = Array.isArray(value) ? value : [value]
    const routes: Route[] = []
    for (const spec of specs) {
      if (typeof spec !== 'string') { warnings.push(`[roles] ${key}: routes must be strings`); continue }
      if (spec.trim() === 'inherit') continue
      const route = parseRoute(spec)
      if (route === undefined) warnings.push(`[roles] ${key}: "${spec}" is not provider/model`)
      else routes.push(route)
    }
    roles[key] = routes
  }
  const effort: Partial<Record<Role, string>> = {}
  for (const [key, value] of Object.entries(tables.effort ?? {})) {
    if (!isRole(key)) { warnings.push(`[effort] ${key}: unknown role`); continue }
    if (typeof value !== 'string' || value.trim() === '') { warnings.push(`[effort] ${key}: expected a non-empty string`); continue }
    effort[key] = value.trim()
  }
  const families: Record<string, string> = {}
  for (const [key, value] of Object.entries(tables.families ?? {})) {
    if (typeof value === 'string') families[key] = value.trim().toLowerCase()
    else warnings.push(`[families] ${key}: expected a string`)
  }
  return { config: { roles, effort, families }, warnings }
}

/**
 * Model family of a route: an explicit `[families]` entry for `provider/model`
 * or `model`, otherwise the leading letters of the model id's last segment
 * (`deepseek-chat` is deepseek, `qwen3-coder` is qwen, `glm-4.6` is glm).
 */
export function familyOf(route: Route, families: Readonly<Record<string, string>>): string {
  const explicit = families[`${route.provider}/${route.model}`] ?? families[route.model]
  if (explicit !== undefined) return explicit.toLowerCase()
  const last = route.model.slice(route.model.lastIndexOf('/') + 1).toLowerCase()
  return /^[a-z]+/.exec(last)?.[0] ?? last
}

export type RoleResolution =
  | { readonly inherit: true; readonly reason: string }
  | { readonly inherit: false; readonly route: Route; readonly family: string; readonly warning?: string }

/**
 * Pick the route for a role. Unmapped roles inherit the parent conversation's
 * route. The review role prefers the first candidate whose family differs from
 * build's, so the reviewer is a different model family when both are
 * configured (DESIGN.md section 3, REVIEW).
 */
export function resolveRole(config: ForgeToml, role: Role): RoleResolution {
  const candidates = config.roles[role] ?? []
  const first = candidates[0]
  if (first === undefined) return { inherit: true, reason: `role "${role}" is not mapped in forge.toml [roles]` }
  if (role !== 'review') return { inherit: false, route: first, family: familyOf(first, config.families) }

  const build = resolveRole(config, 'build')
  if (build.inherit) return { inherit: false, route: first, family: familyOf(first, config.families) }
  const other = candidates.find(route => familyOf(route, config.families) !== build.family)
  if (other !== undefined) return { inherit: false, route: other, family: familyOf(other, config.families) }
  return {
    inherit: false,
    route: first,
    family: familyOf(first, config.families),
    warning: `review uses the same model family as build (${build.family}); add a review candidate from another family in forge.toml [roles]`,
  }
}
