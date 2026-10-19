import type { Phase } from './policy.ts';
/** The `## Principle index` section of AGENTS.md, heading included. */
export declare function principleIndex(agentsMd: string): string | undefined;
/** Skill body without its frontmatter. */
export declare function skillBody(text: string): string;
export interface InjectionInput {
    readonly taskId: string;
    readonly phase: Phase;
    /** Install directory of forge; stated so the model can run `$FORGE_HOME/scripts/...`. */
    readonly forgeHome?: string;
    readonly skillPath?: string;
    readonly skill?: string;
    readonly index?: string;
    readonly maxChars: number;
}
export declare function buildInjection(input: InjectionInput): string;
export declare function hashText(text: string): string;
/**
 * Decides whether this step enters the forge context. In-memory per agent;
 * a Host restart re-enters once, which is harmless.
 */
export declare class InjectionTracker {
    private readonly last;
    shouldEnter(agentId: string, hash: string, turn: number, step: number, every: number): boolean;
    forget(agentId: string): void;
}
/**
 * Load the phase skill (project `.agents/skills/forge-<phase>/SKILL.md` wins,
 * matching DSH's project-over-bundled skill precedence) and the principle
 * index from the forge AGENTS.md.
 */
export declare function loadPhaseContext(projectRoot: string, forgeRoot: string, phase: Phase): Promise<{
    skill?: string;
    skillPath?: string;
    index?: string;
}>;
