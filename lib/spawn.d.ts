/**
 * `forge_spawn`: start a subagent for a forge role on the route forge.toml
 * maps to that role. The official model-facing `subagent` tool takes only
 * description, prompt and run_in_background, so a plugin tool carries the
 * role (DESIGN.md section 10).
 *
 * The host interfaces below are the subset of `ctx.subagents`
 * (@deepseek-ai/dsh-subagent 0.2.1-rc.2 `SubagentRuntime.startActivation`) this tool calls.
 * `src/index.ts` passes the real service through them, so `tsc` checks the
 * real API is assignable to this subset.
 */
import { type ForgeToml, type Role, type Route } from './roles.ts';
export interface SpawnAgentOptions {
    provider?: string;
    model?: string;
}
export interface TextBlockShape {
    readonly type: 'text';
    readonly text: string;
}
/** Settled child result (`SubagentResult`). */
export interface ResultLike {
    readonly output: readonly unknown[];
    readonly stopReason: string;
    readonly diagnostic?: string;
}
/** The activation handle `startActivation` returns (`SubagentActivation`). */
export interface ActivationLike {
    readonly childId: string;
    readonly result: Promise<ResultLike>;
    dispose(): Promise<void>;
}
/** The request this tool sends; index.ts asserts it fits `SubagentActivationSpec['request']`. */
export interface StartRequestShape<Parent> {
    readonly prompt: TextBlockShape[];
    readonly parent: Parent;
    readonly agentOptions?: SpawnAgentOptions;
}
/** The activation spec this tool sends; index.ts asserts it fits `SubagentActivationSpec`. */
export interface ActivationSpecShape<Parent, Id extends string> {
    readonly provider: string;
    readonly label: string;
    readonly childId?: Id;
    readonly request: StartRequestShape<Parent>;
    readonly signal: AbortSignal;
    /** `parent` delivers the result to the parent agent as a message; `caller` only returns it. */
    readonly delivery: 'parent' | 'caller';
}
/** Subset of `SubagentRuntime` used here. */
export interface SubagentsLike<Parent, Id extends string> {
    startActivation(spec: ActivationSpecShape<Parent, Id>): Promise<ActivationLike>;
    getProvider(name: string): object | undefined;
}
export interface SpawnArgs {
    readonly description: string;
    readonly prompt: string;
    readonly role: Role;
    readonly runInBackground: boolean;
}
export interface SpawnPlan {
    readonly role: Role;
    readonly inherit: boolean;
    readonly agentOptions?: SpawnAgentOptions;
    readonly route?: Route;
    readonly family?: string;
    readonly note?: string;
}
/** Validate model arguments. Throws with a model-readable message. */
export declare function parseSpawnArgs(args: Record<string, unknown>): SpawnArgs;
/** Route selection: forge.toml mapping, else inherit the parent's route. */
export declare function planSpawn(config: ForgeToml, role: Role): SpawnPlan;
export type SpawnResult = {
    kind: 'activation';
    subagentId: string;
    role: Role;
    route: string;
    note?: string;
} | {
    kind: 'foreground';
    runId: string;
    role: Role;
    route: string;
    stopReason: string;
    output: string;
    diagnostic?: string;
    note?: string;
};
export interface SpawnDeps<Parent, Id extends string> {
    readonly subagents: SubagentsLike<Parent, Id> | undefined;
    readonly providerName: string;
    readonly parent: Parent | undefined;
    readonly signal: AbortSignal;
    /** Reserve a child id before start so the role is known on the child's first step. */
    readonly newChildId: () => Id;
    /** Record the role for a child id (policy, injection and effort read it). */
    readonly remember: (childId: string, role: Role) => void;
    readonly forget: (childId: string) => void;
}
/**
 * Start the child through `startActivation`. The child id is reserved up front
 * so the role is registered before the child's first step. A background
 * request uses `delivery: 'parent'`: the manager runs the child and delivers
 * its result to the parent as a message, and this call returns the id. A
 * foreground request uses `delivery: 'caller'`, awaits the result, and
 * disposes the activation.
 */
export declare function executeSpawn<Parent, Id extends string>(args: SpawnArgs, plan: SpawnPlan, deps: SpawnDeps<Parent, Id>): Promise<SpawnResult>;
