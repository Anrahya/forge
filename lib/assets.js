/**
 * Where the portable forge layer (skills/, AGENTS.md, scripts/) lives.
 *
 * The repository root is the plugin package, so the package root normally is
 * the forge root. Order:
 * 1. the plugin `forgeRoot` config;
 * 2. the package root itself, when it carries AGENTS.md and skills/ (a git or
 *    link install of this repository);
 * 3. `<package>/assets`, for a package that was built from a nested layout.
 */
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
/** Package root: one level above `src/` or `lib/`. */
export function packageRoot() {
    return resolve(dirname(fileURLToPath(import.meta.url)), '..');
}
export function resolveForgeRoot(configured, pkg = packageRoot()) {
    if (configured !== undefined && configured.trim() !== '')
        return resolve(configured);
    if (existsSync(join(pkg, 'AGENTS.md')) && existsSync(join(pkg, 'skills')))
        return pkg;
    return join(pkg, 'assets');
}
