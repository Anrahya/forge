/**
 * Reads forge task state from the project: `.forge/current` (task id) and
 * `.forge/<id>/state.json` (`{ "phase": ... }`). Node fs only, no DSH imports.
 * State is read fresh on every call; the files are tiny and caching would
 * let a phase change lag behind the policy.
 */
import { readFileSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { isPhase } from "./policy.js";
import { EMPTY_FORGE_TOML, parseForgeToml } from "./roles.js";
const TASK_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
function isFile(path) {
    try {
        return statSync(path).isFile();
    }
    catch {
        return false;
    }
}
/** Nearest ancestor of `start` (inclusive) that contains `.forge/current`. */
export function findForgeRoot(start) {
    let dir = start;
    for (;;) {
        if (isFile(join(dir, '.forge', 'current')))
            return dir;
        const parent = dirname(dir);
        if (parent === dir)
            return undefined;
        dir = parent;
    }
}
/** Nearest ancestor of `start` (inclusive) that contains forge.toml. */
export function findForgeToml(start) {
    let dir = start;
    for (;;) {
        const candidate = join(dir, 'forge.toml');
        if (isFile(candidate))
            return candidate;
        const parent = dirname(dir);
        if (parent === dir)
            return undefined;
        dir = parent;
    }
}
/**
 * Forge is active when `.forge/current` exists and names a task. An empty
 * `current` file means inactive. A bad id or a missing or invalid state.json
 * keeps forge active with `phase: undefined`, which the policy treats as
 * read-only (fail closed) while still allowing writes under `.forge/`.
 */
export function readForgeState(cwd) {
    if (cwd === undefined)
        return { active: false };
    const root = findForgeRoot(cwd);
    if (root === undefined)
        return { active: false };
    let taskId;
    try {
        taskId = readFileSync(join(root, '.forge', 'current'), 'utf8').trim();
    }
    catch {
        return { active: false };
    }
    if (taskId === '')
        return { active: false };
    if (!TASK_ID.test(taskId) || taskId.includes('..')) {
        return { active: true, root, taskId: 'invalid-task-id', taskDir: '.forge', phase: undefined, problem: `.forge/current holds "${taskId.slice(0, 60)}", which is not a valid task id` };
    }
    const taskDir = `.forge/${taskId}`;
    const statePath = join(root, '.forge', taskId, 'state.json');
    let raw;
    try {
        raw = readFileSync(statePath, 'utf8');
    }
    catch {
        return { active: true, root, taskId, taskDir, phase: undefined, problem: `${taskDir}/state.json is missing` };
    }
    let parsed;
    try {
        parsed = JSON.parse(raw);
    }
    catch {
        return { active: true, root, taskId, taskDir, phase: undefined, problem: `${taskDir}/state.json is not valid JSON` };
    }
    const phase = typeof parsed === 'object' && parsed !== null ? parsed.phase : undefined;
    if (!isPhase(phase)) {
        return { active: true, root, taskId, taskDir, phase: undefined, problem: `${taskDir}/state.json phase ${JSON.stringify(phase)} is not one of ground, scout, shape, build, verify, review, report` };
    }
    return { active: true, root, taskId, taskDir, phase };
}
/** forge.toml reader with an mtime cache, since `agent/request` reads it every step. */
export class ForgeTomlCache {
    entries = new Map();
    /**
     * Load the forge.toml nearest to `cwd`. A missing file is an empty config;
     * a syntax error throws so callers can surface it.
     */
    load(cwd) {
        if (cwd === undefined)
            return { config: EMPTY_FORGE_TOML, warnings: [] };
        const path = findForgeToml(cwd);
        if (path === undefined)
            return { config: EMPTY_FORGE_TOML, warnings: [] };
        const mtimeMs = statSync(path).mtimeMs;
        const hit = this.entries.get(path);
        if (hit !== undefined && hit.mtimeMs === mtimeMs)
            return { path, config: hit.config, warnings: hit.warnings };
        const { config, warnings } = parseForgeToml(readFileSync(path, 'utf8'));
        this.entries.set(path, { mtimeMs, config, warnings });
        return { path, config, warnings };
    }
}
