import { type Phase } from './policy.ts';
import { type ForgeToml } from './roles.ts';
export type ForgeState = {
    readonly active: false;
} | {
    readonly active: true;
    /** Directory holding `.forge/`. */
    readonly root: string;
    readonly taskId: string;
    /** Project-relative task directory, `.forge/<id>`. */
    readonly taskDir: string;
    readonly phase: Phase | undefined;
    /** Why phase is undefined. */
    readonly problem?: string;
};
/** Nearest ancestor of `start` (inclusive) that contains `.forge/current`. */
export declare function findForgeRoot(start: string): string | undefined;
/** Nearest ancestor of `start` (inclusive) that contains forge.toml. */
export declare function findForgeToml(start: string): string | undefined;
/**
 * Forge is active when `.forge/current` exists and names a task. An empty
 * `current` file means inactive. A bad id or a missing or invalid state.json
 * keeps forge active with `phase: undefined`, which the policy treats as
 * read-only (fail closed) while still allowing writes under `.forge/`.
 */
export declare function readForgeState(cwd: string | undefined): ForgeState;
/** forge.toml reader with an mtime cache, since `agent/request` reads it every step. */
export declare class ForgeTomlCache {
    private readonly entries;
    /**
     * Load the forge.toml nearest to `cwd`. A missing file is an empty config;
     * a syntax error throws so callers can surface it.
     */
    load(cwd: string | undefined): {
        path?: string;
        config: ForgeToml;
        warnings: string[];
    };
}
