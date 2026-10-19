/**
 * forge-dsh: DeepSeek Harness adapter for forge (DESIGN.md section 10).
 * Cordis function plugin: named `apply`, `inject`, `name`, `Config` exports.
 *
 * Registrations, each a reversible Cordis effect:
 * 1. skills provider for forge's SKILL.md files
 * 2. `tools/pre-execute`: per-phase tool policy (src/policy.ts)
 * 3. `agent/pre-step`: re-enter the phase skill and principle index
 * 4. `agent/turn-stopping`: run scripts/forge-verify.sh; on failure steer the turn on
 * 5. `forge_spawn` tool: role-routed subagents via ctx.subagents
 * 6. `agent/request`: per-role reasoning effort when the route lists it
 *
 * Every event payload and service call below is typed against the published
 * @deepseek-ai/* 0.2.0-rc.2 declarations; README.md "API confirmation" lists
 * which behaviors are confirmed by those declarations and which are not.
 */
import { randomUUID } from 'node:crypto'
import { readFileSync, realpathSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { Context } from '@deepseek-ai/cordis'
import type { Agent } from '@deepseek-ai/dsh-agent'
import { boundContextSummary, createUserMessage, ReasoningEffortId, type ContextFormed, type UserMessage } from '@deepseek-ai/dsh-llm'
import { SessionId } from '@deepseek-ai/dsh-session'
import { BUNDLED_SKILL_RANK, type SkillCandidate, type SkillDefinition, type SkillProvider } from '@deepseek-ai/dsh-skill'
import type { SubagentActivationSpec } from '@deepseek-ai/dsh-subagent'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { JsonValue } from '@deepseek-ai/dsh-util-values'
import Schema from '@deepseek-ai/schemastery'
import { resolveForgeRoot } from './assets.ts'
import { buildInjection, hashText, InjectionTracker, loadPhaseContext } from './inject.ts'
import { evaluateToolCall, type Phase } from './policy.ts'
import { phaseRole, rolePhase, ROLES, type Role } from './roles.ts'
import { scanSkills, substituteForgeHome, toSkillRecord, type SkillRecord } from './skills.ts'
import { executeSpawn, parseSpawnArgs, planSpawn, type ActivationSpecShape } from './spawn.ts'
import { ForgeTomlCache, readForgeState } from './state.ts'
import { resolveVerifyScript, runVerify, verifyFeedback, VerifyRounds } from './verify.ts'

declare module '@deepseek-ai/dsh-llm' {
  interface MessageSourceMap {
    /** Context entered by the forge adapter: phase playbooks and verify feedback. */
    forge: { kind: 'forge' } & ContextFormed
  }
}

// Compile-time proof that the request shapes spawn.ts sends fit the real service types.
type Assert<T extends true> = T
export type ActivationSpecFits = Assert<ActivationSpecShape<Agent, SessionId> extends SubagentActivationSpec ? true : false>

export const name = 'forge-dsh'
export const inject = ['tools', 'skills']

const BOOT_MARKER = '[forge-dsh] loaded'
const SKILL_PROVIDER = 'forge-dsh'
const TOOL_SPAWN = 'forge_spawn'

export interface Config {
  /** Directory holding forge's skills/, AGENTS.md and scripts/. Default: this package when it carries AGENTS.md and skills/, else bundled assets. */
  forgeRoot?: string
  /** Steps between re-entries of identical forge context within one turn. 1 means every step. */
  reinjectEverySteps: number
  /** Upper bound on the entered forge context, in characters. */
  maxInjectChars: number
  /** Run scripts/forge-verify.sh when a top-level turn is about to end. */
  verifyOnTurnStop: boolean
  /** Also verify when a subagent's turn ends. */
  verifySubagents: boolean
  verifyTimeoutMs: number
  /** Failed verify rounds per turn before the turn is allowed to end anyway. */
  maxVerifyRounds: number
  verifyTailLines: number
  verifyTailChars: number
  /** ctx.subagents provider forge_spawn uses. Base bundle name: spawn. */
  spawnProvider: string
  /** Extra absolute directories where writes are always allowed. OS temp dirs are always included. */
  scratchDirs: string[]
}

export const Config: Schema<Config> = Schema.object({
  forgeRoot: Schema.string().description('Directory holding forge skills/, AGENTS.md and scripts/.'),
  reinjectEverySteps: Schema.natural().min(1).default(4).description('Steps between re-entries of unchanged forge context within a turn.'),
  maxInjectChars: Schema.natural().min(1000).default(24_000).description('Upper bound on the entered forge context.'),
  verifyOnTurnStop: Schema.boolean().default(true).description('Run forge-verify.sh before a top-level turn ends.'),
  verifySubagents: Schema.boolean().default(false).description('Also run forge-verify.sh when a subagent turn ends.'),
  verifyTimeoutMs: Schema.natural().min(1000).default(600_000).description('forge-verify.sh time limit.'),
  maxVerifyRounds: Schema.natural().min(1).default(3).description('Failed verify rounds per turn before the turn may end.'),
  verifyTailLines: Schema.natural().min(5).default(80).description('verify.log lines fed back on failure.'),
  verifyTailChars: Schema.natural().min(500).default(6000).description('verify.log characters fed back on failure.'),
  spawnProvider: Schema.string().default('spawn').description('ctx.subagents provider used by forge_spawn.'),
  scratchDirs: Schema.array(Schema.string()).default([]).description('Extra directories where writes are always allowed.'),
})

const DEFAULTS: Config = {
  reinjectEverySteps: 4,
  maxInjectChars: 24_000,
  verifyOnTurnStop: true,
  verifySubagents: false,
  verifyTimeoutMs: 600_000,
  maxVerifyRounds: 3,
  verifyTailLines: 80,
  verifyTailChars: 6000,
  spawnProvider: 'spawn',
  scratchDirs: [],
}

function scratchDirsFor(extra: readonly string[]): string[] {
  const dirs = new Set<string>(['/tmp', '/private/tmp', tmpdir(), ...extra])
  for (const dir of [...dirs]) {
    try { dirs.add(realpathSync(dir)) } catch { /* a missing scratch dir needs no alias */ }
  }
  return [...dirs]
}

function cwdOf(agent: Agent | undefined): string | undefined {
  return agent?.session.header.cwd
}

function forgeMessage(text: string, source: { form: 'instructions' } | { form: 'notice'; summary: string }): UserMessage {
  return createUserMessage({
    content: [{ type: 'text', text }],
    source: source.form === 'notice'
      ? { kind: 'forge', form: 'notice', summary: boundContextSummary(source.summary) }
      : { kind: 'forge', form: 'instructions' },
  })
}

function toJson(value: unknown): JsonValue {
  return JSON.parse(JSON.stringify(value)) as JsonValue
}

function toCandidate(skill: SkillRecord): SkillCandidate {
  return {
    name: skill.name,
    description: skill.description,
    ...skill.whenToUse === undefined ? {} : { whenToUse: skill.whenToUse },
    invocation: { modelInvocable: skill.modelInvocable, userInvocable: skill.userInvocable },
    source: 'bundled',
    provider: SKILL_PROVIDER,
    resourceBase: { kind: 'directory', path: skill.dir },
    rank: BUNDLED_SKILL_RANK,
    locator: skill.path,
    path: skill.path,
  }
}

function createSkillProvider(skillsRoot: string, forgeHome: string): SkillProvider {
  const reported = new Set<string>()
  return {
    name: SKILL_PROVIDER,
    async list() {
      const { skills, problems } = await scanSkills(skillsRoot, forgeHome)
      for (const problem of problems) {
        if (reported.has(problem)) continue
        reported.add(problem)
        console.warn(`[forge-dsh] skipped skill: ${problem}`)
      }
      return skills.map(toCandidate)
    },
    async get(candidate): Promise<SkillDefinition | undefined> {
      const path = typeof candidate.locator === 'string' ? candidate.locator : undefined
      if (path === undefined) return undefined
      let text: string
      try { text = await readFile(path, 'utf8') } catch { return undefined }
      const record = toSkillRecord(path, path.slice(0, -'/SKILL.md'.length), substituteForgeHome(text, forgeHome))
      if ('problem' in record || record.name !== candidate.name) return undefined
      return {
        name: record.name,
        description: record.description,
        ...record.whenToUse === undefined ? {} : { whenToUse: record.whenToUse },
        invocation: { modelInvocable: record.modelInvocable, userInvocable: record.userInvocable },
        source: 'bundled',
        provider: SKILL_PROVIDER,
        resourceBase: { kind: 'directory', path: record.dir },
        content: record.content,
        path: record.path,
      }
    },
  }
}

export function apply(ctx: Context, config?: Partial<Config>): void {
  const cfg: Config = { ...DEFAULTS, ...config }
  const forgeRoot = resolveForgeRoot(cfg.forgeRoot)
  const scratchDirs = scratchDirsFor(cfg.scratchDirs)
  /** Role of each child started by forge_spawn, keyed by child session id. */
  const childRoles = new Map<string, Role>()
  const tomlCache = new ForgeTomlCache()
  const tracker = new InjectionTracker()
  const rounds = new VerifyRounds()
  const effortCache = new Map<string, readonly string[]>()
  console.log(`${BOOT_MARKER} forgeRoot=${forgeRoot}`)

  const isSubagent = (agent: Agent) =>
    agent.session.header.origin === 'subagent' || (agent.session.header.delegationDepth ?? 0) > 0 || childRoles.has(agent.id)

  // 1. Skills. registerProvider returns its own Cordis effect disposer.
  ctx.skills.registerProvider(() => createSkillProvider(join(forgeRoot, 'skills'), forgeRoot))

  // 2. Per-phase tool policy.
  ctx.on('tools/pre-execute', async (exec, next) => {
    const cwd = cwdOf(exec.agent)
    const state = readForgeState(cwd)
    if (!state.active || cwd === undefined) return next()
    const role = exec.agent === undefined ? undefined : childRoles.get(exec.agent.id)
    const roleP = role === undefined ? undefined : rolePhase(role)
    const decision = evaluateToolCall(
      { name: exec.name, args: exec.arguments },
      {
        projectRoot: state.root,
        cwd,
        taskId: state.taskId,
        phase: state.phase,
        ...state.problem === undefined ? {} : { stateProblem: state.problem },
        ...roleP === undefined ? {} : { rolePhase: roleP },
        scratchDirs,
        readFile: path => {
          try { return readFileSync(path, 'utf8') } catch { return undefined }
        },
      },
    )
    if (decision.kind === 'deny') return { kind: 'deny', reason: decision.reason }
    if (decision.kind === 'ask') {
      const downstream = await next()
      return downstream.kind === 'allow' ? { kind: 'ask', reason: decision.reason } : downstream
    }
    return next()
  })

  // 3. Re-enter the phase playbook and principle index.
  ctx.on('agent/pre-step', async (payload, next) => {
    const decision = await next()
    if (decision.kind === 'reject' || payload.signal.aborted) return decision
    // Same guard as dsh-agent model-selection: never turn an empty first step,
    // or a continuation another listener emptied, into a real step.
    if (decision.messages.length === 0 && (payload.step === 1 || payload.messages.length > 0)) return decision
    const state = readForgeState(cwdOf(payload.agent))
    if (!state.active) return decision
    const role = childRoles.get(payload.agent.id)
    const phase: Phase | undefined = (role === undefined ? undefined : rolePhase(role)) ?? state.phase
    let text: string
    if (phase === undefined) {
      text = `<forge-context task="${state.taskId}">\nforge is active but ${state.problem ?? 'the task has no valid phase'}. Fix .forge/${state.taskId}/state.json (phase is one of ground, scout, shape, build, verify, review, report) before other work; only writes under .forge/ are allowed until then.\n</forge-context>`
    } else {
      const loaded = await loadPhaseContext(state.root, forgeRoot, phase)
      text = buildInjection({ taskId: state.taskId, phase, forgeHome: forgeRoot, ...loaded, maxChars: cfg.maxInjectChars })
    }
    if (!tracker.shouldEnter(payload.agent.id, hashText(text), payload.turn, payload.step, cfg.reinjectEverySteps)) return decision
    return { ...decision, messages: [...decision.messages, forgeMessage(text, { form: 'instructions' })] }
  })

  // 4. No "done" without gates.
  ctx.on('agent/turn-stopping', async ({ agent, turn, signal }) => {
    if (!cfg.verifyOnTurnStop || signal.aborted) return
    if (!cfg.verifySubagents && isSubagent(agent)) return
    const state = readForgeState(cwdOf(agent))
    if (!state.active) return
    const round = rounds.next(agent.id, turn)
    if (round > cfg.maxVerifyRounds) {
      if (round === cfg.maxVerifyRounds + 1) {
        console.warn(`[forge-dsh] ${state.taskId}: verify still failing after ${cfg.maxVerifyRounds} rounds; letting turn ${turn} end`)
        agent.inject(forgeMessage(
          `forge: the previous turn ended after ${cfg.maxVerifyRounds} failed verify rounds. Gates for task ${state.taskId} are still failing. Do not report this phase as done; fix the failure or report the stop condition.`,
          { form: 'notice', summary: `${state.taskId}: verify still failing` },
        ))
      }
      return
    }
    if (state.phase === undefined) {
      agent.steer(forgeMessage(
        `forge: ${state.problem ?? 'state.json has no valid phase'}. The turn is not done. Set the phase in .forge/${state.taskId}/state.json so the gates can run.`,
        { form: 'notice', summary: `${state.taskId}: invalid state.json` },
      ))
      return
    }
    const outcome = await runVerify({
      script: resolveVerifyScript(state.root, forgeRoot),
      projectRoot: state.root,
      taskDir: state.taskDir,
      phase: state.phase,
      timeoutMs: cfg.verifyTimeoutMs,
      signal,
      tailLines: cfg.verifyTailLines,
      tailChars: cfg.verifyTailChars,
    })
    if (signal.aborted) return
    if (outcome.kind === 'pass') { rounds.reset(agent.id); return }
    agent.steer(forgeMessage(
      verifyFeedback(outcome, state.taskId, state.phase, round, cfg.maxVerifyRounds),
      { form: 'notice', summary: `${state.taskId} ${state.phase}: verify ${outcome.kind === 'fail' ? 'failed' : 'did not run'}` },
    ))
  })

  // 5. forge_spawn.
  ctx.effect(() => ctx.tools.register(defineTool({
    name: TOOL_SPAWN,
    description:
      'Delegate one forge phase to a fresh subagent. The role picks the model route from forge.toml [roles] (review prefers a different model family than build) and the phase tool policy the child runs under. Send description, prompt, role, and optionally run_in_background. Never send model, provider, or effort; unmapped roles inherit this conversation\'s route. The child does not see this conversation: put file pointers (task.md, ground.md, shape.md, the diff) in the prompt. The escalation role asks the human first.',
    parameters: {
      description: { type: 'string', required: true, description: 'Short (3-5 word) label for the delegated work, shown in the UI.' },
      prompt: { type: 'string', required: true, description: 'Complete, self-contained brief. Point at .forge/<task>/ files instead of pasting them.' },
      role: { type: 'string', enum: ROLES, required: true, description: 'forge role: ground, scout, shape, build, review, report, or escalation.' },
      run_in_background: { type: 'boolean', description: 'Default true: return a subagent id now; the result is delivered to you as a message when the child finishes. false waits for the result.' },
    },
    output: {
      schema: { type: 'json' },
      render: (_args, value) => [{ type: 'text', text: JSON.stringify(value, null, 2) }],
    },
    async execute(args, exec) {
      const parsed = parseSpawnArgs(args)
      const loaded = tomlCache.load(cwdOf(exec.agent))
      const plan = planSpawn(loaded.config, parsed.role)
      const result = await executeSpawn<Agent, SessionId>(parsed, plan, {
        subagents: ctx.get('subagents'),
        providerName: cfg.spawnProvider,
        parent: exec.agent,
        signal: exec.signal,
        newChildId: () => SessionId(randomUUID()),
        remember: (id, role) => { childRoles.set(id, role) },
        forget: id => { childRoles.delete(id) },
      })
      return toJson(loaded.warnings.length > 0 ? { ...result, forgeTomlWarnings: loaded.warnings } : result)
    },
  })), 'forge_spawn tool')

  // 6. Per-role reasoning effort, only when the live route lists that effort id.
  const effortsFor = async (provider: string, model: string, signal: AbortSignal): Promise<readonly string[]> => {
    const key = `${provider}\u0000${model}`
    const hit = effortCache.get(key)
    if (hit !== undefined) return hit
    const llm = ctx.get('llm')
    if (llm === undefined) return []
    try {
      const info = await llm.resolveModelInfo(provider, model, signal)
      const ids = (info.reasoning?.efforts ?? []).map(e => String(e.id))
      effortCache.set(key, ids)
      return ids
    } catch {
      return []
    }
  }

  ctx.on('agent/request', async (payload, next) => {
    const base = await next()
    const cwd = cwdOf(payload.agent)
    let role = childRoles.get(payload.agent.id)
    if (role === undefined && !isSubagent(payload.agent)) {
      const state = readForgeState(cwd)
      role = state.active ? phaseRole(state.phase) : undefined
    }
    if (role === undefined) return base
    let effort: string | undefined
    try {
      effort = tomlCache.load(cwd).config.effort[role]
    } catch {
      return base
    }
    if (effort === undefined || base.reasoningEffort === effort) return base
    const efforts = await effortsFor(base.provider, base.model, payload.signal)
    if (!efforts.includes(effort)) return base
    return { ...base, reasoningEffort: ReasoningEffortId(effort) }
  })

  ctx.on('agent/disposed', ({ agent }) => {
    childRoles.delete(agent.id)
    tracker.forget(agent.id)
    rounds.reset(agent.id)
  })
}
