/**
 * forge per-phase tool policy (gate G11 plus the phase write rules). Pure: no
 * DSH imports and no I/O except the optional `readFile` callback the caller
 * supplies. `src/index.ts` adapts DSH `tools/pre-execute` to this module;
 * `adapters/claude-code/scripts/hooks/policy.sh` is a shell port of the same
 * rules, checked against this module by `tests/claude-code-policy.test.ts`.
 */
import { posix } from 'node:path';
import { analyzePwsh, analyzeShell } from "./shell.js";
export const PHASES = ['ground', 'scout', 'shape', 'build', 'verify', 'review', 'report'];
export function isPhase(value) {
    return typeof value === 'string' && PHASES.includes(value);
}
export const PHASE_MODE = {
    ground: 'read-only',
    scout: 'read-only',
    shape: 'guard-referee',
    build: 'guard-referee',
    verify: 'read-only',
    review: 'read-only',
    report: 'guard-referee',
};
export const ALLOW = Object.freeze({ kind: 'allow' });
// ---------------------------------------------------------------------------
// Referee paths
const CONFIG_BASENAMES = [
    /^vitest\.(config|workspace)\.[cm]?[jt]s$/,
    /^jest\.config\.[cm]?[jt]s(on)?$/,
    /^eslint\.config\.[cm]?[jt]s$/,
    /^\.eslintrc(\.(js|cjs|mjs|json|ya?ml))?$/,
    /^\.eslintignore$/,
    /^tsconfig(\..+)?\.json$/,
    /^jsconfig\.json$/,
    /^biome\.jsonc?$/,
    /^\.prettierrc(\..+)?$/,
    /^prettier\.config\.[cm]?[jt]s$/,
    /^\.?clippy\.toml$/,
    /^\.?rustfmt\.toml$/,
];
/**
 * Whether a project-relative path is a referee file regardless of content.
 * Cargo.toml is content-sensitive and handled in {@link cargoDevDepsReason}.
 */
export function isRefereePath(rel) {
    if (rel === '' || rel.startsWith('../'))
        return false;
    if (rel.startsWith('scripts/gates/') || rel === 'scripts/gates')
        return true;
    if (rel === 'scripts/forge-verify.sh')
        return true;
    if (rel.startsWith('.github/workflows/') || rel === '.github/workflows')
        return true;
    if (isVerifyLog(rel))
        return true;
    const base = posix.basename(rel);
    return CONFIG_BASENAMES.some(re => re.test(base));
}
/** `.forge/<anything>/verify.log`: written only by scripts/forge-verify.sh. */
export function isVerifyLog(rel) {
    return rel.startsWith('.forge/') && posix.basename(rel) === 'verify.log';
}
function isUnderForge(rel) {
    return rel === '.forge' || rel.startsWith('.forge/');
}
function within(path, dir) {
    const rel = posix.relative(dir, path);
    return rel === '' || (!rel.startsWith('../') && rel !== '..' && !posix.isAbsolute(rel));
}
/** Project-relative POSIX path, or a `../` path when outside the project. */
export function projectRelative(projectRoot, abs) {
    return posix.relative(projectRoot, abs);
}
// ---------------------------------------------------------------------------
// Cargo.toml dev-dependencies
const DEV_DEPS_HEADER = /^\s*\[\s*(target\..+\.)?dev-dependencies(\.[^\]]+)?\s*\]\s*(#.*)?$/;
/** Section header name for each line, so line i belongs to `sections[i]`. */
function sectionsByLine(text) {
    const out = [];
    let current = '';
    for (const line of text.split('\n')) {
        const m = /^\s*\[\[?\s*([^\]]+?)\s*\]\]?\s*(#.*)?$/.exec(line);
        if (m)
            current = m[1];
        out.push(current);
    }
    return out;
}
function isDevDepsSection(name) {
    return DEV_DEPS_HEADER.test(`[${name}]`);
}
/** The dev-dependency sections of a Cargo.toml, joined, for before/after comparison. */
export function devDepsText(text) {
    const lines = text.split('\n');
    const sections = sectionsByLine(text);
    return lines
        .filter((line, i) => isDevDepsSection(sections[i]) && !DEV_DEPS_HEADER.test(line))
        .map(l => l.trim())
        .filter(l => l !== '' && !l.startsWith('#'))
        .join('\n');
}
function mentionsDevDeps(text) {
    return text.split('\n').some(line => DEV_DEPS_HEADER.test(line));
}
/**
 * Why a Cargo.toml write is a referee change, or undefined when it is not.
 * Dev-dependencies are referee because they decide which test and lint
 * tooling runs; ordinary dependencies stay writable in BUILD.
 */
export function cargoDevDepsReason(op, current) {
    if (op.kind !== 'path')
        return op.cargoDevDeps ? 'changes [dev-dependencies]' : undefined;
    if (op.edit !== undefined) {
        const { oldText, newText, atLine } = op.edit;
        if (mentionsDevDeps(oldText) || mentionsDevDeps(newText))
            return 'adds or removes a [dev-dependencies] header';
        if (current === undefined)
            return undefined;
        const sections = sectionsByLine(current);
        let line;
        if (atLine !== undefined) {
            line = Math.max(0, Math.min(sections.length - 1, atLine - 1));
        }
        else if (oldText !== '') {
            const idx = current.indexOf(oldText);
            if (idx >= 0)
                line = current.slice(0, idx).split('\n').length - 1;
        }
        if (line !== undefined && isDevDepsSection(sections[line]))
            return 'edits the [dev-dependencies] section';
        return undefined;
    }
    if (op.content !== undefined) {
        return devDepsText(current ?? '') === devDepsText(op.content) ? undefined : 'changes the [dev-dependencies] section';
    }
    return 'is a shell write to Cargo.toml, so the [dev-dependencies] section cannot be checked (use the edit tool)';
}
// ---------------------------------------------------------------------------
// Tool calls to write operations
function str(v) {
    return typeof v === 'string' ? v : undefined;
}
function record(v) {
    return typeof v === 'object' && v !== null ? v : {};
}
/**
 * Model-facing DSH tools that write files, keyed by tool name. Tool names and
 * argument keys: `edit`, `write`, `bash` confirmed against the published
 * 0.2.0-rc.2 packages; `str_replace_editor`, `pwsh`, `terminal_send` from
 * docs/tool-catalog.md on master (HYPOTHESIS for rc.2, same names expected).
 * Tools not listed here are allowed: MCP tools that write are not covered.
 */
export function writesOf(call, cwd) {
    const a = record(call.args);
    const at = (p) => (p === undefined ? undefined : posix.resolve(cwd, p));
    switch (call.name) {
        case 'write': {
            const path = at(str(a.file_path));
            return path === undefined ? [] : [{ kind: 'path', path, via: 'write', content: str(a.content) ?? '' }];
        }
        case 'edit': {
            const path = at(str(a.file_path));
            return path === undefined ? [] : [{ kind: 'path', path, via: 'edit', edit: { oldText: str(a.old_string) ?? '', newText: str(a.new_string) ?? '' } }];
        }
        case 'str_replace_editor': {
            const command = str(a.command);
            const path = at(str(a.path));
            if (path === undefined || command === undefined || command === 'view')
                return [];
            if (command === 'create')
                return [{ kind: 'path', path, via: 'str_replace_editor create', content: str(a.file_text) ?? '' }];
            if (command === 'insert') {
                const line = typeof a.insert_line === 'number' ? a.insert_line : undefined;
                return [{ kind: 'path', path, via: 'str_replace_editor insert', edit: { oldText: '', newText: str(a.new_str) ?? '', ...line === undefined ? {} : { atLine: line + 1 } } }];
            }
            return [{ kind: 'path', path, via: `str_replace_editor ${command}`, edit: { oldText: str(a.old_str) ?? '', newText: str(a.new_str) ?? '' } }];
        }
        case 'bash': {
            const command = str(a.command);
            if (command === undefined)
                return [];
            const workdir = str(a.workdir);
            return analyzeShell(command, workdir === undefined ? cwd : posix.resolve(cwd, workdir));
        }
        case 'pwsh': {
            const command = str(a.command);
            if (command === undefined)
                return [];
            const workdir = str(a.workdir);
            return analyzePwsh(command, workdir === undefined ? cwd : posix.resolve(cwd, workdir));
        }
        case 'terminal_send': {
            const text = str(a.text);
            return text === undefined ? [] : analyzeShell(text, cwd);
        }
        default:
            return [];
    }
}
// ---------------------------------------------------------------------------
// Decision
const RULES_HINT = 'If a gate or referee file looks wrong, stop and report it (stop condition S5); never edit it.';
function display(ctx, abs) {
    const rel = projectRelative(ctx.projectRoot, abs);
    return rel.startsWith('../') ? abs : rel;
}
function readOnlyReason(ctx, phase, what) {
    const task = `.forge/${ctx.taskId}/`;
    if (phase === undefined) {
        return `forge: ${ctx.stateProblem ?? `.forge/${ctx.taskId}/state.json has no valid phase`}. Until state.json names a phase (${PHASES.join(', ')}), only writes under .forge/ are allowed. Blocked: ${what}.`;
    }
    const next = phase === 'review'
        ? 'Record findings in review.md; blocking findings send the task back to BUILD.'
        : phase === 'verify'
            ? 'VERIFY runs gates only; a failure returns to BUILD with the gate message.'
            : `Put what you learned in ${task}${phase}.md; code changes wait for BUILD.`;
    return `forge: phase "${phase}" is read-only. Writes are allowed only under .forge/ and scratch directories. Blocked: ${what}. ${next}`;
}
function refereeReason(what, detail) {
    return `forge: ${what} ${detail ?? 'targets a referee file (gate scripts, forge-verify.sh, test runner config, lint config, CI workflows, verify.log)'}. Agents never write referee files in any phase. ${RULES_HINT}`;
}
function judgeForPhase(op, phase, ctx) {
    const mode = phase === undefined ? 'read-only' : PHASE_MODE[phase];
    const scratch = ctx.scratchDirs ?? [];
    if (op.kind === 'path') {
        const rel = projectRelative(ctx.projectRoot, op.path);
        const inside = !rel.startsWith('../') && rel !== '..';
        const what = `${op.via} ${display(ctx, op.path)}`;
        if (inside && isVerifyLog(rel))
            return { kind: 'deny', reason: refereeReason(what, 'targets verify.log, which only scripts/forge-verify.sh writes') };
        if (!inside) {
            if (scratch.some(dir => within(op.path, dir)))
                return ALLOW;
            return mode === 'read-only' ? { kind: 'deny', reason: readOnlyReason(ctx, phase, what) } : ALLOW;
        }
        if (isUnderForge(rel))
            return ALLOW;
        if (mode === 'read-only')
            return { kind: 'deny', reason: readOnlyReason(ctx, phase, what) };
        if (isRefereePath(rel))
            return { kind: 'deny', reason: refereeReason(what) };
        if (posix.basename(rel) === 'Cargo.toml') {
            const why = cargoDevDepsReason(op, ctx.readFile?.(op.path));
            if (why !== undefined)
                return { kind: 'deny', reason: refereeReason(what, why) };
        }
        return ALLOW;
    }
    // Opaque shell write: the target is unknown.
    const what = `shell command "${op.via}"`;
    const refereeMention = op.mentions.find(abs => {
        const rel = projectRelative(ctx.projectRoot, abs);
        return !rel.startsWith('../') && isRefereePath(rel);
    });
    if (refereeMention !== undefined)
        return { kind: 'deny', reason: refereeReason(`${what} on ${display(ctx, refereeMention)}`) };
    if (op.cargoDevDeps)
        return { kind: 'deny', reason: refereeReason(what, 'changes Cargo.toml [dev-dependencies]') };
    if (mode === 'read-only')
        return { kind: 'deny', reason: readOnlyReason(ctx, phase, `${what} (it may write files outside .forge/)`) };
    return ALLOW;
}
/**
 * Decide one tool call. Deny reasons are model-facing: DSH shows them to the
 * model as the tool result text `Error: <reason>` (confirmed in
 * @deepseek-ai/dsh-tools 0.2.0-rc.2 `ToolRuntime` pre-execute handling).
 */
export function evaluateToolCall(call, ctx) {
    if (call.name === 'forge_spawn' && record(call.args).role === 'escalation') {
        return {
            kind: 'ask',
            reason: 'forge: the escalation role may spend frontier-model budget. forge asks before any frontier spend (DESIGN.md section 12, decision 3). Approve this delegation?',
        };
    }
    const ops = writesOf(call, ctx.cwd);
    if (ops.length === 0)
        return ALLOW;
    const phases = [ctx.phase];
    if (ctx.rolePhase !== undefined && ctx.rolePhase !== ctx.phase)
        phases.push(ctx.rolePhase);
    for (const op of ops) {
        for (const phase of phases) {
            const decision = judgeForPhase(op, phase, ctx);
            if (decision.kind !== 'allow')
                return decision;
        }
    }
    return ALLOW;
}
