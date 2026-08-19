#!/usr/bin/env bash
# hooks/ripwire-nudge.sh — OPT-IN Claude Code PreToolUse hook. Two jobs in one script: the
# ADVISORY-ONLY nudge (below), and the SUBSTITUTION METER (see the §METER block further down).
#
# Nudges an agent from raw grep/rg, from whole-file Read / candidate-Glob, and from raw `git diff`/
# `git log`/`git show --stat`, toward the matching ripwire verb. Ships INACTIVE — only registered via
# `skills/install.sh --hook`, never automatically (see the Phase B5.2 / R5 agent-context-science
# design: "with grep available, the agent defaults to it... a PreToolUse hook is the high-leverage
# lever" — passive skill-description triggering alone is measured ~30-50% reliable). Phase B9
# (Part 3) extends the trigger set to the git-information moments where raw
# output is weakest vs ripwire's structured answers: `git diff` → `--situ`/`--pr-context`, `git log` →
# `--rank-by=churn`/`--map-diff`, `git show --stat` → `--map-diff`. Deliberately excluded: `git status`
# and state-changing commands (add/commit/push/pull/checkout/branch) — nudging those is spam.
#
# 2026-08-10 (skill-orientation audit): Read and Glob added. They were previously excluded by the fast
# bail, which left the LARGEST token sink in the loop — the whole-file read — as the one default this
# hook could not see. A skill description only fires if the agent first RECOGNIZES a moment and then
# spends a call to load the skill; `Read` needs neither. The read nudge is therefore the one that
# matters most, and it is why the Read case is deliberately NOT deduped against the grep case: they
# are different habits and each gets its own one-time nudge.
#
# The read nudge fires ONCE per session and deliberately does NOT try to name the symbol involved:
# suggesting `--expand=<guess>` when the guess is wrong teaches an agent the tool is unreliable, which
# costs more than the nudge gains. It names the verb and lets the agent supply the argument.
#
# Design posture (non-negotiable — do not "improve" this into a blocker):
#   - NEVER blocks, denies, or rewrites the tool call. Always permissionDecision "allow" when it
#     speaks at all; never "deny"/"ask"; never "updatedInput". Any internal failure (missing jq,
#     malformed JSON, no git, no ripwire) degrades to silent allow — exit 0, no stdout.
#   - Fires at MOST once per session per pattern (Grep, Bash-grep, git-diff, git-log, and git-show-stat
#     are separate patterns), via a marker file under $TMPDIR keyed by session_id (falls back to PPID
#     if the payload has none) — an agent sees each nudge once, not on every call.
#   - Only fires when the target directory is inside a git repo AND a `ripwire` binary is on PATH.
#   - Exits fast: the common case (any tool other than Grep/Bash, or a Bash command that matches none
#     of recursive grep/rg / `git diff` / `git log` / `git show --stat`) bails after one or two greps
#     over stdin — no subprocess spawned.
#
# Contract (verified against https://code.claude.com/docs/en/hooks, 2026-07-13): PreToolUse JSON
# arrives on stdin with at least {session_id, cwd, tool_name, tool_input}. Advisory feedback that does
# NOT block the call = exit 0 + this JSON on stdout:
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow",
#    "additionalContext":"..."}}
#
# Usage (wired by the installer, not meant to be run by hand):
#   printf '%s' "$PRETOOLUSE_JSON" | hooks/ripwire-nudge.sh
set -u

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §METER — THE SUBSTITUTION METER (Track B §S2, 2026-08-11)
#
# WHAT IT MEASURES, AND WHY THE UNIT IS A TOOL CALL. The question this project actually wants answered
# is "does an agent with ripwire installed reach for it instead of grep/read?". The task-success
# outcome eval cannot answer it: the power arithmetic puts the minimum detectable effect at 8.5-26pp
# against a pilot that measured parity, so that instrument is dead no matter how long it runs. A
# PreToolUse hook, on the other hand, sits at the exact decision point — the moment a default is
# chosen — and every session produces hundreds of those. So the unit of observation is one TOOL CALL,
# and the metric is a rate over calls: ripwire calls / (ripwire + native retrieval calls).
#
# ONE GLOBAL LOG. Rows append to $RIPWIRE_HOME/substitution.jsonl (default ~/.ripwire/), created
# lazily, one row per line, each tagged with the repo it came from. The hook is registered per-user
# but runs in whatever repo the session is in, so a single global file with a `tag`/`repo` field is
# what makes both cross-repo and per-repo analysis possible from the same data. bench/
# substitution_report.py reads it; docs/SUBSTITUTION_METER.md is the schema and the classifier's
# rule table. One log means one contamination risk, so the §FIXTURE guard in meter_init() is part of
# the design and not a test detail: a gate run must never be able to reach that file.
#
# A REAL RANDOMIZATION MECHANISM NOW EXISTS: `meter_auto_arm`, ACTIVATED BY `arm=auto` (2026-08-19
# fix). From 2026-08-11 through 2026-08-19 the only way to reach the control arm at all was to name it
# explicitly — an operator setting RIPWIRE_METER_ARM=control (or `arm=control` in meter.conf) for an
# ENTIRE machine, session by session, by hand; there was no code path that could ever produce a MIXED
# population, only all-control or all-treatment. Nobody ever set it, across 4,209 logged rows and 21
# sessions: 100% treatment, 0% control, and the meter could not answer its own north-star question
# (does the nudge change behavior vs. no nudge) because there was nothing to compare against. This was
# a silent, unannounced gap: the `arm` field was always present and always "treatment", so the log
# LOOKED complete.
#
# `meter_auto_arm` hashes the session id to a stable ~50/50 split — a pure function of an immutable
# input, so "decided once at SessionStart, persisted for the session" comes for free: every PreToolUse
# invocation in a session recomputes the same hash of the same session id and lands on the same arm,
# with no marker file and no shared state to go stale, including across the internal SessionStart
# resets a long session can produce (see the post_nudge/post_sweep reset behavior above). It is reached
# only when the arm config names the new literal `auto` (RIPWIRE_METER_ARM=auto, or `arm=auto` in
# meter.conf) — UNSET still means treatment, exactly as before this fix, so a machine nobody has
# touched keeps behaving exactly as it always has; going live with a real A/B population is a
# deployment-time config write (`arm=auto`), not a change to what the script defaults to.
#
# THIS FIX DOES NOT CHANGE TREATMENT SEMANTICS. A session that lands on the treatment arm behaves
# bit-for-bit as before: same nudges, same dedup, same sweep. What changes is only that a control arm
# now actually gets populated, and — see the nudge-decision block further down — a control-arm call
# runs through the IDENTICAL eligibility bookkeeping a treatment call does (the same per-category
# marker, the same per-class sweep counter), so the row records "control" when this call would have
# been the one to fire/escalate and "suppressed-control" when it would have been deduped — eligibility
# is measurable in both arms, not just inferred from silence.
#
# THE NUDGE-CAUSES-THE-CALL CONFOUND. A nudge that says "use --grep" is itself a cause of the next
# ripwire call, so a naive rate would partly measure the hook talking to itself. Three fields keep
# that separable at analysis time: `nudged` (this call is the one a nudge fired on), `nudge` (why it
# did or did not: fired/dedup/gated/control/none) and `post_nudge` (a nudge had ALREADY fired earlier
# in this session, before this call). Pre-nudge calls in a session are the clean observations.
#
# SEQUENCES, NOT JUST CALLS. `session` + `seq` (a per-session monotonic counter) order the rows
# unambiguously even when several land in the same wall-clock second, so the analysis can reconstruct
# CHAINS (grep -> read -> read) and rank scenario bundles, not only single calls.
#
# NON-NEGOTIABLE: the meter is subordinate to the tool call it observes. Every write is best-effort —
# no HOME, an unwritable directory, no `date`, no `jq`, a full disk: each returns quietly and the
# hooked command proceeds untouched. Nothing in this block may change the hook's exit status or its
# stdout. `RIPWIRE_METER=0` (or `enabled=0` in meter.conf) turns counting off entirely and leaves the
# nudge working.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §SWEEP — THE SWEEP-ESCALATION NUDGE (Track B §S2b, 2026-08-11)
#
# WHY A SECOND NUDGE EXISTS AT ALL. The meter's first 12 hours (2,095 rows, 34 sessions) said two
# things at once. (1) The one-time nudges above FIRE — 455 of them — and convert at ZERO: substitution
# after a nudge was 0.8%, indistinguishable from before it. Generic advice at the first grep does not
# change the next choice. (2) The dominant behaviour is the SAME-CLASS SWEEP: grep→grep→grep occurred
# 357 times as a trigram, read×3 187 times, git-diff×3 119, and git-log / git-show-stat / glob ×3
# about 39 each. Cross-class motifs are an order of magnitude smaller.
#
# A sweep is trial-and-error retrieval — the agent is paying N round-trips and N outputs for one
# question, and ripwire already has the one-call answer for every sweep class. So the hypothesis this
# block ships is narrow and falsifiable: a nudge converts when it arrives AT THE SWEEP MOMENT and
# carries the EXACT command, built from what was actually observed, rather than a verb name and an
# ellipsis. The grep escalation quotes the agent's own last patterns back at it inside a runnable
# `--for="…"`; the read escalation names the directory of the file just read.
#
# THE CONTRACT (all four are gated in test/hookcheck.sh, arms S1-S14):
#   - At most ONE escalation per CLASS per session — the same dedup posture as the base nudges, with
#     its own marker, so an escalated grep sweep never re-fires and never silences a read sweep.
#   - Advisory only. Same posture as everything else here: permissionDecision "allow", never deny,
#     never a rewrite, and any internal failure degrades to silence.
#   - The escalation is RECORDED — `nudge":"sweep<N>"` on the row it fired on, and `post_sweep` on
#     every row after it in that session. Without those two fields the efficacy question cannot be
#     asked, and an unmeasurable nudge is one nobody can ever turn off on evidence.
#   - It costs a bounded amount per call: one byte appended to a per-class counter file and one
#     fork-free `$(<file)` read of it, on the nudgeable path only. The control arm and non-git calls
#     pay nothing.
#
# THE VERDICT IS PRE-REGISTERED, NOT ASSUMED. docs/EVALS.md §8 registers the one-week readout: the
# primary is the substitution rate on calls following a sweep escalation versus the 0.8% baseline,
# with a stated accept-keep band, and a NULL result DISABLES this block (`RIPWIRE_SWEEP=0`, or
# `sweep=0` in meter.conf — a config flip, deliberately, so the decision costs no code).
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §FIXTURE — A TEST RUN MAY NEVER REACH THE OPERATOR'S LOG (2026-08-12)
#
# This hook has a gate, test/hookcheck.sh, which drives it with invented PreToolUse payloads by the
# dozen. Those invocations write rows in the ordinary way, and a fixture row is INDISTINGUISHABLE
# from a real one at analysis time: same schema, same classes, a plausible session id. Until
# 2026-08-12 the gate ran with the ambient environment, so the meter resolved the real $HOME and
# every gate run appended a burst of synthetic rows to the live log.
#
# The damage is not noise, it is BIAS, which is why this is a guard and not a cleanup note. A gate
# run is a burst of nudge-firing NATIVE calls containing no ripwire call at all: it drags the
# headline rate toward zero, and it lands disproportionately in the nudge-efficacy denominator —
# the exact quantity docs/EVALS.md §4 pre-registers a band against.
#
# Two independent layers now hold the contract, because one layer is a thing a future test forgets:
#   L1  the gate names a sandbox destination once, exported, so every invocation inherits it;
#   L2  RIPWIRE_METER_FIXTURE says "a harness is driving this hook". With no destination named, the
#       only path left is the real one, so meter_dest() writes nothing instead — see the function.
# Section (13) of the gate asserts both held, by PROVENANCE (no row in the operator's log carries
# this run's mktemp path) rather than by byte size, which a concurrent real session makes flaky.
#
# Repairing a log that was already polluted is a separate job with a separate tool:
# bench/substitution_scrub.py, documented in docs/SUBSTITUTION_METER.md.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# ---- meter state, resolved once per invocation: where the log is, whether counting is on, which arm.
#      Reading meter.conf uses a shell read loop rather than grep/sed — no subprocess on a path that
#      runs for every observed tool call. Env wins over the file; the file wins over the defaults. ----
meter_enabled=0
meter_file=""
meter_arm="treatment"
meter_post=0
meter_postsweep=0
meter_repo=""
meter_tag=""
sweep_on=1
sweep_n=3
# ---- meter_dest — WHERE the log goes. Sets `_mhome` (the config directory) and `meter_file`, and
#      applies the §FIXTURE guard. `_mexplicit` is the guard's whole input: it records whether the
#      caller NAMED a destination (RIPWIRE_METER_LOG / RIPWIRE_HOME) or the path was merely INFERRED
#      from $HOME, which is the only distinction between a harness writing to its sandbox and a
#      harness writing to the operator's real telemetry. ----
meter_dest()
{
    _mexplicit=0
    _mhome="${RIPWIRE_HOME:-}"
    [ -n "$_mhome" ] && _mexplicit=1
    [ -n "$_mhome" ] || { [ -n "${HOME:-}" ] && _mhome="$HOME/.ripwire"; }
    meter_file="${RIPWIRE_METER_LOG:-}"
    [ -n "$meter_file" ] && _mexplicit=1
    [ -n "$meter_file" ] || { [ -n "$_mhome" ] && meter_file="$_mhome/substitution.jsonl"; }
    # A harness that named nothing gets nothing: not the real log, and not the host's meter.conf
    # either (clearing `_mhome` is what stops a forgotten arm inheriting the operator's arm and
    # threshold). Silent, like every other meter failure — see §FIXTURE.
    if [ -n "${RIPWIRE_METER_FIXTURE:-}" ] && [ "$_mexplicit" = "0" ]
    then
        meter_file=""
        _mhome=""
    fi
}

# ---- meter_auto_arm SESSION — the ~50/50 split used when the arm config names the literal `auto`
#      (see the design note above §METER). `cksum` (POSIX, present on every platform this hook ships
#      on) hashes the session id to a number; the low two decimal digits split the range in half. Any
#      failure of the hash (no `cksum`, or output this script does not recognize as a plain integer)
#      degrades to "treatment" — the same safe default the rest of this file uses whenever a signal is
#      unavailable, never a crash and never a silently invented third arm. ----
meter_auto_arm()
{
    _aa_h="$( printf '%s' "$1" | cksum 2>/dev/null | cut -d' ' -f1 )"
    case "$_aa_h" in
        ''|*[!0-9]*) printf 'treatment'; return 0 ;;
    esac
    if [ "$(( _aa_h % 100 ))" -lt 50 ]
    then
        printf 'control'
    else
        printf 'treatment'
    fi
}

meter_init()
{
    meter_dest
    _conf_enabled=""
    _conf_arm=""
    _conf_sweep=""
    _conf_sweepn=""
    if [ -n "$_mhome" ] && [ -f "$_mhome/meter.conf" ]
    then
        while IFS='=' read -r _ck _cv
        do
            case "$_ck" in
                enabled) _conf_enabled="$_cv" ;;
                arm)     _conf_arm="$_cv" ;;
                sweep)   _conf_sweep="$_cv" ;;
                sweep_n) _conf_sweepn="$_cv" ;;
            esac
        done < "$_mhome/meter.conf"
    fi

    # The sweep escalation is resolved even when the LOG is unavailable: it is a nudge, not a
    # measurement, and it must not silently switch itself off on a machine with no writable HOME.
    case "${RIPWIRE_SWEEP:-$_conf_sweep}" in
        0|off|no|false) sweep_on=0 ;;
        *)              sweep_on=1 ;;
    esac
    # An N that is not a plain positive integer reads as the default rather than disabling the
    # feature by accident or escalating on the first call.
    case "${RIPWIRE_SWEEP_N:-$_conf_sweepn}" in
        ''|*[!0-9]*) sweep_n=3 ;;
        0)           sweep_n=3 ;;
        *)           sweep_n="${RIPWIRE_SWEEP_N:-$_conf_sweepn}" ;;
    esac

    # THE ARM IS RESOLVED BEFORE THE LOG IS, and that ordering is the fix for a bug this file shipped
    # with (2026-08-12, found by the E1 lane driving the arm for real). The arm is not a property of
    # the log — it decides whether the agent is SPOKEN TO — so a run with nowhere to write must still
    # honour it. Below the early return, `RIPWIRE_METER_ARM=control` with no named destination (the
    # exact shape of a fixture-guarded harness, and of the control arm the A/B phase will run) left
    # `meter_arm` at its `treatment` default and the control session got nudged anyway: 466 bytes of
    # advice where the contract promises none. A control arm that silently does not control is worse
    # than no control arm, because the resulting data looks valid.
    #
    # The literal `control`/`treatment` still force an arm (an operator override, or a test harness
    # pinning one side) — that contract, and its "any unrecognized value reads as treatment" safety
    # net, is UNCHANGED, on purpose: this file's own default stays `treatment` so a machine that never
    # touches meter.conf keeps behaving exactly as it always has. What is NEW is a third literal value,
    # `auto`, which activates the session-id hash split in `meter_auto_arm` — this is the fix's actual
    # deliverable, but it is opt-in at the CONFIG layer (deployment writes `arm=auto` to
    # ~/.ripwire/meter.conf) rather than a change to what an unconfigured hook does. That split keeps
    # "does this commit change treatment semantics" answerable with "no" — nothing about this hook's
    # behavior moves unless something now names `auto` where nothing was named before.
    case "${RIPWIRE_METER_ARM:-$_conf_arm}" in
        control)    meter_arm="control" ;;
        auto)       meter_arm="$( meter_auto_arm "$session" )" ;;
        *)          meter_arm="treatment" ;;
    esac

    [ -n "$meter_file" ] || return 0          # no HOME and no explicit log path — nothing to write to

    case "${RIPWIRE_METER:-$_conf_enabled}" in
        0|off|no|false) meter_enabled=0 ;;
        *)              meter_enabled=1 ;;
    esac
}

# ---- JSON string escape for the no-jq fallback. Control characters are DELETED rather than escaped:
#      it costs nothing here and it makes "one row is one line" true by construction. ----
meter_esc()
{
    printf '%s' "$1" | tr -d '\000-\037' | cut -c1-200 | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# ---- meter_log CLASS FAMILY NUDGED NUDGEREASON DETAIL — append one row. Silent, never fatal. ----
meter_log()
{
    [ "$meter_enabled" = "1" ] || return 0
    [ -n "$meter_file" ] || return 0
    _mclass="$1"; _mfamily="$2"; _mnudged="$3"; _mreason="$4"; _mdetail="$5"

    # Both directories in one call: the log's, and the one the per-session counter lives in. A TMPDIR
    # that does not exist is a real configuration in the wild, and it must cost neither a lost sequence
    # number nor a line of stderr.
    _mseqf="${TMPDIR:-/tmp}/ripwire-meter.${session}.seq"
    if [ ! -d "${meter_file%/*}" ] || [ ! -d "${_mseqf%/*}" ]
    then
        mkdir -p "${meter_file%/*}" "${_mseqf%/*}" 2>/dev/null || return 0
    fi

    _mts="$( date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null )" || _mts=""

    # per-session monotonic counter: one byte appended per row, the file's SIZE is the sequence number.
    # Append-of-one-byte is atomic, so two concurrent tool calls cannot land on the same number.
    # NOTE the brace form: in `cmd >>f 2>/dev/null` the shell opens `>>f` FIRST and reports its own
    # failure on the still-unredirected stderr, so the 2>/dev/null arrives too late to suppress it.
    # Wrapping the redirect in a group is what actually makes an unwritable path silent.
    { printf '.' >>"$_mseqf"; } 2>/dev/null || true
    _mseqraw="$( wc -c <"$_mseqf" 2>/dev/null )" || _mseqraw=0
    [ -n "$_mseqraw" ] || _mseqraw=0
    _mseq=$(( _mseqraw + 0 ))

    # `detail` is scrubbed and truncated INSIDE the row builder rather than by a printf|tr|cut pipeline:
    # jq already encodes control characters correctly and can slice, and three saved processes on a
    # path that runs before every Read is worth more than the symmetry.
    if command -v jq >/dev/null 2>&1
    then
        _mrow="$( jq -cn --arg ts "$_mts" --argjson seq "$_mseq" --arg session "$session" \
            --arg repo "$meter_repo" --arg tag "$meter_tag" --arg tool "$tool_name" \
            --arg class "$_mclass" --arg family "$_mfamily" --argjson nudged "$_mnudged" \
            --arg nudge "$_mreason" --argjson post_nudge "$meter_post" \
            --argjson post_sweep "$meter_postsweep" --arg arm "$meter_arm" \
            --arg detail "$_mdetail" \
            '{v:2,ts:$ts,seq:$seq,session:$session,repo:$repo,tag:$tag,tool:$tool,class:$class,family:$family,nudged:$nudged,nudge:$nudge,post_nudge:$post_nudge,post_sweep:$post_sweep,arm:$arm,detail:($detail|.[0:200])}' \
            2>/dev/null )" || _mrow=""
    else
        _mrow="{\"v\":2,\"ts\":\"$( meter_esc "$_mts" )\",\"seq\":$_mseq,\"session\":\"$( meter_esc "$session" )\",\"repo\":\"$( meter_esc "$meter_repo" )\",\"tag\":\"$( meter_esc "$meter_tag" )\",\"tool\":\"$( meter_esc "$tool_name" )\",\"class\":\"$_mclass\",\"family\":\"$_mfamily\",\"nudged\":$_mnudged,\"nudge\":\"$_mreason\",\"post_nudge\":$meter_post,\"post_sweep\":$meter_postsweep,\"arm\":\"$meter_arm\",\"detail\":\"$( meter_esc "$_mdetail" )\"}"
    fi
    [ -n "$_mrow" ] || return 0
    { printf '%s\n' "$_mrow" >>"$meter_file"; } 2>/dev/null || true
    return 0
}

# ---- meter_lead CMD — the command's leading word (basename) and its second word, space-separated,
#      after stripping the things that stand between a command line and the verb it actually runs:
#      leading VAR=val assignments, transparent wrappers, and RTK'S REWRITE. `rtk grep …` is what a
#      Bash hook sees on a machine where rtk's own PreToolUse hook rewrites dev commands; scoring
#      that as "not a grep" would make this meter's rate an artifact of another tool's hook. Word
#      splitting runs under `set -f` so an unquoted glob in the command cannot expand against the
#      filesystem; quoting is not honored, which is fine for a classifier that reads two words. ----
#      Sets globals rather than echoing: a command substitution is a fork, and this runs on the fast-
#      bail path that every Bash tool call passes through. A function's positional parameters are its
#      own in bash, so `set --` here cannot disturb the script's; `set -f` is global and is restored.
#
#      2026-08-11 (S2b), from the live log rather than from imagination: 784 of 890 `unclassified`
#      rows led with `cd`. An agent in a worktree-heavy repo writes `cd <dir> && grep …` constantly,
#      and every one of those was scored as "a line this tool could not read" when the answer was
#      sitting two words in. `cd`/`pushd` and their directory operand are therefore stripped like any
#      other transparent prefix, as are the separators (`&&`, `;`, `||`) that follow. `git`'s own
#      pre-subcommand options are skipped too, so `git -C /w diff` classifies as `git diff`.
#
#      2026-08-12 (S2c): the compound-statement keywords `do`/`then`/`else`/`elif`/`done`/`fi`/`esac`
#      join the strip list. They are prefixes with no operand, and a segment of the form
#      `do bash test/$g.sh` — every iteration body in this repo's `for g in …check; do …; done`
#      idiom — is otherwise a line whose leading word is a shell keyword and whose command is one
#      word further in. `for`/`while`/`if` themselves are NOT stripped: their operands are not a
#      command, so those segments are meant to decide nothing.
meter_w1=""
meter_w2=""
meter_arg1=""
meter_lead()
{
    set -f
    # shellcheck disable=SC2086
    set -- $1
    set +f
    while [ "$#" -gt 0 ]
    do
        case "$1" in
            '&&'|'||'|';'|'&'|'{'|'(')                     shift ;;
            do|then|else|elif|done|fi|esac)                shift ;;
            *=*)                                           shift ;;
            sudo|command|env|time|nice|nohup|exec|builtin)  shift ;;
            cd|pushd)                                      shift
                                                           # drop the directory operand, unless what
                                                           # follows is already a separator (`cd &&`)
                                                           case "${1:-}" in
                                                               ''|'&&'|'||'|';'|'&') ;;
                                                               *) shift ;;
                                                           esac ;;
            rtk)                                           shift
                                                           if [ "${1:-}" = "proxy" ]; then shift; fi ;;
            *)                                             break ;;
        esac
    done
    meter_w1="${1:-}"
    meter_w1="${meter_w1##*/}"
    [ "$#" -gt 0 ] && shift
    if [ "$meter_w1" = "git" ]
    then
        while [ "$#" -gt 0 ]
        do
            case "$1" in
                -C|-c)                                    shift; [ "$#" -gt 0 ] && shift ;;
                --git-dir=*|--work-tree=*|--no-pager|-P)  shift ;;
                *)                                        break ;;
            esac
        done
    fi
    meter_w2="${1:-}"
    # First non-flag operand after the command word — for a grep-family line that is the PATTERN, and
    # the sweep escalation quotes it back at the agent. Word splitting does not honor quotes, so
    # `rg "foo bar"` yields `"foo`; the sanitizer strips the stray quote and the disclosure in
    # docs/SUBSTITUTION_METER.md says so rather than pretending the parse is a shell.
    meter_arg1=""
    while [ "$#" -gt 0 ]
    do
        case "$1" in
            -*) ;;
            *)  meter_arg1="$1"; break ;;
        esac
        shift
    done
}

# ---- meter_classify_bash CMD — the class of a Bash command line, or empty for "not an observation
#      this meter makes". Leading word first, then git's subcommand, then a vocabulary scan whose only
#      verdict is `unclassified` — ambiguity is logged, never dropped. Rules: docs/SUBSTITUTION_METER.md
#
#      2026-08-11 (S2b): the non-retrieval classes (`build`, `gate-run`, `git-remote`, `git-misc`,
#      `shell-misc`) are new. They are NOT part of the substitution rate — their families are
#      `other`/`meta`/`git`, and §1 of the report divides ripwire by native only. They exist because
#      Track B §S4 ranks the absorption queue from the command mix an agent ACTUALLY runs, and a
#      command class that writes no row is a class that survey can never see. The cost of the change
#      is honest and stated: rows a previous version dropped now appear, so row counts across the
#      v1/v2 boundary are not comparable and the schema version says which side a row is on.
#
#      2026-08-12 (S2c — THE CLASSIFIER-GAP ROUND): three structural gaps, all read off the live log's
#      post-isolation-deploy window rather than imagined, plus one new class:
#
#        - THE FIRST WORD IS NOT THE COMMAND. `echo "=== x ==="; grep -n E1 PLAN.md`,
#          `mkdir -p $D; ls -R $D`, `for g in …check; do bash test/$g.sh; done` — the command the
#          agent actually ran sits in a LATER segment, and the classifier only ever looked at the
#          first. `meter_classify_walk` walks the sequenced segments; see the reasoning there for why
#          pipeline stages are deliberately excluded from that walk.
#        - A NEWLINE IS A SEPARATOR, NOT A SPACE. The un-escape substituted a space, which glued a
#          multi-line command into one segment: `cd /w⏎for g in …⏎do …⏎done` became a single
#          unsplittable line. It now substitutes `;`, which is what a newline actually is in shell.
#        - A PATH COMPONENT IS NOT A COMMAND WORD. The vocabulary scan fired on `ripwire` inside
#          `/opt/homebrew/share/ripwire/hooks/…`, so every command that merely NAMED a file under a
#          directory called `ripwire` was filed `unclassified`. A `/` immediately after the word is
#          the tell, and the scan now requires its absence.
#
#      The new class is `script-run` (family `other`, never in the rate): an interpreter handed an
#      INLINE program (`python3 -c …`, `python3 - <<EOF`, `node -e`, `bash -c`) or a non-gate script
#      path. It is a disclosure, not a claim: a lexical classifier cannot see what a script does, so
#      naming the opacity is more honest than filing it under `unclassified`, which by contract means
#      "this table is missing a rule" and is read as a bug report. Rows that used to reach
#      `unclassified` only because the script's TEXT happened to contain the word `cat` or `sed` were
#      never evidence of a missing rule.

# ---- meter_classify_git — `git`'s subcommand table. Its own function because git is the one
#      leading word whose SUBCOMMAND decides the class, and it spans three families: two of its
#      subcommands are retrieval (`grep`, and `diff`/`log`/`show --stat` as history reads), the rest
#      are state and plumbing. The state ones are counted but NEVER nudged — that rule predates the
#      meter and does not change; what changed is that the S4 survey now sees the real git mix
#      instead of only the three read-only verbs.
meter_classify_git()
{
    case "$_bsub" in
        grep) mclass="grep" ;;
        diff) mclass="git-diff" ;;
        log)  mclass="git-log" ;;
        push|fetch|pull|clone|remote|ls-remote|submodule)
              mclass="git-remote" ;;
        show)
            mclass="git-misc"
            case "$_bc" in
                *--stat*) mclass="git-show-stat" ;;
            esac ;;
        *)    mclass="git-misc" ;;          # add/commit/status/checkout/branch/worktree/merge/…
    esac
    return 0
}

# ---- meter_classify_other — the command-MIX classes, read from the same `_blead`/`_bsub` the
#      retrieval table above read. Kept apart from meter_classify_bash on purpose: these classes
#      answer a DIFFERENT question for a DIFFERENT consumer (what does the agent's command mix look
#      like, for the S4 absorption queue) and are excluded from the substitution rate by their
#      family. Sets `mclass`, or only `_bmisc` for the heads that must defer to the vocabulary scan.
meter_classify_other()
{
    case "$_blead" in
        gh)
            mclass="git-remote" ;;
        make|ninja|xcodebuild|gradle|mvn|bazel|clang|clang++|gcc|g++|c++|cc|swiftc|tsc|rustc|cmake)
            mclass="build" ;;
        pytest|ctest|tox|*check.sh|pargates.py|regression.sh|test/*|*/test/*)
            # `test/*` catches the loop body this repo writes constantly — `for g in …; do
            # r=$(bash test/$g.sh); done`, where the assignment strip leaves `test/$g.sh` as the
            # leading word and the unexpanded `$g` defeats the `*check.sh` pattern.
            mclass="gate-run" ;;
        cargo|go|npm|yarn|pnpm|dotnet)
            case "$_bsub" in
                test|t)  mclass="gate-run" ;;
                *)       mclass="build" ;;
            esac ;;
        python3|python|bash|sh|zsh|node|ruby|perl|osascript)
            # The repo's own gate discipline is `python3 test/pargates.py …` / `bash test/*check.sh` /
            # `test/regression.sh`, and that reading comes first. Everything else an interpreter is
            # handed is `script-run` — see the class's rationale in the meter_classify_bash header.
            # The `-` case is `python3 - <<'EOF'`, a heredoc program on stdin; `''` is an interpreter
            # with no operand at all, which is a REPL and not a script, so it decides nothing.
            case "$_bsub" in
                test/*|*/test/*|*check.sh|*pargates*|*regression.sh) mclass="gate-run" ;;
                '')                                                  ;;
                *)                                                   mclass="script-run" ;;
            esac
            # An INLINE program swallows the rest of the line: everything after `-c`, `-e` or a
            # heredoc marker is program TEXT, not further commands, so the segment walk must not
            # descend into it and read a Python statement as a shell command. A script PATH
            # (`python3 bench/x.py`, `bash -n f.sh`) is an ordinary command and stays walkable —
            # which is the whole reason `bash -n f.sh && ./build/ripwire …` still counts as a
            # ripwire call.
            case "$_bsub" in
                -c|-e|-|--command) _binline=1 ;;
            esac
            case "$_bc" in
                *'<<'*)            _binline=1 ;;
            esac ;;
        mkdir|rmdir|cp|mv|rm|touch|chmod|chown|echo|printf|pwd|which|date|sleep|wc|df|du|ps|pgrep|kill|export|true|false|jobs|wait|open|mktemp|basename|dirname|source|.)
            _bmisc=1 ;;
        stat|diff|cmp|tr|sort|uniq|cut|tee|seq|realpath|readlink|:)
            # 2026-08-12: the second half of the path-component fix. These heads used to reach a row
            # only because the vocabulary scan false-positived on a path like
            # `/opt/homebrew/share/ripwire/hooks/…`; with that FP closed they would have gone from a
            # (wrong) row to NO row, and a dropped observation is the worse of the two errors. They
            # are plumbing, they are named as plumbing, and the S4 survey keeps seeing them.
            _bmisc=1 ;;
        '')
            # Nothing survived the prefix strip: the whole line was `cd …`, an assignment, or a
            # wrapper with no command after it.
            mclass="shell-misc" ;;
    esac
    return 0
}

# ---- meter_classify_head SEGMENT — the leading-word tables applied to ONE command segment. Sets
#      `mclass` (empty = undecided) and may set `_bmisc`. Split out of meter_classify_bash so that the
#      segment walk below runs the SAME table the first segment ran, rather than a second copy of it
#      that would drift. `_bmisc` is deliberately NOT reset here — it belongs to the whole line, and
#      its owner is the caller.
meter_classify_head()
{
    _bc="$1"
    meter_lead "$_bc"
    _blead="$meter_w1"
    _bsub="$meter_w2"
    mclass=""
    case "$_blead" in
        ripwire)
            mclass="ripwire-cli"; return 0 ;;
        grep|egrep|fgrep|zgrep|rg|ag|ack|ack-grep|ugrep)
            mclass="grep"; return 0 ;;
        find|fd|fdfind)
            mclass="find"; return 0 ;;
        cat|head|tail|less|more|bat|nl|tac)
            # `cat > /tmp/msg.txt <<'EOF'` is a WRITE wearing the same word, and scoring it `read`
            # puts a file the agent AUTHORED into the native-retrieval denominator, which is the
            # direction that makes the substitution rate look worse than it is.
            # `shell-misc` rather than `_bmisc`, deliberately: deferring would hand the line to the
            # vocabulary scan, which would then see the very `cat` this arm just ruled a write and
            # answer `unclassified` — the classifier contradicting itself one step later.
            case "$_bsub" in
                '>'*) mclass="shell-misc"; return 0 ;;
                *)    mclass="read";       return 0 ;;
            esac ;;
        ls)
            # a tree walk, not a directory listing: -R (in any cluster) or --recursive
            if printf '%s' "$_bc" | grep -qE -- '(^|[[:space:]])-[A-Za-z]*R[A-Za-z]*([[:space:]]|$)|--recursive([[:space:]]|$)'
            then
                mclass="find"; return 0
            fi
            _bmisc=1 ;;
        awk|gawk|mawk)
            # only a PATTERN program is a search: awk '/needle/ …'. `awk '{print $1}' /tmp/x` is not,
            # which is why the test anchors on a quote immediately followed by the slash.
            if printf '%s' "$_bc" | grep -qE "['\"]/"
            then
                mclass="grep"; return 0
            fi ;;
        sed)
            # `sed -n '1,80p' f` is a whole-file read wearing a different hat; `sed -i …` is an edit.
            if printf '%s' "$_bc" | grep -qE -- '(^|[[:space:]])-[A-Za-z]*n([[:space:]]|$)'
            then
                mclass="read"; return 0
            fi ;;
        git)
            meter_classify_git; return 0 ;;
    esac
    # Not a retrieval verb. The command-MIX classes are a separate job with a separate consumer —
    # they never touch the substitution rate, they feed the S4 absorption survey — so they live in
    # their own function rather than lengthening the table above.
    meter_classify_other
    return 0
}

# ---- meter_classify_walk LINE — THE SEGMENT WALK. A compound command line was classified by its
#      first word alone, and in the live log's post-isolation-deploy window that was the single
#      largest source of `unclassified`: the first word is routinely plumbing (`echo "=== x ==="`,
#      `mkdir -p $D`, `ls -la $f`, a `for` header) and the command the agent actually ran is one
#      segment further along. This walks the SEQUENCED segments — `;`, `&&`, `||` — and stops at the
#      first one the leading-word table decides.
#
#      PIPELINE STAGES ARE DELIBERATELY NOT WALKED, and that exclusion is the load-bearing half of
#      the rule. `A | B` hands B the output of A, so B is a filter on that output and not an
#      independent retrieval; walking into it would score every `… | head -40` as a native `read`
#      and every `… | wc -l` as retrieval, inflating the rate's denominator with pagers and biasing
#      the substitution rate DOWN. `ls test | grep -i doc` therefore keeps the verdict
#      docs/SUBSTITUTION_METER.md already gives it — `unclassified`, the vocabulary scan's honest
#      "there is grep evidence here and I cannot say whose" — instead of being resolved here.
#
#      No fork: `&&`/`||` are folded onto `;` by parameter expansion and the segments are peeled the
#      same way. Word splitting still does not honour quotes, so a `;` inside a quoted string splits
#      too — harmless, because a walk only ever ACCEPTS a class the table decided and a fragment of
#      a string decides nothing.
meter_classify_walk()
{
    _wrest="${1//&&/;}"
    _wrest="${_wrest//||/;}"
    case "$_wrest" in
        *';'*) ;;
        *)     mclass=""; return 0 ;;       # nothing to walk
    esac
    # Which segment did the head path already judge? NOT necessarily the first: the prefix strip
    # eats whole leading segments (`cd /w &&`, `SP=… ;`), so the head's verdict is about the first
    # segment that carries a command word at all. The walk therefore skips segments until it has
    # passed that one, instead of skipping a fixed count — get this wrong and
    # `cd /w && bash -n f.sh && ./build/ripwire …` re-judges the `bash` segment and never reaches
    # the ripwire call, which is the exact undercount the v1→v2 correction was about.
    _wseen=0
    while [ -n "$_wrest" ]
    do
        _wseg="${_wrest%%;*}"
        case "$_wrest" in
            *';'*) _wrest="${_wrest#*;}" ;;
            *)     _wrest="" ;;
        esac
        meter_classify_head "$_wseg"
        if [ "$_wseen" = "0" ]
        then
            [ -n "$meter_w1" ] && _wseen=1
            continue
        fi
        # A segment that strips to NOTHING — `cd $D`, a bare `done`, an empty run of separators —
        # reaches meter_classify_other's empty-lead case and comes back `shell-misc`. Letting that
        # decide would halt the walk on the plumbing between two real commands, which is precisely
        # the shape (`mkdir -p $D ; cd $D ; grep -rn x .`) this walk exists to read.
        case "$mclass" in
            ''|shell-misc) ;;
            *)             return 0 ;;
        esac
        # A heredoc ends the walk: everything past `<<MARKER` is body text — a commit message, a
        # fixture file, a Python program — and reading the next line of it as a shell command is how
        # a classifier invents observations that never happened.
        case "$_wseg" in
            *'<<'*) mclass=""; return 0 ;;
        esac
    done
    mclass=""
    return 0
}

# ---- meter_classify_bash CMD — the whole resolution order, in one place. Head, then walk, then the
#      vocabulary scan, then `shell-misc`. The one judgement it makes beyond "first match wins" is
#      that a RETRIEVAL class found by the walk outranks a non-retrieval class found by the head:
#      `bash -n hooks/x.sh && ./build/ripwire . --quality-delta` is a ripwire call, and the v1→v2
#      correction already established that undercounting the tool's own invocations is this
#      instrument's most damaging failure mode. The cost is stated rather than hidden: such a line
#      contributes its retrieval row and not a `build`/`script-run` row, so the S4 command-mix survey
#      sees one fewer of those.
meter_classify_bash()
{
    _bmisc=0
    _binline=0
    meter_classify_head "$1"
    _bhead="$mclass"
    case "$_bhead" in
        ripwire-cli|grep|find|read|git-diff|git-log|git-show-stat)
            return 0 ;;                     # the first command IS the observation
    esac
    # An inline program's own text is not a sequence of shell commands — do not walk it.
    [ "$_binline" = "1" ] && [ -n "$_bhead" ] && return 0

    # `_bmisc` deliberately ACCUMULATES across the walk: a line whose every segment is plumbing
    # (`D=…; for f in …; do echo "$f"; done`) is plumbing, and labelling it `shell-misc` keeps it in
    # the S4 command-mix survey instead of dropping it. The family is `other`, so nothing that
    # happens here can reach the substitution rate.
    _bw1="$meter_w1"; _bw2="$meter_w2"; _ba1="$meter_arg1"
    meter_classify_walk "$1"
    _bwalk="$mclass"
    if [ -z "$_bwalk" ]
    then
        # A walk that decided nothing must leave no trace: the sweep escalation reads `meter_arg1`
        # for the pattern it quotes back at the agent, and that has to stay the head's operand.
        meter_w1="$_bw1"; meter_w2="$_bw2"; meter_arg1="$_ba1"
    fi
    case "$_bwalk" in
        ripwire-cli|grep|find|read|git-diff|git-log|git-show-stat)
            mclass="$_bwalk"; return 0 ;;
    esac
    if [ -n "$_bhead" ]
    then
        mclass="$_bhead"; return 0          # leftmost non-retrieval verdict wins
    fi
    if [ -n "$_bwalk" ]
    then
        mclass="$_bwalk"; return 0
    fi

    # Neither position named a command this table knows — but if the LINE names a retrieval verb
    # anywhere (a pipeline, a loop body, xargs, a subshell), the call IS an observation and must not
    # vanish from the denominator just because this classifier cannot say which kind it is.
    #
    # A `/` immediately after the word disqualifies it: `/opt/homebrew/share/ripwire/hooks/…` names
    # a DIRECTORY called ripwire, not an invocation of it, and before this guard every command that
    # merely mentioned a file under such a path was filed `unclassified`. A `/` BEFORE the word is
    # not disqualifying — `xargs /usr/bin/grep …` is a real invocation — so only the trailing side
    # is tightened, and the residue is the rare `xargs /usr/bin/grep` inside a path-shaped line.
    #
    # `head` `tail` `less` `more` `bat` `nl` `tac` are NOT in this list, and their absence is a rule
    # rather than an oversight. As a leading word the head table already reads them as `read`, and in
    # a later sequenced segment so does the walk; the only position this scan could still catch them
    # in is a PIPELINE STAGE — `ls docs/ | head -40`, `claude --help | head -80` — where they page
    # another command's output and retrieve nothing. Counting those was the same pager error the walk
    # avoids by not descending into pipelines, arriving by the other road. The residue is the rare
    # `$(head -1 f)` / `xargs tail`, which now writes no row instead of an `unclassified` one.
    if printf '%s' "$1" \
        | grep -qE '(^|[^A-Za-z0-9_.-])(ripwire|grep|egrep|fgrep|rg|ag|ack|ugrep|find|fd|cat|awk|sed)([^A-Za-z0-9_/-]|$)'
    then
        mclass="unclassified"; return 0
    fi
    # The shell-misc heads are the one family checked AFTER the vocabulary scan, deliberately: `ls
    # test | grep -i doc` is evidence about a grep, not about `ls`, and a leading-word rule that
    # returned first would destroy that evidence. A bare `ls -la docs/` has none to destroy.
    [ "$_bmisc" = "1" ] && mclass="shell-misc"
    return 0
}

# ---- meter_family CLASS — the coarse bucket the substitution rate is computed over. Only `ripwire`
#      and `native` enter the rate; `git`, `other` and `meta` are context for the S4 absorption
#      survey and are printed apart, never folded in. ----
meter_family()
{
    case "$1" in
        ripwire-cli|ripwire-mcp)        printf 'ripwire' ;;
        grep|find|read|glob)            printf 'native' ;;
        git-diff|git-log|git-show-stat) printf 'git' ;;
        git-remote|git-misc)            printf 'git' ;;
        session-start|gate-run)         printf 'meta' ;;
        build|script-run|shell-misc)    printf 'other' ;;
        *)                              printf 'other' ;;
    esac
}

# ---- SessionStart mode (`--session-start`): inject the use-when blurb ONCE at session start ----
# The PreToolUse nudges above are reactive — they only speak after the agent has already reached for a
# default. This is the proactive half: a binary on PATH is invisible until the context says when to
# reach for it, and not every user has pasted the blurb into CLAUDE.md. The text is EXTRACTED from
# `ripwire wrap claude` rather than restated here, so it cannot drift from wrapUseWhenBlurbLines() in
# src/wrap.h (the single source of truth the wrap gate diffs across agents). If wrap refuses — e.g. a
# CRITICAL skill-scan finding — the fence is absent, the blurb is empty, and this degrades to silence.
if [ "${1:-}" = "--session-start" ]
then
    input="$( cat )"

    dir=$( printf '%s' "$input" | tr '\n' ' ' | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
        | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' )
    [ -n "$dir" ] || dir="$PWD"

    session=$( printf '%s' "$input" | tr '\n' ' ' | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
        | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' )
    [ -n "$session" ] || session="ppid$PPID"

    # §METER: a session boundary is the denominator's denominator — without it "12 ripwire calls" has
    # no per-session scale. Logged BEFORE the ripwire/git gates below, so a session that never
    # qualified for a nudge still counts as a session. This hook is registered for startup|resume|
    # clear, so a long session can legitimately produce more than one of these rows.
    tool_name="SessionStart"
    meter_repo=$( git -C "$dir" rev-parse --show-toplevel 2>/dev/null )
    [ -n "$meter_repo" ] || meter_repo="$dir"
    meter_tag="${meter_repo##*/}"
    meter_init
    meter_log "session-start" "meta" 0 "none" "${dir}"

    # THE PRIMER IS A NUDGE, SO THE CONTROL ARM DOES NOT GET IT (2026-08-12, with the arm-ordering
    # fix in meter_init above; found by the E1 lane). This branch injects ~1.6 KB of use-when
    # guidance into the session's context — by a wide margin the largest single thing this hook ever
    # says — and it was doing so in BOTH arms. A control arm that is silent at every PreToolUse
    # moment and then hands the agent the whole manual at startup is not a control arm; it would
    # have made the first real A/B measure the primer and call it the nudge. The session-start ROW
    # is still written above, because the control arm is counted, only never spoken to.
    [ "$meter_arm" = "control" ] && exit 0

    command -v ripwire >/dev/null 2>&1 || exit 0
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

    marker="${TMPDIR:-/tmp}/ripwire-nudge.${session}.session-start"
    [ -e "$marker" ] && exit 0
    { : > "$marker"; } 2>/dev/null || true

    blurb=$( ripwire wrap claude 2>/dev/null \
        | sed -n '/^# --- paste into/,/^# --- end paste ---$/p' | sed '1d;$d' )
    [ -n "$blurb" ] || exit 0

    if command -v jq >/dev/null 2>&1
    then
        jq -n --arg m "$blurb" \
            '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
    else
        esc=$( printf '%s' "$blurb" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{printf "%s\\n", $0}' )
        printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
    fi
    exit 0
fi

input="$( cat )"

# ---- fast bail: only Grep, Glob, Read and Bash can ever match; every other tool (Edit/Write/...)
#      exits here after a single grep over stdin, before spawning anything. ----
tool_name=$( printf '%s' "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
    | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//' )

case "$tool_name" in
    Grep) category="grep"; mclass="grep" ;;
    Read) category="read"; mclass="read" ;;
    Glob) category="glob"; mclass="glob" ;;
    Bash) category="";     mclass="" ;;    # both decided below, once the command text is available
    # §METER: ripwire's own MCP verbs. Never nudged (nudging a ripwire call toward ripwire is noise) —
    # they are here purely so the NUMERATOR is not silently missing every agent that prefers the MCP
    # server to the CLI. This only works for a settings.json whose matcher was written by the current
    # installer; see the disclosure in docs/SUBSTITUTION_METER.md for what stays invisible.
    mcp__ripwire__*) category=""; mclass="ripwire-mcp" ;;
    *) exit 0 ;;
esac

# ---- field extractor: jq if present (robust, handles escaping) else a flat grep/sed fallback that
#      is adequate for this payload's simple, non-repeating string keys (tool_name, cwd, session_id,
#      pattern, command, path never recur across nesting levels here). Degraded fallback never crashes
#      — worst case it returns empty and a caller-side guard skips the nudge. ----
field()
{
    if command -v jq >/dev/null 2>&1
    then
        printf '%s' "$input" | jq -r --arg k "$1" '(.tool_input[$k] // .[$k]) // empty' 2>/dev/null
    else
        printf '%s' "$input" | tr '\n' ' ' | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 \
            | sed -E 's/^[^:]*:[[:space:]]*"//; s/"$//'
    fi
}

# ---- fields3 KEY — cwd, session_id and one tool_input KEY in a SINGLE jq spawn, as three globals.
#      jq costs ~10 ms of process startup and this hook used to pay it once per field; the meter needs
#      a third field, so fetching all three at once is what keeps the metered hook CHEAPER on the
#      Read path than the unmetered one was, rather than 50% dearer. @tsv is the reason this is safe
#      to split on a tab: jq escapes any tab, newline or backslash inside a value, so the three fields
#      are guaranteed to be one line with exactly two separators. Falls back to the flat extractor. ----
f3_cwd=""
f3_session=""
f3_detail=""
fields3()
{
    if ! command -v jq >/dev/null 2>&1
    then
        f3_cwd="$( field cwd )"
        f3_session="$( field session_id )"
        [ -n "${1:-}" ] && f3_detail="$( field "$1" )"
        return 0
    fi
    _f3="$( printf '%s' "$input" \
        | jq -r --arg k "${1:-}" '[(.cwd // ""), (.session_id // ""), (.tool_input[$k] // "" | tostring)] | @tsv' \
        2>/dev/null )"
    _oIFS="$IFS"
    IFS="$( printf '\t' )"
    # shellcheck disable=SC2086
    read -r f3_cwd f3_session f3_detail <<EOF2
$_f3
EOF2
    IFS="$_oIFS"
    return 0
}

if [ "$tool_name" = "Bash" ]
then
    # `command` doubles as this tool's detail field, so one fetch serves the nudge AND the meter row.
    fields3 command
    cmd="$f3_detail"
    [ -n "$cmd" ] || exit 0
    # ---- undo jq's @tsv escaping, for the READERS only. `fields3` fetches three fields in one jq
    #      spawn by joining them with tabs, which means jq escapes any newline or tab inside a value
    #      — so a MULTI-LINE Bash command (`cd <worktree>\ngit diff`, which is most of what an agent
    #      writes in a worktree-heavy repo) arrives here as one physical line with literal `\n`
    #      two-character sequences in it. Every reader below then failed on it in the same way:
    #      `\bgit[[:space:]]+diff\b` never matched across a `\n`, and the classifier's word split gave
    #      a leading token of `/a/b\ngit` whose basename is `b\ngit`, which matches no rule. That is
    #      how 742 of the live log's 916 `unclassified` rows were made. `detail` is deliberately NOT
    #      rewritten: the log keeps the exact single-line form it always stored.
    #
    #      2026-08-12 (S2c): the substitute is ` ; `, not a space. A newline IS a command separator
    #      in shell, and calling it whitespace glued a multi-line command into one unsplittable
    #      segment — `cd /w⏎for g in …⏎do bash test/$g.sh⏎done` presented as a single line whose
    #      leading word is `for` and whose real command the segment walk could not reach. Every
    #      reader below is whitespace-delimited AND separator-tolerant, so the stronger substitution
    #      costs them nothing; it costs no fork either.
    cmdx="${cmd//\\n/ ; }"
    cmdx="${cmdx//\\t/ }"
    # Only a RECURSIVE/tree-wide text search counts — a single-file grep or a filter on other output
    # (e.g. `ls | grep foo`) is not the "blind grep over the tree" case this hook targets. Checked
    # first since it is the highest-volume pattern.
    if printf '%s' "$cmdx" | grep -qE '\brg\b'
    then
        category="bash-grep"   # ripgrep invocations are inherently tree-wide
    elif printf '%s' "$cmdx" | grep -qE '\b(grep|egrep|fgrep)\b' \
        && printf '%s' "$cmdx" | grep -qE -- '(-[A-Za-z]*[rR][A-Za-z]*\b|--recursive\b)'
    then
        category="bash-grep"   # grep/egrep/fgrep with an explicit recursive flag
    # `git show <sha> --stat` / `git show --stat` — a commit's stat summary; checked before the plain
    # `git diff`/`git log` patterns since "show" is a distinct subcommand from either.
    elif printf '%s' "$cmdx" | grep -qE '\bgit[[:space:]]+show\b' \
        && printf '%s' "$cmdx" | grep -qE -- '--stat\b'
    then
        category="git-show-stat"
    # `git diff` (HEAD, --stat, path-limited, ...) — deliberately NOT `git status`/add/commit/push/
    # pull/checkout/branch (state-changing or trivially cheap; nudging those is spam).
    elif printf '%s' "$cmdx" | grep -qE '\bgit[[:space:]]+diff\b'
    then
        category="git-diff"
    # `git log` (-N, --oneline, path-limited, ...)
    elif printf '%s' "$cmdx" | grep -qE '\bgit[[:space:]]+log\b'
    then
        category="git-log"
    else
        category=""
    fi

    # §METER: classification is INDEPENDENT of the nudge decision above, and deliberately wider — the
    # nudge only speaks where it has good advice, the meter has to see the whole denominator (a
    # single-file grep, a `cat`, a `find`, an `ls -R` are all the native retrieval this tool competes
    # with). Where the classifier declines but the nudge chain matched, the nudge's own verdict is the
    # class: that covers forms like `cd sub && git diff` that lead with neither.
    meter_classify_bash "$cmdx"         # sets mclass, without a fork
    # `shell-misc` means only that the LEADING word was a no-op (`echo "=== git log ===" && git log
    # --oneline`), so the nudge chain's verdict is strictly better evidence and outranks it — the
    # same deferral the classifier already makes to the vocabulary scan, applied one level up.
    if [ -z "$mclass" ] || [ "$mclass" = "shell-misc" ]
    then
        case "$category" in
            bash-grep)     mclass="grep" ;;
            git-diff)      mclass="git-diff" ;;
            git-log)       mclass="git-log" ;;
            git-show-stat) mclass="git-show-stat" ;;
        esac
    fi
    # A ripwire invocation is never nudged toward ripwire. This also closes a live false positive that
    # predates the meter: `ripwire . --grep=…` matched the recursive-grep regex above (`--grep` clears
    # \bgrep\b, and `-grep` clears the [rR]-flag test), so the tool nudged itself.
    [ "$mclass" = "ripwire-cli" ] && category=""

    # Nothing this meter has a name for (`npx foo`, `python3 -c …` with no retrieval word in it):
    # out of scope for both jobs, and the fast bail stays fast — one grep more than before, no
    # subprocess beyond it. Since S2b a build/gate/git/shell command DOES get a row (family other/
    # meta/git, never in the rate) so the S4 absorption queue can be ranked from the real mix.
    [ -n "$mclass" ] || exit 0
fi

# ---- cwd, session_id, and this tool's own primary argument (the row's `detail`), in one fetch. The
#      Bash branch above already ran it; every other tool runs it here with its own detail key. ----
case "$tool_name" in
    Bash)      ;;                       # already fetched, with `command` as the detail key
    Read)      fields3 file_path ;;
    Grep|Glob) fields3 pattern ;;
    *)         fields3 ;;
esac
mdetail="$f3_detail"

dir="$f3_cwd"
[ -n "$dir" ] || dir="$PWD"

# ---- gates for the NUDGE: git repo + ripwire on PATH, both required, both cheap. One `rev-parse
#      --show-toplevel` does the git check AND yields the repo the row is tagged with.
#      The METER logs either way: an un-nudgeable call is still a call, and dropping those would bias
#      the denominator toward exactly the sessions the nudge can reach. ----
nudge_ok=1
meter_repo=$( git -C "$dir" rev-parse --show-toplevel 2>/dev/null )
if [ -z "$meter_repo" ]
then
    meter_repo="$dir"
    nudge_ok=0
fi
meter_tag="${meter_repo##*/}"
command -v ripwire >/dev/null 2>&1 || nudge_ok=0

session="$f3_session"
[ -n "$session" ] || session="ppid$PPID"
meter_init

# ---- did a nudge ALREADY fire earlier in this session? Read BEFORE this call's own marker is set, so
#      `post_nudge` means "this call happened in an already-nudged session", not "this call nudged". --
[ -e "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anynudge" ] && meter_post=1

# ---- the nudge decision, recorded as both a boolean and a REASON. Dedup is per session per category
#      (or per-PPID if the payload carries no session_id); a deduped call is silent but still counted.
#
# 2026-08-19: the control arm now runs through the SAME marker as treatment instead of a shortcut that
# always said "control" — that shortcut is why every control-arm row looked identical whether or not
# the trigger condition had already been satisfied earlier in the session, which threw away exactly
# the eligibility signal a control arm exists to carry. `nudge` now distinguishes the two control-arm
# cases the same way treatment's `fired`/`dedup` already do: "control" is this call's counterfactual
# — the marker was unset, so a treatment session WOULD have spoken here — and "suppressed-control" is
# the counterfactual dedup — the marker was already set, so treatment would have stayed silent too.
# `nudged` stays 0 in both control cases; only the arm decides whether text is ever built or emitted.
nudged=0
nudge="none"
if [ -z "$category" ]
then
    nudge="none"                                        # observed, but no nudge pattern applies
elif [ "$nudge_ok" != "1" ]
then
    nudge="gated"                                       # not a git repo, or no ripwire on PATH
else
    marker="${TMPDIR:-/tmp}/ripwire-nudge.${session}.${category}"
    if [ -e "$marker" ]
    then
        if [ "$meter_arm" = "control" ]
        then
            nudge="suppressed-control"                  # counterfactual dedup: treatment would be silent too
        else
            nudge="dedup"
        fi
    else
        { : > "$marker"; } 2>/dev/null || true
        { : > "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anynudge"; } 2>/dev/null || true
        if [ "$meter_arm" = "control" ]
        then
            nudge="control"                             # counterfactual fire: treatment would have spoken
        else
            nudged=1
            nudge="fired"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §SWEEP — the escalation. Counts calls PER CLASS in this session; at the Nth one, replaces the
# generic tip with the exact command built from what was observed. See the design block at the top.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
[ -e "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anysweep" ] && meter_postsweep=1

# 2026-08-19: the outer gate no longer excludes the control arm. Counting still has to happen there —
# same reasoning as the base-tier marker above — so that `sweep_count`/the `.esc` marker reach the
# same state a treatment session's would, and a control-arm row can say "control" (this call is the
# counterfactual escalation) instead of just "this session was in the control arm, who knows if
# anything would have fired here." Only the pattern capture (`.pat`, used solely to BUILD delivered
# text) is skipped for control — nothing ever reads it there, so writing it would be pure waste.
sweep_hit=0
sweep_count=0
sweep_q=""
if [ "$sweep_on" = "1" ] && [ "$nudge_ok" = "1" ]
then
    case "$mclass" in
        grep|read|glob|git-diff|git-log|git-show-stat)
            # One byte per observed call; the file's LENGTH is the count. Read back with `$(<f)`,
            # which bash serves without forking — the whole per-call cost of this feature is that
            # append and this read, and the measurement in docs/SUBSTITUTION_METER.md says so.
            _swf="${TMPDIR:-/tmp}/ripwire-nudge.${session}.sweep-${mclass}"
            if [ ! -d "${_swf%/*}" ]
            then
                mkdir -p "${_swf%/*}" 2>/dev/null || true
            fi
            { printf '.' >>"$_swf"; } 2>/dev/null || true
            _swdots=""
            { _swdots="$(<"$_swf")"; } 2>/dev/null || _swdots=""
            sweep_count="${#_swdots}"

            # The grep escalation is the one that can quote the agent's own query back at it, so the
            # patterns are remembered as they go past. Sanitized HERE, not at emit time: whatever
            # lands in this file is already safe to interpolate into a double-quoted --for=. Skipped
            # in the control arm: this capture only ever feeds delivered text, and control never
            # delivers text.
            if [ "$mclass" = "grep" ] && [ "$meter_arm" != "control" ]
            then
                _swpat="$mdetail"
                [ "$tool_name" = "Bash" ] && _swpat="$meter_arg1"
                _swpat="${_swpat//[!A-Za-z0-9_.:-]/ }"
                while [ "${_swpat}" != "${_swpat//  / }" ]
                do
                    _swpat="${_swpat//  / }"
                done
                _swpat="${_swpat# }"; _swpat="${_swpat% }"
                _swpat="${_swpat:0:60}"
                [ -n "$_swpat" ] && { printf '%s\n' "$_swpat" >>"${_swf}.pat"; } 2>/dev/null
            fi

            if [ "$sweep_count" -ge "$sweep_n" ] && [ ! -e "${_swf}.esc" ]
            then
                { : > "${_swf}.esc"; } 2>/dev/null || true
                { : > "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anysweep"; } 2>/dev/null || true
                { : > "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anynudge"; } 2>/dev/null || true
                # An escalation retires the weaker one-time tip for the same category: having said
                # the specific thing, saying the generic thing later would only teach the agent that
                # this hook repeats itself. Retiring it in the control arm too keeps the counterfactual
                # consistent with what a treatment session in this same state would do next.
                [ -n "$category" ] && { : > "${TMPDIR:-/tmp}/ripwire-nudge.${session}.${category}"; } 2>/dev/null
                sweep_hit=1
                if [ "$meter_arm" = "control" ]
                then
                    nudge="control"                     # counterfactual escalation: treatment would fire here
                else
                    nudged=1
                    nudge="sweep${sweep_n}"
                fi
            fi
            ;;
    esac
fi

meter_log "$mclass" "$( meter_family "$mclass" )" "$nudged" "$nudge" "$mdetail"

[ "$nudged" = "1" ] || exit 0

if [ "$sweep_hit" = "1" ]
then
    # The directory the pasted command should be run against: the repo root, except for a read sweep,
    # where the directory of the file just read is the tighter and more useful scope. Only an absolute
    # path is trusted — a relative one would produce a command that is wrong from anywhere else.
    sweep_dir="$meter_repo"
    if [ "$mclass" = "read" ]
    then
        case "$mdetail" in
            /*/*) sweep_dir="${mdetail%/*}" ;;
        esac
    fi

    if [ "$mclass" = "grep" ] && [ -e "${_swf}.pat" ]
    then
        # The last three patterns, oldest first, deduplicated, space-joined — the agent's own words,
        # which is the whole point: a query it can paste without inventing anything.
        _swq=""
        while IFS= read -r _swline
        do
            [ -n "$_swline" ] || continue
            case " $_swq " in
                *" $_swline "*) continue ;;
            esac
            _swq="${_swq:+$_swq }$_swline"
        done <<EOF3
$( tail -n 3 "${_swf}.pat" 2>/dev/null )
EOF3
        sweep_q="${_swq:0:100}"
    fi

    case "$mclass" in
        grep)
            _swfor="${sweep_q:-<the task, in words>}"
            msg="ripwire tip (SWEEP, ${sweep_count} search calls this session): a same-class sweep is trial-and-error retrieval — N round-trips and N outputs for one question. ONE call replaces it, paste-ready: \`ripwire ${sweep_dir} --for=\"${_swfor}\"\` — ranked over the WHOLE corpus (it matches doc-comments and bodies, not just the literal string) with signatures attached, so there is no read-the-file-for-context step after it. Want everything in one budgeted bundle instead — ranking + top bodies + callers + tests_to_run? \`ripwire ${sweep_dir} --pack-task=\"${_swfor}\"\`. Still after a literal string? \`ripwire ${sweep_dir} --grep='STR'\` returns each match with its enclosing function. (Escalated once per class per session; advisory only — your command runs either way.)"
            ;;
        read)
            msg="ripwire tip (SWEEP, ${sweep_count} whole-file reads this session): reading files one after another is the largest token sink in an agent loop, and less context measures MORE accurate, not just cheaper (code-repair accuracy fell 29%->3% as context grew 32K->256K, LongCodeBench). ONE call replaces the sweep, paste-ready: \`ripwire ${sweep_dir} --pack-task=\"<what you are trying to do>\"\` — ranking + top bodies + caller signatures + notes + tests_to_run in one bundle under one token budget. Already know the symbol? \`ripwire ${sweep_dir} --expand=SYM\` returns its body plus its callees' signatures instead of the file around it. (Escalated once per class per session; advisory only — your command runs either way.)"
            ;;
        glob)
            msg="ripwire tip (SWEEP, ${sweep_count} filename globs this session): a glob finds files by NAME, which is exactly why it takes several tries. ONE call replaces the sweep, paste-ready: \`ripwire ${sweep_dir} --for=\"<the task, in words>\"\` ranks files by what the code actually DOES (doc-comments and bodies, not paths) and hands back signatures instead of a path list you still have to open. Just want the lay of the land? \`ripwire ${sweep_dir}\` with no flags is the whole map. (Escalated once per class per session; advisory only — your command runs either way.)"
            ;;
        git-diff|git-log|git-show-stat)
            msg="ripwire tip (SWEEP, ${sweep_count} raw git-history calls this session): ONE call replaces the sweep, paste-ready: \`ripwire ${sweep_dir} --situ\` — the mid-task bundle: the blast radius of what you have changed, tests_to_run, the co-change partners you have forgotten, and a hotspot alert, in one pass. Reviewing someone else's branch instead? \`ripwire ${sweep_dir} --pr-context\`. Want what changed STRUCTURALLY rather than line counts? \`ripwire ${sweep_dir} --map-diff\`. (Escalated once per class per session; advisory only — your command runs either way.)"
            ;;
        *)
            msg="ripwire tip (SWEEP, ${sweep_count} calls this session): \`ripwire ${sweep_dir} --for=\"<the task, in words>\"\` answers the whole sweep in one ranked call. (Escalated once per class per session; advisory only — your command runs either way.)"
            ;;
    esac

    if command -v jq >/dev/null 2>&1
    then
        jq -n --arg m "$msg" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",additionalContext:$m}}'
    else
        esc=$( printf '%s' "$msg" | tr '\n' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' )
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"%s"}}\n' "$esc"
    fi
    exit 0
fi

# ---- build the one-time suggestion (one short message per category; the git-diff/git-log/
#      git-show-stat messages each name a SINGLE best verb for the observed form, not a catalog) ----
case "$category" in
    grep)
        pattern=$( field pattern )
        [ -n "$pattern" ] || pattern="PATTERN"
        pattern=$( printf '%s' "$pattern" | cut -c1-60 )
        msg="ripwire tip: for text search across this repo, \`ripwire . --grep='${pattern}'\` returns each match WITH its enclosing function/class — often replacing the read-the-file-for-context step. Conceptual/multi-word task instead of a literal string? \`ripwire . --for=\"...\"\`. Symbol usage/call sites? \`ripwire . --callers=SYM\` / \`--uses=SYM\`. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    git-diff)
        msg="ripwire tip: for a diff, \`ripwire . --situ\` maps the mid-task blast radius, tests-to-run, and forgotten co-change partners in one pass (swap in \`--pr-context\` when reviewing a PR). (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    git-log)
        msg="ripwire tip: for git log, \`ripwire . --rank-by=churn\` ranks who's actually churning that code (swap in \`--map-diff\` for what changed structurally). (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    git-show-stat)
        msg="ripwire tip: for a commit's --stat summary, \`ripwire . --map-diff\` shows what changed structurally, not just line counts. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    read)
        msg="ripwire tip: reading whole files is the biggest token sink in an agent loop, and less context measures MORE accurate, not just cheaper (code-repair accuracy fell 29%->3% as context grew 32K->256K, LongCodeBench). To understand ONE symbol, \`ripwire . --expand=SYM\` returns its body plus its callees' signatures instead of the file around it. Don't yet know which file to open? \`ripwire . --for=\"<task in words>\"\` ranks them, or \`ripwire . --pack-task=\"<task>\"\` returns ranking + bodies + callers + tests in ONE budgeted call. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    glob)
        msg="ripwire tip: a filename glob finds files by NAME; \`ripwire . --for=\"<task in words>\"\` ranks them by what the code actually does (matching doc-comments and bodies, not just paths) and hands back signatures rather than a path list you still have to open. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
    *)
        msg="ripwire tip: this looks like a recursive grep/rg over the tree. \`ripwire . --grep='PATTERN'\` (literal) or \`ripwire . --for=\"task in words\"\` (conceptual) often answers the same question with the enclosing symbol attached, in far fewer tokens than raw grep + file reads. (One-time tip this session; \`ripwire --help\` lists everything.)"
        ;;
esac

if command -v jq >/dev/null 2>&1
then
    jq -n --arg m "$msg" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",additionalContext:$m}}'
else
    esc=$( printf '%s' "$msg" | tr '\n' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' )
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"%s"}}\n' "$esc"
fi

exit 0
