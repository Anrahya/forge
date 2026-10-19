import type { Context } from '@deepseek-ai/cordis';
import type { Agent } from '@deepseek-ai/dsh-agent';
import { type ContextFormed } from '@deepseek-ai/dsh-llm';
import { SessionId } from '@deepseek-ai/dsh-session';
import type { SubagentActivationSpec } from '@deepseek-ai/dsh-subagent';
import Schema from '@deepseek-ai/schemastery';
import { type ActivationSpecShape } from './spawn.ts';
declare module '@deepseek-ai/dsh-llm' {
    interface MessageSourceMap {
        /** Context entered by the forge adapter: phase playbooks and verify feedback. */
        forge: {
            kind: 'forge';
        } & ContextFormed;
    }
}
type Assert<T extends true> = T;
export type ActivationSpecFits = Assert<ActivationSpecShape<Agent, SessionId> extends SubagentActivationSpec ? true : false>;
export declare const name = "forge-dsh";
export declare const inject: string[];
export interface Config {
    /** Directory holding forge's skills/, AGENTS.md and scripts/. Default: this package when it carries AGENTS.md and skills/, else bundled assets. */
    forgeRoot?: string;
    /** Steps between re-entries of identical forge context within one turn. 1 means every step. */
    reinjectEverySteps: number;
    /** Upper bound on the entered forge context, in characters. */
    maxInjectChars: number;
    /** Run scripts/forge-verify.sh when a top-level turn is about to end. */
    verifyOnTurnStop: boolean;
    /** Also verify when a subagent's turn ends. */
    verifySubagents: boolean;
    verifyTimeoutMs: number;
    /** Failed verify rounds per turn before the turn is allowed to end anyway. */
    maxVerifyRounds: number;
    verifyTailLines: number;
    verifyTailChars: number;
    /** ctx.subagents provider forge_spawn uses. Base bundle name: spawn. */
    spawnProvider: string;
    /** Extra absolute directories where writes are always allowed. OS temp dirs are always included. */
    scratchDirs: string[];
}
export declare const Config: Schema<Config>;
export declare function apply(ctx: Context, config?: Partial<Config>): void;
export {};
