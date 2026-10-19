/** One write found in a command. */
export type ShellWrite = {
    /** A write to a path we could resolve. */
    readonly kind: 'path';
    readonly path: string;
    /** The command word or redirect that writes it, for the denial reason. */
    readonly via: string;
} | {
    /** A write whose target we cannot resolve (git commit, npm install, a variable path). */
    readonly kind: 'opaque';
    readonly via: string;
    /** Absolute forms of every path-like argument, for referee matching. */
    readonly mentions: readonly string[];
    /** `cargo add --dev` and friends: edits Cargo.toml dev-dependencies. */
    readonly cargoDevDeps?: true;
};
type Token = {
    readonly t: 'word';
    readonly v: string;
    readonly unresolved: boolean;
} | {
    readonly t: 'sep';
} | {
    readonly t: 'redir';
    readonly op: string;
};
/**
 * Split a command into words, separators, and redirect operators. Quotes are
 * honored, heredoc bodies are dropped (they are data, not commands), and a
 * word containing `$`, a backtick, a glob, or a leading `~` is marked
 * unresolved because its path is not knowable statically.
 */
export declare function tokenize(command: string): Token[];
/**
 * Every write a bash command might perform.
 * @param command - the command text as the model sent it.
 * @param cwd - absolute directory relative paths resolve against.
 */
export declare function analyzeShell(command: string, cwd: string): ShellWrite[];
/**
 * Every write a PowerShell command might perform. Cmdlet targets are reported
 * as opaque writes with their path-like arguments; redirects resolve normally.
 * Coarser than the bash analysis; see README.md.
 */
export declare function analyzePwsh(command: string, cwd: string): ShellWrite[];
export {};
