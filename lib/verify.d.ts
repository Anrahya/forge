import type { Phase } from './policy.ts';
export type VerifyOutcome = {
    readonly kind: 'pass';
} | {
    readonly kind: 'fail';
    readonly exitCode: number;
    readonly logTail: string;
} | {
    readonly kind: 'error';
    readonly message: string;
    readonly logTail?: string;
};
/** Last `maxLines` lines, then at most `maxChars` characters from the end. */
export declare function tailText(text: string, maxLines: number, maxChars: number): string;
/** Project script wins (forge-verify-setup may vendor one); else the forge copy. */
export declare function resolveVerifyScript(projectRoot: string, forgeRoot: string): string | undefined;
export interface RunVerifyOptions {
    readonly script: string | undefined;
    readonly projectRoot: string;
    readonly taskDir: string;
    readonly phase: Phase;
    readonly timeoutMs: number;
    readonly signal?: AbortSignal;
    readonly tailLines: number;
    readonly tailChars: number;
}
export declare function runVerify(opts: RunVerifyOptions): Promise<VerifyOutcome>;
/** The steering text that continues the turn after a failed check. */
export declare function verifyFeedback(outcome: Exclude<VerifyOutcome, {
    kind: 'pass';
}>, taskId: string, phase: Phase, round: number, maxRounds: number): string;
/** Counts verify rounds per agent and turn, so a failing gate cannot loop forever. */
export declare class VerifyRounds {
    private readonly rounds;
    next(agentId: string, turn: number): number;
    reset(agentId: string): void;
}
