#!/usr/bin/env bash
# qualitystalecheck.sh — gate for the STALE-baseline guard on --quality-delta. A .ripwire_quality_baseline
# left by an abandoned/parallel session (or written before a commit) used to SILENTLY take precedence and
# report a wall of false regressions on an otherwise-clean tree — the flagship "before I push" reflex
# punishing the agent who obeyed it (adoption-audit finding). The fix stamps the HEAD sha into the sidecar.
#
# B10.1b (signal-to-noise round 2) once refined WHICH mismatches count as "stale": a pinned sha that was still
# an ANCESTOR of the current HEAD (this session simply committed more work since baselining) was treated as a
# legitimate, deliberately-pinned floor and honored SILENTLY. That carve-out is GONE — see R3 below. What
# SURVIVES from B10.1b is the noise fix and the self-heal: a stale sidecar is silently DELETED (no stderr
# warning) and the run falls back to the git-HEAD auto-baseline, with the ONLY record being the
# `baseline="git-HEAD (stale sidecar removed)"` XML attribute.
#
# R3 OWNER RULING (2026-07-29) — ANCESTOR CARVE-OUT REVOKED: strict sha equality, both arms. A sidecar whose
# pinned sha != the CURRENT HEAD sha is stale, whether or not it is reachable. The incident: a parallel
# session's sidecar, pinned at a commit that happened to be an ancestor of this session's HEAD, made the CLI
# report 31 phantom regressions on a clean tree while the MCP quality_delta verb (same binary, same repo, same
# second) honestly reported zero — the reachable-ancestor pin describes some OTHER tree, so everything
# committed since it reads as a working-tree regression. Both arms now route through ONE seam
# (quality::selectBaseline); the per-arm difference is policy only (CLI unlinks and says "removed", the
# read-only MCP verb keeps the file and says "ignored"). Arms 3 and 3b below assert the NEW meaning; the old
# reachable-ancestor-is-honored expectation is deliberately inverted here, not deleted.
# Usage:  test/qualitystalecheck.sh   |   test/qualitystalecheck.sh asan/ripwire   |   RIPWIRE_BIN=asan/ripwire test/qualitystalecheck.sh
# Exits non-zero on any failure. Does NOT edit regression.sh. Needs git.
#
# w1 FIXUP (2026-07-29) — arms 7 and 8 cover the two MED findings the wave-1 verifier raised against R3's seam:
# the self-heal unlink can FAIL (read-only parent dir) and the marker used to claim "removed" anyway with no
# observable degrade (arm 7), and the CLI's no-HEAD-to-fall-back-to fatal used to say "no <file>" even when the
# file was stale-and-just-dropped, or stale-and-STILL-THERE (arm 8).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

# Sandboxes whose WRITE BIT this script deliberately clears (arms 7/8b). They must be made writable again
# before the rm -rf, and that has to happen even when an assertion above it failed — a red gate that leaves an
# unwritable tmpdir behind poisons the next run of every gate that shares /tmp.
ROSANDBOXES=""
cleanup(){ for d in $ROSANDBOXES; do chmod -R u+w "$d" 2>/dev/null; done; rm -rf $ROSANDBOXES "$REPO"; }
REPO="$(mktemp -d)"; trap cleanup EXIT
cd "$REPO" || exit 1
git init -q; git config user.email x@y; git config user.name x
printf 'int f( int x ){ if( x > 0 ){ return 1; } return 2; }\n' > a.cpp
git add a.cpp; git commit -qm init

# 1) --quality-baseline stamps the current HEAD sha into the sidecar
"$BIN" "$REPO" --quality-baseline --no-cache >/dev/null 2>&1
head_sha="$( git -C "$REPO" rev-parse HEAD )"
grep -q "^head $head_sha$" "$REPO/.ripwire_quality_baseline" \
    && ok "--quality-baseline stamps the HEAD sha into the sidecar" \
    || no "sidecar is missing the 'head <HEAD-sha>' stamp"

# 2) FRESH sidecar (same HEAD, no edit) is HONORED — the mid-task convergence loop is unchanged
fresh="$("$BIN" "$REPO" --quality-delta --no-cache 2>/dev/null)"
{ echo "$fresh" | grep -q 'baseline="sidecar"' && echo "$fresh" | grep -q 'regressions="0"'; } \
    && ok "fresh sidecar (HEAD unchanged) is honored: baseline=sidecar, 0 regressions" \
    || { no "fresh sidecar not honored"; echo "     got: $(echo "$fresh" | grep -oE 'baseline="[^"]*" regressions="[0-9]+"')"; }

# 3) R3 owner ruling 2026-07-29: ancestor carve-out revoked — strict sha equality, both arms. HEAD advances via
#    a REAL commit on top, so the pinned sha stays a REACHABLE ANCESTOR of the new HEAD ("committed some work
#    since baselining"). This arm asserted the OPPOSITE until R3 (it required baseline="sidecar", honored, file
#    kept) — the meaning is INVERTED here, deliberately, not deleted. The pin now describes a tree that is no
#    longer HEAD, so it is STALE like any other mismatch: self-healed away, marker "stale sidecar removed",
#    still silent on stderr (the B10.1b noise fix is untouched by the ruling).
git commit -qam "advance HEAD (pin becomes a reachable ancestor)" --allow-empty
# single invocation: this run DELETES the sidecar, so stdout and stderr must come from the same call.
advanced_out="$("$BIN" "$REPO" --quality-delta --no-cache 2>"$REPO/.stderr.tmp")"
advanced_err="$(cat "$REPO/.stderr.tmp")"; rm -f "$REPO/.stderr.tmp"
{ echo "$advanced_out" | grep -q 'baseline="git-HEAD (stale sidecar removed)"' && echo "$advanced_out" | grep -q 'regressions="0"'; } \
    && ok "R3: reachable-ancestor pin is STALE (self-healed, baseline=\"git-HEAD (stale sidecar removed)\", 0 regressions)" \
    || { no "R3: reachable-ancestor pin was still honored — the revoked carve-out is back"; echo "     got: $(echo "$advanced_out" | grep -oE 'baseline="[^"]*" regressions="[0-9]+"')"; }
[ -z "$advanced_err" ] && ok "R3: reachable-ancestor self-heal prints no stderr (B10.1b no-warning-spam fix intact)" \
    || no "reachable-ancestor case printed stderr: $advanced_err"
[ -f "$REPO/.ripwire_quality_baseline" ] \
    && no "R3: reachable-ancestor sidecar file NOT deleted (the CLI arm must self-heal it)" \
    || ok "R3: reachable-ancestor sidecar file deleted (self-healed)"

# 3b) THE R3 INCIDENT SHAPE, both arms on the SAME sidecar. This is the arm the incident lacked: the CLI and the
#     MCP quality_delta verb must agree on WHICH sidecars are trustworthy and on the resulting regression COUNT.
#     Before R3 the CLI honored an ancestor-pinned sidecar (31 phantom regressions on a clean tree) while MCP
#     dropped it (0) — same binary, same repo, same second. The only legitimate difference is POLICY: MCP is
#     read-only and leaves the file ("ignored"), the CLI self-heals it away ("removed").
#     Order matters: MCP runs FIRST, because the CLI run deletes the file it is meant to judge.
MREPO="$(mktemp -d)"
( cd "$MREPO" && git init -q . && git config user.email x@y && git config user.name x \
  && printf 'int f( int x ){ return x + 1; }\n' > a.cpp && git add a.cpp && git commit -qm A ) >/dev/null 2>&1
"$BIN" "$MREPO" --quality-baseline --no-cache >/dev/null 2>&1
# land a gnarly function as a COMMIT: the working tree stays clean, so the honest answer is 0 regressions — but
# a trusted ancestor-pinned sidecar would score every committed symbol as a working-tree regression.
cat >> "$MREPO/a.cpp" <<'CPPEOF'
int gnarly( int a, int b, int c, int d, int e, int g )
{
    int t = 0;
    for( int i = 0; i < a; ++i ) { if( i % 2 == 0 ) { if( b > 0 ) { if( c > 0 ) { if( d > 0 ) { if( e > 0 ) { t += i * g; } } } } } }
    return t;
}
CPPEOF
( cd "$MREPO" && git add a.cpp && git commit -qm B ) >/dev/null 2>&1
git -C "$MREPO" merge-base --is-ancestor "$(sed -n 's/^head //p' "$MREPO/.ripwire_quality_baseline")" HEAD \
    && ok "R3 incident shape: the pin IS a reachable ancestor of HEAD (the setup the carve-out used to trust)" \
    || no "R3 incident shape: setup failed — the pin is not an ancestor of HEAD"
mcp_line="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
             '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$MREPO"'"}}}' \
             | "$BIN" --mcp 2>/dev/null | tail -1 )"
mcp_regs="$( printf '%s' "$mcp_line" | sed -n 's/.*\\"regressions\\":\([0-9]*\).*/\1/p' )"
printf '%s' "$mcp_line" | grep -q 'stale sidecar ignored' \
    && ok "R3 incident shape: MCP quality_delta calls the ancestor-pinned sidecar stale (\"ignored\")" \
    || { no "R3 incident shape: MCP did not report the sidecar as stale"; printf '     got: %s\n' "$(printf '%s' "$mcp_line" | head -c 200)"; }
[ -f "$MREPO/.ripwire_quality_baseline" ] \
    && ok "R3 incident shape: MCP is READ-ONLY — the sidecar file survives its run" \
    || no "R3 incident shape: the read-only MCP verb DELETED the sidecar"
mcp_err="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
            '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$MREPO"'"}}}' \
            | "$BIN" --mcp 2>&1 1>/dev/null )"
[ -z "$mcp_err" ] && ok "R3 incident shape: the MCP stale path prints no stderr either (no warning spam on either arm)" \
    || no "R3 incident shape: the MCP stale path printed stderr: $mcp_err"
cli_out="$("$BIN" "$MREPO" --quality-delta --no-cache 2>/dev/null)"
cli_regs="$( printf '%s' "$cli_out" | sed -n 's/.*<quality-delta baseline="[^"]*" regressions="\([0-9]*\)".*/\1/p' )"
printf '%s' "$cli_out" | grep -q 'baseline="git-HEAD (stale sidecar removed)"' \
    && ok "R3 incident shape: the CLI calls the SAME sidecar stale (\"removed\")" \
    || { no "R3 incident shape: the CLI still honored the sidecar the MCP arm dropped — the divergence is back"; echo "     got: $(printf '%s' "$cli_out" | grep -oE 'baseline="[^"]*" regressions="[0-9]+"')"; }
{ [ -n "$cli_regs" ] && [ -n "$mcp_regs" ] && [ "$cli_regs" = "$mcp_regs" ]; } \
    && ok "R3 incident shape: CLI and MCP report the SAME honest regression count ($cli_regs)" \
    || no "R3 incident shape: regression counts DIVERGE — cli='$cli_regs' mcp='$mcp_regs'"
[ "$cli_regs" = "0" ] \
    && ok "R3 incident shape: a clean working tree scores 0 — no phantom regressions from the stale pin" \
    || no "R3 incident shape: phantom regressions on a clean tree (cli=$cli_regs) — the incident reproduced"
rm -rf "$MREPO"

# 4) UNREACHABLE pin: an orphan branch shares no history with the pinned sha at all. Post-R3 this is no longer a
#    SEPARATE category (any mismatch is stale) but it is kept as its own arm because it exercises a different
#    git shape — an unresolvable/divergent history — which must still self-heal rather than error or crash.
#    Arm 3 consumed the sidecar, so re-pin at the current HEAD first.
"$BIN" "$REPO" --quality-baseline --no-cache >/dev/null 2>&1
[ -f "$REPO/.ripwire_quality_baseline" ] || no "setup: could not re-pin the sidecar before the orphan arm"
git checkout -q --orphan orphanbr
git rm -rf --cached . >/dev/null 2>&1
printf 'int g(){ return 1; }\n' > a.cpp
git add a.cpp; git commit -qm "orphan root (shares no history with the pin)"
# single invocation: the sidecar is deleted as a SIDE EFFECT of this run, so stdout/stderr must come from
# the SAME call (a second call would legitimately hit the "never baselined" informative message instead).
unreachable_combined="$("$BIN" "$REPO" --quality-delta --no-cache 2>"$REPO/.stderr.tmp")"
unreachable_err="$(cat "$REPO/.stderr.tmp")"; rm -f "$REPO/.stderr.tmp"
echo "$unreachable_combined" | grep -q 'baseline="git-HEAD (stale sidecar removed)"' \
    && ok "unreachable-pin sidecar self-heals (baseline=\"git-HEAD (stale sidecar removed)\")" \
    || { no "unreachable-pin sidecar was not self-healed"; echo "     got: $(echo "$unreachable_combined" | grep -oE 'baseline="[^"]*"')"; }
[ -z "$unreachable_err" ] && ok "unreachable-pin self-heal prints no stderr (no warning spam)" \
    || no "unreachable-pin self-heal printed stderr: $unreachable_err"
[ -f "$REPO/.ripwire_quality_baseline" ] \
    && no "unreachable-pin sidecar file NOT deleted (should self-heal)" \
    || ok "unreachable-pin sidecar file deleted (self-healed)"

# 5) STALE by MISSING stamp (a pre-stamp / hand-written sidecar): re-pin at the new HEAD, then STRIP the head
#    line → an unstamped sidecar's pinned sha reads "" (unresolvable) → must self-heal exactly like an
#    unreachable pin, not be trusted as a floor.
"$BIN" "$REPO" --quality-baseline --no-cache >/dev/null 2>&1
grep -v "^head " "$REPO/.ripwire_quality_baseline" > "$REPO/.b.tmp" && mv "$REPO/.b.tmp" "$REPO/.ripwire_quality_baseline"
unstamped="$("$BIN" "$REPO" --quality-delta --no-cache 2>/dev/null)"
echo "$unstamped" | grep -q 'baseline="git-HEAD (stale sidecar removed)"' \
    && ok "unstamped sidecar self-heals (cannot verify freshness → removed), not silently trusted" \
    || { no "unstamped sidecar was trusted (the exact silent-false-regressions bug)"; echo "     got: $(echo "$unstamped" | grep -oE 'baseline="[^"]*"')"; }
[ -f "$REPO/.ripwire_quality_baseline" ] \
    && no "unstamped sidecar file NOT deleted (should self-heal)" \
    || ok "unstamped sidecar file deleted (self-healed)"

# 6) determinism
r1="$("$BIN" "$REPO" --quality-delta --no-cache 2>/dev/null)"; r2="$("$BIN" "$REPO" --quality-delta --no-cache 2>/dev/null)"
[ "$r1" = "$r2" ] && ok "--quality-delta deterministic run-to-run" || no "--quality-delta non-deterministic"

# ── DEGRADE-OBSERVABILITY PROBE (for arm 7) ───────────────────────────────────────────────────────────────
# Arm 7 asserts a DEGRADED_PATH_ALERT, which a Release/NDEBUG build compiles OUT ("if you add a degrade path,
# it is the PLAIN run that proves it" — CLAUDE.md). Probe the flavour with an UNRELATED, already-gated
# degrading invocation (--since=notadate) so that a missing alert inside arm 7 itself is a genuine FAILURE
# rather than a silent skip — the whole point of the finding is that no alert fired where one was owed.
alerts_observable=0
"$BIN" "$REPO" --rank-by=churn --since=notadate >/dev/null 2>"$REPO/.probe.err"
grep -q 'math degraded' "$REPO/.probe.err" && alerts_observable=1
rm -f "$REPO/.probe.err"

# 7) w1 MED #1 — the self-heal unlink FAILS (read-only parent dir). The marker used to say "stale sidecar
#    removed" on the strength of the CLI's INTENT while the file was demonstrably still on disk (the unlink's
#    std::error_code was captured and never read), and no DEGRADED_PATH_ALERT fired, so the plain build could
#    not observe the degrade either. Post-fix the seam reports what the DISK says: "stale sidecar ignored" (the
#    same honest string the read-only MCP arm uses, because ignored-not-removed is now the truth), exactly one
#    alert, and an otherwise UNCHANGED answer — the git-HEAD fallback still runs, so a clean tree still scores 0.
RREPO="$(mktemp -d)"; ROSANDBOXES="$ROSANDBOXES $RREPO"
( cd "$RREPO" && git init -q . && git config user.email x@y && git config user.name x \
  && printf 'int f( int x ){ return x + 1; }\n' > a.cpp && git add a.cpp && git commit -qm A ) >/dev/null 2>&1
"$BIN" "$RREPO" --quality-baseline --no-cache >/dev/null 2>&1
[ -f "$RREPO/.ripwire_quality_baseline" ] || no "setup(7): could not pin a sidecar in the read-only-dir sandbox"
git -C "$RREPO" commit -qam "advance HEAD (the pin goes stale)" --allow-empty >/dev/null 2>&1
chmod a-w "$RREPO"                                     # unlink of an entry needs write on the PARENT dir → the self-heal must fail
# stderr sink lives OUTSIDE the read-only sandbox, and stdout/stderr come from ONE invocation.
ro_out="$("$BIN" "$RREPO" --quality-delta --no-cache 2>"$REPO/.ro.err")"
ro_err="$(cat "$REPO/.ro.err")"; ro_alerts="$( grep -c 'math degraded' "$REPO/.ro.err" )"; rm -f "$REPO/.ro.err"
[ -f "$RREPO/.ripwire_quality_baseline" ] \
    && ok "read-only dir: the stale sidecar really did SURVIVE the self-heal (the premise of this arm)" \
    || no "read-only dir: the sidecar was deleted anyway — the sandbox is not read-only, arm 7 proves nothing"
echo "$ro_out" | grep -q 'baseline="git-HEAD (stale sidecar ignored)"' \
    && ok "failed unlink reports baseline=\"git-HEAD (stale sidecar ignored)\" — the marker matches the disk" \
    || { no "failed unlink still claims a removal that did not happen"; echo "     got: $(echo "$ro_out" | grep -oE 'baseline="[^"]*"')"; }
echo "$ro_out" | grep -q 'regressions="0"' \
    && ok "failed unlink still falls back to git HEAD (clean tree → 0 regressions, answer unchanged)" \
    || { no "failed unlink changed the ANSWER, not just the marker"; echo "     got: $(echo "$ro_out" | grep -oE 'regressions="[0-9]+"')"; }
if [ "$alerts_observable" -eq 1 ]; then
    [ "$ro_alerts" -eq 1 ] \
        && ok "failed unlink fires exactly ONE [math degraded] alert (the plain build can observe the degrade)" \
        || no "expected exactly 1 [math degraded] alert on the failed unlink, got $ro_alerts"
    printf '%s' "$ro_err" | grep -q 'math degraded.*ripwire_quality_baseline' \
        && ok "…and the alert NAMES the sidecar that stayed on disk" \
        || { no "the alert does not name the sidecar"; printf '     got: %s\n' "$( printf '%s' "$ro_err" | grep 'math degraded' | head -1 )"; }
    printf '%s' "$ro_err" | grep -q 'math degraded.*git HEAD' \
        && ok "…and says the baseline still falls back to git HEAD (states the CONSEQUENCE, not just the failure)" \
        || no "the alert does not say what the run fell back to"
else
    no "this binary compiles DEGRADED_PATH_ALERT out (Release/NDEBUG): arm 7's degrade assertion CANNOT be made — run the PLAIN build"
fi
chmod u+w "$RREPO"; rm -rf "$RREPO"; ROSANDBOXES=""

# 8) w1 MED #2 — STALE sidecar *and* no HEAD tree to fall back to: the CLI fatal used to print the flat
#    "no <file> — run --quality-baseline BEFORE the change", which is stale-UNAWARE and, when the unlink failed,
#    factually false (it names a file that is sitting right there). The MCP twin has been stale-aware all along;
#    this arm holds the CLI to the same two-way split. Shape: pin a sidecar at a real HEAD, then move to an
#    UNBORN branch (git checkout --orphan, no commit) so the pin is non-empty, HEAD does not resolve, and
#    computeHeadSnapshot fails AFTER staleness is decided. 8a = unlink succeeds, 8b = read-only dir, unlink fails.
mkorphan()   # $1 = dir; leaves a stale pin + an unborn HEAD
{
    ( cd "$1" && git init -q . && git config user.email x@y && git config user.name x \
      && printf 'int f( int x ){ return x + 1; }\n' > a.cpp && git add a.cpp && git commit -qm A ) >/dev/null 2>&1
    "$BIN" "$1" --quality-baseline --no-cache >/dev/null 2>&1
    ( cd "$1" && git checkout -q --orphan unbornbr && git rm -rf --cached . ) >/dev/null 2>&1
}
NOHEAD="$(mktemp -d)"; mkorphan "$NOHEAD"
{ [ -f "$NOHEAD/.ripwire_quality_baseline" ] && ! git -C "$NOHEAD" rev-parse --verify -q HEAD >/dev/null 2>&1; } \
    && ok "setup(8): a stale-pinned sidecar in a repo whose HEAD does NOT resolve (unborn branch)" \
    || no "setup(8): sandbox is not the stale-pin + no-HEAD shape"
"$BIN" "$NOHEAD" --quality-delta --no-cache >/dev/null 2>"$REPO/.nohead.err"
nohead_rc=$?; nohead_err="$(cat "$REPO/.nohead.err")"; rm -f "$REPO/.nohead.err"
[ "$nohead_rc" -eq 1 ] && ok "stale + no-HEAD still exits 1 (exit-code semantics unchanged)" || no "stale + no-HEAD exit code is $nohead_rc, expected 1"
printf '%s' "$nohead_err" | grep -q 'was STALE (pinned at a different HEAD)' \
    && ok "stale + no-HEAD fatal is STALE-AWARE (mirrors the MCP twin's wording)" \
    || { no "stale + no-HEAD fatal is not stale-aware"; printf '     got: %s\n' "$nohead_err"; }
printf '%s' "$nohead_err" | grep -q 'has been removed' \
    && ok "…and says the stale sidecar HAS BEEN REMOVED (the unlink landed here)" \
    || { no "the successful-unlink case does not say the file was removed"; printf '     got: %s\n' "$nohead_err"; }
printf '%s' "$nohead_err" | grep -qF "no $NOHEAD/.ripwire_quality_baseline" \
    && no "stale + no-HEAD fatal still claims \"no <file>\" — the pre-fix false statement" \
    || ok "stale + no-HEAD fatal no longer claims \"no <file>\" for a sidecar that DID exist"
rm -rf "$NOHEAD"
# 8b) same shape, read-only dir: the unlink fails, so the file IS still there and the message must say so —
#     "no <file>" would be a flat lie about the filesystem.
NOHEADRO="$(mktemp -d)"; ROSANDBOXES="$ROSANDBOXES $NOHEADRO"; mkorphan "$NOHEADRO"
chmod a-w "$NOHEADRO"
"$BIN" "$NOHEADRO" --quality-delta --no-cache >/dev/null 2>"$REPO/.nohead2.err"
nohead2_rc=$?; nohead2_err="$(cat "$REPO/.nohead2.err")"; rm -f "$REPO/.nohead2.err"
[ "$nohead2_rc" -eq 1 ] && ok "stale + no-HEAD + failed unlink still exits 1" || no "stale + no-HEAD + failed unlink exit code is $nohead2_rc, expected 1"
[ -f "$NOHEADRO/.ripwire_quality_baseline" ] \
    && ok "stale + no-HEAD + read-only dir: the sidecar is STILL on disk (the premise of 8b)" \
    || no "8b premise broken: the sidecar was removed from a read-only dir"
printf '%s' "$nohead2_err" | grep -q 'was STALE (pinned at a different HEAD)' \
    && ok "8b: the fatal is stale-aware here too" || { no "8b: fatal is not stale-aware"; printf '     got: %s\n' "$nohead2_err"; }
printf '%s' "$nohead2_err" | grep -q 'still on disk' \
    && ok "8b: the fatal says the stale sidecar is STILL ON DISK (agrees with the failed unlink)" \
    || { no "8b: the fatal does not admit the file survived"; printf '     got: %s\n' "$nohead2_err"; }
printf '%s' "$nohead2_err" | grep -qF "no $NOHEADRO/.ripwire_quality_baseline" \
    && no "8b: the fatal claims \"no <file>\" while that exact file exists — the false-statement finding" \
    || ok "8b: the fatal never claims \"no <file>\" for a file that exists"

# 8c) §B12.11 — the SAME sandbox as 8b, but asserting the [math degraded] ALERT text itself, which fires
#     INSIDE quality::selectBaseline (quality.h ~1769) BEFORE the fatal 8b already checks, and is a separate
#     string. Pre-fix, the alert unconditionally said "...the baseline still falls back to git HEAD" even
#     here, where headSha is EMPTY (unborn branch / non-git — no HEAD to fall back to at all) — a false
#     statement in the exact state it fires in. The fatal immediately after was already correct (8b proves
#     it), so no consumer was misled TODAY — but the alert itself must not assert a fallback that does not
#     exist. Reuses $nohead2_err and $alerts_observable from arm 8b/the probe above rather than re-building
#     the read-only sandbox a third time.
if [ "$alerts_observable" -eq 1 ]; then
    printf '%s' "$nohead2_err" | grep -q 'math degraded.*ripwire_quality_baseline' \
        && ok "8c: the no-HEAD read-only-dir case still fires the stale-unlink alert" \
        || no "8c: expected a [math degraded] stale-unlink alert in the no-HEAD case too"
    printf '%s' "$nohead2_err" | grep -q 'math degraded.*falls back to git HEAD' \
        && no "8c: the alert claims the baseline falls back to git HEAD where this tree has NO git HEAD to fall back to — the false-statement finding (quality.h ~1769)" \
        || ok "8c: the alert no longer claims an unconditional git-HEAD fallback in the no-HEAD state"
    printf '%s' "$nohead2_err" | grep -q 'math degraded.*no baseline floor at all' \
        && ok "8c: the alert instead names the TRUE consequence (no baseline floor at all)" \
        || { no "8c: the alert does not name the true no-HEAD consequence"; printf '     got: %s\n' "$( printf '%s' "$nohead2_err" | grep 'math degraded' | head -1 )"; }
else
    no "8c: this binary compiles DEGRADED_PATH_ALERT out (Release/NDEBUG): the §B12.11 alert-wording assertion CANNOT be made — run the PLAIN build"
fi
chmod u+w "$NOHEADRO"; rm -rf "$NOHEADRO"; ROSANDBOXES=""

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
