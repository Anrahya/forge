import { type ShellWrite } from './shell.ts';
export declare const PHASES: readonly ["ground", "scout", "shape", "build", "verify", "review", "report"];
export type Phase = (typeof PHASES)[number];
export declare function isPhase(value: unknown): value is Phase;
/**
 * How a phase treats writes.
 * - `read-only`: only `.forge/` and scratch directories. GROUND, SCOUT and
 *   REVIEW per DESIGN.md section 7; VERIFY because its work is scripted.
 * - `guard-referee`: anything except referee paths. SHAPE writes skeletons and
 *   prototypes, BUILD writes code, REPORT writes prose.
 */
export type PhaseMode = 'read-only' | 'guard-referee';
export declare const PHASE_MODE: Readonly<Record<Phase, PhaseMode>>;
export type Decision = {
    readonly kind: 'allow';
} | {
    readonly kind: 'deny';
    readonly reason: string;
} | {
    readonly kind: 'ask';
    readonly reason: string;
};
export declare const ALLOW: Decision;
/** What the policy needs to know about the session. All paths absolute POSIX. */
export interface PolicyContext {
    /** Directory that holds `.forge/`. */
    readonly projectRoot: string;
    /** Base for relative tool paths: the session's working directory. */
    readonly cwd: string;
    /** Task id from `.forge/current`. */
    readonly taskId: string;
    /** Phase from `.forge/<task>/state.json`; undefined when missing or invalid. */
    readonly phase: Phase | undefined;
    /** Why `phase` is undefined, for the denial text. */
    readonly stateProblem?: string;
    /**
     * Phase implied by the calling subagent's forge role (a `review` child is
     * read-only even while the task is in BUILD). Both phases must allow a write.
     */
    readonly rolePhase?: Phase;
    /** Absolute directories where writes are always allowed (OS temp dirs). */
    readonly scratchDirs?: readonly string[];
    /** Current text of a file, or undefined when absent. Used for Cargo.toml. */
    readonly readFile?: (absPath: string) => string | undefined;
}
export interface ToolCall {
    readonly name: string;
    readonly args: unknown;
}
/** A write to a known path. Shell path writes carry neither `edit` nor `content`. */
export interface PathWrite {
    readonly kind: 'path';
    readonly path: string;
    readonly via: string;
    /** Literal replacement, for section-aware Cargo.toml checks. */
    readonly edit?: {
        readonly oldText: string;
        readonly newText: string;
        readonly atLine?: number;
    };
    /** Full new content, for whole-file writes. */
    readonly content?: string;
}
/** One write a tool call would perform. */
export type WriteOp = PathWrite | Extract<ShellWrite, {
    kind: 'opaque';
}>;
/**
 * Whether a project-relative path is a referee file regardless of content.
 * Cargo.toml is content-sensitive and handled in {@link cargoDevDepsReason}.
 */
export declare function isRefereePath(rel: string): boolean;
/** `.forge/<anything>/verify.log`: written only by scripts/forge-verify.sh. */
export declare function isVerifyLog(rel: string): boolean;
/** Project-relative POSIX path, or a `../` path when outside the project. */
export declare function projectRelative(projectRoot: string, abs: string): string;
/** The dev-dependency sections of a Cargo.toml, joined, for before/after comparison. */
export declare function devDepsText(text: string): string;
/**
 * Why a Cargo.toml write is a referee change, or undefined when it is not.
 * Dev-dependencies are referee because they decide which test and lint
 * tooling runs; ordinary dependencies stay writable in BUILD.
 */
export declare function cargoDevDepsReason(op: WriteOp, current: string | undefined): string | undefined;
/**
 * Model-facing DSH tools that write files, keyed by tool name. Tool names and
 * argument keys: `edit`, `write`, `bash` confirmed against the published
 * 0.2.0-rc.2 packages; `str_replace_editor`, `pwsh`, `terminal_send` from
 * docs/tool-catalog.md on master (HYPOTHESIS for rc.2, same names expected).
 * Tools not listed here are allowed: MCP tools that write are not covered.
 */
export declare function writesOf(call: ToolCall, cwd: string): WriteOp[];
/**
 * Decide one tool call. Deny reasons are model-facing: DSH shows them to the
 * model as the tool result text `Error: <reason>` (confirmed in
 * @deepseek-ai/dsh-tools 0.2.0-rc.2 `ToolRuntime` pre-execute handling).
 */
export declare function evaluateToolCall(call: ToolCall, ctx: PolicyContext): Decision;
