/**
 * forge roles and their model routes, read from forge.toml. Pure.
 *
 * ```toml
 * [roles]
 * build  = "deepseek-official/deepseek-chat"
 * review = ["openrouter/qwen/qwen3-coder", "deepseek-official/deepseek-reasoner"]
 * escalation = "inherit"
 *
 * [effort]          # LlmCallConfig.reasoningEffort ids, applied only when the route lists them
 * review = "high"
 *
 * [families]       # optional; default family is the leading letters of the model id
 * "deepseek-reasoner" = "deepseek"
 * ```
 *
 * A route is `provider/model`; the first `/` splits, so model ids may contain
 * slashes. A list gives candidates in preference order.
 */
import type { Phase } from './policy.ts';
export declare const ROLES: readonly ["ground", "scout", "shape", "build", "review", "report", "escalation"];
export type Role = (typeof ROLES)[number];
export declare function isRole(value: unknown): value is Role;
/** Policy phase a child spawned with this role runs under; escalation follows the task. */
export declare function rolePhase(role: Role): Phase | undefined;
/** A phase whose name is also a role, for phase-driven effort on the main agent. */
export declare function phaseRole(phase: Phase | undefined): Role | undefined;
export interface Route {
    readonly provider: string;
    readonly model: string;
}
export interface ForgeToml {
    readonly roles: Partial<Record<Role, readonly Route[]>>;
    readonly effort: Partial<Record<Role, string>>;
    readonly families: Readonly<Record<string, string>>;
}
export declare const EMPTY_FORGE_TOML: ForgeToml;
export declare function parseRoute(spec: string): Route | undefined;
/**
 * Read the role tables of forge.toml. Unknown roles and malformed routes are
 * reported as warnings and skipped; TOML syntax errors throw `TomlError`.
 */
export declare function parseForgeToml(text: string): {
    config: ForgeToml;
    warnings: string[];
};
/**
 * Model family of a route: an explicit `[families]` entry for `provider/model`
 * or `model`, otherwise the leading letters of the model id's last segment
 * (`deepseek-chat` is deepseek, `qwen3-coder` is qwen, `glm-4.6` is glm).
 */
export declare function familyOf(route: Route, families: Readonly<Record<string, string>>): string;
export type RoleResolution = {
    readonly inherit: true;
    readonly reason: string;
} | {
    readonly inherit: false;
    readonly route: Route;
    readonly family: string;
    readonly warning?: string;
};
/**
 * Pick the route for a role. Unmapped roles inherit the parent conversation's
 * route. The review role prefers the first candidate whose family differs from
 * build's, so the reviewer is a different model family when both are
 * configured (DESIGN.md section 3, REVIEW). `avoidFamilies` picks the first
 * candidate outside those families instead, which is how a review panel gets
 * its second reviewer from a different family than the first.
 */
export declare function resolveRole(config: ForgeToml, role: Role, avoidFamilies?: readonly string[]): RoleResolution;
