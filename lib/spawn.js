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
import { resolveRole, isRole } from "./roles.js";
/** Validate model arguments. Throws with a model-readable message. */
export function parseSpawnArgs(args) {
    const description = typeof args.description === 'string' ? args.description.trim() : '';
    const prompt = typeof args.prompt === 'string' ? args.prompt : '';
    const role = args.role;
    if (description === '')
        throw new Error('forge_spawn: description is required');
    if (prompt.trim() === '')
        throw new Error('forge_spawn: prompt is required; the child does not see this conversation');
    if (!isRole(role))
        throw new Error('forge_spawn: role must be one of ground, scout, shape, build, review, report, escalation');
    return { description, prompt, role, runInBackground: args.run_in_background !== false };
}
/** Route selection: forge.toml mapping, else inherit the parent's route. */
export function planSpawn(config, role) {
    const resolved = resolveRole(config, role);
    if (resolved.inherit)
        return { role, inherit: true, note: resolved.reason };
    return {
        role,
        inherit: false,
        agentOptions: { provider: resolved.route.provider, model: resolved.route.model },
        route: resolved.route,
        family: resolved.family,
        ...resolved.warning === undefined ? {} : { note: resolved.warning },
    };
}
function routeLabel(plan) {
    return plan.route === undefined ? 'inherit' : `${plan.route.provider}/${plan.route.model}`;
}
function textOf(blocks) {
    return blocks
        .map(b => (typeof b === 'object' && b !== null && b.type === 'text' ? String(b.text ?? '') : ''))
        .filter(t => t !== '')
        .join('\n');
}
/**
 * Start the child through `startActivation`. The child id is reserved up front
 * so the role is registered before the child's first step. A background
 * request uses `delivery: 'parent'`: the manager runs the child and delivers
 * its result to the parent as a message, and this call returns the id. A
 * foreground request uses `delivery: 'caller'`, awaits the result, and
 * disposes the activation.
 */
export async function executeSpawn(args, plan, deps) {
    if (deps.parent === undefined)
        throw new Error('forge_spawn must be called by an agent');
    const subagents = deps.subagents;
    if (subagents === undefined)
        throw new Error('forge_spawn needs the DSH subagent service (@deepseek-ai/dsh-subagent); it is not loaded');
    const provider = subagents.getProvider(deps.providerName);
    if (provider === undefined)
        throw new Error(`forge_spawn: subagent provider "${deps.providerName}" is not registered`);
    const prompt = [{ type: 'text', text: args.prompt }];
    const route = routeLabel(plan);
    const note = plan.note === undefined ? {} : { note: plan.note };
    const agentOptions = plan.agentOptions === undefined ? {} : { agentOptions: plan.agentOptions };
    const childId = deps.newChildId();
    deps.remember(childId, args.role);
    let activation;
    try {
        activation = await subagents.startActivation({
            provider: deps.providerName,
            label: args.description,
            childId,
            request: { prompt, parent: deps.parent, ...agentOptions },
            signal: deps.signal,
            delivery: args.runInBackground ? 'parent' : 'caller',
        });
    }
    catch (error) {
        deps.forget(childId);
        throw error;
    }
    if (activation.childId !== childId) {
        deps.forget(childId);
        deps.remember(activation.childId, args.role);
    }
    if (args.runInBackground) {
        return { kind: 'activation', subagentId: activation.childId, role: args.role, route, ...note };
    }
    try {
        const result = await activation.result;
        return {
            kind: 'foreground',
            runId: activation.childId,
            role: args.role,
            route,
            stopReason: result.stopReason,
            output: textOf(result.output),
            ...result.diagnostic === undefined ? {} : { diagnostic: result.diagnostic },
            ...note,
        };
    }
    finally {
        await activation.dispose();
    }
}
