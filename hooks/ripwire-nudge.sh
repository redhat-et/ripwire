#!/usr/bin/env bash
# hooks/ripwire-nudge.sh — OPT-IN Claude Code PreToolUse + SessionStart hook.
#
# READ §RETIRED FIRST. As of 2026-09-02 the PreToolUse path SAYS NOTHING: a randomized A/B measured
# both nudge tiers inert and the registered consequence was applied. What survives on that path is the
# SUBSTITUTION METER (§METER) plus the eligibility bookkeeping that tells a later readout which calls
# the retired advice would have landed on. The SessionStart primer still speaks, and is still the one
# thing the control arm does not get. The design record below describes a mechanism that is GONE; it
# is kept because a measured negative whose reasoning is deleted gets rebuilt by the next person.
#
# The original two-jobs description follows. Historically: two jobs in one script, the ADVISORY-ONLY
# nudge (below) and the SUBSTITUTION METER (see the §METER block further down).
#
# Nudged an agent from raw grep/rg, from whole-file Read / candidate-Glob, and from raw `git diff`/
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
# 2026-08-29 (P4.2): the grep/rg base nudge no longer fires on a short single-literal pattern (the
# case our own docs concede to `rg`) — only on a multi-pattern/OR-chain search, where the bundle
# genuinely wins. See §CEDE, near where `category` is demoted, for the full rationale; the sweep
# escalation below is untouched and still escalates on a same-class run of literal greps.
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
# §RETIRED — BOTH NUDGE TIERS NO LONGER SPEAK (2026-09-02). THE INSTRUMENT STAYS.
#
# WHAT THE A/B FOUND. The `arm=auto` split described above went live 2026-08-19 and finally produced
# the randomized population the two blocks above were waiting for. Window 2 (`ts >= 2026-08-19T12`,
# `ts < 2026-09-02T00`, `session != smoketest`) is a roughly balanced treatment/control sample across
# hundreds of sessions, and NO CUT SEPARATES THE ARMS: not the pooled substitution share inside a
# single repository, not the per-session median with sessions as the unit (a 95% bootstrap CI on the
# treatment/control median ratio that spans 1.0 with room to spare), and not the before/after around
# the moment a nudge fires — where the treatment arm's dip is reproduced, larger, by the control arm's
# own counterfactual, which makes it regression to the mean after a sweep and not an effect of
# anything this file said. The full readout, its argv and its confounds are registered in
# `docs/EVALS.md` §4; the numbers themselves are operator telemetry and live in the operator ledger.
#
# THE CONSEQUENCE, APPLIED RATHER THAN WRITTEN DOWN. Both tiers stop emitting text:
#   - the BASE tier (the §CEDE-gated one-time tips) — its own §SWEEP header already recorded, from the
#     2026-08-11 first-12-hours readout, that it converts at ~0%; the A/B is the randomized
#     confirmation of a finding this file has carried in a comment for three weeks;
#   - the SWEEP escalation (§SWEEP) — resolved against ITS OWN pre-registered band. The registration
#     in `docs/EVALS.md` §4 asks for `post_sweep=1` substitution >= 3xB to KEEP and < ~1.4xB to
#     DISABLE, over >=200 rate-eligible calls in >=10 sessions. The minimum data is met several times
#     over and the reading is BELOW 1xB — escalated sessions substitute slightly LESS after the
#     escalation than before it, and less than the control arm's counterfactual over the same window.
#     That is a DISABLE by the rule as written, and the rule was written before the data existed.
#
# WHAT "RETIRED" MEANS HERE, PRECISELY. The advice is gone; every other thing this file does is
# untouched. The eligibility bookkeeping still runs, in both arms, on exactly the counters and the
# cooldown policy it ran on before (§DEDUP), so the log still records WHICH CALL WOULD HAVE BEEN
# SPOKEN TO — that is what keeps "how often was the moment even reached" answerable for the next
# instrument, and it is the covariate the Claude Code prompt router's readout will want. What changed
# in the row is only the vocabulary of `nudge`: `retired` where a delivery would have happened,
# `retired-sweep` where an escalation would have, `dedup` where the cooldown would have silenced it.
# `fired`/`sweep<N>`/`control`/`suppressed-control` are no longer written — historical rows keep them,
# and `docs/SUBSTITUTION_METER.md` records the boundary as a schema note.
#
# `nudged` is now always 0, and `post_nudge`/`post_sweep` become pure counterfactual markers ("an
# eligible base-tier / sweep-tier moment already occurred in this session"), identical in both arms.
# They are kept, not deleted: a schema that drops a field cannot be compared across its own boundary.
#
# THE ARM STILL MEANS SOMETHING. It now separates exactly one behaviour: the SessionStart primer,
# which the control arm does not receive. That is the lever the 2026-08-10 finding actually credited
# — CONCENTRATION (skill and CLAUDE.md text), never the PreToolUse hook — so the live A/B from here
# is primer-vs-no-primer, and this file's PreToolUse path is now identical in both arms.
#
# RIPWIRE_SWEEP / `sweep=` in meter.conf still resolve, and still gate the sweep tier's COUNTERS. They
# no longer gate any delivery, because there is none left to gate.
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
dedup_cooldown=20
dedup_cap=3
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

# ---- meter_set_repo DIR — resolve `meter_repo` (where the call happened) and `meter_tag` (which
#      REPOSITORY to group it under) in ONE git invocation, and set `meter_isrepo`.
#
#      WHY THE TAG IS NOT THE REPO DIRECTORY'S BASENAME ANY MORE (2026-09-02). It was, and every linked
#      worktree of one repository therefore reported as its own repo: a dozen `.claude/worktrees/<name>`
#      checkouts of ripwire appeared in the report as a dozen different "repos", each with its own tiny
#      sample. The per-repo cut is precisely the one that controls for repository composition — the
#      confound that makes the pooled A/B ratio uninterpretable — so a per-repo cut that shatters one
#      repository into twelve is the cut most damaged by getting this wrong.
#
#      `--git-common-dir` is the fix because it is exactly the thing a linked worktree SHARES with its
#      main worktree: `/path/to/repo/.git` for both, while `--show-toplevel` differs. Strip the
#      trailing `/.git` and the basename is the repository. `repo` is left alone and still names the
#      worktree the call actually happened in — folding the TAG must not falsify the PATH.
#
#      One fork, not two: `--path-format=absolute` makes `--show-toplevel` and `--git-common-dir`
#      answerable together (a bare `--git-common-dir` prints a RELATIVE `.git` when git's cwd is the
#      toplevel). That option needs git >= 2.31, and an older git rejects the whole invocation rather
#      than part of it, so the fallback re-asks for the toplevel alone — otherwise an old git would
#      turn every call into "not a repo" and silently stop the tag AND the nudge gate together. The
#      fallback costs a second fork only where the first form failed: outside a repo, or on an old git.
meter_isrepo=0
meter_set_repo()
{
    meter_repo=""
    meter_tag=""
    meter_isrepo=0
    _msr="$( git -C "$1" rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>/dev/null )"
    _mcommon=""
    case "$_msr" in
        *"$_mnl"*) meter_repo="${_msr%%"$_mnl"*}"
                   _mcommon="${_msr#*"$_mnl"}"
                   _mcommon="${_mcommon%%"$_mnl"*}" ;;
        *)         meter_repo="$_msr" ;;
    esac
    if [ -z "$meter_repo" ]
    then
        meter_repo="$( git -C "$1" rev-parse --show-toplevel 2>/dev/null )"
        _mcommon=""
    fi
    [ -n "$meter_repo" ] && meter_isrepo=1
    [ -n "$meter_repo" ] || meter_repo="$1"

    # `/path/repo/.git` -> `/path/repo`. A relative or empty answer, and a bare repository's
    # `/path/foo.git` (which does not end in `/.git`), fall through to the worktree path — honest
    # rather than clever, and the fallback is exactly the pre-2026-09-02 behaviour.
    _mt="${_mcommon%/}"
    case "$_mt" in
        /*/.git) _mt="${_mt%/.git}" ;;
        *)       _mt="" ;;
    esac
    [ -n "$_mt" ] || _mt="$meter_repo"
    meter_tag="${_mt##*/}"
    return 0
}

# A literal newline, once, as a variable: a `case` pattern cannot carry one inline, and the $'\n'
# spelling inside a pattern is not portable across the shells this hook is asked to run under.
_mnl="
"

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
    _conf_cooldown=""
    _conf_cap=""
    if [ -n "$_mhome" ] && [ -f "$_mhome/meter.conf" ]
    then
        while IFS='=' read -r _ck _cv
        do
            case "$_ck" in
                enabled)        _conf_enabled="$_cv" ;;
                arm)            _conf_arm="$_cv" ;;
                sweep)          _conf_sweep="$_cv" ;;
                sweep_n)        _conf_sweepn="$_cv" ;;
                dedup_cooldown) _conf_cooldown="$_cv" ;;
                dedup_cap)      _conf_cap="$_cv" ;;
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
    # DEDUP/COOLDOWN POLICY (2026-08-19 retune — see the §DEDUP block below for the full rationale and
    # the policy it replaces). Same "not a plain positive integer reads as the default" guard as
    # sweep_n, for the same reason: a malformed override must degrade to the shipped policy, never to
    # 0 (which would mean "re-arm instantly", i.e. no cooldown at all) or to disabling delivery.
    case "${RIPWIRE_DEDUP_COOLDOWN:-$_conf_cooldown}" in
        ''|*[!0-9]*) dedup_cooldown=20 ;;
        0)           dedup_cooldown=20 ;;
        *)           dedup_cooldown="${RIPWIRE_DEDUP_COOLDOWN:-$_conf_cooldown}" ;;
    esac
    case "${RIPWIRE_DEDUP_CAP:-$_conf_cap}" in
        ''|*[!0-9]*) dedup_cap=3 ;;
        0)           dedup_cap=3 ;;
        *)           dedup_cap="${RIPWIRE_DEDUP_CAP:-$_conf_cap}" ;;
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
        mkdir|rmdir|cp|mv|rm|touch|chmod|chown|echo|printf|pwd|which|date|sleep|wc|df|du|kill|export|true|false|jobs|wait|open|mktemp|basename|dirname|source|.)
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
            # A COUNT-ONLY or QUIET grep is a POLL, not a search (2026-09-02, from mining the log for
            # the A/B readout: ~14% of that window's grep-class rows were these). `grep -c Building
            # <buildlog>` asks how far a build has got; `grep -q PARGATES_EXIT <taskfile>` asks whether
            # a gate run has finished. Neither retrieves any content, so neither is a call a ranked map
            # could ever have answered instead — counting them as native retrieval put calls in the
            # denominator that this tool is not competing for, and they were not evenly distributed
            # across the A/B's arms, which made the artifact directional rather than merely noisy.
            #
            # The test is deliberately syntactic and lowercase-only: `-c`/`-q` in any cluster, or the
            # long forms. `-C` is grep's CONTEXT flag and must not match, which is why the character
            # class is not case-insensitive. A legitimate "count occurrences in source" `grep -c` is
            # swept up too; that is accepted, because a count is not a thing this tool returns either.
            if printf '%s' "$_bc" | grep -qE -- '(^|[[:space:]])(-[A-Za-z]*[cq][A-Za-z]*|--count|--quiet)([[:space:]]|$)'
            then
                mclass="build-poll"; return 0
            fi
            mclass="grep"; return 0 ;;
        ps|pgrep)
            # A PROCESS POLL: a liveness check on a background job (the wait-loop idiom), where the
            # grep in the pipeline filters a PROCESS TABLE rather than searching a codebase. Decided at
            # the HEAD, before the vocabulary scan, which is what stops that piped grep being read as
            # the observation. These two words used to reach meter_classify_other's plumbing list; they
            # no longer get that far, and the entry there was removed rather than left as dead pattern.
            mclass="process-poll"; return 0 ;;
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
        process-poll)
            # A poll's line often continues into a real command after the loop it guards, so the walk
            # still runs and a RETRIEVAL class it finds outranks the poll — the same rule the
            # build/script-run heads already follow. What the poll head buys is that the pipeline grep
            # beside the process listing never becomes the observation.
            ;;
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
        build-poll|process-poll)        printf 'meta' ;;
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
    meter_set_repo "$dir"
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

# ---- grep_worth_nudging PATTERN [CMDLINE] — true (0) when PATTERN shows the one signal the base
#      grep/rg nudge is gated on below (§CEDE): an OR-chain / multi-pattern alternation. A literal `|`
#      in PATTERN is the primary signal; when CMDLINE is also given (the Bash form only — the Grep
#      tool's `pattern` field has no separate flag syntax to scan), two or more standalone `-e` pattern
#      flags (`grep -e foo -e bar`) count too, since PATTERN alone is only ever the FIRST operand
#      (see meter_lead) and cannot see a second `-e`. Anything else — including a single non-trivial
#      regex with no alternation — returns false: that is exactly the comparison our own docs concede
#      to `rg` (see the §CEDE block at its call site), so this stays silent rather than nag about it.
grep_worth_nudging()
{
    case "$1" in
        *'|'*) return 0 ;;
    esac
    if [ -n "${2:-}" ]
    then
        _gwn_ec="$( printf '%s' "$2" | grep -oE '(^|[[:space:]])-e([[:space:]]|$)' 2>/dev/null | wc -l | tr -d ' ' )"
        case "${_gwn_ec:-0}" in
            0|1) ;;
            *)   return 0 ;;
        esac
    fi
    return 1
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

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §CEDE — DO NOT NAG ABOUT A COMPARISON THE TOOL LOSES (P4.2, 2026-08-29)
#
# THE PROBLEM, STATED PLAINLY. Agents correctly drop to `rg`/`grep` for a known-literal hunt — our own
# docs concede the case (the ripwire-efficient/ripwire-orient/ripwire-navigate skills: "for a broad
# common-word question, plain `rg` + one read can still win"), and until the `--grep` fast path lands
# (P4 fix 1, a separate change — not this file) a plain `rg "exact string"` genuinely beats `ripwire
# --grep` on wall clock. The BASE (one-time) nudge fired on the FIRST eligible grep of a session
# regardless of what the pattern looked like, so it nagged about exactly the comparison it was
# conceding — advertising a verb that loses, which trains an agent to discount every OTHER nudge in
# this file along with it.
#
# THE FIX IS A GATE ON THE EXISTING TIER, NOT A NEW MECHANISM. §SWEEP's own header (above) already
# measured, in the 2026-08-11 first-12-hours readout, that this base one-time tip converts at ~0% and
# that the dominant behaviour is the SAME-CLASS SWEEP. So this narrows WHEN THE BASE TIER FIRES rather
# than bolting a second tracking system next to it: `grep_worth_nudging` (above) demotes `category`
# back to "" — the identical "observed, no nudge pattern applies" verdict a single-file, non-recursive
# grep already gets — when the pattern shows no evidence of a multi-pattern/OR-chain search, i.e. the
# one case where the ranked bundle genuinely beats a single `rg` call. Everything downstream of
# `category` (the §DEDUP bookkeeping, the message text) is untouched by this block.
#
# §SWEEP IS DELIBERATELY LEFT ALONE. `mclass` (what the sweep counters key on) is never touched here:
# three single-literal greps in a row is still real trial-and-error retrieval regardless of any ONE
# pattern's shape, the escalation already measures its own conversion independently, and its own
# RIPWIRE_SWEEP=0 is its own kill switch. A grep-then-read CHAIN needs no new code either: the
# (unmodified) read-category base nudge fires on its own first sighting the moment the agent opens the
# file the grep pointed at — this gate only ever silences the GREP half of that sequence, never the
# read half.
#
# THE SIGNAL IS DELIBERATELY NARROW AND SYNTACTIC, PER THE PLAN'S OWN INSTRUCTION NOT TO BUILD A
# SEMANTIC DETECTOR: a literal `|` in the pattern, or two-or-more standalone `-e` pattern flags on the
# Bash command line. Anything else — including a single non-trivial regex with no alternation — still
# cedes to `rg` silently. A `-e`/`|` inside an unrelated argument can misfire in either direction; that
# risk is accepted because the failure mode is silence (a nudge that could have helped does not fire),
# never a wrong or noisy one.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §RETIRED (2026-09-02): this gate now decides ELIGIBILITY ONLY — `category` no longer selects any
# text, it selects whether the row records a base-tier moment at all. The rule is kept rather than
# dropped because the retired tier's eligibility is the thing the next instrument compares against,
# and a gate quietly widened after the advice was removed would change what "eligible" counted.
if [ "$category" = "grep" ] || [ "$category" = "bash-grep" ]
then
    if [ "$tool_name" = "Bash" ]
    then
        grep_worth_nudging "$meter_arg1" "$cmdx" || category=""
    else
        grep_worth_nudging "$mdetail" || category=""
    fi
fi

dir="$f3_cwd"
[ -n "$dir" ] || dir="$PWD"

# ---- gates for the NUDGE: git repo + ripwire on PATH, both required, both cheap. One `rev-parse
#      --show-toplevel` does the git check AND yields the repo the row is tagged with.
#      The METER logs either way: an un-nudgeable call is still a call, and dropping those would bias
#      the denominator toward exactly the sessions the nudge can reach. ----
nudge_ok=1
meter_set_repo "$dir"
[ "$meter_isrepo" = "1" ] || nudge_ok=0
command -v ripwire >/dev/null 2>&1 || nudge_ok=0

session="$f3_session"
[ -n "$session" ] || session="ppid$PPID"
meter_init

# ---- did a nudge ALREADY fire earlier in this session? Read BEFORE this call's own marker is set, so
#      `post_nudge` means "this call happened in an already-nudged session", not "this call nudged". --
[ -e "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anynudge" ] && meter_post=1

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §DEDUP — RE-ARMING COOLDOWN, NOT FIRE-ONCE-EVER (2026-08-19 retune)
#
# OLD POLICY (2026-08-11 through 2026-08-19): a plain marker file. First eligible call of a category
# this session fires; the marker's mere EXISTENCE silences every later call of that category for the
# rest of the session, no matter how long the session runs or how many more times the trigger
# condition recurs. Combined with §SWEEP's own one-shot `.esc` marker (one escalation, ever, per
# class, which also retired the base marker on firing), the net effect measured in the field
# (readout 2026-08-19, 4,209-row snapshot): the trigger condition was met 1,546 times but delivered
# only 17 times (1.1%) — a nudge or two near session start, then silence for the rest of a session that
# can run thousands of rows. `grep`-class native calls, the largest and cleanest substitution target
# (931 occurrences, dominant pattern a single literal `grep -n SYM file`), went unaddressed 95.9% of
# the time — not because the trigger stopped firing, but because the delivery mechanism could not.
#
# NEW POLICY: RE-ARM AFTER A COOLDOWN, CAPPED. Each category tracks three counts — eligible
# OBSERVATIONS so far this session (`.obs`, every matching call, delivered or not), DELIVERIES so far
# (`.deliv`), and the observation count AT the last delivery (`.last`). A call delivers when either (a)
# no delivery has happened yet this session for this category — same "fires on first sight" as the old
# policy — or (b) at least `dedup_cooldown` MORE eligible observations of this category have occurred
# since the last delivery AND fewer than `dedup_cap` deliveries have happened so far. Defaults:
# cooldown 20 (a session has to show the SAME native habit 20 more times before hearing about it again
# — enough to skip incidental one-offs, short enough to reach mid-session on a 900+ row grep habit),
# cap 3 (this hook does not want to become the thing it is telling the agent to stop doing — a nudge
# that fires every 20 calls forever is its own kind of noise). Both are overridable
# (RIPWIRE_DEDUP_COOLDOWN / RIPWIRE_DEDUP_CAP, or `dedup_cooldown` / `dedup_cap` in meter.conf) with
# the same "not a plain positive integer reads as the shipped default" guard sweep_n already uses.
#
# THIS TIER'S CAP AND §SWEEP'S CAP ARE COUNTED SEPARATELY, ON PURPOSE. A class with both a base tip
# and an escalated sweep tip (grep/read/glob/git-*) can therefore receive up to `dedup_cap` GENERIC
# tips plus `dedup_cap` ESCALATED tips across a session — with the shipped default, up to 6 total, not
# unbounded and not exactly-one-shared-3. A single counter shared across both tiers was tried and
# rejected: the base tier's own cooldown clock (`_dobs`, gated to only nudge-eligible occurrences) and
# §SWEEP's (`sweep_count`, every occurrence of the class) advance at different rates, and whichever
# tier reached its threshold FIRST would silently consume the other's only delivery slot — turning
# "escalate at exactly the Nth occurrence" into "escalate at the Nth occurrence, unless the generic
# tip got there first, in which case wait for a whole cooldown period instead." Two independent,
# small, bounded caps are simpler to reason about and to test than one shared counter with an
# order-dependent race.
#
# THE OBSERVATION WINDOW RESTARTS WITH THIS COMMIT. Every row logged before this change used the old
# fire-once policy; every row after uses this one. `nudge":"dedup"` in an old row and `nudge":"dedup"`
# in a new one are NOT the same measurement — the new one only means "within cooldown of the last
# delivery," not "will never fire again this session." Any before/after comparison across this commit
# must treat it as a regime change, not noise.
#
# CONTROL-ARM ELIGIBILITY RIDES THE SAME MECHANISM (unchanged from the 2026-08-19 arm-assignment fix):
# a control-arm call runs through the identical `.obs`/`.deliv`/`.last` bookkeeping, so `nudge` records
# "control" (this call is a counterfactual delivery) or "suppressed-control" (a treatment session would
# be within cooldown here too) under the SAME re-arming policy treatment now gets — the two commits
# compose without control-arm rows silently reverting to the old one-shot semantics.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
nudged=0
nudge="none"
if [ -z "$category" ]
then
    nudge="none"                                        # observed, but no nudge pattern applies
elif [ "$nudge_ok" != "1" ]
then
    nudge="gated"                                       # not a git repo, or no ripwire on PATH
else
    # Keyed by `mclass`, not `category`: they agree everywhere except a Bash recursive grep, where
    # `category` is the finer "bash-grep" (so the base TIP text can say something Bash-specific) but
    # `mclass` already resolves to the same "grep" the §SWEEP block below tracks against. Using
    # `mclass` here means a recursive Bash grep and a Grep-tool call share ONE cooldown clock instead
    # of two, which is the one piece of state this tier intentionally does share with the tool-name
    # split — it does NOT share its `.deliv` cap file with §SWEEP's, see that block's comment for why.
    _dobs="${TMPDIR:-/tmp}/ripwire-nudge.${session}.${mclass}.obs"
    _ddeliv="${TMPDIR:-/tmp}/ripwire-nudge.${session}.${mclass}.deliv"
    _dlast="${TMPDIR:-/tmp}/ripwire-nudge.${session}.${mclass}.base-last"

    { printf '.' >>"$_dobs"; } 2>/dev/null || true
    _dobsdots=""
    { _dobsdots="$(<"$_dobs")"; } 2>/dev/null || _dobsdots=""
    _dobsn="${#_dobsdots}"

    _ddots=""
    [ -e "$_ddeliv" ] && { _ddots="$(<"$_ddeliv")"; } 2>/dev/null
    _ddelivn="${#_ddots}"

    _dlastn=0
    [ -e "$_dlast" ] && { _dlastn="$(<"$_dlast")"; } 2>/dev/null
    case "$_dlastn" in ''|*[!0-9]*) _dlastn=0 ;; esac

    _darm=0
    if [ "$_ddelivn" -eq 0 ]
    then
        _darm=1                                          # first sighting this session: always fires
    elif [ "$_ddelivn" -lt "$dedup_cap" ] && [ $(( _dobsn - _dlastn )) -ge "$dedup_cooldown" ]
    then
        _darm=1                                          # re-armed: cooldown elapsed, cap not yet spent
    fi

    # §RETIRED (2026-09-02): the arming decision is computed and RECORDED exactly as before, and then
    # nothing is said. Both arms take the same branch — the base tier's control/treatment distinction
    # was a counterfactual for text that no longer exists in either arm — so the two reasons below are
    # arm-independent and mean "this call was the delivery moment" / "the cooldown covered this call".
    if [ "$_darm" = "1" ]
    then
        { printf '.' >>"$_ddeliv"; } 2>/dev/null || true
        { printf '%s' "$_dobsn" >"$_dlast"; } 2>/dev/null || true
        { : > "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anynudge"; } 2>/dev/null || true
        nudge="retired"
    else
        nudge="dedup"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# §SWEEP — the escalation. Counts calls PER CLASS in this session; at the Nth one, replaces the
# generic tip with the exact command built from what was observed. See the design block at the top.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
[ -e "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anysweep" ] && meter_postsweep=1

# 2026-08-19: the outer gate no longer excludes the control arm. Counting still has to happen there —
# same reasoning as the base-tier marker above — so that `sweep_count` and the delivery markers reach
# the same state a treatment session's would, and the row can say which call was the escalation moment
# instead of just "this session was in the control arm, who knows if anything would have fired here."
#
# §RETIRED (2026-09-02): the PATTERN CAPTURE is gone with the text it fed. It existed only to quote the
# agent's own last three search patterns back at it inside a runnable `--for="…"`; with no message to
# build, keeping it would mean writing sanitized copies of the operator's queries into $TMPDIR for a
# reader that no longer exists. Counting is what remains.
sweep_count=0
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

            # 2026-08-19 retune: the escalation used to be a ONE-SHOT `.esc` marker, exactly the
            # fire-once-forever shape §DEDUP above replaces for the base tier, and for the same
            # measured reason — a 900+ call grep habit gets exactly one escalated tip, ever, then
            # nothing for the rest of the session. It now shares the SAME cooldown/cap POLICY
            # (`dedup_cooldown`/`dedup_cap`) as the base tier, counted against `sweep_count` (this
            # class's own observation count), via its own `.deliv`/`.last` pair next to the existing
            # `.pat` file — a SEPARATE counter from the base tier's, deliberately: the two tiers watch
            # different observation streams (this one is every occurrence of the class; the base
            # tier's `_dobs` only counts nudge-eligible ones) and merging them into one shared counter
            # made the classic "escalate at exactly the Nth occurrence" contract depend on whether the
            # base tier had already spent a shared slot first, which is a foot-gun disguised as
            # economy. The practical ceiling on a class that has both tiers is therefore up to
            # `dedup_cap` GENERIC tips plus `dedup_cap` ESCALATED tips across the session — bounded,
            # simple, and independently verifiable per tier, rather than 2x` dedup_cap` of one message
            # kind unpredictably borrowed from the other.
            _swdelivdots=""
            [ -e "${_swf}.deliv" ] && { _swdelivdots="$(<"${_swf}.deliv")"; } 2>/dev/null
            _swdelivn="${#_swdelivdots}"
            _swlastn=0
            [ -e "${_swf}.last" ] && { _swlastn="$(<"${_swf}.last")"; } 2>/dev/null
            case "$_swlastn" in ''|*[!0-9]*) _swlastn=0 ;; esac

            _swarm=0
            if [ "$sweep_count" -ge "$sweep_n" ]
            then
                if [ "$_swdelivn" -eq 0 ]
                then
                    _swarm=1                              # first time this class crosses the threshold
                elif [ "$_swdelivn" -lt "$dedup_cap" ] && [ $(( sweep_count - _swlastn )) -ge "$dedup_cooldown" ]
                then
                    _swarm=1                              # re-armed: cooldown elapsed, cap not yet spent
                fi
            fi

            # §RETIRED (2026-09-02): armed, recorded, silent — and arm-independent, for the same
            # reason the base tier's branch above is. `retired-sweep` OVERWRITES a `retired` the base
            # tier may have set on the same call: the escalation was the stronger of the two tips, so
            # naming it is what keeps "which tier reached this moment" readable in one field.
            if [ "$_swarm" = "1" ]
            then
                { printf '.' >>"${_swf}.deliv"; } 2>/dev/null || true
                { printf '%s' "$sweep_count" >"${_swf}.last"; } 2>/dev/null || true
                { : > "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anysweep"; } 2>/dev/null || true
                { : > "${TMPDIR:-/tmp}/ripwire-nudge.${session}.anynudge"; } 2>/dev/null || true
                nudge="retired-sweep"
            fi
            ;;
    esac
fi

meter_log "$mclass" "$( meter_family "$mclass" )" "$nudged" "$nudge" "$mdetail"
# ---- §RETIRED (2026-09-02): the PreToolUse path ENDS here. It writes one meter row and exits 0 with
#      an EMPTY stdout, unconditionally, on every tool call it observes. The one-time tips and the
#      sweep escalation that used to be built below are gone — see §RETIRED at the top of this file
#      for the readout that retired them and for what stayed. The SessionStart primer (above, and
#      still arm-differentiated) is the only thing this hook says to an agent now.
#
#      This is a CONTRACT, not an incidental property, and test/hookcheck.sh asserts it directly: a
#      PreToolUse invocation of this hook produces no stdout. An advisory hook that is measured to be
#      inert and keeps talking anyway is just tokens.
exit 0
