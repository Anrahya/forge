/**
 * Builds the per-step forge context message: the current phase skill body
 * plus the principle index from AGENTS.md. Pure apart from `loadPhaseContext`,
 * which reads the files.
 *
 * Cost: every entered message becomes a durable `user/message` in the session
 * log and stays in history until compaction. A phase skill is one page (about
 * 1k to 2k tokens) and the index about 600, so entering it on every step of a
 * 30-step turn would add 50k or more tokens. `InjectionTracker` enters it on
 * the first step of each turn, whenever the content changes (phase change or
 * edited skill), and otherwise every `reinjectEverySteps` steps.
 */
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parseFrontmatter } from "./skills.js";
/** The `## Principle index` section of AGENTS.md, heading included. */
export function principleIndex(agentsMd) {
    const text = agentsMd.replace(/\r\n/g, '\n');
    const start = text.search(/^## Principle index\s*$/m);
    if (start < 0)
        return undefined;
    const after = text.slice(start);
    const next = after.slice(1).search(/^## /m);
    return (next < 0 ? after : after.slice(0, next + 1)).trim();
}
/** Skill body without its frontmatter. */
export function skillBody(text) {
    return (parseFrontmatter(text)?.body ?? text).trim();
}
export function buildInjection(input) {
    const home = input.forgeHome ?? '$FORGE_HOME';
    const parts = [
        `<forge-context task="${input.taskId}" phase="${input.phase}">`,
        `forge is active. Task ${input.taskId} is in phase ${input.phase.toUpperCase()}. State: .forge/${input.taskId}/. The harness enforces this phase's tool policy and runs ${home}/scripts/forge-verify.sh before the turn may end.`,
        `FORGE_HOME=${home}`,
    ];
    if (input.skill !== undefined && input.skill !== '') {
        parts.push(`## Phase playbook (${input.skillPath ?? `forge-${input.phase}`})`, input.skill.split('$FORGE_HOME').join(home));
    }
    else {
        parts.push(`No phase skill found for ${input.phase}. Follow skills/forge/SKILL.md.`);
    }
    if (input.index !== undefined)
        parts.push(input.index);
    parts.push('</forge-context>');
    let text = parts.join('\n\n');
    if (text.length > input.maxChars) {
        const tail = '\n\n[forge-context truncated; read the phase SKILL.md for the rest]\n</forge-context>';
        text = text.slice(0, Math.max(0, input.maxChars - tail.length)) + tail;
    }
    return text;
}
export function hashText(text) {
    return createHash('sha256').update(text).digest('hex').slice(0, 16);
}
/**
 * Decides whether this step enters the forge context. In-memory per agent;
 * a Host restart re-enters once, which is harmless.
 */
export class InjectionTracker {
    last = new Map();
    shouldEnter(agentId, hash, turn, step, every) {
        const prior = this.last.get(agentId);
        const enter = prior === undefined
            || prior.hash !== hash
            || prior.turn !== turn
            || step - prior.step >= Math.max(1, every);
        if (enter)
            this.last.set(agentId, { hash, turn, step });
        return enter;
    }
    forget(agentId) {
        this.last.delete(agentId);
    }
}
async function readOptional(path) {
    try {
        return await readFile(path, 'utf8');
    }
    catch {
        return undefined;
    }
}
/**
 * Load the phase skill (project `.agents/skills/forge-<phase>/SKILL.md` wins,
 * matching DSH's project-over-bundled skill precedence) and the principle
 * index from the forge AGENTS.md.
 */
export async function loadPhaseContext(projectRoot, forgeRoot, phase) {
    const name = `forge-${phase}`;
    const candidates = [
        { path: join(projectRoot, '.agents', 'skills', name, 'SKILL.md'), label: `.agents/skills/${name}/SKILL.md` },
        { path: join(forgeRoot, 'skills', name, 'SKILL.md'), label: `skills/${name}/SKILL.md` },
    ];
    let skill;
    let skillPath;
    for (const c of candidates) {
        const text = await readOptional(c.path);
        if (text !== undefined) {
            skill = skillBody(text);
            skillPath = c.label;
            break;
        }
    }
    const agents = await readOptional(join(forgeRoot, 'AGENTS.md'));
    const index = agents === undefined ? undefined : principleIndex(agents);
    return { ...skill === undefined ? {} : { skill, skillPath }, ...index === undefined ? {} : { index } };
}
