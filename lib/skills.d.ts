export declare const SKILL_NAME: RegExp;
export interface SkillRecord {
    readonly name: string;
    readonly description: string;
    readonly whenToUse?: string;
    readonly modelInvocable: boolean;
    readonly userInvocable: boolean;
    /** Markdown body after the frontmatter. */
    readonly content: string;
    /** Absolute directory holding SKILL.md (resource base for playbooks). */
    readonly dir: string;
    /** Absolute SKILL.md path. */
    readonly path: string;
}
export interface ParsedFrontmatter {
    readonly fields: Readonly<Record<string, string>>;
    readonly body: string;
}
/**
 * Minimal YAML frontmatter reader: `key: value` lines plus `|` and `>` block
 * scalars (indented continuation lines). Nested maps and lists are skipped.
 */
export declare function parseFrontmatter(text: string): ParsedFrontmatter | undefined;
/** Parse one SKILL.md. Returns a problem string instead of a record when invalid. */
export declare function toSkillRecord(path: string, dir: string, text: string): SkillRecord | {
    problem: string;
};
/**
 * Every valid SKILL.md under `root`, sorted by name. Invalid files and
 * duplicate names are returned as problems; the first path in sorted order
 * wins a duplicate.
 */
/** Replace `$FORGE_HOME` with the install directory so skills can name scripts by absolute path. */
export declare function substituteForgeHome(text: string, forgeHome: string | undefined): string;
export declare function scanSkills(root: string, forgeHome?: string): Promise<{
    skills: SkillRecord[];
    problems: string[];
}>;
