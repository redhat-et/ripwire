#!/usr/bin/env bash
# qualitysignalcheck.sh — gate for the 2026-07-13 --quality-delta SIGNAL-TO-NOISE round (§5 quality-delta
# noise rules). Four decided behaviors, each measured on this repo's own dogfood evidence (intentional findings
# drowning real ones):
#   1. short-horizon-churn needs COMMITTED thrash evidence — a symbol flags only when its body already changed
#      across commits inside the 14-day window (or first appeared there) AND this diff rewrites it again. The
#      current uncommitted edit alone is a first write, not churn: an in-window-committed-but-never-rewritten
#      symbol, a brand-new symbol, and a markdown Section must all stay silent.
#   2. test-fixture dirs (test|tests/*fix/, fixture(s)/) are exempt from dead-code — fixtures are dead by design.
#   3. --quality-ack[=REASON] — a per-finding ratchet: acked findings are suppressed on re-runs (acked="N" stays
#      honest) and REAPPEAR only when the finding worsens past its acked magnitude.
#   4. materiality tiers — a small numeric delta (ccx < 3) is sev="minor" and does NOT gate exit 2 by itself;
#      a material delta stays major and exits 2.
#
# Uses git-init fixtures + the auto-vs-HEAD baseline path (same idiom as qualitykindscheck.sh). Operates
# entirely in temp dirs; the repo is never touched.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/qualitysignalcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # BOTH seams: positional AND env (a single-bound gate silently ignores the binary a red-first run hands it)
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolutize BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qualitysignalcheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "qualitysignalcheck: BIN=$BIN  (temp corpora)"

# ── 1) CHURN NEEDS COMMITTED EVIDENCE ────────────────────────────────────────────────────────────────────
#   f.cpp gets TWO in-window commits: hot() is rewritten between them (genuine thrash); steady() is byte-
#   identical across both (the file churns around it). The working tree then rewrites hot(), steady(), AND
#   adds a brand-new fresh(). Only hot() has committed thrash evidence → only hot() flags.
CH="$WORK/ch"; mkdir -p "$CH/src"
( cd "$CH" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){ return 1; }\nint steady(){ return 100; }\nint drive(){ return hot()+steady(); }\n' > "$CH/src/f.cpp"
( cd "$CH" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )
printf 'int hot(){ return 2; }\nint steady(){ return 100; }\nint drive(){ return hot()+steady(); }\n' > "$CH/src/f.cpp"
( cd "$CH" && git add -A >/dev/null 2>&1 && git commit -qm c2 >/dev/null 2>&1 )
dch(){  ( cd "$CH" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecch(){ ( cd "$CH" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 1a) clean tree → exit 0 (control)
[ "$( ecch )" = 0 ] && dch | grep -q 'regressions="0"' \
    && ok "churn evidence: clean tree → exit 0 (control)" \
    || { no "churn evidence: clean tree should be clean (exit $( ecch ))"; dch | tr '>' '\n' | grep '<r '; }

# 1b) rewrite hot() + steady(), add fresh() — only hot() has committed in-window thrash.
printf 'int hot(){ return 3; }\nint steady(){ return 900; }\nint fresh(){ return 42; }\nint drive(){ return hot()+steady()+fresh(); }\n' > "$CH/src/f.cpp"
OCH="$( dch )"
printf '%s' "$OCH" | grep -q 'kind="short-horizon-churn" sym="hot"' \
    && ok "churn evidence: hot() flagged (rewritten in a window commit AND again now)" \
    || { no "churn evidence: hot() not flagged (real thrash lost)"; printf '%s\n' "$OCH" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OCH" | grep -q 'kind="short-horizon-churn" sym="steady"' \
    && no "churn evidence: steady() wrongly flagged — its only rewrite is the CURRENT uncommitted edit" \
    || ok "churn evidence: steady() silent (edited now, but never rewritten across window commits)"
printf '%s' "$OCH" | grep -q 'kind="short-horizon-churn" sym="fresh"' \
    && no "churn evidence: brand-new fresh() wrongly flagged (a first write is not a REwrite)" \
    || ok "churn evidence: brand-new symbol silent (no committed history at all)"
[ "$( ecch )" = 2 ] && ok "churn evidence: hot() thrash still gates exit 2" || no "churn evidence: should exit 2 on hot() (got $( ecch ))"
[ "$OCH" = "$( dch )" ] && ok "churn evidence: delta byte-identical run-to-run" || no "churn evidence: non-deterministic delta"

# 1c) markdown Sections are exempt from churn even when genuinely thrashed: a section body rewritten in a
#     window commit and again in the working tree must stay silent (doc sections are not code churn).
MD="$WORK/md"; mkdir -p "$MD"
( cd "$MD" && git init -q && git config user.email t@t && git config user.name t )
printf '# Notes\n\n## Alpha\n\nfirst draft\n\n## Beta\n\nstable text\n' > "$MD/notes.md"
( cd "$MD" && git add -A >/dev/null 2>&1 && git commit -qm d1 >/dev/null 2>&1 )
printf '# Notes\n\n## Alpha\n\nsecond draft\n\n## Beta\n\nstable text\n' > "$MD/notes.md"
( cd "$MD" && git add -A >/dev/null 2>&1 && git commit -qm d2 >/dev/null 2>&1 )
printf '# Notes\n\n## Alpha\n\nthird draft\n\n## Beta\n\nstable text\n' > "$MD/notes.md"
OMD="$( cd "$MD" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
EMD="$( cd "$MD" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
printf '%s' "$OMD" | grep -q 'kind="short-horizon-churn"' \
    && { no "churn evidence: markdown Section wrongly flagged (doc sections exempt from churn)"; printf '%s\n' "$OMD" | tr '>' '\n' | grep '<r '; } \
    || ok "churn evidence: thrashed markdown section silent (Section symbols exempt)"
[ "$EMD" = 0 ] && ok "churn evidence: doc-only edit → exit 0" || no "churn evidence: doc-only edit should exit 0 (got $EMD)"

# ── 1d) CROSS-FILE SAME-NAME: churn identity is (file, scope, name), never the bare name ────────────────
#   W1-S2 repro (2026-08-11): adding a shell function rows() in one test script produced a churn finding
#   against the same-named rows() in a file the change never touched. canonicalId() degrades to the bare
#   name for a scope-less symbol, so every scope-less rows() in the tree folded to ONE key across the
#   baseline / window-ref / working-tree body-hash maps, and gates 2+3 then judged a cross-file FOLD, not
#   a symbol. The fixture pins the shape: cold.cpp's rows() is committed inside the window (bare-name
#   gate-3 evidence), hot.cpp is a hot file (2 in-window commits) whose WORKING TREE gains a brand-new
#   rows(). A first write is not a REwrite (§1b), and cold.cpp's rows() was never touched — no churn row
#   may appear for rows in either file. alpha() (genuine thrash in the same repo) is the control proving
#   the qualified join still fires.
XF="$WORK/xf"; mkdir -p "$XF/src"
( cd "$XF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int alpha(){ return 1; }\nint use(){ return alpha(); }\n' > "$XF/src/hot.cpp"
printf 'int other(){ return 5; }\n'                               > "$XF/src/cold.cpp"
( cd "$XF" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )
printf 'int alpha(){ return 2; }\nint use(){ return alpha(); }\n'  > "$XF/src/hot.cpp"
printf 'int other(){ return 5; }\nint rows(){ return 10; }\n'      > "$XF/src/cold.cpp"
( cd "$XF" && git add -A >/dev/null 2>&1 && git commit -qm c2 >/dev/null 2>&1 )
# working tree: hot.cpp gains a brand-new rows(); alpha() is rewritten AGAIN (the true-positive control).
printf 'int alpha(){ return 3; }\nint use(){ return alpha(); }\nint rows(){ return 77; }\n' > "$XF/src/hot.cpp"
OXF="$( cd "$XF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OXF" | grep -q 'kind="short-horizon-churn" sym="rows"' \
    && { no "cross-file churn: brand-new rows() flagged via cold.cpp's same-named rows() (bare-name join)"; printf '%s\n' "$OXF" | tr '>' '\n' | grep '<r '; } \
    || ok "cross-file churn: a same-named symbol in an untouched file never donates churn identity"
printf '%s' "$OXF" | grep -q 'kind="short-horizon-churn" sym="alpha"' \
    && ok "cross-file churn: genuine thrash (alpha) still flagged under the qualified join (control)" \
    || { no "cross-file churn: alpha() lost — the qualified join broke the true positive"; printf '%s\n' "$OXF" | tr '>' '\n' | grep '<r '; }

# ── 2) TEST-FIXTURE DIRS EXEMPT FROM DEAD-CODE ──────────────────────────────────────────────────────────
#   The working tree adds three uncalled functions: one under src/ (a REAL dead-code regression), one under
#   test/somefix/ and one under test/fixture/ (fixtures — dead by design). Only the src/ one flags.
FX="$WORK/fx"; mkdir -p "$FX/src" "$FX/test/somefix" "$FX/test/fixture"
( cd "$FX" && git init -q && git config user.email t@t && git config user.name t )
printf 'int used(){ return 1; }\nint caller(){ return used(); }\n' > "$FX/src/lib.cpp"
( cd "$FX" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
printf 'int orphan_one(){ return 7; }\n'        > "$FX/src/orphan.cpp"
printf 'int fixture_dead(){ return 8; }\n'      > "$FX/test/somefix/dead.cpp"
printf 'int fixture_dead_two(){ return 9; }\n'  > "$FX/test/fixture/dead2.cpp"
OFX="$( cd "$FX" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
EFX="$( cd "$FX" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
printf '%s' "$OFX" | grep -q 'kind="dead-code" sym="orphan_one"' \
    && ok "fixture exempt: real dead code under src/ still flagged (control)" \
    || { no "fixture exempt: real dead code lost"; printf '%s\n' "$OFX" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OFX" | grep -q 'sym="fixture_dead"' \
    && no "fixture exempt: test/somefix/ symbol wrongly flagged dead (fixtures are dead BY DESIGN)" \
    || ok "fixture exempt: test/*fix/ symbol silent"
printf '%s' "$OFX" | grep -q 'sym="fixture_dead_two"' \
    && no "fixture exempt: test/fixture/ symbol wrongly flagged dead" \
    || ok "fixture exempt: test/fixture/ symbol silent"
# r26 ORIGIN SPLIT — orphan_one is a BRAND-NEW symbol in a brand-new file, so it is still REPORTED (asserted
# above — that is what this section is about: fixture paths stay silent while src/ does not) but classified
# origin="new-symbol" and therefore non-gating: nothing that existed at the baseline got worse. Gating on
# PREEXISTING findings is asserted in §3/§4 below, and exhaustively in test/qualityorigincheck.sh.
{ [ "$EFX" = 0 ] && printf '%s' "$OFX" | tr '>' '\n' | grep '<r kind="dead-code" sym="orphan_one"' | grep -q 'origin="new-symbol"'; } \
    && ok "fixture exempt: the real (new) dead-code finding is reported, classified new-symbol, exit 0" \
    || { no "fixture exempt: expected orphan_one reported origin=new-symbol + exit 0 (got $EFX)"; printf '%s\n' "$OFX" | tr '>' '\n' | grep '<r '; }

# ── 2b) SHELL TOP-LEVEL INVOCATION IS A USE (W1-S2 dead-code false positive) ────────────────────────────
#   A bash function whose ONLY call site is a top-level script statement (not inside another function) is
#   alive: buildGraph deliberately drops file-scope references from the call-graph CSR (no caller symbol →
#   no edge), so the dead kind must consult top-level call sites itself. The script lives OUTSIDE test/
#   (hooks/) on purpose — test scripts are already exempt wholesale via isTestScriptPath, which would mask
#   exactly this hole. never_called() is the other direction's control: the fix must not kill the kind.
TL="$WORK/tl"; mkdir -p "$TL/src" "$TL/hooks"
( cd "$TL" && git init -q && git config user.email t@t && git config user.name t )
printf 'int used(){ return 1; }\nint caller(){ return used(); }\n' > "$TL/src/lib.cpp"
( cd "$TL" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
cat > "$TL/hooks/nudge.sh" <<'SH'
#!/usr/bin/env bash
top_called() {
    echo "top"
}
helper_called() {
    echo "helper"
}
runner() {
    helper_called
}
never_called() {
    echo "never"
}
top_called
runner
SH
OTL="$( cd "$TL" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OTL" | grep -q 'kind="dead-code" sym="never_called"' \
    && ok "shell toplevel: truly-uncalled never_called() still flagged (control — the kind survives the fix)" \
    || { no "shell toplevel: never_called() lost (fix over-suppressed the dead kind)"; printf '%s\n' "$OTL" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OTL" | grep -q 'sym="top_called"' \
    && { no "shell toplevel: top_called() wrongly flagged dead — its top-level invocation IS a use"; printf '%s\n' "$OTL" | tr '>' '\n' | grep '<r '; } \
    || ok "shell toplevel: top_called() silent (called from a top-level script statement)"
printf '%s' "$OTL" | grep -q 'sym="runner"' \
    && { no "shell toplevel: runner() wrongly flagged dead — invoked at top level"; printf '%s\n' "$OTL" | tr '>' '\n' | grep '<r '; } \
    || ok "shell toplevel: runner() silent (invoked at top level)"
printf '%s' "$OTL" | grep -q 'sym="helper_called"' \
    && { no "shell toplevel: helper_called() wrongly flagged dead (fn→fn edge — always worked)"; printf '%s\n' "$OTL" | tr '>' '\n' | grep '<r '; } \
    || ok "shell toplevel: helper_called() silent (called from inside runner — control)"

# ── 3) ACK RATCHET ──────────────────────────────────────────────────────────────────────────────────────
#   A real complexity regression fires; --quality-ack records it with a reason; the re-run suppresses it
#   (exit 0, acked="1"); worsening it PAST the acked magnitude makes it reappear (the ratchet).
ifs(){ n=$1; s=''; i=1; while [ "$i" -le "$n" ]; do s="$s if(a>$i){ s++; }"; i=$(( i + 1 )); done; printf '%s' "$s"; }
AK="$WORK/ak"; mkdir -p "$AK/src"
( cd "$AK" && git init -q && git config user.email t@t && git config user.name t )
printf 'int f( int a ){ int s=0;%s return s; }\nint usef(){ return f(1); }\n' "$( ifs 5 )" > "$AK/src/c.cpp"
( cd "$AK" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
printf 'int f( int a ){ int s=0;%s return s; }\nint usef(){ return f(1); }\n' "$( ifs 20 )" > "$AK/src/c.cpp"
dak(){  ( cd "$AK" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecak(){ ( cd "$AK" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }
OAK="$( dak )"
printf '%s' "$OAK" | grep -q 'kind="complexity" sym="f"' && [ "$( ecak )" = 2 ] \
    && ok "ack ratchet: material complexity regression fires first (control, exit 2)" \
    || { no "ack ratchet: control regression missing (exit $( ecak ))"; printf '%s\n' "$OAK" | tr '>' '\n' | grep '<r '; }

( cd "$AK" && "$BIN" . --quality-ack='known refactor debt' --no-cache >/dev/null 2>&1 )
AKEC=$?
[ "$AKEC" = 0 ] && ok "ack ratchet: --quality-ack exits 0" || no "ack ratchet: --quality-ack should exit 0 (got $AKEC)"
[ -f "$AK/.ripwire_quality_acks" ] && grep -q 'known refactor debt' "$AK/.ripwire_quality_acks" \
    && ok "ack ratchet: .ripwire_quality_acks written with the reason" \
    || no "ack ratchet: acks sidecar missing or reason not recorded"

OAK2="$( dak )"
printf '%s' "$OAK2" | grep -q 'kind="complexity" sym="f"' \
    && no "ack ratchet: acked finding still reported (should be suppressed)" \
    || ok "ack ratchet: acked finding suppressed on re-run"
printf '%s' "$OAK2" | grep -q 'acked="1"' \
    && ok "ack ratchet: suppression is honest (acked=\"1\" in the header)" \
    || { no "ack ratchet: acked count missing from header"; printf '%s\n' "$OAK2" | head -c 300; }
[ "$( ecak )" = 0 ] && ok "ack ratchet: acked-only run → exit 0" || no "ack ratchet: acked-only run should exit 0 (got $( ecak ))"

printf 'int f( int a ){ int s=0;%s return s; }\nint usef(){ return f(1); }\n' "$( ifs 30 )" > "$AK/src/c.cpp"
OAK3="$( dak )"
printf '%s' "$OAK3" | grep -q 'kind="complexity" sym="f"' && [ "$( ecak )" = 2 ] \
    && ok "ack ratchet: worsening past the acked magnitude REAPPEARS (ratchet, exit 2)" \
    || { no "ack ratchet: worsened finding stayed suppressed (exit $( ecak ))"; printf '%s\n' "$OAK3" | tr '>' '\n' | grep '<r '; }
[ "$OAK3" = "$( dak )" ] && ok "ack ratchet: delta byte-identical run-to-run" || no "ack ratchet: non-deterministic delta"

# ── 4) MATERIALITY TIERS ────────────────────────────────────────────────────────────────────────────────
#   g() is committed already OVER the ccx bar. A +1-ccx edit is a regression by the letter but immaterial:
#   it must be reported sev="minor" and NOT gate exit 2. A +10-ccx edit stays major and exits 2.
MT="$WORK/mt"; mkdir -p "$MT/src"
( cd "$MT" && git init -q && git config user.email t@t && git config user.name t )
printf 'int g( int a ){ int s=0;%s return s; }\nint useg(){ return g(1); }\n' "$( ifs 16 )" > "$MT/src/m.cpp"
( cd "$MT" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
dmt(){  ( cd "$MT" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecmt(){ ( cd "$MT" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

printf 'int g( int a ){ int s=0;%s return s; }\nint useg(){ return g(1); }\n' "$( ifs 17 )" > "$MT/src/m.cpp"
OMT="$( dmt )"
printf '%s' "$OMT" | grep -q 'kind="complexity" sym="g"[^/]*sev="minor"' \
    && ok "materiality: +1-ccx over-the-bar edit reported sev=\"minor\"" \
    || { no "materiality: +1-ccx edit not marked minor"; printf '%s\n' "$OMT" | tr '>' '\n' | grep '<r '; }
[ "$( ecmt )" = 0 ] && ok "materiality: minor-only run → exit 0 (does not gate)" || no "materiality: minor-only run should exit 0 (got $( ecmt ))"

printf 'int g( int a ){ int s=0;%s return s; }\nint useg(){ return g(1); }\n' "$( ifs 26 )" > "$MT/src/m.cpp"
OMT2="$( dmt )"
printf '%s' "$OMT2" | tr '>' '\n' | grep '<r kind="complexity" sym="g"' | grep -q 'sev="minor"' \
    && no "materiality: +10-ccx edit wrongly marked minor" \
    || ok "materiality: material (+10 ccx) regression stays major"
[ "$( ecmt )" = 2 ] && ok "materiality: major regression still gates exit 2" || no "materiality: major regression should exit 2 (got $( ecmt ))"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OMT" | xmllint --noout - 2>/dev/null && printf '%s' "$OMT2" | xmllint --noout - 2>/dev/null \
        && ok "materiality: xml well-formed (minor + major outputs)" || no "materiality: xml malformed"
fi

# ── 5) TEST-SCRIPT EXEMPTION (B10.1a) ───────────────────────────────────────────────────────────────────
#   Two sibling shell test scripts each define a helper `inertPair()` invoked only via `$(...)` — invisible
#   to the parser's call graph, so it would otherwise false-flag as BOTH dead-code (no caller in the indexed
#   tree) and cross-script duplication (identical bodies). A REAL dead function under src/ must still flag.
TS="$WORK/tscript"; mkdir -p "$TS/test" "$TS/src"
( cd "$TS" && git init -q && git config user.email t@t && git config user.name t )
printf 'int used(){ return 1; }\nint caller(){ return used(); }\n' > "$TS/src/lib.cpp"
( cd "$TS" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
printf '#!/usr/bin/env bash\ninertPair(){ echo "$1-$2"; }\nx=$(inertPair a b)\necho "$x"\n' > "$TS/test/checkA.sh"
printf '#!/usr/bin/env bash\ninertPair(){ echo "$1-$2"; }\ny=$(inertPair c d)\necho "$y"\n' > "$TS/test/checkB.sh"
printf 'int orphan_real(){ return 7; }\n' > "$TS/src/orphan.cpp"
OTS="$( cd "$TS" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OTS" | grep -q 'sym="inertPair"' \
    && { no "test-script exempt: inertPair() wrongly flagged dead-code ($(...) calls are invisible to the parser)"; printf '%s\n' "$OTS" | tr '>' '\n' | grep '<r '; } \
    || ok "test-script exempt: inertPair() dead-code silent"
printf '%s' "$OTS" | grep -q 'kind="duplication"' \
    && { no "test-script exempt: sibling checkA.sh/checkB.sh inertPair() bodies wrongly flagged duplication"; printf '%s\n' "$OTS" | tr '>' '\n' | grep '<r '; } \
    || ok "test-script exempt: cross-script inertPair() duplication silent"
printf '%s' "$OTS" | grep -q 'kind="dead-code" sym="orphan_real"' \
    && ok "test-script exempt: real dead code under src/ still flagged (control)" \
    || { no "test-script exempt: real dead code lost"; printf '%s\n' "$OTS" | tr '>' '\n' | grep '<r '; }

# ── 6) STALE-BASELINE SELF-HEAL (B10.1b self-heal + R3 staleness rule) ──────────────────────────────────
#   A STALE sidecar is silently DELETED by the CLI arm and the run falls back to auto-vs-HEAD, with no stderr
#   warning and only the XML baseline= attribute recording it.
#
#   R3 owner ruling 2026-07-29: ancestor carve-out revoked — strict sha equality, both arms. WHICH sidecars are
#   stale changed under this ruling: it used to be only the UNREACHABLE pins, with a REACHABLE ANCESTOR of
#   current HEAD ("committed more work since baselining") honored silently as a deliberate floor. A parallel
#   session's ancestor-pinned sidecar then produced 31 phantom regressions on the CLI while the MCP
#   quality_delta verb honestly reported zero, so ANY pinned sha != current HEAD sha is now stale. Arm 6a below
#   asserted the honored-ancestor behavior and is INVERTED here, deliberately, not deleted; 6b keeps the
#   orphan/divergent-history shape as its own arm (it is no longer a distinct CATEGORY, but it is a distinct git
#   shape that must still self-heal instead of erroring). The full CLI-vs-MCP agreement arm lives in
#   test/qualitystalecheck.sh.
SB="$WORK/stale"; mkdir -p "$SB/src"
( cd "$SB" && git init -q && git config user.email t@t && git config user.name t )
printf 'int a(){ return 1; }\n' > "$SB/src/a.cpp"
( cd "$SB" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )
( cd "$SB" && "$BIN" . --quality-baseline >/dev/null 2>&1 )
[ -f "$SB/.ripwire_quality_baseline" ] && ok "stale-baseline self-heal: sidecar written (setup)" || no "stale-baseline self-heal: sidecar not written (setup)"

# 6a) reachable-ancestor case: commit more work on top — the pinned sha stays an ancestor of HEAD. Post-R3 that
#     is STALE. ONE invocation only: this run deletes the sidecar, so a second call would legitimately hit the
#     "never baselined" informative message and the stderr assertion would be measuring the wrong run.
printf 'int a(){ return 1; }\nint b(){ return 2; }\n' > "$SB/src/a.cpp"
( cd "$SB" && git add -A >/dev/null 2>&1 && git commit -qm c2 >/dev/null 2>&1 )
OSBA="$( cd "$SB" && "$BIN" . --quality-delta --no-cache 2>"$WORK/esba.tmp" )"
ESBA="$( cat "$WORK/esba.tmp" )"; rm -f "$WORK/esba.tmp"
printf '%s' "$OSBA" | grep -q 'baseline="git-HEAD (stale sidecar removed)"' \
    && ok "R3: reachable-ancestor sidecar is STALE and self-heals (baseline=\"git-HEAD (stale sidecar removed)\")" \
    || { no "R3: reachable-ancestor sidecar was still honored — the revoked carve-out is back"; printf '%s\n' "$OSBA" | head -c 300; }
[ -z "$ESBA" ] && ok "R3: reachable-ancestor self-heal is silent (no stderr — the B10.1b noise fix survives)" \
    || no "stale-baseline self-heal: reachable-ancestor case printed stderr: $ESBA"
[ -f "$SB/.ripwire_quality_baseline" ] \
    && no "R3: reachable-ancestor sidecar file NOT deleted (the CLI arm must self-heal it)" \
    || ok "R3: reachable-ancestor sidecar file deleted (self-healed)"

# 6b) unreachable case: an orphan branch shares no history with the pinned sha at all. 6a consumed the sidecar,
#     so re-pin at the current HEAD first.
( cd "$SB" && "$BIN" . --quality-baseline >/dev/null 2>&1 )
( cd "$SB" && git checkout -q --orphan orphanbr >/dev/null 2>&1 && git rm -rf --cached . >/dev/null 2>&1 )
printf 'int c(){ return 1; }\n' > "$SB/src/a.cpp"
( cd "$SB" && git add -A >/dev/null 2>&1 && git commit -qm "orphan root" >/dev/null 2>&1 )
[ -f "$SB/.ripwire_quality_baseline" ] && ok "stale-baseline self-heal: sidecar still present before the unreachable run" || no "stale-baseline self-heal: setup lost the sidecar"
OSBB="$( cd "$SB" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
ESBB="$( cd "$SB" && : )"   # nothing left to run — the prior call already consumed/healed the sidecar; re-check state below
printf '%s' "$OSBB" | grep -q 'baseline="git-HEAD (stale sidecar removed)"' \
    && ok "stale-baseline self-heal: unreachable sidecar self-heals (baseline=\"git-HEAD (stale sidecar removed)\")" \
    || { no "stale-baseline self-heal: unreachable sidecar not self-healed"; printf '%s\n' "$OSBB" | head -c 300; }
[ -f "$SB/.ripwire_quality_baseline" ] \
    && no "stale-baseline self-heal: unreachable sidecar file NOT deleted (should self-heal)" \
    || ok "stale-baseline self-heal: unreachable sidecar file deleted (self-healed)"

# ── 7) SORTED ACKS ROUND-TRIP (B10.1c) ──────────────────────────────────────────────────────────────────
#   .ripwire_quality_acks is merge-friendly: the reader tolerates an out-of-order file and CRLF line endings
#   (e.g. merged in from a different session/checkout); the writer ALWAYS re-emits fully (kind,key)-sorted,
#   LF-only output on every write, regardless of what shape the file arrived in.
ifs2(){ n=$1; s=''; i=1; while [ "$i" -le "$n" ]; do s="$s if(x>$i){ s++; }"; i=$(( i + 1 )); done; printf '%s' "$s"; }
AR="$WORK/acksort"; mkdir -p "$AR/src"
( cd "$AR" && git init -q && git config user.email t@t && git config user.name t )
printf 'int a( int x ){ int s=0; return s; }\nint b(){ return a(1); }\n' > "$AR/src/a.cpp"
( cd "$AR" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )
printf 'int a( int x ){ int s=0;%s return s; }\nint b(){ return a(1); }\n' "$( ifs2 20 )" > "$AR/src/a.cpp"
( cd "$AR" && "$BIN" . --quality-ack='seed' --no-cache >/dev/null 2>&1 )
# hand-scramble: prepend an out-of-order line and give it a CRLF terminator (a Windows-checkout merge shape).
printf 'ack zzz-kind aaaaaaaaaaaaaaaa 1 legacy CRLF line\r\n' > "$AR/scrambled.tmp"
cat "$AR/.ripwire_quality_acks" >> "$AR/scrambled.tmp"
mv "$AR/scrambled.tmp" "$AR/.ripwire_quality_acks"
# reader tolerance: the scrambled/CRLF file must still suppress the seeded finding correctly.
OAR="$( cd "$AR" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OAR" | grep -q 'acked="1"' \
    && ok "sorted acks round-trip: reader tolerates an out-of-order, CRLF-terminated acks file" \
    || { no "sorted acks round-trip: scrambled acks file not read correctly"; printf '%s\n' "$OAR" | head -c 300; }
# writer canonicalization: worsen the finding so a rewrite happens, then check the file is fully sorted + LF-only.
printf 'int a( int x ){ int s=0;%s return s; }\nint b(){ return a(1); }\n' "$( ifs2 30 )" > "$AR/src/a.cpp"
( cd "$AR" && "$BIN" . --quality-ack='2nd' --no-cache >/dev/null 2>&1 )
crcount="$( grep -c $'\r' "$AR/.ripwire_quality_acks" 2>/dev/null || true )"
[ "${crcount:-0}" = 0 ] \
    && ok "sorted acks round-trip: writer strips CRLF (LF-only canonical output)" \
    || no "sorted acks round-trip: rewritten acks file still contains CRLF"
grep '^ack ' "$AR/.ripwire_quality_acks" > "$AR/acklines.txt"
if diff -q "$AR/acklines.txt" <( sort "$AR/acklines.txt" ) >/dev/null 2>&1; then
    ok "sorted acks round-trip: writer re-emits fully (kind,key)-sorted output"
else
    no "sorted acks round-trip: rewritten acks file is not sorted"
fi
grep -q '^# format: ack ' "$AR/.ripwire_quality_acks" \
    && ok "sorted acks round-trip: format grammar documented in a header comment line" \
    || no "sorted acks round-trip: header comment missing the format grammar"

# ── 8) API-SURFACE TIERING: new-symbol vs contract-change (B10.2e) ─────────────────────────────────────────
#   A brand-new public symbol added to an already-existing header is additive (sev="minor",
#   surface="new-symbol"); a parameter-count change to an EXISTING public symbol is a real contract break
#   (stays major, surface="contract-change") — even though its param count (1→2) never crosses kParamBar.
API="$WORK/apitier"; mkdir -p "$API/include"
( cd "$API" && git init -q && git config user.email t@t && git config user.name t )
printf '#pragma once\nint pubfn( int a );\nint pubfn( int a ){ return a; }\n' > "$API/include/api.h"
( cd "$API" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )

printf '#pragma once\nint pubfn( int a );\nint pubfn( int a ){ return a; }\nint newpubfn(){ return 1; }\n' > "$API/include/api.h"
ONS="$( cd "$API" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$ONS" | grep -q 'kind="api-surface" sym="newpubfn"[^/]*sev="minor"[^/]*surface="new-symbol"' \
    && ok "api-surface tiering: brand-new public symbol → sev=\"minor\" surface=\"new-symbol\"" \
    || { no "api-surface tiering: new-symbol case not tiered correctly"; printf '%s\n' "$ONS" | tr '>' '\n' | grep '<r '; }
ENS="$( cd "$API" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
[ "$ENS" = 0 ] && ok "api-surface tiering: new-symbol-only run does not gate exit 2" || no "api-surface tiering: new-symbol run should exit 0 (got $ENS)"

( cd "$API" && git checkout -q -- include/api.h )
printf '#pragma once\nint pubfn( int a, int b );\nint pubfn( int a, int b ){ return a+b; }\n' > "$API/include/api.h"
OCC="$( cd "$API" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OCC" | grep -q 'kind="api-surface" sym="pubfn" was="1" now="2" surface="contract-change"' \
    && ok "api-surface tiering: param-count change on an existing public symbol → surface=\"contract-change\" (was=1 now=2)" \
    || { no "api-surface tiering: contract-change case not detected correctly"; printf '%s\n' "$OCC" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OCC" | grep -q 'kind="api-surface" sym="pubfn"[^/]*sev="minor"' \
    && no "api-surface tiering: contract-change wrongly marked sev=\"minor\" (a public signature edit is always major)" \
    || ok "api-surface tiering: contract-change stays MAJOR"
ECC="$( cd "$API" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
[ "$ECC" = 2 ] && ok "api-surface tiering: contract-change gates exit 2" || no "api-surface tiering: contract-change should exit 2 (got $ECC)"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$ONS" | xmllint --noout - 2>/dev/null && printf '%s' "$OCC" | xmllint --noout - 2>/dev/null \
        && ok "api-surface tiering: xml well-formed (new-symbol + contract-change outputs)" || no "api-surface tiering: xml malformed"
fi

# ── 9) D1 (HIGH): sidecars must resolve against the ANALYZED ROOT, not the process CWD ────────────
#   `ripwire <rootB> --quality-ack` invoked from a FOREIGN cwd (its own separate, unrelated ripwire
#   project — with its own committed baseline) must read/write ONLY rootB's sidecars. Before the fix, the
#   bare relative filenames resolved against CWD: a foreign cwd's `.ripwire_quality_acks` could get silently
#   rewritten, and the stale-baseline self-heal could DELETE the foreign cwd's own (unrelated, legitimate)
#   baseline. Both must now be impossible — the foreign cwd's sidecars are byte-identical before/after.
FCWD="$WORK/foreigncwd"; mkdir -p "$FCWD/src"
( cd "$FCWD" && git init -q && git config user.email t@t && git config user.name t )
printf 'int foreignFn(){ return 1; }\n' > "$FCWD/src/f.cpp"
( cd "$FCWD" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )
( cd "$FCWD" && "$BIN" . --quality-baseline >/dev/null 2>&1 )
[ -f "$FCWD/.ripwire_quality_baseline" ] \
    && ok "D1 foreign-cwd: foreign cwd's own baseline written (setup)" \
    || no "D1 foreign-cwd: foreign cwd's own baseline setup failed"
FCWD_BASELINE_SNAPSHOT="$( cat "$FCWD/.ripwire_quality_baseline" 2>/dev/null )"

ROOTB="$WORK/rootb"; mkdir -p "$ROOTB/src"
( cd "$ROOTB" && git init -q && git config user.email t@t && git config user.name t )
printf 'int g(){ int s=0;%s return s; }\nint useg(){ return g(); }\n' "$( ifs 20 )" > "$ROOTB/src/r.cpp"
( cd "$ROOTB" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )
printf 'int g(){ int s=0;%s return s; }\nint useg(){ return g(); }\n' "$( ifs 30 )" > "$ROOTB/src/r.cpp"   # a real regression, unstaged (working-tree edit vs HEAD)

# 9a) --quality-delta on rootB, invoked FROM foreigncwd: must report rootB's own regression, and must
#     leave foreigncwd untouched — no baseline/acks file created there (quality-delta never writes a
#     baseline; the only sidecar writer in this call is the reader-side self-heal, which must target rootB).
ODEL="$( cd "$FCWD" && "$BIN" "$ROOTB" --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$ODEL" | grep -q 'kind="complexity" sym="g"' \
    && ok "D1 foreign-cwd: --quality-delta on rootB (from foreigncwd) sees ROOTB's own regression" \
    || { no "D1 foreign-cwd: rootB regression not detected"; printf '%s\n' "$ODEL" | tr '>' '\n' | grep '<r '; }
[ -f "$ROOTB/.ripwire_quality_acks" ] \
    && no "D1 foreign-cwd: --quality-delta must not write an acks sidecar at all" \
    || ok "D1 foreign-cwd: no acks sidecar written by --quality-delta (correct — read-only verb)"
[ "$( cat "$FCWD/.ripwire_quality_baseline" 2>/dev/null )" = "$FCWD_BASELINE_SNAPSHOT" ] \
    && ok "D1 foreign-cwd: foreign cwd's baseline UNCHANGED after --quality-delta targeted rootB" \
    || no "D1 foreign-cwd: foreign cwd's baseline was mutated by a call that should only ever touch rootB"

# 9b) --quality-ack on rootB, invoked FROM foreigncwd: the ack must land in ROOTB, never in foreigncwd.
EACK="$( cd "$FCWD" && "$BIN" "$ROOTB" --quality-ack='cross-cwd test' --no-cache >/dev/null 2>&1; echo $? )"
[ "$EACK" = 0 ] && ok "D1 foreign-cwd: --quality-ack on rootB (from foreigncwd) exits 0" || no "D1 foreign-cwd: --quality-ack should exit 0 (got $EACK)"
[ -f "$ROOTB/.ripwire_quality_acks" ] && grep -q 'cross-cwd test' "$ROOTB/.ripwire_quality_acks" \
    && ok "D1 foreign-cwd: rootB's OWN .ripwire_quality_acks written with the ack" \
    || no "D1 foreign-cwd: rootB's acks sidecar missing or reason not recorded"
[ -f "$FCWD/.ripwire_quality_acks" ] \
    && no "D1 foreign-cwd: foreign cwd's .ripwire_quality_acks was WRONGLY created (D1 regression)" \
    || ok "D1 foreign-cwd: foreign cwd got NO .ripwire_quality_acks (correctly isolated)"
[ "$( cat "$FCWD/.ripwire_quality_baseline" 2>/dev/null )" = "$FCWD_BASELINE_SNAPSHOT" ] \
    && ok "D1 foreign-cwd: foreign cwd's baseline still UNCHANGED after --quality-ack targeted rootB" \
    || no "D1 foreign-cwd: foreign cwd's baseline was mutated by --quality-ack targeted at rootB"

# 9c) --quality-baseline on rootB, invoked FROM foreigncwd: must write INTO rootB, never foreigncwd.
( cd "$FCWD" && "$BIN" "$ROOTB" --quality-baseline >/dev/null 2>&1 )
[ -f "$ROOTB/.ripwire_quality_baseline" ] \
    && ok "D1 foreign-cwd: --quality-baseline on rootB (from foreigncwd) writes INTO rootB" \
    || no "D1 foreign-cwd: rootB never got its own baseline written"
[ "$( cat "$FCWD/.ripwire_quality_baseline" 2>/dev/null )" = "$FCWD_BASELINE_SNAPSHOT" ] \
    && ok "D1 foreign-cwd: foreign cwd's baseline still UNCHANGED after --quality-baseline targeted rootB" \
    || no "D1 foreign-cwd: --quality-baseline on rootB clobbered the foreign cwd's own baseline"

# 9d) the DELETE scenario: rootB's baseline is STALE (pinned at an unreachable sha) — the self-heal must
#     delete ROOTB's stale sidecar (correct target) and must NEVER touch foreigncwd's legitimate one, even
#     though foreigncwd is the process's actual CWD for this call (the exact shape of the reported bug: "the
#     stale-baseline self-heal can DELETE cwd A's baseline").
( cd "$ROOTB" && git checkout -q --orphan orphanbr >/dev/null 2>&1 && git rm -rf --cached . >/dev/null 2>&1 )
printf 'int h(){ return 1; }\n' > "$ROOTB/src/r.cpp"
( cd "$ROOTB" && git add -A >/dev/null 2>&1 && git commit -qm "orphan root" >/dev/null 2>&1 )
[ -f "$ROOTB/.ripwire_quality_baseline" ] \
    && ok "D1 foreign-cwd: rootB's now-stale (unreachable-pin) baseline present before the healing run" \
    || no "D1 foreign-cwd: setup lost rootB's baseline before the healing run"
ODEL2="$( cd "$FCWD" && "$BIN" "$ROOTB" --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$ODEL2" | grep -q 'baseline="git-HEAD (stale sidecar removed)"' \
    && ok "D1 foreign-cwd: rootB's unreachable-pin baseline self-heals (git-HEAD fallback)" \
    || { no "D1 foreign-cwd: rootB's stale baseline was not self-healed as expected"; printf '%s\n' "$ODEL2" | head -c 300; }
[ -f "$ROOTB/.ripwire_quality_baseline" ] \
    && no "D1 foreign-cwd: rootB's OWN stale baseline should have been deleted (self-heal target wrong)" \
    || ok "D1 foreign-cwd: rootB's own stale baseline correctly deleted (self-heal targeted the right root)"
[ -f "$FCWD/.ripwire_quality_baseline" ] && [ "$( cat "$FCWD/.ripwire_quality_baseline" )" = "$FCWD_BASELINE_SNAPSHOT" ] \
    && ok "D1 foreign-cwd: foreign cwd's baseline SURVIVED rootB's self-heal (the HIGH-severity bug, fixed)" \
    || no "D1 foreign-cwd: foreign cwd's baseline was deleted or mutated by rootB's self-heal — D1 regression"
# ── 10) DUPLICATE ACK LINES: MAX-WINS, NOT LAST-WINS (D2) ───────────────────────────────────────────
#   A hand-edited or badly-merged .ripwire_quality_acks can contain two lines for the SAME (kind,key) with
#   different ackNow. The reader must keep the HIGHEST ackNow (the ratchet floor can only ever go UP via a
#   duplicate) — never whichever line happens to be LAST in the file (last-wins would let a lower duplicate
#   silently lower an already-accepted floor, and a rewrite would then bake that lowered floor back in).
DP="$WORK/dupack"; mkdir -p "$DP/src"
( cd "$DP" && git init -q && git config user.email t@t && git config user.name t )
printf 'int f( int a ){ int s=0;%s return s; }\nint usef(){ return f(1); }\n' "$( ifs 5 )" > "$DP/src/c.cpp"
( cd "$DP" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
printf 'int f( int a ){ int s=0;%s return s; }\nint usef(){ return f(1); }\n' "$( ifs 20 )" > "$DP/src/c.cpp"
ddp(){  ( cd "$DP" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
edp(){ ( cd "$DP" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

( cd "$DP" && "$BIN" . --quality-ack='seed' --no-cache >/dev/null 2>&1 )
ACKLINE="$( grep '^ack complexity ' "$DP/.ripwire_quality_acks" )"
[ -n "$ACKLINE" ] && ok "duplicate acks: seed ack line written (setup)" || no "duplicate acks: setup failed to write an ack line"
HEXKEY="$( printf '%s' "$ACKLINE" | awk '{print $3}' )"
REALNOW="$( printf '%s' "$ACKLINE" | awk '{print $4}' )"

# append a DUPLICATE line for the same (kind,key) with a much LOWER ackNow, placed LAST in the file — exactly
# the shape that would defeat a naive last-wins reader.
printf 'ack complexity %s 1 duplicate-lower-should-not-win\n' "$HEXKEY" >> "$DP/.ripwire_quality_acks"
[ "$( grep -c "^ack complexity $HEXKEY " "$DP/.ripwire_quality_acks" )" = 2 ] \
    && ok "duplicate acks: two lines for the same (kind,key) now on disk (setup)" \
    || no "duplicate acks: setup did not produce a duplicate line"

# unchanged source (magnitude stays REALNOW): a max-wins reader keeps the real floor and stays suppressed; a
# last-wins reader would drop the floor to 1 and let the finding reappear as a fresh regression.
ODP="$( ddp )"
printf '%s' "$ODP" | grep -q 'kind="complexity" sym="f"' \
    && { no "duplicate acks: max-wins broken — finding reappeared after a lower duplicate line (last-wins bug)"; printf '%s\n' "$ODP" | tr '>' '\n' | grep '<r '; } \
    || ok "duplicate acks: finding stays suppressed — reader kept the HIGHER duplicate's ackNow as the floor"
[ "$( edp )" = 0 ] && ok "duplicate acks: still exit 0 after the lower duplicate line" || no "duplicate acks: should stay exit 0 (got $( edp ))"

# a rewrite (another --quality-ack call) must collapse the duplicate to ONE canonical line, and it must keep
# the HIGHER (real) value — not the lower duplicate that happened to sort last.
( cd "$DP" && "$BIN" . --quality-ack --no-cache >/dev/null 2>&1 )
[ "$( grep -c "^ack complexity $HEXKEY " "$DP/.ripwire_quality_acks" )" = 1 ] \
    && ok "duplicate acks: rewrite collapses the duplicate to a single canonical line" \
    || no "duplicate acks: rewrite left more than one line for the same (kind,key)"
grep -q "^ack complexity $HEXKEY $REALNOW " "$DP/.ripwire_quality_acks" \
    && ok "duplicate acks: collapsed line kept the HIGHER (real) ackNow=$REALNOW, not the lower duplicate" \
    || { no "duplicate acks: collapsed line lost the higher ackNow"; grep "^ack complexity $HEXKEY " "$DP/.ripwire_quality_acks"; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
