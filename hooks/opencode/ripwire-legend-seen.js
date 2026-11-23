// hooks/opencode/ripwire-legend-seen.js — the opencode plugin twin of hooks/ripwire-legend-seen.sh (lane LS1).
//
// opencode has no shell hooks; it loads plugin modules from {plugin,plugins}/*.{ts,js} under ~/.config/opencode (or a
// project's .opencode/). This plugin hands each event to the SAME shell hook Claude Code uses, in that hook's payload
// shape, so the per-session FILE, the rewrite rules and every safety rule live in one place:
//   tool.execute.before (bash)  -> PreToolUse: the hook may answer an updatedInput command (--legend-seen=FILE inserted
//                                  after the binary word); output.args.command takes it, nothing else changes
//   tool.execute.after  (bash)  -> PostToolUse: the output the agent received; opencode marks a cut output with
//                                  metadata.truncated, and a truncated output is not recorded (as an interrupted one)
//   event session.compacted / session.deleted -> the session's FILE is forgotten (a compacted context no longer holds it)
// A subagent runs in its own opencode session, so it gets its own FILE. Any surprise (no bash, no jq, the hook missing,
// a parse error) leaves the call untouched. RIPWIRE_LEGEND_SEEN=0 turns it off (the hook reads it).
// Installed by skills/install.sh --opencode --hook-legend-seen. Gate: test/legendseenportcheck.sh.
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HOOK = join(dirname(fileURLToPath(import.meta.url)), "..", "ripwire-legend-seen.sh");
const stateRoot = () =>
  process.env.RIPWIRE_LEGEND_STATE ??
  join(process.env.RIPWIRE_HOME ?? join(process.env.HOME ?? "", ".ripwire"), "legend-seen-opencode");

function hook(event) {
  try {
    const r = spawnSync("bash", [HOOK], {
      input: JSON.stringify(event),
      encoding: "utf8",
      env: { ...process.env, RIPWIRE_LEGEND_STATE: stateRoot() },
      timeout: 10000,
    });
    if (r.status !== 0 || !r.stdout || !r.stdout.trim()) return {};
    return JSON.parse(r.stdout);
  } catch {
    return {};
  }
}

export const RipwireLegendSeen = async ({ directory }) => ({
  "tool.execute.before": async (input, output) => {
    if (input?.tool !== "bash" || typeof output?.args?.command !== "string") return;
    const res = hook({
      hook_event_name: "PreToolUse",
      session_id: input.sessionID,
      cwd: directory,
      tool_name: "Bash",
      tool_input: { command: output.args.command },
    });
    const cmd = res?.hookSpecificOutput?.updatedInput?.command;
    if (typeof cmd === "string" && cmd.length > 0) output.args.command = cmd;
  },
  "tool.execute.after": async (input, output) => {
    if (input?.tool !== "bash") return;
    hook({
      hook_event_name: "PostToolUse",
      session_id: input.sessionID,
      cwd: directory,
      tool_name: "Bash",
      tool_input: { command: typeof input?.args?.command === "string" ? input.args.command : "" },
      tool_response: {
        stdout: typeof output?.output === "string" ? output.output : "",
        interrupted: Boolean(output?.metadata?.truncated),
        isImage: false,
      },
    });
  },
  event: async ({ event }) => {
    if (event?.type !== "session.compacted" && event?.type !== "session.deleted") return;
    const sid = event?.properties?.sessionID ?? event?.properties?.info?.id;
    if (typeof sid === "string") hook({ hook_event_name: "PreCompact", session_id: sid });
  },
});
