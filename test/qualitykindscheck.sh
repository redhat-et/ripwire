#!/usr/bin/env bash
# qualitykindscheck.sh — gate for the THREE GitClear-2026-backed --quality-delta kinds (§D#4 / §E-17):
#   error-masking            — a NEW error-masking construct (empty catch / bare-pass except / swallowed .catch)
#   short-horizon-churn      — a symbol whose FILE had ≥2 commits in the last 14 days (from git commit
#                              TIMESTAMPS vs HEAD's epoch, NOT wall-clock) that this diff rewrites again
#   new-clone-of-reused-helper — a NEW clone of an existing helper with fan-in ≥ 3 (reuse-connectivity decline)
# plus (§5) error-masking's two widened shapes, log-only and rethrow-only, per language — gating in Python,
# report-only (sev="minor") elsewhere — and (§6) the eleventh kind, placeholder (an added stub or TODO),
# which is new-symbol by construction and never gates.
#
# Each kind must fire ONLY on a regression vs baseline (never on pre-existing debt) and preserve the
# quality-delta exit-2 contract. Uses git-init fixtures + the auto-vs-HEAD baseline path (same idiom as
# qualitycheck.sh §7). Operates entirely in temp dirs; the repo is never touched.
#
# Usage:  RIPWIRE_BIN=build_w3/ripwire bash test/qualitykindscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolutize BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qualitykindscheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "qualitykindscheck: BIN=$BIN  (temp corpora)"

# ── 1) ERROR-MASKING ────────────────────────────────────────────────────────────────────────────────────
#   Baseline (committed): handle() catches AND logs; a SEPARATE pre-existing empty catch lives in legacy() —
#   committed too, so it is pre-existing debt. Working-tree edit adds an EMPTY catch to handle() (the
#   regression) and does NOT touch legacy(). Assert: handle flagged, legacy NOT flagged, exit 2.
EM="$WORK/em"; mkdir -p "$EM/src"
( cd "$EM" && git init -q && git config user.email t@t && git config user.name t )
printf 'void log_it(){}\nvoid handle(){ try { risky(); } catch( ... ) { log_it(); } }\nvoid legacy(){ try { risky(); } catch( ... ) {} }\nvoid risky(){}\nvoid drive(){ handle(); legacy(); }\n' > "$EM/src/a.cpp"
( cd "$EM" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
dem(){  ( cd "$EM" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecem(){ ( cd "$EM" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 1a) clean tree (== HEAD) → zero regressions, exit 0 (the pre-existing empty catch in legacy() is NOT flagged)
[ "$( ecem )" = 0 ] && dem | grep -q 'regressions="0"' \
    && ok "error-masking: clean tree → exit 0 (pre-existing empty catch in legacy() NOT flagged)" \
    || { no "error-masking: clean tree should be clean (exit $( ecem ))"; dem | tr '>' '\n' | grep '<r '; }

# 1b) add an EMPTY catch to handle() (uncommitted) → regression fires, exit 2
printf 'void log_it(){}\nvoid handle(){ try { risky(); } catch( ... ) {} }\nvoid legacy(){ try { risky(); } catch( ... ) {} }\nvoid risky(){}\nvoid drive(){ handle(); legacy(); }\n' > "$EM/src/a.cpp"
OEM="$( dem )"
if [ "$( ecem )" = 2 ]; then ok "error-masking: new empty catch → exit 2"; else no "error-masking: new empty catch should exit 2 (got $( ecem ))"; fi
printf '%s' "$OEM" | grep -q 'kind="error-masking" sym="handle"' \
    && ok "error-masking: handle() flagged (empty catch added)" || { no "error-masking: handle() not flagged"; printf '%s\n' "$OEM" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OEM" | grep -q 'kind="error-masking" sym="legacy"' \
    && no "error-masking: legacy() wrongly flagged (its empty catch is pre-existing, untouched)" \
    || ok "error-masking: pre-existing empty catch in untouched legacy() NOT flagged (contract)"

# 1c) determinism + xml
if [ "$OEM" = "$( dem )" ]; then ok "error-masking: delta byte-identical run-to-run"; else no "error-masking: non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OEM" | xmllint --noout - 2>/dev/null; then ok "error-masking: xml well-formed"; else no "error-masking: xml malformed"; fi
fi

# 1d) Python bare/pass except — a second-language sanity check on the rule table.
PY="$WORK/empy"; mkdir -p "$PY"
( cd "$PY" && git init -q && git config user.email t@t && git config user.name t )
printf 'def handle():\n    try:\n        risky()\n    except Exception:\n        log_it()\n\ndef risky():\n    pass\n\ndef log_it():\n    pass\n' > "$PY/a.py"
( cd "$PY" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
printf 'def handle():\n    try:\n        risky()\n    except Exception:\n        pass\n\ndef risky():\n    pass\n\ndef log_it():\n    pass\n' > "$PY/a.py"
OPY="$( cd "$PY" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OPY" | grep -q 'kind="error-masking" sym="handle"' \
    && ok "error-masking (python): except: pass flagged on handle()" || { no "error-masking (python): except-pass not flagged"; printf '%s\n' "$OPY" | tr '>' '\n' | grep '<r '; }

# ── 2) SHORT-HORIZON CHURN ───────────────────────────────────────────────────────────────────────────────
#   A file committed TWICE (both within the 14-day window measured from HEAD's own commit epoch), then
#   rewritten a THIRD time in the working tree. Its symbol must flag short-horizon-churn (file ≥2 in-window
#   commits AND rewritten again). A DIFFERENT file committed only ONCE and edited must NOT flag (churn<2).
SH="$WORK/shc"; mkdir -p "$SH/src"
( cd "$SH" && git init -q && git config user.email t@t && git config user.name t )
# hot.cpp: two commits (both recent) → will be edited a third time. cold.cpp: one commit → edited once.
# hot() is MULTI-LINE and gets TWO in-window commits on TWO DIFFERENT lines, because that is what the kind
# gates on since the 2026-09-10 dial round: churn="self" (the edit touches a line committed inside the window)
# is informational, and only "rewritten by >= 2 COMMITTED in-window commits, the working edit not counted"
# fires exit 2. A one-line hot() rewritten by a single commit can never show more than ONE blamed commit, so
# the old fixture could no longer exercise the gating arm at all (see test/qddialscheck.sh §1 for the pair).
printf 'int hot(){\n    int x = 1;\n    return x;\n}\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )
printf 'int hot(){\n    int x = 2;\n    return x;\n}\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c2 >/dev/null 2>&1 )
printf 'int hot(){\n    int x = 2;\n    return x + 0;\n}\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c3 >/dev/null 2>&1 )
# a SEPARATE file with only ONE commit (churn == 1 < 2 → never flags short-horizon-churn even when edited)
printf 'int lone(){ return 0; }\nint uselone(){ return lone(); }\n' > "$SH/src/g.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c3single >/dev/null 2>&1 )
dsh(){  ( cd "$SH" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecsh(){ ( cd "$SH" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 2a) clean tree (== HEAD) → nothing rewritten → zero short-horizon-churn regressions.
[ "$( ecsh )" = 0 ] && dsh | grep -q 'regressions="0"' \
    && ok "short-horizon-churn: clean tree → exit 0 (nothing rewritten)" \
    || { no "short-horizon-churn: clean tree should be clean (exit $( ecsh ))"; dsh | tr '>' '\n' | grep '<r '; }

# 2b) rewrite hot() (its file has 2 in-window commits) AND lone() (its file has 1) in the working tree.
printf 'int hot(){\n    int x = 3;\n    return x + 1;\n}\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
printf 'int lone(){ return 9; }\nint uselone(){ return lone(); }\n' > "$SH/src/g.cpp"
OSH="$( dsh )"
if [ "$( ecsh )" = 2 ]; then ok "short-horizon-churn: rewrite of lines TWO in-window commits wrote → exit 2"; else no "short-horizon-churn: should exit 2 (got $( ecsh ))"; fi
printf '%s' "$OSH" | grep -q 'kind="short-horizon-churn" sym="hot"' \
    && ok "short-horizon-churn: hot() flagged (file had ≥2 recent commits, rewritten again)" || { no "short-horizon-churn: hot() not flagged"; printf '%s\n' "$OSH" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OSH" | grep -q 'kind="short-horizon-churn" sym="lone"' \
    && no "short-horizon-churn: lone() wrongly flagged (its file had only 1 commit < 2)" \
    || ok "short-horizon-churn: single-commit file NOT flagged even when edited (min-commits gate)"
printf '%s' "$OSH" | grep -q 'kind="short-horizon-churn" sym="cold"' \
    && no "short-horizon-churn: cold() wrongly flagged (in a churny file but NOT rewritten this diff)" \
    || ok "short-horizon-churn: untouched symbol in a churny file NOT flagged (rewrite gate)"
if [ "$OSH" = "$( dsh )" ]; then ok "short-horizon-churn: delta byte-identical run-to-run (deterministic)"; else no "short-horizon-churn: non-deterministic delta"; fi

# ── 3) NEW-CLONE-OF-REUSED-HELPER ────────────────────────────────────────────────────────────────────────
#   A helper accumulate() with fan-in ≥ 3 (called from three sites) is committed. The working tree adds a
#   NEW function reinvent() whose body is a Type-1/2 clone of accumulate() — reuse-connectivity decline.
#   Assert the new-clone-of-reused-helper kind fires (exit 2) and names the clone pair.
#   3a/3b is also the CONTROL for 3c/3d below: a genuine reuse-decline (no recognized idiom, no shared
#   test-script path) must keep gating at full severity — the fix must not blunt the kind, only narrow it.
#   3c/3d extend this section to give reuse-decline the SAME two demotions `duplication` already has
#   (src/quality.h reportReusedClones, which reads reportNewClones's own CloneIdiomVerdict/isTestScriptPath
#   rather than a second copy of either test): idiom-class collisions demote to minor instead of gating, and
#   a clone group entirely made of test SCRIPTS is skipped outright, the same as `duplication`.
RC="$WORK/reuse"; mkdir -p "$RC/src"
( cd "$RC" && git init -q && git config user.email t@t && git config user.name t )
# accumulate() has a distinctive ≥18-token body; it is called from c1/c2/c3 → in-edge fan-in = 3.
printf 'int accumulate(){ int x=0; x+=1; x+=2; x+=3; x+=4; x+=5; x+=6; return x*x+7; }\n' >  "$RC/src/h.cpp"
printf 'int c1(){ return accumulate(); }\nint c2(){ return accumulate(); }\nint c3(){ return accumulate(); }\n' >> "$RC/src/h.cpp"
( cd "$RC" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
drc(){  ( cd "$RC" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecrc(){ ( cd "$RC" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 3a) clean tree → exit 0 (no clone group yet)
[ "$( ecrc )" = 0 ] && drc | grep -q 'regressions="0"' \
    && ok "reuse-connectivity: clean tree → exit 0 (no duplicate yet)" \
    || { no "reuse-connectivity: clean tree should be clean (exit $( ecrc ))"; drc | tr '>' '\n' | grep '<r '; }

# 3b) add reinvent() — a byte-for-byte body clone of accumulate() (which has fan-in 3) in a new file.
printf 'int reinvent(){ int x=0; x+=1; x+=2; x+=3; x+=4; x+=5; x+=6; return x*x+7; }\nint user(){ return reinvent(); }\n' > "$RC/src/dup.cpp"
ORC="$( drc )"
if [ "$( ecrc )" = 2 ]; then ok "reuse-connectivity: new clone of a reused helper → exit 2"; else no "reuse-connectivity: should exit 2 (got $( ecrc ))"; fi
printf '%s' "$ORC" | grep -q 'kind="new-clone-of-reused-helper"' && printf '%s' "$ORC" | grep -q 'accumulate' \
    && ok "reuse-connectivity: new-clone-of-reused-helper flagged (reinvent duplicates accumulate, fan-in≥3)" \
    || { no "reuse-connectivity: new-clone-of-reused-helper missing"; printf '%s\n' "$ORC" | tr '>' '\n' | grep '<r '; }
# CONTROL (3b, strengthened): accumulate()/reinvent() share no recognized idiom and no test-script path, so
# this genuine reuse-decline must gate at FULL severity — gating="1", no sev="minor", no idiom= — proving the
# demotions added in 3c/3d below narrow the kind and do not blunt it.
RCROW="$( printf '%s' "$ORC" | tr '<' '\n' | grep '^r kind="new-clone-of-reused-helper"' )"
printf '%s' "$RCROW" | grep -q 'gating="1"' \
    && ok "reuse-connectivity CONTROL: a genuine (non-idiom, non-test-script) clone still gates at full severity" \
    || no "reuse-connectivity CONTROL: genuine reuse-decline lost its gating attribute: $RCROW"
printf '%s' "$RCROW" | grep -qE 'sev="minor"|idiom="' \
    && no "reuse-connectivity CONTROL: genuine reuse-decline was wrongly demoted (sev=minor/idiom= present): $RCROW" \
    || ok "reuse-connectivity CONTROL: no sev=\"minor\", no idiom= on the genuine finding"
if [ "$ORC" = "$( drc )" ]; then ok "reuse-connectivity: delta byte-identical run-to-run (deterministic)"; else no "reuse-connectivity: non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$ORC" | xmllint --noout - 2>/dev/null; then ok "reuse-connectivity: xml well-formed"; else no "reuse-connectivity: xml malformed"; fi
fi

# 3c) IDIOM-CLASS COLLISION on a reused helper: altitudeBandOf() (a scalar threshold-ladder over a 4-band
#     enum, fan-in=3 via 3 baseline callers) is committed. The working tree adds tankStateFor() — the SAME
#     threshold-ladder shape in a different namespace/file, sharing NOT ONE non-keyword identifier with
#     altitudeBandOf — the exact shape src/cloneidiom.h demotes for `duplication` (test/cloneidiomcheck.sh's
#     ladder_demote fixture). Because the group also contains a fan-in≥3 PREEXISTING helper, this is ALSO a
#     new-clone-of-reused-helper candidate; the fix requires it to demote (sev="minor", no gating) exactly
#     like `duplication` does, via the SAME CloneIdiomVerdict — not a second idiom test of its own.
ID="$WORK/idiom"; mkdir -p "$ID/src"
( cd "$ID" && git init -q && git config user.email t@t && git config user.name t )
cat > "$ID/src/altitude.cpp" <<'EOF'
namespace flight
{
enum class AltitudeBand : unsigned char { Low, Mid, High, Danger };
AltitudeBand altitudeBandOf( float y )
{
    if( y <  6.0f ) return AltitudeBand::Low;
    if( y < 12.0f ) return AltitudeBand::Mid;
    if( y < 16.0f ) return AltitudeBand::High;
    return AltitudeBand::Danger;
}
int callA( float y ) { return int( altitudeBandOf( y ) ); }
int callB( float y ) { return int( altitudeBandOf( y ) ); }
int callC( float y ) { return int( altitudeBandOf( y ) ); }
}
EOF
( cd "$ID" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
did(){  ( cd "$ID" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecid(){ ( cd "$ID" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

[ "$( ecid )" = 0 ] && did | grep -q 'regressions="0"' \
    && ok "reuse-connectivity idiom: clean tree → exit 0 (no duplicate yet)" \
    || { no "reuse-connectivity idiom: clean tree should be clean (exit $( ecid ))"; did | tr '>' '\n' | grep '<r '; }

cat > "$ID/src/tank.cpp" <<'EOF'
namespace supply
{
enum class TankState : unsigned char { Empty, Reserve, Cruise, Brimming };
TankState tankStateFor( float litres )
{
    if( litres <  20.0f ) return TankState::Empty;
    if( litres <  90.0f ) return TankState::Reserve;
    if( litres < 140.0f ) return TankState::Cruise;
    return TankState::Brimming;
}
}
EOF
OID="$( did )"
if [ "$( ecid )" = 0 ]; then ok "reuse-connectivity idiom: idiom collision on a reused helper does NOT gate (exit 0)"; else no "reuse-connectivity idiom: should stay exit 0, an idiom collision must demote not gate (got $( ecid ))"; fi
IDROW="$( printf '%s' "$OID" | tr '<' '\n' | grep '^r kind="new-clone-of-reused-helper"' )"
printf '%s' "$IDROW" | grep -q . \
    && ok "reuse-connectivity idiom: new-clone-of-reused-helper still PRINTS (demoted, not deleted)" \
    || { no "reuse-connectivity idiom: new-clone-of-reused-helper row missing entirely (demotion must still print)"; printf '%s\n' "$OID" | tr '>' '\n' | grep '<r '; }
printf '%s' "$IDROW" | grep -q 'sev="minor"' \
    && ok "reuse-connectivity idiom: row carries sev=\"minor\" (demoted)" \
    || no "reuse-connectivity idiom: row is not sev=\"minor\": $IDROW"
printf '%s' "$IDROW" | grep -q 'idiom="threshold-ladder"' \
    && ok "reuse-connectivity idiom: row names its idiom (threshold-ladder)" \
    || no "reuse-connectivity idiom: row does not name idiom=\"threshold-ladder\": $IDROW"
printf '%s' "$IDROW" | grep -q 'gating="1"' \
    && no "reuse-connectivity idiom: demoted row still carries gating=\"1\"" \
    || ok "reuse-connectivity idiom: demoted row carries no gating=\"1\""
if [ "$OID" = "$( did )" ]; then ok "reuse-connectivity idiom: delta byte-identical run-to-run (deterministic)"; else no "reuse-connectivity idiom: non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OID" | xmllint --noout - 2>/dev/null; then ok "reuse-connectivity idiom: xml well-formed"; else no "reuse-connectivity idiom: xml malformed"; fi
fi

# 3d) ALL-TEST-SCRIPT SKIP on a reused helper: mcp_call() (a shell test-harness helper, fan-in=3 via 3
#     baseline callers, ALL under test/) is committed. The working tree adds a sibling gate script whose
#     helper is a Type-1/2 clone of mcp_call() — the house "every sibling gate repeats mcp_call()-style
#     boilerplate" convention `duplication` already exempts (isTestScriptPath). Because every member of the
#     group is a test script, the fix requires the row to be SKIPPED OUTRIGHT (never printed, not even
#     minor) — the same continue `reportNewClones` takes, reused rather than re-implemented.
TS="$WORK/testscript"; mkdir -p "$TS/test"
( cd "$TS" && git init -q && git config user.email t@t && git config user.name t )
cat > "$TS/test/hcheck.sh" <<'EOF'
#!/usr/bin/env bash
mcp_call() {
    local a="$1"
    local n=0
    n=$(( n + 1 ))
    n=$(( n + 2 ))
    n=$(( n + 3 ))
    n=$(( n + 4 ))
    n=$(( n + 5 ))
    n=$(( n + 6 ))
    echo "$a:$n"
}
siteA() { mcp_call "x"; }
siteB() { mcp_call "y"; }
siteC() { mcp_call "z"; }
siteA; siteB; siteC
EOF
( cd "$TS" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
dts(){  ( cd "$TS" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ects(){ ( cd "$TS" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

[ "$( ects )" = 0 ] && dts | grep -q 'regressions="0"' \
    && ok "reuse-connectivity test-script: clean tree → exit 0 (no duplicate yet)" \
    || { no "reuse-connectivity test-script: clean tree should be clean (exit $( ects ))"; dts | tr '>' '\n' | grep '<r '; }

cat > "$TS/test/dupcheck.sh" <<'EOF'
#!/usr/bin/env bash
mcp_call_dup() {
    local a="$1"
    local n=0
    n=$(( n + 1 ))
    n=$(( n + 2 ))
    n=$(( n + 3 ))
    n=$(( n + 4 ))
    n=$(( n + 5 ))
    n=$(( n + 6 ))
    echo "$a:$n"
}
EOF
OTS="$( dts )"
if [ "$( ects )" = 0 ]; then ok "reuse-connectivity test-script: all-test-script clone of a reused helper does NOT gate (exit 0)"; else no "reuse-connectivity test-script: should stay exit 0, all-test-script groups are skipped outright (got $( ects ))"; fi
printf '%s' "$OTS" | grep -q 'kind="new-clone-of-reused-helper"' \
    && no "reuse-connectivity test-script: new-clone-of-reused-helper fired on an all-test-script group (should be skipped outright)" \
    || ok "reuse-connectivity test-script: new-clone-of-reused-helper is SKIPPED (no row at all, not even minor)"
printf '%s' "$OTS" | grep -q 'regressions="0"' \
    && ok "reuse-connectivity test-script: regressions=\"0\" (the skip drops the row, not just its severity)" \
    || { no "reuse-connectivity test-script: expected regressions=\"0\""; printf '%s\n' "$OTS" | tr '>' '\n' | grep '<r '; }
if [ "$OTS" = "$( dts )" ]; then ok "reuse-connectivity test-script: delta byte-identical run-to-run (deterministic)"; else no "reuse-connectivity test-script: non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OTS" | xmllint --noout - 2>/dev/null; then ok "reuse-connectivity test-script: xml well-formed"; else no "reuse-connectivity test-script: xml malformed"; fi
fi

# ── 4) SELF vs AMBIENT CHURN (B10.2d, signal-to-noise round 2) ─────────────────────────────────────────────
#   A symbol that already clears the three short-horizon-churn gates above gets a further split: does THIS
#   uncommitted diff modify a pre-existing line that was itself last committed inside the churn window (SELF —
#   genuine thrash, stays major, facet churn="self"), or does it only ADD new lines / touch lines that predate
#   the window (AMBIENT — the file is hot but this edit isn't touching hot content) → sev="minor",
#   facet churn="ambient". Three sub-cases: 4a in-place edit of a recently-committed line (self, control — the
#   existing hot()-flagged assertions in §2 above already cover this shape, so this control just names the
#   facet); 4b a pure line-count-growing insertion into an already window-churned function (ambient: adds
#   lines); 4c an edit that touches a line whose real last commit predates the window even though the FILE
#   is churn-hot from unrelated recent activity (ambient: touches cold lines — needs a backdated commit via
#   GIT_AUTHOR_DATE/GIT_COMMITTER_DATE, same idiom rankbycheck.sh/ownerscheck.sh already use).
commit_at(){ local dir="$1" ts="$2" msg="$3"; git -C "$dir" add -A >/dev/null 2>&1
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_AUTHOR_DATE="$ts" \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_COMMITTER_DATE="$ts" \
        git -C "$dir" commit -q -m "$msg" >/dev/null 2>&1; }
NOW="$( date -u +%Y-%m-%dT%H:%M:%S )"

# 4a) SELF (control): in-place rewrite of a line committed in the last window commit, edited again now.
SF="$WORK/selfchurn"; mkdir -p "$SF/src"
( cd "$SF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){ return 1; }\nint drive(){ return hot(); }\n' > "$SF/src/f.cpp"
commit_at "$SF" "$NOW" c1
printf 'int hot(){ return 2; }\nint drive(){ return hot(); }\n' > "$SF/src/f.cpp"
commit_at "$SF" "$NOW" c2
printf 'int hot(){ return 3; }\nint drive(){ return hot(); }\n' > "$SF/src/f.cpp"
OSF="$( cd "$SF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OSF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*churn="self"' \
    && ok "self/ambient churn: in-place edit of a recently-committed line → facet churn=\"self\"" \
    || { no "self/ambient churn: expected churn=\"self\" on hot()"; printf '%s\n' "$OSF" | tr '>' '\n' | grep '<r '; }
# DIAL 2026-09-10 — this assertion is INVERTED on purpose, and the inversion is the finding: hot() here was
# rewritten by exactly ONE in-window commit (c2), which is a touch, not thrash. SELF names that the edit lands
# on hot content and stops there; what gates is 2 or more committed in-window rewrites (§2 above, and
# test/qddialscheck.sh §1 measures the pair side by side). Over twelve LANDED commits of this repo the old
# "SELF gates" rule supplied 135 of 171 gating rows at 0% precision (audit Q1 §2b/§2d).
printf '%s' "$OSF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*sev="minor"' \
    && ok "self/ambient churn: ONE in-window rewrite is informational — sev=\"minor\", facet still self" \
    || { no "self/ambient churn: a single in-window rewrite must not gate"; printf '%s\n' "$OSF" | tr '>' '\n' | grep '<r '; }
ESF="$( cd "$SF" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
if [ "$ESF" = 0 ]; then ok "self/ambient churn: a self-only finding does not gate exit 2"; else no "self/ambient churn: self-only run should exit 0 (got $ESF)"; fi

# 4b) AMBIENT — adds lines: the working-tree edit only INSERTS a new statement, touching no existing line.
AF="$WORK/ambientadd"; mkdir -p "$AF/src"
( cd "$AF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){\n    int y=1;\n    return y;\n}\nint drive(){ return hot(); }\n' > "$AF/src/f.cpp"
commit_at "$AF" "$NOW" c1
printf 'int hot(){\n    int y=9;\n    return y;\n}\nint drive(){ return hot(); }\n' > "$AF/src/f.cpp"
commit_at "$AF" "$NOW" c2
printf 'int hot(){\n    int y=9;\n    int z=2;\n    return y;\n}\nint drive(){ return hot(); }\n' > "$AF/src/f.cpp"
OAF="$( cd "$AF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
EAF="$( cd "$AF" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
printf '%s' "$OAF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*sev="minor"[^/]*churn="ambient"' \
    && ok "self/ambient churn: pure line-insertion edit → sev=\"minor\" churn=\"ambient\" (adds lines)" \
    || { no "self/ambient churn: pure-insert edit not downgraded to ambient"; printf '%s\n' "$OAF" | tr '>' '\n' | grep '<r '; }
if [ "$EAF" = 0 ]; then ok "self/ambient churn: ambient-only finding does not gate exit 2"; else no "self/ambient churn: ambient-only run should exit 0 (got $EAF)"; fi

# 4c) AMBIENT — touches a cold line: the file is churn-hot (2 recent commits) via an UNRELATED line, but the
#     working tree edits a line whose real last commit is a backdated, out-of-window commit.
CF="$WORK/ambientcold"; mkdir -p "$CF/src"
( cd "$CF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){\n    int a=1;\n    int b=2;\n    return a+b;\n}\nint drive(){ return hot(); }\n' > "$CF/src/f.cpp"
commit_at "$CF" "2026-01-01T00:00:00" "c1 backdated (>14d before HEAD)"
printf 'int hot(){\n    int a=9;\n    int b=2;\n    return a+b;\n}\nint drive(){ return hot(); }\n' > "$CF/src/f.cpp"
commit_at "$CF" "$NOW" "c2 recent (touches a — the committed-thrash evidence)"
printf 'int hot(){\n    int a=9;\n    int b=2;\n    return a+b;\n}\nint drive(){ return hot()+0; }\n' > "$CF/src/f.cpp"
commit_at "$CF" "$NOW" "c3 recent (2nd in-window file commit, does not touch hot())"
printf 'int hot(){\n    int a=9;\n    int b=20;\n    return a+b;\n}\nint drive(){ return hot()+0; }\n' > "$CF/src/f.cpp"
OCF="$( cd "$CF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OCF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*sev="minor"[^/]*churn="ambient"' \
    && ok "self/ambient churn: edit of a line last committed outside the window → ambient (touches cold lines)" \
    || { no "self/ambient churn: cold-line edit not downgraded to ambient"; printf '%s\n' "$OCF" | tr '>' '\n' | grep '<r '; }
[ "$OCF" = "$( cd "$CF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "self/ambient churn: delta byte-identical run-to-run" || no "self/ambient churn: non-deterministic delta"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OSF" | xmllint --noout - 2>/dev/null && printf '%s' "$OAF" | xmllint --noout - 2>/dev/null && printf '%s' "$OCF" | xmllint --noout - 2>/dev/null \
        && ok "self/ambient churn: xml well-formed (self + both ambient outputs)" || no "self/ambient churn: xml malformed"
fi


# ── 5) ERROR-MASKING, WIDENED: log-only and rethrow-only (the 0.6.5 masking round) ───────────────────────
#   One fixture per language, the same shape as §1: every function exists at the baseline with a handler
#   that USES the error, and the working tree rewrites some of them into the two widened shapes while the
#   rest become the near-misses the shapes must refuse (the error named in the log, a narrow except, a
#   logger.exception, a wrapped re-throw, a re-throw that is not the only handler). A row fires only on the
#   positive functions. Python is the one language whose two shapes GATE (kHandlerShapeGates, measured
#   precision in docs/EVALS.md); everywhere else the same row is sev="minor" and the exit stays 0.
qd_pair(){   # DIR FILE BASELINE EDIT → QD_OUT (the delta document) and QD_RC (its exit code)
    local d="$WORK/$1"
    mkdir -p "$d"
    ( cd "$d" && git init -q && git config user.email t@t && git config user.name t )
    printf '%s' "$3" > "$d/$2"
    ( cd "$d" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
    printf '%s' "$4" > "$d/$2"
    cmp -s <( printf '%s' "$3" ) "$d/$2" && no "$1: the edit did not take (fixture identical to its baseline)"
    QD_OUT="$( cd "$d" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
    QD_RC=$?
}
qd_row(){ printf '%s' "$QD_OUT" | tr '>' '\n' | grep "<r kind=\"$1\" sym=\"$2\""; }   # KIND SYM → the row, or nothing
qd_has(){   # LABEL KIND SYM WANT(gating|minor|new-symbol)
    local row; row="$( qd_row "$2" "$3" )"
    if [ -z "$row" ]; then no "$1: no $2 row on $3"; printf '%s\n' "$QD_OUT" | tr '>' '\n' | grep '<r '; return; fi
    case "$4" in
        gating)     printf '%s' "$row" | grep -q 'gating="1"' && ! printf '%s' "$row" | grep -q 'sev="minor"' \
                        && ok "$1: $2 row on $3, gating" || no "$1: $2 row on $3 should gate: $row" ;;
        minor)      printf '%s' "$row" | grep -q 'sev="minor"' && ! printf '%s' "$row" | grep -q 'gating=' \
                        && ok "$1: $2 row on $3, sev=minor (report-only)" || no "$1: $2 row on $3 should be report-only: $row" ;;
        new-symbol) printf '%s' "$row" | grep -q 'origin="new-symbol"' && ! printf '%s' "$row" | grep -q 'gating=' \
                        && ok "$1: $2 row on $3, origin=new-symbol, never gating" || no "$1: $2 row on $3 should be new-symbol: $row" ;;
    esac
}
qd_none(){  # LABEL KIND SYM WHY
    if [ -z "$( qd_row "$2" "$3" )" ]; then ok "$1: no $2 row on $3 ($4)"; else no "$1: $2 row on $3 is a false positive ($4): $( qd_row "$2" "$3" )"; fi
}

# 5a) Python — both shapes gate.
PYB='import logging
log = logging.getLogger(__name__)

def swallow():
    try:
        risky()
    except Exception as e:
        recover(e)

def rethrow():
    try:
        risky()
    except ValueError as e:
        recover(e)

def named():
    try:
        risky()
    except Exception as e:
        recover(e)

def narrow():
    try:
        risky()
    except ValueError as e:
        recover(e)

def tb():
    try:
        risky()
    except Exception as e:
        recover(e)

def wrapped():
    try:
        risky()
    except Exception as e:
        recover(e)

def routed():
    try:
        risky()
    except KeyError as e:
        recover(e)
    except Exception as e:
        recover(e)

def risky():
    return 1

def recover(e):
    return e
'
PYE='import logging
log = logging.getLogger(__name__)

def swallow():
    try:
        risky()
    except Exception:
        log.warning("failed")

def rethrow():
    try:
        risky()
    except ValueError:
        raise

def named():
    try:
        risky()
    except Exception as e:
        log.warning(f"failed: {e}")

def narrow():
    try:
        risky()
    except ValueError:
        print("bad value, using the default")

def tb():
    try:
        risky()
    except Exception:
        log.exception("failed")

def wrapped():
    try:
        risky()
    except Exception as e:
        raise RuntimeError("wrapped") from e

def routed():
    try:
        risky()
    except KeyError:
        raise
    except Exception as e:
        recover(e)

def risky():
    return 1

def recover(e):
    return e
'
qd_pair mask_py a.py "$PYB" "$PYE"
qd_has  "masking (python)" error-masking swallow gating
qd_has  "masking (python)" error-masking rethrow gating
qd_none "masking (python)" error-masking named   "the log names the error"
qd_none "masking (python)" error-masking narrow  "a narrow except states its cause in its type"
qd_none "masking (python)" error-masking tb      "logger.exception writes the traceback"
qd_none "masking (python)" error-masking wrapped "a wrapped re-raise is not unchanged"
qd_none "masking (python)" error-masking routed  "a re-raise ahead of a broader sibling routes, it is not redundant"
[ "$QD_RC" = 2 ] && ok "masking (python): a new log-only / rethrow-only construct in an existing symbol exits 2" \
                 || no "masking (python): should exit 2 (got $QD_RC)"

# 5b) TypeScript — the same two shapes, report-only.
TSB='export function swallow(): void { try { risky(); } catch (e) { recover(e); } }
export function rethrow(): number { try { return risky(); } catch (e) { return recover(e); } }
export function named(): number { const n = 2; try { return risky() * n; } catch (e) { recover(e); } return n; }
export function wrapped(): void { try { risky(); } catch (e) { recover(e); } }
function risky(): number { return 1; }
function recover(e: unknown): number { return 0; }
export function keepAlive(): number { return recover(0); }
'
TSE='export function swallow(): void { try { risky(); } catch (e) { console.error("failed"); } }
export function rethrow(): number { try { return risky(); } catch (e) { throw e; } }
export function named(): number { const n = 2; try { return risky() * n; } catch (e) { console.error(`failed ${e}`); } return n; }
export function wrapped(): void { try { risky(); } catch (e) { throw new Error("wrapped", { cause: e }); } }
function risky(): number { return 1; }
function recover(e: unknown): number { return 0; }
export function keepAlive(): number { return recover(0); }
'
qd_pair mask_ts a.ts "$TSB" "$TSE"
qd_has  "masking (ts)" error-masking swallow minor
qd_has  "masking (ts)" error-masking rethrow minor
qd_none "masking (ts)" error-masking named   "the template names the error"
qd_none "masking (ts)" error-masking wrapped "a wrapped throw is not unchanged"
if [ "$QD_RC" = 0 ]; then ok "masking (ts): report-only rows never fire exit 2"; else no "masking (ts): should exit 0 (got $QD_RC)"; fi
if [ "$QD_OUT" = "$( cd "$WORK/mask_ts" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ]; then ok "masking (ts): byte-identical run-to-run"; else no "masking (ts): non-deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$QD_OUT" | xmllint --noout - 2>/dev/null; then ok "masking (ts): xml well-formed"; else no "masking (ts): xml malformed"; fi
fi
# The full legend defines the report-only sev="minor" exactly when such a row is present.
( cd "$WORK/mask_ts" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null ) | grep -q 'widened shape that does not gate' \
    && ok "masking (ts): the full legend explains a report-only error-masking row" \
    || no "masking (ts): the full legend does not define the report-only error-masking row"

# 5c) Java / C# / Kotlin / Ruby / Go / C++ — one positive and one near-miss each, all report-only.
qd_pair mask_java A.java \
'class A { void swallow() { try { risky(); } catch (Exception e) { recover(e); } }
 void named() { try { risky(); } catch (Exception e) { recover(e); } }
 void risky() {} }
' \
'class A { void swallow() { try { risky(); } catch (Exception e) { LOG.warn("failed"); } }
 void named() { try { risky(); } catch (Exception e) { LOG.warn("failed " + e.getMessage()); } }
 void risky() {} }
'
qd_has  "masking (java)" error-masking swallow minor
qd_none "masking (java)" error-masking named "the log reads the error"

qd_pair mask_cs A.cs \
'class A { void Swallow() { try { Risky(); } catch (Exception ex) { Recover(ex); } }
 void Filtered() { try { Risky(); } catch (Exception ex) { Recover(ex); } }
 void Risky() {} }
' \
'class A { void Swallow() { try { Risky(); } catch (Exception) { Console.WriteLine("failed"); } }
 void Filtered() { try { Risky(); } catch (Exception ex) when (ex.HResult == 1) { Console.WriteLine("failed"); } }
 void Risky() {} }
'
qd_has  "masking (c#)" error-masking Swallow minor
qd_none "masking (c#)" error-masking Filtered "a when-filtered handler is conditional"

qd_pair mask_kt a.kt \
'fun swallow() { try { risky() } catch (e: Exception) { recover(e) } }
fun rethrow() { try { risky() } catch (e: IOException) { recover(e) } }
fun risky() {}
' \
'fun swallow() { try { risky() } catch (e: Exception) { log.warn("failed") } }
fun rethrow() { try { risky() } catch (e: IOException) { throw e } }
fun risky() {}
'
qd_has  "masking (kotlin)" error-masking swallow minor
qd_has  "masking (kotlin)" error-masking rethrow minor

qd_pair mask_rb a.rb \
'def swallow
  risky
rescue => e
  recover(e)
end

def narrow
  risky
rescue IOError => e
  recover(e)
end

def risky; end
' \
'def swallow
  risky
rescue => e
  logger.warn("failed")
end

def narrow
  risky
rescue IOError
  puts "no file"
end

def risky; end
'
qd_has  "masking (ruby)" error-masking swallow minor
qd_none "masking (ruby)" error-masking narrow "a narrow rescue states its cause in its class"

qd_pair mask_go a.go \
'package p

import "log"

func swallow() {
	err := risky()
	if err != nil {
		handle(err)
	}
}

func fatal() {
	err := risky()
	if err != nil {
		handle(err)
	}
}

func risky() error { return nil }
' \
'package p

import "log"

func swallow() {
	err := risky()
	if err != nil {
		log.Printf("failed")
	}
}

func fatal() {
	err := risky()
	if err != nil {
		log.Fatal("failed")
	}
}

func risky() error { return nil }
'
qd_has  "masking (go)" error-masking swallow minor
qd_none "masking (go)" error-masking fatal "log.Fatal ends the program, it does not continue"

qd_pair mask_cpp a.cpp \
'void risky();
void rethrow() { try { risky(); } catch( ... ) { recover(); } }
void routed() { try { risky(); } catch( const Oops& ) { recover(); } catch( ... ) { recover(); } }
' \
'void risky();
void rethrow() { try { risky(); } catch( ... ) { throw; } }
void routed() { try { risky(); } catch( const Oops& ) { throw; } catch( ... ) { recover(); } }
'
qd_has  "masking (c++)" error-masking rethrow minor
qd_none "masking (c++)" error-masking routed "a re-throw ahead of a catch-all sibling routes, it is not redundant"

# ── 5b) EMPTY ERROR BRANCHES in Go and Rust (QD-K6E-GO / QD-K6E-RUST) + Rust log-only + C++ stream logging (K6L-CXX)
#   Go: `if err != nil {}` (comment-only counts), err bound from a CALL in the if's initializer or the statement right
#   before it; Rust: `if let Err(..) = f() {}` and `Err(..) => {}` / `=> ()`. Both GATE, as Python's `except: pass` does.
#   Rust log-only: an Err arm / if-let Err whose body only prints or logs and never names the binding — sev=minor.
#   C++ log-only: a catch whose body is only `std::cerr << …`, `LOG( x ) << …`, `fprintf( stderr, … )`, `fputs( …, stderr )`
#   — sev=minor. Every negative arm first COUNTS the sites it judges (ripwire's own --match over the edited fixture) and
#   FAILS on zero, so a fixture that stopped parsing as the shape cannot pass vacuously.
premise(){   # LABEL DIR SYM QUERY → FAIL unless the query hits at least once inside SYM
    local n; n="$( cd "$WORK/$2" && "$BIN" . --match="$4" --no-cache 2>/dev/null | tr '>' '\n' | grep -c "<m p=[^ ]* in=\"$3\"" )"
    if [ "${n:-0}" -gt 0 ]; then ok "$1: premise — $n site(s) judged in $3"; else no "$1: premise — 0 sites in $3 (the negative arm is vacuous)"; fi
}
GOB='package p

import (
	"log"
	"os"
)

func initEmpty() { touch() }
func prevEmpty() { touch() }
func retErr() error { touch(); return nil }
func logged() { touch() }
func paramErr(err error) { touch() }
func discard() { touch() }
func elseBranch() { touch() }
func callFirst() { touch() }
func callSecond() { touch() }
func multiInit(savedErr error, items []int) { touch() }
func multiPrev(savedErr error, items []int) { touch() }
func wrongPosInit(savedErr error) { touch() }
func wrongPosPrev(savedErr error) { touch() }

func risky() error { return nil }
func touch() { log.Print(os.Args) }
'
GOE='package p

import (
	"log"
	"os"
)

func initEmpty() {
	touch()
	if _, err := os.Stat("."); err != nil {
	}
}
func prevEmpty() {
	touch()
	err := risky()
	if err != nil {
		// ignored
	}
}
func retErr() error {
	touch()
	if err := risky(); err != nil {
		return err
	}
	return nil
}
func logged() {
	touch()
	if err := risky(); err != nil {
		log.Printf("%v", err)
	}
}
func paramErr(err error) {
	touch()
	if err != nil {
	}
}
func discard() {
	touch()
	defer func() { _ = recover() }()
}
func elseBranch() {
	touch()
	if err := risky(); err != nil {
	} else {
		touch()
	}
}
func callFirst() {
	touch()
	if err, n := risky(), 3; err != nil {
	}
}
func callSecond() {
	touch()
	n, err := 3, risky()
	if err != nil {
	}
}
func multiInit(savedErr error, items []int) {
	touch()
	if err, _ := savedErr, len(items); err != nil {
	}
}
func multiPrev(savedErr error, items []int) {
	touch()
	err, _ := savedErr, len(items)
	if err != nil {
	}
}
func wrongPosInit(savedErr error) {
	touch()
	if err, n := savedErr, risky(); err != nil {
	}
}
func wrongPosPrev(savedErr error) {
	touch()
	n, err := risky(), savedErr
	if err != nil {
	}
}

func risky() error { return nil }
func touch() { log.Print(os.Args) }
'
qd_pair empty_go a.go "$GOB" "$GOE"
qd_has  "empty (go)" error-masking initEmpty gating
qd_has  "empty (go)" error-masking prevEmpty gating
qd_has  "empty (go)" error-masking callFirst gating    # err, n := f(), 3 — err IS the call's result
qd_has  "empty (go)" error-masking callSecond gating   # n, err := 3, f()
for s in retErr logged paramErr elseBranch; do premise "empty (go)" empty_go "$s" '(binary_expression right: (nil)) @m'; done
premise "empty (go)" empty_go discard '(assignment_statement left: (expression_list (identifier) @m))'
qd_none "empty (go)" error-masking retErr     "the branch returns the error"
qd_none "empty (go)" error-masking logged     "the branch logs the error by name"
qd_none "empty (go)" error-masking paramErr   "err is a parameter, not a call result here"
qd_none "empty (go)" error-masking discard    "_ = recover() is out of scope"
qd_none "empty (go)" error-masking elseBranch "an if/else is not an error branch alone"
# CR #632 4556210611: a multi-value right-hand side binds err to the expression IN ITS POSITION, not to a call elsewhere
for s in multiInit multiPrev wrongPosInit wrongPosPrev; do premise "empty (go)" empty_go "$s" '(expression_list (identifier) (_)) @m'; done
qd_none "empty (go)" error-masking multiInit    "err, _ := savedErr, len(items) binds err to a variable, not a call"
qd_none "empty (go)" error-masking multiPrev    "the same multi-value binding in the statement before the if"
qd_none "empty (go)" error-masking wrongPosInit "err, n := savedErr, f() — the call feeds n, not err"
qd_none "empty (go)" error-masking wrongPosPrev "n, err := f(), savedErr — the call feeds n, not err"
if [ "$QD_RC" = 2 ]; then ok "empty (go): the gating rows fire exit 2"; else no "empty (go): should exit 2 (got $QD_RC)"; fi

RSB='use std::fmt::Write;

fn touch() {}
pub fn iflet_empty() { touch(); }
pub fn arm_empty() { touch(); }
pub fn arm_unit() { touch(); }
pub fn log_only() { touch(); }
pub fn log_arm() { touch(); }
pub fn ret_err() -> Result<(), std::io::Error> { touch(); Ok(()) }
pub fn write_char(buf: &mut String) { touch(); }
pub fn names_e() { touch(); }
pub fn variant_log() { touch(); }
pub fn or_log() { touch(); }
pub fn at_log() { touch(); }
pub fn iflet_variant_log() { touch(); }
pub fn ref_named() { touch(); }
pub fn ref_log() { touch(); }
pub fn guard_unit() { touch(); }
pub fn guard_block() { touch(); }
pub fn chain_empty() { touch(); }
'
RSE='use std::fmt::Write;

fn touch() {}
pub fn iflet_empty() {
    touch();
    if let Err(_) = std::fs::metadata(".") {
    }
}
pub fn arm_empty() {
    touch();
    match std::fs::metadata(".") { Ok(_) => {}, Err(_frame) => {} }
}
pub fn arm_unit() {
    touch();
    match std::fs::metadata(".") { Ok(_) => touch(), Err(_) => () }
}
pub fn log_only() {
    touch();
    if let Err(_) = std::fs::metadata(".") {
        eprintln!("ignored");
    }
}
pub fn log_arm() {
    touch();
    match std::fs::metadata(".") { Ok(_) => touch(), Err(_e) => log::warn!("failed") }
}
pub fn ret_err() -> Result<(), std::io::Error> {
    touch();
    match std::fs::metadata(".") { Ok(_) => Ok(()), Err(e) => return Err(e.into()) }
}
pub fn write_char(buf: &mut String) {
    touch();
    let _ = buf.write_char(char::from(10));
}
pub fn names_e() {
    touch();
    match std::fs::metadata(".") { Ok(_) => touch(), Err(e) => eprintln!("failed: {e}") }
}
pub fn variant_log() {
    touch();
    match load() { Ok(_) => touch(), Err(MyError::NotFound) => eprintln!("missing"), Err(e) => panic!("{e}") }
}
pub fn or_log() {
    touch();
    match load() { Ok(_) => touch(), Err(MyError::A | MyError::B) => eprintln!("skipped"), Err(e) => panic!("{e}") }
}
pub fn at_log() {
    touch();
    match load() { Ok(_) => touch(), Err(e @ MyError::Busy) => eprintln!("busy"), Err(e) => panic!("{e}") }
}
pub fn iflet_variant_log() {
    touch();
    if let Err(MyError::NotFound) = load() {
        eprintln!("missing");
    }
}
pub fn ref_named() {
    touch();
    match std::fs::metadata(".") { Ok(_) => touch(), Err(ref e) => eprintln!("failed: {e}") }
}
pub fn ref_log() {
    touch();
    match std::fs::metadata(".") { Ok(_) => touch(), Err(ref mut _e) => log::warn!("failed") }
}
pub fn guard_unit() -> Result<(), MyError> {
    touch();
    match load() { Ok(_) => (), Err(e) if recover(&e) => (), Err(e) => return Err(e) }
}
pub fn guard_block() {
    touch();
    match load() { Ok(_) => touch(), Err(e) if recover(&e) => {}, Err(e) => panic!("{e}") }
}
pub fn chain_empty() {
    touch();
    if let Err(e) = load() && recover(&e) {
    }
}
'
qd_pair empty_rs a.rs "$RSB" "$RSE"
qd_has  "empty (rust)" error-masking iflet_empty gating
qd_has  "empty (rust)" error-masking arm_empty gating
qd_has  "empty (rust)" error-masking arm_unit gating
qd_has  "log-only (rust)" error-masking log_only minor
qd_has  "log-only (rust)" error-masking log_arm minor
for s in ret_err names_e; do premise "empty (rust)" empty_rs "$s" '(tuple_struct_pattern) @m'; done
premise "empty (rust)" empty_rs write_char '(let_declaration) @m'
qd_none "empty (rust)" error-masking ret_err    "the arm returns the error"
qd_none "empty (rust)" error-masking write_char "let _ = fallible(); is out of scope"
qd_none "empty (rust)" error-masking names_e    "the arm logs the error by name, inside the format string"
qd_has  "log-only (rust)" error-masking ref_log minor   # Err(ref mut _e): the wrappers still bind the whole error side
# CR #632 4556210583: an Err pattern that names ONE variant (or a few) is not a broad handler
for s in variant_log or_log at_log iflet_variant_log ref_named guard_unit guard_block chain_empty; do premise "rust variants" empty_rs "$s" '(tuple_struct_pattern) @m'; done
qd_none "log-only (rust)" error-masking variant_log       "Err(MyError::NotFound) handles one variant"
qd_none "log-only (rust)" error-masking or_log            "Err(A | B) handles two variants"
qd_none "log-only (rust)" error-masking at_log            "Err(e @ MyError::Busy) handles one variant"
qd_none "log-only (rust)" error-masking iflet_variant_log "if let Err(MyError::NotFound) handles one variant"
qd_none "log-only (rust)" error-masking ref_named         "Err(ref e) logs the error by name"
# CR #632 4556210784: a match guard is where the error is handled
qd_none "empty (rust)" error-masking guard_unit  "Err(e) if recover(&e) => () — the guard handles it"
qd_none "empty (rust)" error-masking guard_block "Err(e) if recover(&e) => {} — the guard handles it"
qd_none "empty (rust)" error-masking chain_empty "if let Err(e) = f() && recover(&e) {} — the chain's condition handles it"

CXB='#include <cstdio>
#include <iostream>
#include <sstream>
void risky();
void stream_log() { risky(); }
void macro_log() { risky(); }
void fprintf_log() { risky(); }
void fputs_log() { risky(); }
void log_rethrow() { risky(); }
void log_return_value() { risky(); }
void oss_thrown() { risky(); }
void oss_only() { risky(); }
'
CXE='#include <cstdio>
#include <iostream>
#include <sstream>
void risky();
void stream_log() { try { risky(); } catch( ... ) { std::cerr << "ignored" << std::endl; } }
void macro_log() { try { risky(); } catch( ... ) { LOG( ERROR ) << "ignored"; } }
void fprintf_log() { try { risky(); } catch( ... ) { fprintf( stderr, "ignored\n" ); } }
void fputs_log() { try { risky(); } catch( ... ) { fputs( "ignored\n", stderr ); } }
void log_rethrow() { try { risky(); } catch( ... ) { std::cerr << "failed" << std::endl; throw; } }
int log_return_value() { try { risky(); } catch( ... ) { std::cerr << "failed\n"; return -1; } return 0; }
void oss_thrown() { try { risky(); } catch( ... ) { std::ostringstream os; os << "failed"; throw std::runtime_error( os.str() ); } }
void oss_only() { try { risky(); } catch( ... ) { trace_buffer << "failed"; } }
'
qd_pair log_cpp a.cpp "$CXB" "$CXE"
for s in stream_log macro_log fprintf_log fputs_log; do qd_has "log-only (c++)" error-masking "$s" minor; done
for s in log_rethrow log_return_value oss_thrown oss_only; do premise "log-only (c++)" log_cpp "$s" '(catch_clause) @m'; done
qd_none "log-only (c++)" error-masking log_rethrow      "it logs and re-throws"
qd_none "log-only (c++)" error-masking log_return_value "it logs and returns an error value"
qd_none "log-only (c++)" error-masking oss_thrown       "the << builds an exception message that is thrown"
qd_none "log-only (c++)" error-masking oss_only         "a << into a non-console stream is not logging"
# the fixture's near-identical one-liners are duplication rows (those gate); no error-masking row may
if printf '%s' "$QD_OUT" | tr '>' '\n' | grep '<r kind="error-masking"' | grep -q 'gating='; then
    no "log-only (c++): an error-masking row gates"
else
    ok "log-only (c++): no error-masking row gates"
fi

# ── 6) PLACEHOLDER — the eleventh kind: a stub or TODO the change ADDED ───────────────────────────────────
#   Never gates: every row is origin="new-symbol" by construction, including one that lands in a symbol that
#   existed at the baseline (other() below). The near-misses are the ones the kind must not count: a TODO
#   naming an issue, an @abstractmethod raise, a bare NotImplementedError as a METHOD body (the abstract-by-
#   convention interface), a guard `raise NotImplementedError( "... not supported" )`, a TODO-ARM label, and a
#   pre-existing TODO in an untouched function.
PHB='import abc

def other():
    return 1

def untouched():
    # TODO: already here before the change
    return 2

class Base(abc.ABC):
    def keep(self):
        return 0
'
PHE='import abc

def other():
    # TODO: wire this up
    return 1

def untouched():
    # TODO: already here before the change
    return 2

def later():
    raise NotImplementedError

def tracked():
    # TODO(#123): tracked upstream
    return 3

def guard(x):
    if x:
        raise NotImplementedError("sharding is not supported")
    return x

def labelled():
    # TODO-ARM: a label, not a todo
    return 4

class Base(abc.ABC):
    def keep(self):
        return 0

    @abc.abstractmethod
    def area(self):
        raise NotImplementedError

    def perimeter(self):
        raise NotImplementedError
'
qd_pair stub_py a.py "$PHB" "$PHE"
qd_has  "placeholder (python)" placeholder other new-symbol
qd_has  "placeholder (python)" placeholder later new-symbol
qd_none "placeholder (python)" placeholder untouched "a TODO the change did not add"
qd_none "placeholder (python)" placeholder tracked   "the TODO names an issue"
qd_none "placeholder (python)" placeholder guard     "a guard for an unsupported case is not a stub"
qd_none "placeholder (python)" placeholder labelled  "TODO-ARM names something, it leaves nothing undone"
qd_none "placeholder (python)" placeholder area      "an @abstractmethod raise is a contract"
qd_none "placeholder (python)" placeholder perimeter "a bare NotImplementedError METHOD body is the abstract-by-convention interface"
if [ "$QD_RC" = 0 ]; then ok "placeholder (python): placeholder rows never gate (exit 0)"; else no "placeholder (python): should exit 0 (got $QD_RC)"; fi
if printf '%s' "$QD_OUT" | grep -q 'gating="0"'; then ok "placeholder (python): gating=0 on the header"; else no "placeholder (python): gating should be 0"; fi
( cd "$WORK/stub_py" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null ) | grep -q 'placeholder is new-symbol by construction' \
    && ok "placeholder (python): the full legend says why every placeholder row is new-symbol" \
    || no "placeholder (python): the full legend does not define the placeholder origin rule"

# 6b) the other spellings, one fixture each: every row new-symbol, exit 0.
qd_pair stub_rs a.rs 'fn keep() -> i32 { 1 }
' 'fn keep() -> i32 { 1 }
fn later() -> i32 { todo!() }
fn never() { unimplemented!("soon") }
'
qd_has "placeholder (rust)" placeholder later new-symbol
qd_has "placeholder (rust)" placeholder never new-symbol

qd_pair stub_ts a.ts 'export function keep(): number { return 1; }
' 'export function keep(): number { return 1; }
export function later(): number { throw new Error("Method not implemented."); }
export function guard(x: number): number { if (x) { throw new Error("negative input"); } return x; }
'
qd_has  "placeholder (ts)" placeholder later new-symbol
qd_none "placeholder (ts)" placeholder guard "a throw that says nothing about implementation"

qd_pair stub_cs A.cs 'class A { int Keep() { return 1; } }
' 'class A { int Keep() { return 1; }
 int Later() { throw new NotImplementedException(); }
 int Guard() { throw new NotSupportedException(); } }
'
qd_has  "placeholder (c#)" placeholder Later new-symbol
qd_none "placeholder (c#)" placeholder Guard "NotSupportedException is the deliberate refusal, not the stub"

qd_pair stub_kt a.kt 'fun keep(): Int = 1
' 'fun keep(): Int = 1
fun later(): Int { return TODO("wire it") }
'
qd_has "placeholder (kotlin)" placeholder later new-symbol

qd_pair stub_go a.go 'package p

func keep() int { return 1 }
' 'package p

func keep() int { return 1 }

func later() int { panic("not implemented") }

func guard(x int) int {
	if x < 0 {
		panic("negative")
	}
	return x
}
'
qd_has  "placeholder (go)" placeholder later new-symbol
qd_none "placeholder (go)" placeholder guard "a panic that says nothing about implementation"

qd_pair stub_java A.java 'class A { int keep() { return 1; } }
' 'class A { int keep() { return 1; }
 int later() { throw new UnsupportedOperationException("not implemented yet"); }
 java.util.List<Integer> frozen() { throw new UnsupportedOperationException(); } }
'
qd_has  "placeholder (java)" placeholder later new-symbol
qd_none "placeholder (java)" placeholder frozen "a bare UnsupportedOperationException is the immutable-collection refusal"

qd_pair stub_cpp a.cpp 'int keep() { return 1; }
' 'int keep() { return 1; }
int later() { throw std::logic_error( "not implemented" ); }
int never() { assert( false && "not implemented" ); return 0; }
int unreachable() { assert( false && "unreachable" ); return 0; }
'
qd_has  "placeholder (c++)" placeholder later new-symbol
qd_has  "placeholder (c++)" placeholder never new-symbol
qd_none "placeholder (c++)" placeholder unreachable "assert(false) for an unreachable path is not a stub"

# 6c) the kind costs no bytes where it has nothing to say: a diff that adds no stub and no TODO carries no
#     placeholder row and no placeholder attribute anywhere in the document.
qd_pair stub_none a.py 'def keep():
    return 1
' 'def keep():
    return 2
'
printf '%s' "$QD_OUT" | grep -q 'placeholder' && no "placeholder: a stub-free diff mentions placeholder: $QD_OUT" \
    || ok "placeholder: a stub-free diff carries no placeholder row or attribute"

# 5l) 0.6.6 review: a log RECEIVER is a whole word, not a substring. isLogReceiver matched "log" anywhere in the last
#     segment, so catalog / backlog / dialog read as loggers, and a Python handler that STORES the record
#     (`except Exception: store.catalog.write(x)`) became a gating log-only row. The words log / logger / logging (first
#     or last word of the segment, split on _ and camelCase) still qualify: logger.error and app_log.warning stay rows.
LRB='def save_catalog(store, x):
    try:
        risky()
    except Exception as e:
        recover(e)

def save_backlog(x):
    try:
        risky()
    except Exception as e:
        recover(e)

def save_logged(x):
    try:
        risky()
    except Exception as e:
        recover(e)

def save_app_log(x):
    try:
        risky()
    except Exception as e:
        recover(e)
'
LRE='def save_catalog(store, x):
    try:
        risky()
    except Exception:
        store.catalog.write(x)

def save_backlog(x):
    try:
        risky()
    except Exception:
        backlog.info(x)

def save_logged(x):
    try:
        risky()
    except Exception:
        logger.error("save failed")

def save_app_log(x):
    try:
        risky()
    except Exception:
        app_log.warning("save failed")
'
qd_pair logrecv m.py "$LRB" "$LRE"
qd_none "5l python" error-masking save_catalog "store.catalog.write stores the record: catalog is not a logger"
qd_none "5l python" error-masking save_backlog "backlog.info: backlog is not a logger"
qd_has  "5l python" error-masking save_logged gating
qd_has  "5l python" error-masking save_app_log gating

# 5l, second pass (train 22 delta review): the whole-word rule split only on _ - and camelCase, so real loggers fell out
# and Python's gating rows with them: a call before the last dot (logging.getLogger(__name__)), a sigil (@logger,
# this.#logger, $logger), an acronym run (HTTPLogger), a digit (logger2), a one-word name (mylog, vlog, structlog).
# Every listed spelling is a row again; the English words that end in "log" stay out.
lr_py_pos='logging.getLogger(__name__) logging.getLogger() get_logger() structlog.get_logger() self.get_logger() mylog logfire logbook logger2 vlog structlog logging.getLogger("service.worker)")'
lr_py_neg='catalog dialog backlog changelog analog technology blog getStore("logger(")'
LPB=''; LPE=''; n=0
for r in $lr_py_pos $lr_py_neg; do n=$(( n + 1 ))
    LPB="$LPB
def lr$n(x):
    try:
        risky()
    except Exception as e:
        recover(e)
"
    LPE="$LPE
def lr$n(x):
    try:
        risky()
    except Exception:
        $r.error(\"save failed\")
"
done
qd_pair logrecv2 m.py "$LPB" "$LPE"
n=0
for r in $lr_py_pos; do n=$(( n + 1 )); qd_has "5l python $r" error-masking "lr$n" gating; done
for r in $lr_py_neg; do n=$(( n + 1 )); qd_none "5l python $r" error-masking "lr$n" "$r is not a logger"; done
LRB=''; LRE=''; n=0
for r in @logger @log '$logger' @catalog; do n=$(( n + 1 ))
    LRB="$LRB
def lr$n(x)
  risky
rescue StandardError => e
  recover(e)
end
"
    LRE="$LRE
def lr$n(x)
  risky
rescue StandardError
  $r.error(\"save failed\")
end
"
done
qd_pair logrecvrb m.rb "$LRB" "$LRE"
qd_has "5l ruby @logger" error-masking lr1 minor; qd_has "5l ruby @log" error-masking lr2 minor; qd_has "5l ruby \$logger" error-masking lr3 minor
qd_none "5l ruby @catalog" error-masking lr4 "@catalog is not a logger"
LTB='class A {'; LTE='class A {'; n=0
for r in 'this.#logger' 'this.HTTPLogger' 'log4js.getLogger()' 'this.dialog'; do n=$(( n + 1 ))
    LTB="$LTB
  lr$n(): void { try { risky(); } catch (e) { recover(e); } }"
    LTE="$LTE
  lr$n(): void { try { risky(); } catch (e) { $r.error(\"save failed\"); } }"
done
qd_pair logrecvts m.ts "$LTB
}
" "$LTE
}
"
qd_has "5l ts this.#logger" error-masking lr1 minor; qd_has "5l ts this.HTTPLogger" error-masking lr2 minor; qd_has "5l ts log4js.getLogger()" error-masking lr3 minor
qd_none "5l ts this.dialog" error-masking lr4 "dialog is not a logger"
LJB='class A {'; LJE='class A {'; n=0
for r in HTTPLogger DBLogger logger2 backlog; do n=$(( n + 1 ))
    LJB="$LJB
  void lr$n() { try { risky(); } catch (Exception e) { recover(e); } }"
    LJE="$LJE
  void lr$n() { try { risky(); } catch (Exception e) { $r.error(\"save failed\"); } }"
done
qd_pair logrecvjava A.java "$LJB
}
" "$LJE
}
"
qd_has "5l java HTTPLogger" error-masking lr1 minor; qd_has "5l java DBLogger" error-masking lr2 minor; qd_has "5l java logger2" error-masking lr3 minor
qd_none "5l java backlog" error-masking lr4 "backlog is not a logger"

# 5m) 0.6.6 review: the error-masking QUERY group had a 5000-per-tag budget over a PATH-sorted list, and
#     empty-catch-java captures EVERY catch body. At the baseline A.java holds 6000 catches, so the cut fell inside it
#     and Z.java's untouched empty catch was never counted; the working tree trims A.java to 100 catches, the cut moved
#     past Z.java, and victim() read as a PRE-EXISTING error-masking regression that gated exit 2 on code nobody touched.
#     Both groups are unbounded now: no victim row, exit 0.
CAPD="$WORK/maskcap"; mkdir -p "$CAPD"
( cd "$CAPD" && git init -q && git config user.email t@t && git config user.name t )
mkjava(){   # N methods of 100 catches each → A.java
    python3 - "$1" <<'PY' >"$CAPD/A.java"
import sys
n = int( sys.argv[1] )
print( "class A {" )
for m in range( n ):
    print( "  void m%d() {" % m )
    for c in range( 100 ):
        print( "    try { f(); } catch (Exception e) { use(e); }" )
    print( "  }" )
print( "  void f() {}\n  void use(Exception e) {}\n}" )
PY
}
mkjava 60
printf 'class Z {\n  void victim() {\n    try { g(); } catch (Exception e) { }\n  }\n  void g() {}\n}\n' >"$CAPD/Z.java"
( cd "$CAPD" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
mkjava 1
CAPOUT="$( cd "$CAPD" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"; CAPRC=$?
if printf '%s' "$CAPOUT" | tr '>' '\n' | grep -q '<r kind="error-masking" sym="[^"]*victim"'; then
    no "5m cap: untouched Z.victim reads as an error-masking regression (the per-tag cut moved): $( printf '%s' "$CAPOUT" | tr '>' '\n' | grep 'victim' | head -2 )"
else ok "5m cap: 6000 -> 100 catches in A.java leaves untouched Z.victim with no error-masking row"; fi
if [ "$CAPRC" = 0 ]; then ok "5m cap: the delta exits 0 (removing catches is not a regression)"; else no "5m cap: the delta exits $CAPRC, want 0"; fi

# 5n) 0.6.6 review: mentionsName (does a log call's argument name the caught error?) recursed with no depth bound, and
#     no nesting refusal covers Python: a 20000-deep argument overflowed the worker stack (SIGBUS, exit 138). It now
#     reads at most kMentionsNameMaxDepth levels and answers "mentions it" past that — a miss, never a finding.
DEEPD="$WORK/deepnest"; mkdir -p "$DEEPD"
( cd "$DEEPD" && git init -q && git config user.email t@t && git config user.name t && printf 'def ok():\n    return 1\n' >m.py && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
python3 -c 'N = 20000; print( "def deep(x):\n    try:\n        risky()\n    except Exception as e:\n        log.error(" + "f(" * N + "x" + ")" * N + ")" )' >"$DEEPD/m.py"
DEEPOUT="$( cd "$DEEPD" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"; DEEPRC=$?
if [ "$DEEPRC" -lt 128 ]; then ok "5n deep: a 20000-deep log argument does not overflow the stack (rc=$DEEPRC)"; else no "5n deep: --quality-delta died on a 20000-deep log argument (rc=$DEEPRC)"; fi
printf '%s' "$DEEPOUT" | tr '>' '\n' | grep -q '<r kind="error-masking" sym="deep"' \
    && no "5n deep: a handler too deep to read is reported log-only (the bound must answer 'mentions it')" \
    || ok "5n deep: past the depth bound the handler is not called log-only"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
