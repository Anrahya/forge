/**
 * Runs `scripts/forge-verify.sh --task-dir .forge/<id> --phase <phase>` and
 * turns its result into the message that keeps a turn from ending as done.
 * Node child_process and fs only, no DSH imports.
 *
 * Script contract (owned by scripts/forge-verify.sh): exit 0 pass, exit 1
 * gate failure, writes `.forge/<id>/verify.log`. Any other exit, a timeout,
 * or a missing script is an infrastructure error, reported to the model as
 * such so it does not claim done and does not try to edit the referee.
 */
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
/** Last `maxLines` lines, then at most `maxChars` characters from the end. */
export function tailText(text, maxLines, maxChars) {
    const lines = text.replace(/\s+$/, '').split('\n');
    let tail = lines.slice(-maxLines).join('\n');
    if (tail.length > maxChars)
        tail = tail.slice(tail.length - maxChars);
    const cut = lines.length > maxLines || tail.length >= maxChars;
    return cut ? `[... earlier lines omitted ...]\n${tail}` : tail;
}
/** Project script wins (forge-verify-setup may vendor one); else the forge copy. */
export function resolveVerifyScript(projectRoot, forgeRoot) {
    for (const candidate of [join(projectRoot, 'scripts', 'forge-verify.sh'), join(forgeRoot, 'scripts', 'forge-verify.sh')]) {
        if (existsSync(candidate))
            return candidate;
    }
    return undefined;
}
export async function runVerify(opts) {
    if (opts.script === undefined) {
        return { kind: 'error', message: 'scripts/forge-verify.sh was not found in the project or the forge install, so no gate ran' };
    }
    const logPath = join(opts.projectRoot, opts.taskDir, 'verify.log');
    const mtimeBefore = await stat(logPath).then(s => s.mtimeMs, () => undefined);
    const run = await new Promise(resolvePromise => {
        let output = '';
        let timedOut = false;
        // Own process group, so a timeout or cancel also stops the test runners the script started.
        const child = spawn('bash', [opts.script, '--task-dir', opts.taskDir, '--phase', opts.phase], {
            cwd: opts.projectRoot,
            stdio: ['ignore', 'pipe', 'pipe'],
            env: { ...process.env, FORGE_HARNESS: 'dsh' },
            detached: process.platform !== 'win32',
        });
        const keep = (chunk) => {
            output += chunk.toString('utf8');
            if (output.length > 200_000)
                output = output.slice(-100_000);
        };
        child.stdout.on('data', keep);
        child.stderr.on('data', keep);
        let killTimer;
        const signalGroup = (sig) => {
            try {
                if (child.pid !== undefined && process.platform !== 'win32')
                    process.kill(-child.pid, sig);
                else
                    child.kill(sig);
            }
            catch {
                // The group already exited.
            }
        };
        const stop = () => {
            signalGroup('SIGTERM');
            killTimer = setTimeout(() => signalGroup('SIGKILL'), 5_000);
        };
        const timer = setTimeout(() => { timedOut = true; stop(); }, opts.timeoutMs);
        const onAbort = () => stop();
        opts.signal?.addEventListener('abort', onAbort, { once: true });
        child.on('error', error => {
            clearTimeout(timer);
            opts.signal?.removeEventListener('abort', onAbort);
            resolvePromise({ code: null, signal: null, output, timedOut, spawnError: error.message });
        });
        child.on('close', (code, signal) => {
            clearTimeout(timer);
            if (killTimer !== undefined)
                clearTimeout(killTimer);
            opts.signal?.removeEventListener('abort', onAbort);
            resolvePromise({ code, signal, output, timedOut });
        });
    });
    // A verify.log the script did not rewrite in this run is stale evidence; fall back to its output.
    const mtimeAfter = await stat(logPath).then(s => s.mtimeMs, () => undefined);
    const fresh = mtimeAfter !== undefined && (mtimeBefore === undefined || mtimeAfter > mtimeBefore);
    let log;
    if (fresh) {
        try {
            log = await readFile(logPath, 'utf8');
        }
        catch {
            log = undefined;
        }
    }
    const tail = (text) => tailText(text, opts.tailLines, opts.tailChars);
    if (run.spawnError !== undefined)
        return { kind: 'error', message: `could not start forge-verify.sh: ${run.spawnError}` };
    if (run.timedOut)
        return { kind: 'error', message: `forge-verify.sh did not finish within ${Math.round(opts.timeoutMs / 1000)}s`, logTail: tail(log ?? run.output) };
    if (run.code === 0)
        return { kind: 'pass' };
    if (run.code === 1)
        return { kind: 'fail', exitCode: 1, logTail: tail(log ?? run.output) };
    const how = run.code === null ? `signal ${run.signal ?? 'unknown'}` : `exit ${run.code}`;
    return { kind: 'error', message: `forge-verify.sh ended with ${how} (expected 0 or 1)`, logTail: tail(log ?? run.output) };
}
/** The steering text that continues the turn after a failed check. */
export function verifyFeedback(outcome, taskId, phase, round, maxRounds) {
    const head = outcome.kind === 'fail'
        ? `forge: the ${phase.toUpperCase()} gates failed (scripts/forge-verify.sh exit 1). The turn is not done. Fix what the gate names, rerun, and only then finish. Do not edit gate scripts or verify.log; if a gate is wrong, report stop condition S5.`
        : `forge: verification could not run: ${outcome.message}. The turn is not done. Do not claim the phase passed. If you cannot fix the cause from your side, report stop condition S2 or S5 and stop.`;
    const log = outcome.logTail === undefined || outcome.logTail === '' ? '' : `\n\nTail of .forge/${taskId}/verify.log:\n\n${outcome.logTail}`;
    return `${head}\n\nVerify round ${round} of ${maxRounds}.${log}`;
}
/** Counts verify rounds per agent and turn, so a failing gate cannot loop forever. */
export class VerifyRounds {
    rounds = new Map();
    next(agentId, turn) {
        const prior = this.rounds.get(agentId);
        const count = prior !== undefined && prior.turn === turn ? prior.count + 1 : 1;
        this.rounds.set(agentId, { turn, count });
        return count;
    }
    reset(agentId) {
        this.rounds.delete(agentId);
    }
}
