#!/usr/bin/env bash
# qualitycheck.sh — gate for --quality-baseline / --quality-delta (the convergence-loop oracle). Snapshot the
# code-quality state, make a change, and assert --quality-delta reports ONLY what got worse (new complexity
# over the ccx bar, new duplication, newly-dead), exit 2 on new debt / 0 when clean / 1 with no baseline.
#
# Operates entirely in a temp dir (the baseline sidecar lands in CWD), so the repo is never touched.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/qualitycheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"
# clean baseline state: one trivial fn + a caller (so nothing is dead)
printf 'int simple(){ return 1; }\nint useit(){ return simple(); }\n' > "$WORK/src/a.cpp"
cd "$WORK"                                            # so .ripwire_quality_baseline is written HERE, not in the repo
echo "qualitycheck: BIN=$BIN  (temp corpus)"

# L1 (2026-09-19): the CLI default legend is compact and spells `<r kind= sym= …>` inside its comment; this reads real rows, so it asks for the full legend.
dq(){ "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null; }
ec(){ "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $?; }

# ── 1) snapshot the clean state ───────────────────────────────────────────────────────────────────────
"$BIN" . --quality-baseline --no-cache >/dev/null 2>&1
if [ -f .ripwire_quality_baseline ]; then ok "--quality-baseline writes the sidecar"; else no "no .ripwire_quality_baseline written"; fi

# ── 2) no change ⇒ zero regressions, exit 0 ───────────────────────────────────────────────────────────
{ dq | grep -q 'regressions="0"'; } && [ "$( ec )" = 0 ] \
    && ok "unchanged tree → 0 regressions, exit 0" || no "unchanged tree should be clean (exit $( ec ))"

# ── 3) introduce: a complex fn (CALLED, so not dead) + a duplicated pair (CALLED) + an ORPHAN ──────────
printf 'int complex_fn( int a, int b ){ int s=0; for(int i=0;i<a;++i){ if(i%%2 && b>0){ for(int j=0;j<b;++j){ if(j>i){ if(j%%3){ while(j){ s+=j; if(s>9 && b<5){ s--; } else { s++; } j--; } } } } } else if(i>10 || b<0){ s+=i; } } return s; }\nint callc(){ return complex_fn(3,4)+dup1()+dup2(); }\nint dup1(){ int x=0; x+=1; x+=2; x+=3; x+=4; x+=5; return x*x+1; }\nint dup2(){ int x=0; x+=1; x+=2; x+=3; x+=4; x+=5; return x*x+1; }\nint orphaned_helper(){ int x=0; x+=1; x+=2; x+=3; return x; }\n' > "$WORK/src/b.cpp"
# callc() calls complex_fn + dup1 + dup2 (so those aren't dead); callc itself + orphaned_helper have no caller.
OUT="$( dq )"

# r26 ORIGIN SPLIT — every symbol added here is BRAND NEW (a whole new src/b.cpp), so every finding below is
# classified origin="new-symbol": still fully REPORTED (the assertions that follow all still hold), but the
# exit code no longer fires, because nothing that existed at the baseline got worse. The exit-2 half of the
# contract is asserted on PREEXISTING regressions in §4b (grow/deepen/widen) and §7b (simple() vs HEAD), and
# exhaustively in test/qualityorigincheck.sh.
[ "$( ec )" = 0 ] && ok "new-symbol-only debt → exit 0 (reported, non-gating — r26 origin split)" \
    || { no "new-symbol-only debt should exit 0 (got $( ec ))"; printf '%s\n' "$OUT" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OUT" | tr '>' '\n' | grep '<r ' | grep -qv 'origin="new-symbol"' \
    && { no "new-symbol-only change produced a row NOT classified new-symbol"; printf '%s\n' "$OUT" | tr '>' '\n' | grep '<r '; } \
    || ok "every finding on an all-new addition carries origin=\"new-symbol\""
printf '%s' "$OUT" | grep -q 'kind="complexity" sym="complex_fn" was="0" now="' \
    && ok "complexity regression: complex_fn flagged (new fn over the ccx bar)" || { no "complexity regression missing"; printf '%s\n' "$OUT" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OUT" | grep -q 'kind="duplication"' && printf '%s' "$OUT" | grep -q 'dup1' \
    && ok "duplication regression: the dup1/dup2 clone group flagged" || no "duplication regression missing"
printf '%s' "$OUT" | grep -q 'kind="dead-code" sym="orphaned_helper"' \
    && ok "dead-code regression: orphaned_helper flagged (newly uncalled)" || no "dead-code regression missing"
# the CALLED additions must NOT be flagged dead (precision)
printf '%s' "$OUT" | grep -q 'kind="dead-code" sym="complex_fn"' \
    && no "complex_fn wrongly flagged dead (it IS called by callc)" || ok "called additions not flagged dead (precision)"

# ── 4) determinism + XML well-formed ──────────────────────────────────────────────────────────────────
if [ "$OUT" = "$( dq )" ]; then ok "deterministic (delta byte-identical run-to-run)"; else no "non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OUT" | xmllint --noout - 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── 4b) Q1 kinds: verbosity / nesting / params / api-surface ───────────────────────────────────────────
# A dedicated sub-corpus so each new kind fires on a crafted regression and does NOT fire unchanged. Each
# target is CALLED (so not dead) and defined in a .cpp (so not itself public, isolating api-surface).
QD="$WORK/qd"; mkdir -p "$QD/src"; rm -f "$QD/.ripwire_quality_baseline"
# baseline: a small fn (few lines / shallow / 1 param), a public header decl, and callers so nothing is dead.
printf 'int grow( int a ){ return a+1; }\n'                                   >  "$QD/src/g.cpp"
printf 'int deepen( int a ){ if(a>0){ return a; } return 0; }\n'             >> "$QD/src/g.cpp"
printf 'int widen( int a ){ return a; }\n'                                    >> "$QD/src/g.cpp"
printf 'int drive(){ return grow(1)+deepen(1)+widen(1); }\n'                 >> "$QD/src/g.cpp"
printf 'int existing_public( int a );\n'                                      >  "$QD/src/api.h"
( cd "$QD" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 )
dqd(){ ( cd "$QD" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecd(){ ( cd "$QD" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }
if [ "$( ecd )" = 0 ]; then ok "Q1 sub-corpus: unchanged → exit 0"; else { no "Q1 sub-corpus should start clean (exit $( ecd ))"; dqd; }; fi

# now regress each kind at once: grow() LOC over kLocBar(60), deepen() nesting over kNestBar(4),
# widen() params over kParamBar(5), and add a NEW public header symbol (contract drift).
{ printf 'int grow( int a ){\n'; for i in $( seq 1 70 ); do printf '  a = a + %d;\n' "$i"; done; printf '  return a;\n}\n'
  printf 'int deepen( int a ){ if(a>0){ if(a>1){ if(a>2){ if(a>3){ if(a>4){ return a; } } } } } return 0; }\n'
  printf 'int widen( int a, int b, int c, int d, int e, int f ){ return a+b+c+d+e+f; }\n'
  printf 'int drive(){ return grow(1)+deepen(1)+widen(1,2,3,4,5,6); }\n'
} > "$QD/src/g.cpp"
printf 'int existing_public( int a );\nint newly_public( int a );\n' > "$QD/src/api.h"
OD="$( dqd )"
if [ "$( ecd )" = 2 ]; then ok "Q1 regressions → exit 2"; else no "Q1 regressions should exit 2 (got $( ecd ))"; fi
printf '%s' "$OD" | grep -q 'kind="verbosity" sym="grow" was="' \
    && ok "verbosity regression: grow flagged (LOC grew over the bar)"  || { no "verbosity regression missing"; printf '%s\n' "$OD" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OD" | grep -q 'kind="nesting" sym="deepen" was="' \
    && ok "nesting regression: deepen flagged (nesting grew over the bar)" || no "nesting regression missing"
printf '%s' "$OD" | grep -q 'kind="params" sym="widen" was="' \
    && ok "params regression: widen flagged (param count grew over the bar)" || no "params regression missing"
# Q-DIAL-4 (2026-09-10): a brand-new export is counted on the root, not printed as a row it can never gate on.
printf '%s' "$OD" | grep -q 'api-new-surface="[1-9]' \
    && ok "api-surface: the new exported symbol is counted on the root (api-new-surface)" \
    || { no "api-surface: newly_public not counted"; printf '%s\n' "$OD" | tr '>' '\n' | grep -E '<quality-delta|<r '; }
# precision: the pre-existing public decl must NOT be reported (it was in the baseline set)
printf '%s' "$OD" | grep -q 'kind="api-surface" sym="existing_public"' \
    && no "existing_public wrongly flagged (it was already public in the baseline)" || ok "pre-existing public not re-flagged (precision)"
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OD" | xmllint --noout - 2>/dev/null; then ok "Q1 delta xml well-formed"; else no "Q1 delta xml malformed"; fi
fi

# ── 4c) THE OVERLOAD/CANONID TRAP: overloads share a canonId → MAX-aggregated on both sides so a re-run ─
#        with NO edit reports ZERO regressions (a low-metric overload written last must not phantom-regress).
OV="$WORK/ov"; mkdir -p "$OV/src"; rm -f "$OV/.ripwire_quality_baseline"
# two overloads of ovl(): a BIG one (high loc/nest/params) then a SMALL one written LAST (the trap trigger).
{ printf 'int ovl( int a, int b, int c, int d, int e, int f ){\n'
  for i in $( seq 1 70 ); do printf '  a = a + %d;\n' "$i"; done
  printf '  if(a>0){ if(a>1){ if(a>2){ if(a>3){ if(a>4){ a++; } } } } }\n  return a;\n}\n'
  printf 'int ovl( int a ){ return a; }\n'                       # small overload LAST — MUST NOT lower the per-id max
  printf 'int useovl(){ return ovl(1)+ovl(1,2,3,4,5,6); }\n'
} > "$OV/src/o.cpp"
( cd "$OV" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 )
OVEC="$( cd "$OV" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
OVOUT="$( cd "$OV" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
{ [ "$OVEC" = 0 ] && printf '%s' "$OVOUT" | grep -q 'regressions="0"'; } \
    && ok "overload trap: baseline then re-run unedited → exit 0, zero regressions (NO phantom)" \
    || { no "overload phantom regression (the trap): exit $OVEC"; printf '%s\n' "$OVOUT" | tr '>' '\n' | grep '<r '; }

# ── 5) missing baseline ⇒ a clean exit 1 with guidance (not a crash) ──────────────────────────────────
rm -f .ripwire_quality_baseline
if [ "$( ec )" = 1 ]; then ok "no baseline → exit 1 (tells you to run --quality-baseline first)"; else no "missing baseline should exit 1"; fi

# ── 6) baseline-format compatibility: a PRE-v4 baseline is REFUSED, never silently misread ─────────────
#       This arm used to assert only "does not crash", and until 2026-08-25 that was the whole contract: an
#       old sidecar simply contributed no lines for kinds it predated. The scope-less fold round made the
#       question sharper, because it changed the per-symbol KEY SPACE (fnv1a64(baselineCanonId) ->
#       pathQualifiedKey). A v1/v2/v3 sidecar's keys are now computed from a different byte string, so
#       reading one yields a baseline in which NO current symbol exists — every function in the tree reports
#       as brand-new debt, with nothing to say anything went wrong. "Does not crash" would pass on exactly
#       that outcome, which is why the arm now pins the REFUSAL and its two honest landings.
V1="$WORK/v1"; mkdir -p "$V1/src"
printf 'int f(){ return 0; }\nint g(){ return f(); }\n' > "$V1/src/a.cpp"
printf '# ripwire quality baseline v1 — regenerate with --quality-baseline; do not hand-edit\n' > "$V1/.ripwire_quality_baseline"
V1OUT="$( cd "$V1" && "$BIN" . --quality-delta --no-cache 2>&1 )"; V1EC=$?
# (a) NO git history and no usable sidecar => the documented exit-1 degrade with an actionable message.
#     Not a crash: the refusal names itself on the degrade channel first.
case "$V1EC" in
    0|1|2) ok "pre-v4 baseline read without crashing (exit $V1EC)" ;;
    *)     no "pre-v4 baseline crashed (exit $V1EC)" ;;
esac
case "$V1OUT" in
    *"predates this binary's baseline format"*) ok "the outdated sidecar is REFUSED by name, not silently misread" ;;
    *) no "an outdated sidecar was consumed without a refusal — every symbol would read as new debt: $( printf '%s' "$V1OUT" | head -c 160 )" ;;
esac
# (b) WITH git history the refusal must land on the disclosed git-HEAD fallback rather than on nothing.
if command -v git >/dev/null 2>&1; then
    V1G="$WORK/v1git"; mkdir -p "$V1G/src"
    printf 'int f(){ return 0; }\nint g(){ return f(); }\n' > "$V1G/src/a.cpp"
    ( cd "$V1G" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1
    printf '# ripwire quality baseline v1 — regenerate with --quality-baseline; do not hand-edit\n' > "$V1G/.ripwire_quality_baseline"
    V1GB="$( cd "$V1G" && "$BIN" . --quality-delta --no-cache 2>/dev/null | sed -n 's/.*<quality-delta [^>]*baseline="\([^"]*\)".*/\1/p' | head -1 )"
    case "$V1GB" in
        git-HEAD*) ok "a refused pre-v4 sidecar falls back to the disclosed floor (baseline=\"$V1GB\")" ;;
        *)         no "a refused pre-v4 sidecar did not land on the git-HEAD floor (baseline=\"$V1GB\")" ;;
    esac
fi

# ── 7) T0.1 — AUTO-BASELINE vs git HEAD when NO sidecar exists ─────────────────────────────────────────
#       In a synthetic git repo: commit a clean tree, then edit a function to add LOC+nesting (a real
#       regression). With NO .ripwire_quality_baseline, --quality-delta must auto-compare vs HEAD and report
#       the regression (exit 2). A clean tree (== HEAD) → exit 0, zero regressions. Determinism holds (HEAD
#       content is fixed). The explicit-sidecar path still wins (precedence). The overload trap stays fixed
#       against the HEAD side too. A non-git dir with no sidecar keeps the exit-1 degrade (covered in §5).
if command -v git >/dev/null 2>&1; then
    GH="$WORK/ghead"; mkdir -p "$GH/src"
    ( cd "$GH" && git init -q && git config user.email t@t && git config user.name t )
    printf 'int simple(){ return 1; }\nint useit(){ return simple(); }\n' > "$GH/src/a.cpp"
    ( cd "$GH" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
    dgh(){  ( cd "$GH" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
    ecgh(){ ( cd "$GH" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

    # 7a) clean working tree (identical to HEAD) → zero regressions, exit 0 — NO sidecar present.
    [ ! -f "$GH/.ripwire_quality_baseline" ] || rm -f "$GH/.ripwire_quality_baseline"
    CLEAN="$( dgh )"
    { printf '%s' "$CLEAN" | grep -q 'baseline="git-HEAD"'; } \
        && ok "T0.1 auto-baseline: no sidecar → compares vs git-HEAD (baseline=\"git-HEAD\")" \
        || { no "T0.1: expected baseline=\"git-HEAD\" attribute"; printf '%s\n' "$CLEAN" | head -c 400; }
    { printf '%s' "$CLEAN" | grep -q 'regressions="0"'; } && [ "$( ecgh )" = 0 ] \
        && ok "T0.1: clean tree (== HEAD) → 0 regressions, exit 0" || no "T0.1: clean tree should be clean vs HEAD (exit $( ecgh ))"

    # 7b) edit simple() to add LOC + deep nesting (a genuine regression, uncommitted) → auto-delta vs HEAD.
    { printf 'int simple(){\n'
      for i in $( seq 1 70 ); do printf '  int x%d=%d; if(x%d>0){ if(x%d>1){ if(x%d>2){ if(x%d>3){ if(x%d>4){ return %d; } } } } }\n' "$i" "$i" "$i" "$i" "$i" "$i" "$i" "$i"; done
      printf '  return 1;\n}\nint useit(){ return simple(); }\n'
    } > "$GH/src/a.cpp"
    RGH="$( dgh )"
    if [ "$( ecgh )" = 2 ]; then ok "T0.1: uncommitted regression vs HEAD → exit 2"; else no "T0.1: regression vs HEAD should exit 2 (got $( ecgh ))"; fi
    printf '%s' "$RGH" | grep -q 'kind="verbosity" sym="simple"' \
        && ok "T0.1: verbosity regression on simple() flagged vs HEAD" || { no "T0.1: verbosity regression missing"; printf '%s\n' "$RGH" | tr '>' '\n' | grep '<r '; }
    printf '%s' "$RGH" | grep -q 'kind="nesting" sym="simple"' \
        && ok "T0.1: nesting regression on simple() flagged vs HEAD" || no "T0.1: nesting regression missing"

    # GNU tar treats paths with a colon in -f as a remote host (e.g. Windows C:\... drive letters,
    # or POSIX paths with colons). materializeCommitTree feeds the archive through stdin (< archiveFile)
    # so tar extracts cleanly without treating the archive path as a remote host.
    COLON_DIR="C:x"
    if ( cd "$GH" && mkdir -p "$COLON_DIR" 2>/dev/null ); then
        # POSIX host (Linux, macOS): a cwd-relative directory named 'C:x'.
        ( cd "$GH" && echo "C:x" >> .gitignore )
        WHEAD="$( cd "$GH" && TMPDIR="$COLON_DIR" "$BIN" . --quality-delta --no-cache 2>/dev/null )"; WRC=$?
        rm -rf "$GH/$COLON_DIR"
    else
        # Windows: NTFS disallows colons in directory names, but native absolute paths already contain C:.
        WCACHE="$WORK/wincache"; mkdir -p "$WCACHE"
        WHEAD="$( cd "$GH" && TMPDIR="$WCACHE" "$BIN" . --quality-delta --no-cache 2>/dev/null )"; WRC=$?
        rm -rf "$WCACHE"
    fi
    if [ "$WRC" = 2 ] && printf '%s' "$WHEAD" | grep -q 'baseline="git-HEAD"'; then
        ok "colon-bearing cache path: archived HEAD remains available and detects the regression"
    else
        no "colon-bearing cache path: archived HEAD unavailable (exit $WRC)"
    fi

    # The --quality-delta=A..B range form extracts a second archive (materializeCommitSubset, reached only when the memory
    # guard degrades the range to the changed files: RIPWIRE_TEST_MEMGUARD=project:1, as qddegradecheck.sh) and must take the
    # same stdin path. Commit the 7b regression on a copy of the fixture so HEAD~1..HEAD is a real gating range.
    GR="$WORK/ghrange"; cp -R "$GH" "$GR"
    ( cd "$GR" && git add -A >/dev/null 2>&1 && git commit -qm regress >/dev/null 2>&1 )
    if ( cd "$GR" && mkdir -p "$COLON_DIR" 2>/dev/null ); then
        RHEAD="$( cd "$GR" && TMPDIR="$COLON_DIR" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache 2>/dev/null )"; RRC=$?
        rm -rf "$GR/$COLON_DIR"
    else
        mkdir -p "$WORK/wincache2"
        RHEAD="$( cd "$GR" && TMPDIR="$WORK/wincache2" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache 2>/dev/null )"; RRC=$?
        rm -rf "$WORK/wincache2"
    fi
    if [ "$RRC" = 2 ] && printf '%s' "$RHEAD" | grep -q 'skipped_why="memory"' && printf '%s' "$RHEAD" | grep -q 'kind="nesting" sym="simple"'; then
        ok "colon-bearing cache path: the degraded A..B range form extracts its archive and detects the regression"
    else
        no "colon-bearing cache path: the A..B range form failed (exit $RRC)"
    fi

    # 7c) determinism: HEAD content is fixed → byte-identical run-to-run.
    if [ "$RGH" = "$( dgh )" ]; then ok "T0.1: auto-vs-HEAD delta byte-identical run-to-run (deterministic)"; else no "T0.1: non-deterministic auto-vs-HEAD delta"; fi
    if command -v xmllint >/dev/null 2>&1; then
        if printf '%s' "$RGH" | xmllint --noout - 2>/dev/null; then ok "T0.1: auto-vs-HEAD xml well-formed"; else no "T0.1: auto-vs-HEAD xml malformed"; fi
    fi

    # 7d) PRECEDENCE — an explicit sidecar (snapshot of the CURRENT edited tree) WINS over HEAD: baseline it
    #     now, and the same edited tree reports 0 regressions (baselined against itself, not HEAD) with
    #     baseline="sidecar". Proves the explicit path still wins and is unchanged.
    #
    #     RE-PINNED to the H11 contract (capture-audit 2026-09-04, test/baselinedirtycheck.sh): this tree is
    #     DIRTY and gating by construction (7b just asserted exit 2 against HEAD), which is exactly the pin
    #     that used to swallow the debt silently. The BARE form now refuses it — asserted here, because this
    #     is the one gate that already had the fixture for it — and --allow-dirty is how a caller says "yes,
    #     that floor is what I mean". Precedence itself is unchanged and is still what the arm measures.
    ( cd "$GH" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 ) \
        && no "T0.1: --quality-baseline pinned a gating dirty tree silently (H11 regression)" \
        || ok "T0.1: --quality-baseline refuses to pin a floor over this tree's own gating debt (H11)"
    [ -f "$GH/.ripwire_quality_baseline" ] && no "T0.1: the H11 refusal still wrote the sidecar" \
                                           || ok "T0.1: the H11 refusal wrote nothing"
    ( cd "$GH" && "$BIN" . --quality-baseline --allow-dirty --no-cache >/dev/null 2>&1 )
    SC="$( dgh )"
    printf '%s' "$SC" | grep -q 'baseline_absorbed="' \
        && ok "T0.1: the allow-dirty pin discloses what it absorbed (baseline_absorbed=)" \
        || { no "T0.1: an allow-dirty pin's delta carries no baseline_absorbed="; printf '%s\n' "$SC" | head -c 300; }
    { printf '%s' "$SC" | grep -q 'baseline="sidecar"' && printf '%s' "$SC" | grep -q 'regressions="0"' && [ "$( ecgh )" = 0 ]; } \
        && ok "T0.1 precedence: explicit sidecar wins over HEAD (baseline=\"sidecar\", 0 regressions vs itself)" \
        || { no "T0.1 precedence: explicit sidecar should win + report clean"; printf '%s\n' "$SC" | head -c 300; }
    rm -f "$GH/.ripwire_quality_baseline"

    # 7e) OVERLOAD TRAP vs HEAD — the HEAD side goes through the SAME MAX-aggregation, so committing an
    #     overload pair (big then small-last) and re-running with NO edit must report ZERO regressions.
    OVH="$WORK/ovhead"; mkdir -p "$OVH/src"
    ( cd "$OVH" && git init -q && git config user.email t@t && git config user.name t )
    { printf 'int ovl( int a, int b, int c, int d, int e, int f ){\n'
      for i in $( seq 1 70 ); do printf '  a = a + %d;\n' "$i"; done
      printf '  if(a>0){ if(a>1){ if(a>2){ if(a>3){ if(a>4){ a++; } } } } }\n  return a;\n}\n'
      printf 'int ovl( int a ){ return a; }\n'                       # small overload LAST
      printf 'int useovl(){ return ovl(1)+ovl(1,2,3,4,5,6); }\n'
    } > "$OVH/src/o.cpp"
    ( cd "$OVH" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
    OVHEC="$( cd "$OVH" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
    OVHOUT="$( cd "$OVH" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
    { [ "$OVHEC" = 0 ] && printf '%s' "$OVHOUT" | grep -q 'regressions="0"'; } \
        && ok "T0.1 overload trap vs HEAD: committed overloads, unedited re-run → exit 0, zero (NO phantom)" \
        || { no "T0.1 overload phantom vs HEAD: exit $OVHEC"; printf '%s\n' "$OVHOUT" | tr '>' '\n' | grep '<r '; }
else
    printf '  SKIP  T0.1 auto-baseline-vs-HEAD (git not available)\n'
fi

# Python virtual hooks (#228): deleting a redundant direct caller must not make an override dead
# while an inherited self/cls dispatch still reaches it. The unrelated class is the negative control.
if python3 - "$BIN" "$WORK/python-dispatch" <<'PYDISPATCH'
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

binary, directory = sys.argv[1:]
root = pathlib.Path(directory)
root.mkdir()
(root / "base.py").write_text("""class Base:
    @classmethod
    def setup(
        # Parameters are AST facts even when comments precede the receiver.
        cls,
    ):
        return cls.create_test_objects()

    @classmethod
    def create_test_objects(cls):
        return -1

    def exercise(
        # A signature-text prefix check would miss this receiver.
        self,
    ):
        return self.detail_url_kwargs()

    def detail_url_kwargs(self):
        return {"pk": -1}
""")
(root / "middle.py").write_text("from base import Base\n\nclass Middle(Base):\n    pass\n")
for index in range(30):
    directory = root / f"app_{index}"
    directory.mkdir()
    (directory / "hooks.py").write_text(f"""from middle import Middle

class Child{index}(Middle):
    @classmethod
    def create_test_objects(cls):
        return {index}

    def detail_url_kwargs(self):
        return {{"pk": {index}}}

    @classmethod
    def redundant_setup(cls):
        return cls.create_test_objects()

    def redundant_exercise(self):
        return self.detail_url_kwargs()
""")
control = root / "unrelated.py"
control.write_text("""class Unrelated:
    def detail_url_kwargs(self):
        return {"pk": 900}

    def only_caller(self):
        return self.detail_url_kwargs()
""")

sibling = root / "siblings.py"
sibling.write_text("""class Parent:
    pass

class Left(Parent):
    def dispatch(self):
        return self.hook()

    def hook(self):
        return 1

class Right(Parent):
    def hook(self):
        return 2

    def redundant(self):
        return self.hook()
""")

(root / "nested_pkg").mkdir()
(root / "nested_pkg/parent.py").write_text("""class NestedParent:
    def wrapper(self):
        def inner(cls):
            return cls.hook()
        return inner

    def second_parameter(other, cls):
        return cls.hook()
""")
nested = root / "nested_child.py"
nested.write_text("""from nested_pkg.parent import NestedParent

class NestedChild(NestedParent):
    def hook(self):
        return 3

    def redundant(self):
        return self.hook()
""")

def git(*args):
    return subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                           "-c", "core.hooksPath=/dev/null", *args], cwd=root,
                          check=True, capture_output=True, text=True)

git("init", "-q")
git("add", ".")
git("commit", "-qm", "direct and inherited callers")

def run(*args):
    return subprocess.run([binary, ".", *args, "--no-cache"], cwd=root,
                          text=True, capture_output=True)

def dead_rows(result):
    assert result.returncode in (0, 2), result.stderr
    return [row.attrib["sym"] for row in ET.fromstring(result.stdout).findall("r")
            if row.attrib["kind"] == "dead-code"]

baseline = run("--quality-baseline")
assert baseline.returncode == 0, baseline.stderr
assert not dead_rows(run("--quality-delta")), "unchanged baseline differs"
for path in root.glob("app_*/hooks.py"):
    text = path.read_text()
    assert "def redundant_setup" in text and "def redundant_exercise" in text
    path.write_text(text[:text.index("    @classmethod\n    def redundant_setup")])
control.write_text(control.read_text().split("    def only_caller")[0])
sibling.write_text(sibling.read_text().split("    def redundant")[0])
nested.write_text(nested.read_text().split("    def redundant")[0])

# Execute the inherited dispatch as well: these are reachable overrides, not merely matching names.
sys.dont_write_bytecode = True
sys.path.insert(0, str(root))
for index in range(30):
    namespace = {}
    exec((root / f"app_{index}/hooks.py").read_text(), namespace)
    child = namespace[f"Child{index}"]
    assert child.setup() == index and child().exercise() == {"pk": index}

result = run("--quality-delta")
rows = dead_rows(result)
assert rows == ["nested_child.py::NestedChild::hook", "siblings.py::Right::hook",
                "unrelated.py::Unrelated::detail_url_kwargs"], rows
assert result.returncode == 2, "the genuinely orphaned control must still gate"
# Automatic HEAD, cached HEAD and committed-range paths must use the same eligibility rule.
(root / ".ripwire_quality_baseline").unlink()
assert dead_rows(run("--quality-delta")) == rows
assert dead_rows(run("--quality-delta")) == rows
git("add", ".")
git("commit", "-qm", "remove redundant direct callers")
assert dead_rows(run("--quality-delta=HEAD~1..HEAD")) == rows
clean = run("--quality-delta")
assert clean.returncode == 0 and not dead_rows(clean)

base = root / "base.py"
source = base.read_text()
assert source.count("return cls.create_test_objects()") == 1
assert source.count("return self.detail_url_kwargs()") == 1
base.write_text(source.replace("return cls.create_test_objects()", "return None")
                      .replace("return self.detail_url_kwargs()", "return None"))
without_dispatch = run("--quality-delta")
assert len([row for row in dead_rows(without_dispatch) if row.startswith("app_")]) == 60
assert without_dispatch.returncode == 2
print("inherited hooks stay live only while dispatch exists; unrelated and sibling orphans gate")
PYDISPATCH
then
    ok "Python inherited self/cls hooks survive removal of redundant callers"
else
    no "Python inherited self/cls hooks were classified dead or the orphan was hidden"
fi

# Python test-framework hooks (#228): unittest and Django call setUp/tearDown/setUpClass/setUpTestData and
# test_* methods by protocol, so the call graph never sees them. Closures inside a method reach the method's
# self/cls as a free variable. Both must stay live. The orphans are the sensitivity control: the arm must
# still see real dead code in the same tree.
if python3 - "$BIN" "$WORK/django-hooks" <<'PYHOOKS'
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

binary, directory = sys.argv[1:]
root = pathlib.Path(directory)
root.mkdir()

def git(*args):
    return subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                           "-c", "core.hooksPath=/dev/null", *args], cwd=root,
                          check=True, capture_output=True, text=True)

def run(*args):
    return subprocess.run([binary, ".", *args, "--no-cache"], cwd=root, text=True, capture_output=True)

def dead_rows(result):
    assert result.returncode in (0, 2), result.stderr
    return sorted(row.attrib["sym"] for row in ET.fromstring(result.stdout).findall("r")
                  if row.attrib["kind"] == "dead-code")

(root / "app.py").write_text("def main():\n    return 0\n")
git("init", "-q")
git("add", ".")
git("commit", "-qm", "application only")

(root / "tests").mkdir()
(root / "tests/__init__.py").write_text("")
(root / "tests/base_case.py").write_text("""from django.test import TestCase


class BaseCase(TestCase):
    @classmethod
    def setUpTestData(cls):
        def inner():
            return cls.make_shared()
        cls.shared = inner()

    @classmethod
    def make_shared(cls):
        return 1

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

    def setUp(self):
        self.value = self.make_value()

    def make_value(self):
        return 2

    def tearDown(self):
        pass

    def test_thing(self):
        self.run_closure()
        self.run_bound()
        return self.value

    def testCamel(self):
        return 3

    def run_closure(self):
        def inner():
            return self.closure_hook()
        return inner()

    def closure_hook(self):
        return 4

    def run_bound(self):
        def cb(self):
            return self.bound_hook()
        return cb

    def bound_hook(self):
        return 10

    def never_called(self):
        return 5


def unused_helper():
    return 6
""")
(root / "tests/test_fw.py").write_text("""from tests.base_case import BaseCase


class FwCase(BaseCase):
    @classmethod
    def make_shared(cls):
        return 9

    def setUp(self):
        super().setUp()

    def make_value(self):
        return 7

    def closure_hook(self):
        return 8

    def bound_hook(self):
        return 11
""")
(root / "app_helpers.py").write_text("""def test_helper():
    return 1


class Svc:
    def testThing(self):
        return 2

    def setup_method(self, method):
        return 3
""")
(root / "tests/test_xunit.py").write_text("""def setup_module(module):
    return 1


def teardown_module(module):
    return 2


def setup_function(function):
    return 3


def teardown_function(function):
    return 4


class TestShop:
    @classmethod
    def setup_class(cls):
        return 5

    @classmethod
    def teardown_class(cls):
        return 6

    def setup_method(self, method):
        return 7

    def teardown_method(self, method):
        return 8

    def test_buy(self):
        return 9
""")
(root / "plugin_hooks.py").write_text("""import pytest


@pytest.fixture
def shared_resource():
    return 1


def pytest_configure(config):
    return 2
""")
(root / "checks").mkdir()
(root / "checks/tests.py").write_text("""from django.test import TestCase


class ChecksTests(TestCase):
    def setUp(self):
        self.ready = True

    def test_one(self):
        return self.ready

    def testlower(self):
        return 1

    def runTest(self):
        return 2

    async def asyncSetUp(self):
        return 3

    async def asyncTearDown(self):
        return 4
""")
git("add", ".")
git("commit", "-qm", "django hooks")

# Framework hooks, the closure dispatch, and the subclass overrides must not be dead. The two orphans
# (never_called, unused_helper) are the control: the arm must still see real dead code in this shape.
rows = dead_rows(run("--quality-delta=HEAD~1..HEAD"))
# Negatives: a test* def in application code stays dead (the test-module clause), and a closure that binds self as
# its own parameter does not keep the host's overrides live (the bound-receiver clause). The pytest xunit hooks in
# tests/test_xunit.py are live (kXunitHooks, shared with pythonRunnerRoot); the same name in application code
# (Svc.setup_method) is not.
# plugin_hooks.py: a conftest hook (pytest_configure) is still reported; the @pytest.fixture beside it is not (the changelog
# fragment says so, and a decorated def is a value-use: ingest_valuerefs.h emitDecorators).
expected = sorted(["tests/base_case.py::BaseCase::never_called", "unused_helper", "test_helper", "pytest_configure",
                   "app_helpers.py::Svc::testThing", "app_helpers.py::Svc::setup_method",
                   "tests/test_fw.py::FwCase::bound_hook"])
assert rows == expected, rows
print("django hooks and closure dispatch stay live; the two orphans gate")
PYHOOKS
then
    ok "Django/unittest hooks (setUp, setUpTestData, test_*) and closure self-dispatch are not dead"
else
    no "Django/unittest hooks or closure self-dispatch classified dead (#228)"
fi

# ── (U) THE UNCHANGED-TREE INVARIANT — a no-op diff must never gate (issue #228, part 1) ──────────────────
#
# THE CONTRACT: a working tree whose TRACKED files are identical to HEAD reports regressions="0" gating="0"
# and exit 0, whatever shape the checkout has. The reporter's tree was exactly that — `git status` clean of
# modifications, untracked directories present, a shallow clone — and it gated 58 dead-code rows, all
# `preexisting-worse`, exit 2. A pre-commit hook that fires on an unchanged tree is unusable, and the escape
# hatch is blocked with it: --quality-baseline refuses to pin over a tree that "already holds N gating
# finding(s) against HEAD".
#
# WHY THE SHAPES. Before the identity basis (src/quality.h) the HEAD side was `git archive HEAD` re-ingested
# in a temp dir, which is a DIFFERENT POPULATION from the working tree, and a dead-code verdict is a property
# of the whole population. Measured on the binary before the fix, each row's tree `git status`-clean of
# modifications unless marked (+dirty): untracked file 1 gating row, untracked nested repo 2, export-ignore 1,
# sparse checkout 2, `--no-ignore` over a gitignored same-named definition 1 — every one of them exit 2. A
# shallow clone on its own read ZERO, which is why the reporter's `+shallow` is a bystander and is pinned here
# as one.
#
# AND THE OTHER DIRECTION, which is why the (U5) family exists. `git diff --quiet HEAD` is SPECIFIED to be
# blind to a `skip-worktree` or `assume-unchanged` path, so taking it as proof that the tree IS HEAD let a
# REAL dead-code regression inside such a file report gating="0" exit 0. A false negative on the gate's
# central promise is worse than the false positive this work set out to remove. The first fix refused only
# when such a path was still ON DISK, and that was defeated by DELETING it — the bit hides a deletion exactly
# as it hides an edit. The next fix kept an exception for cone-mode sparse checkout and decided for itself
# which paths a cone includes; that was defeated by a file in an ANCESTOR of a listed directory, which real
# cone mode materializes. So there is no exception left: ANY flagged path, present or absent, sparse or not,
# refuses the identity basis, and the root says so with head_basis="archived-index-hidden". (U5) runs both
# bits against both an edit and a deletion, inside and outside a cone; (U5a) is the ancestor-directory shape
# that defeated the cone rule; (U5c) is the "refusal costs nothing" half; (U4) records what a sparse checkout
# pays for the refusal as a KNOWN GAP. Every (U5) arm also asserts that --quality-baseline declines to pin,
# because an escape hatch that launders the finding is the same bug with a different exit code.
#
# EVERY ARM HAS A SENSITIVITY CONTROL, because a delta that reports nothing would pass a zero-assertion for
# the wrong reason (CONTRIBUTING §2, "empty equals agreement"): U7 makes a REAL edit in the hardest shape and
# requires exactly one gating dead-code row, U1 requires the untracked file's own new-symbol debt to still be
# reported, and every zero arm pins `head_basis=` so that a zero from the WRONG floor cannot pass for the
# right one. TMPDIR is set explicitly in every arm and the fixture directories are neutrally named, so neither
# this gate's own location nor the temp dir's can decide a verdict through isFixturePath.
UROOT="$WORK/unchanged"; mkdir -p "$UROOT"
UTMP="$UROOT/scratch"; mkdir -p "$UTMP"
ug(){ git -c user.name=qc -c user.email=qc@x -c core.hooksPath=/dev/null "$@"; }
umk(){   # $1 = dir — a tree with a symbol whose verdict MOVES when the population changes
    mkdir -p "$1/lib" "$1/app"
    printf 'def zeta_helper(v):\n    return v + 1\n'                                  > "$1/lib/core.py"
    printf 'def driver():\n    return zeta_helper(1)\n'                               > "$1/app/main.py"
    printf 'void omicron_helper(int v);\nvoid omicron_helper(int v) { (void)v; }\n'    > "$1/lib/core.c"
    printf 'void omicron_helper(int v);\nvoid runner(void) { omicron_helper(2); }\n'   > "$1/app/main.c"
    ( cd "$1" && ug init -q . && ug add -A && ug commit -qm init ) >/dev/null 2>&1
}
UOUT=""; UATTR(){ printf '%s' "$UOUT" | grep -o "<quality-delta [^>]*>" | head -1 | sed -n "s/.*[^-]$1=\"\([^\"]*\)\".*/\1/p"; }
urun(){  # $1 = dir, rest = extra flags — fills UOUT / URC
    local d="$1"; shift
    UOUT="$( cd "$d" && TMPDIR="$UTMP" "$BIN" "$PWD" --quality-delta --legend=compact "$@" 2>/dev/null )"; URC=$?
}
# `uzero` asserts the WHOLE contract, and asserts the document exists FIRST: a crashed run also prints no rows.
# The contract is NOT "no rows at all" — a file the tree holds and HEAD does not track is new code, and its own
# debt is reported as it always was. It is "nothing pre-existing got worse": exit 0, gating="0",
# preexisting-worse="0", and every row counted in regressions= accounted for by new-symbol=.
uzero(){  # $1 = label, rest = urun args
    local label="$1"; shift
    urun "$@"
    local reg gat pre new
    reg="$( UATTR regressions )"; gat="$( UATTR gating )"; pre="$( UATTR preexisting-worse )"; new="$( UATTR new-symbol )"
    if ! printf '%s' "$UOUT" | grep -q '<quality-delta '; then
        no "(U) $label: no quality-delta document at all (exit $URC) — the run did not produce a report"
    elif [ "$( UATTR head_basis )" != "identity" ]; then
        # WHICH floor answered is half the claim. A zero from the archived tree here would be a DIFFERENT
        # (and, on these shapes, historically wrong) answer that happens to read the same, so the arm pins
        # the basis as well as the counts — see the (U5) family for the shapes that must NOT take it.
        no "(U) $label: head_basis=$( UATTR head_basis ) — the identity basis was not taken, so this zero is not the one the arm is about"
    elif [ "$URC" -eq 0 ] && [ "$gat" = "0" ] && [ "$pre" = "0" ] && [ "$reg" = "$new" ]; then
        ok "(U) $label: head_basis=identity gating=0 preexisting-worse=0 exit 0 (regressions=$reg, all new-symbol)"
    else
        no "(U) $label: exit $URC regressions=$reg gating=$gat preexisting-worse=$pre new-symbol=$new — a no-op diff gated"
    fi
}

umk "$UROOT/plain";  uzero "clean tree"                    "$UROOT/plain"
umk "$UROOT/tmpfix"; mkdir -p "$UROOT/fixtures/tmp"
# CodeRabbit 4057546124: this ran `uzero` inside a ( … ) subshell to scope UTMP. `no()` sets fail=1, and a
# subshell's fail=1 dies with the subshell — the arm could print FAIL while the gate exited 0. There is no
# `set -e` and nothing checked $?, so the vacuity was total. UTMP is saved and restored in the PARENT
# instead; the override is just as scoped and the assertion now reaches the gate's own exit code.
UTMP_SAVED="$UTMP"; UTMP="$UROOT/fixtures/tmp"
uzero "TMPDIR under a fixtures/ directory" "$UROOT/tmpfix"
UTMP="$UTMP_SAVED"

# U1 untracked content — the reporter's own shape — and the control that its debt is still REPORTED.
umk "$UROOT/untracked"
mkdir -p "$UROOT/untracked/scratchdir"
printf 'def zeta_helper(v):\n    return v * 5\n' > "$UROOT/untracked/scratchdir/dup.py"
uzero "untracked directory with a same-named definition" "$UROOT/untracked"
urun "$UROOT/untracked"
[ "$( UATTR new-symbol )" != "0" ] && [ -n "$( UATTR new-symbol )" ] \
    && ok "(U1) control: the untracked file's own debt is still reported as new-symbol=$( UATTR new-symbol ) (never gating)" \
    || no "(U1) control: the untracked file contributed NO new-symbol row — the zero above could be a silenced tree"
case "$( UATTR at )" in *+dirty*) ok "(U1) the stamp still says +dirty — the untracked content is disclosed, not hidden";;
                        *) no "(U1) at=$( UATTR at ) does not carry +dirty although untracked content is present";; esac

umk "$UROOT/nestedrepo"; umk "$UROOT/nestedrepo/vendored"
uzero "untracked nested git repository" "$UROOT/nestedrepo"

# U2 a shallow clone, with and without untracked content: `+shallow` is a bystander, pinned as one.
umk "$UROOT/shallowsrc"
ug clone -q --depth=1 "file://$UROOT/shallowsrc" "$UROOT/shallow" >/dev/null 2>&1
if [ -d "$UROOT/shallow/.git" ]; then
    uzero "shallow clone" "$UROOT/shallow"
    case "$( UATTR at )" in *+shallow*) ok "(U2) the stamp says +shallow — the shape is disclosed";;
                            *) no "(U2) at=$( UATTR at ) does not carry +shallow in a --depth=1 clone";; esac
    mkdir -p "$UROOT/shallow/scratchdir"
    printf 'def zeta_helper(v):\n    return v * 7\n' > "$UROOT/shallow/scratchdir/dup.py"
    uzero "shallow clone WITH an untracked directory (the reported shape)" "$UROOT/shallow"
else
    no "(U2) could not make a shallow clone of a local path — the shallow arms would be vacuous"
fi

# U3 export-ignore: `git archive` drops the file, the working tree keeps it. git status: clean.
umk "$UROOT/exportignore"
printf 'def zeta_helper(v):\n    return v * 9\n' > "$UROOT/exportignore/lib/other.py"
printf 'lib/other.py export-ignore\n'            > "$UROOT/exportignore/.gitattributes"
( cd "$UROOT/exportignore" && ug add -A && ug commit -qm attrs ) >/dev/null 2>&1
uzero "a tracked file marked export-ignore" "$UROOT/exportignore"

# U4 sparse checkout hiding a tracked caller. git status: clean.
umk "$UROOT/sparsesrc"
ug clone -q "$UROOT/sparsesrc" "$UROOT/sparse" >/dev/null 2>&1
if ( cd "$UROOT/sparse" && ug sparse-checkout init --cone && ug sparse-checkout set lib ) >/dev/null 2>&1; then
    # Cone-mode sparse sets skip-worktree on every excluded path — the same bit (U5) refuses over — and this
    # arm's uzero REQUIRES head_basis=identity, which is the point: those files are DELETED from disk, so they
    # are absent from both sides of a self-comparison and can lie about nothing. Present-on-disk is what (U5)
    # tests, and the two arms together pin that the distinction is the one being made.
    # KNOWN GAP, and the acceptance test for closing it is flipping this arm.
    #
    # A sparse checkout sets skip-worktree on every excluded path, so it lands in (U5)'s refusal and takes the
    # ARCHIVED comparison. That tree is not sparse-aware — `git archive HEAD` materializes the excluded files —
    # so an excluded caller reads as vanished and GATES, on a tree with no edit in it. That is the same
    # population divergence this block exists to remove, left in place for this one shape, and it is main's
    # pre-existing behaviour rather than anything the identity basis introduced.
    #
    # It is left in place on purpose. Deciding for ourselves which paths a cone includes is what this lane
    # tried twice and had defeated twice — most recently by a file in an ANCESTOR of a listed directory, which
    # real cone mode materializes and a hand-written rule did not know about. `git sparse-checkout check-rules`
    # would be authoritative but lands in git 2.42, newer than this tool's supported floor. So the answer says
    # which branch it took (head_basis="archived-index-hidden") and the fix belongs to slice 2 of
    # prompts/help-wanted/quality-delta-unchanged-tree-zero.md: make the ARCHIVED side's population equal by
    # construction, which fixes this shape and every other one at once.
    if [ -z "$( cd "$UROOT/sparse" && ug ls-files -v | grep '^S ' )" ]; then
        no "(U4) no skip-worktree bit in the sparse checkout — this arm proves nothing about the bit"
    else
        urun "$UROOT/sparse"
        { [ "$( UATTR head_basis )" = "archived-index-hidden" ] && [ "$URC" -eq 2 ]; } \
            && ok "(U4) KNOWN GAP: a sparse checkout refuses the identity basis and gates on the archived tree, and the root SAYS which branch it took (head_basis=archived-index-hidden, exit 2) — flipping this arm to gating=0 is the acceptance test for slice 2" \
            || no "(U4) exit $URC head_basis=$( UATTR head_basis ) — expected the disclosed archived refusal; if this now reports gating=0 with head_basis=identity, the gap is CLOSED and this arm should be flipped to uzero"
    fi
else
    no "(U4) sparse-checkout is unavailable here — the arm would be vacuous"
fi

# U5 THE TWO INDEX BITS GIT'S OWN DIFF IS SPECIFIED NOT TO READ. `git update-index --skip-worktree` and
# `--assume-unchanged` both make `git diff --quiet HEAD` exit 0 over a file whose on-disk bytes genuinely
# differ from HEAD — that is the entire purpose of the bits. Treating that exit code as "the tree IS HEAD"
# turned a REAL dead-code regression into gating="0" exit 0: a false NEGATIVE, which is a worse answer than
# the false positive the identity basis exists to remove. So the identity basis is refused whenever such a
# path is still ON DISK, and these arms are the proof. They must read exactly like the archived comparison,
# because that is what answers them.
# $1 = label, $2 = git update-index flag, $3 = how the caller is made to vanish: `edit` or `delete`,
# $4 = optional `cone:<dirs>` to run the same shape inside an ACTIVE cone-mode sparse checkout.
ublind(){
    local label="$1" flag="$2" how="$3" cone="${4:-}"
    local d; d="$UROOT/blind$( printf '%s%s%s' "$flag" "$how" "$cone" | tr -cd 'a-z' )"   # own dir per shape: one `local` cannot expand a name it is still assigning
    umk "$d"
    if [ -n "$cone" ]; then
        ( cd "$d" && ug sparse-checkout init --cone && ug sparse-checkout set ${cone#cone:} ) >/dev/null 2>&1 \
            || { no "(U5) $label: sparse-checkout is unavailable here — the arm would be vacuous"; return; }
    fi
    ( cd "$d" && ug update-index "$flag" app/main.py ) >/dev/null 2>&1
    case "$how" in
        edit)   printf 'def driver():\n    return 0\n' > "$d/app/main.py" ;;   # a REAL edit: the only caller, gone
        delete) rm -f "$d/app/main.py" ;;                                       # a REAL deletion: the file that held it, gone
        *)      no "(U5) $label: unknown mode $how"; return ;;
    esac
    # The arm is only about the BIT if git itself reports nothing. If the change shows in `git status` the
    # ordinary dirty path would catch it anyway and the arm proves nothing.
    if [ -n "$( cd "$d" && ug status --porcelain )" ]; then
        no "(U5) $label: git status is NOT clean, so the bit is not hiding the change and the arm is vacuous"
        return
    fi
    urun "$d"
    local dead; dead="$( printf '%s' "$UOUT" | grep -c 'kind="dead-code" sym="zeta_helper"' )"
    { [ "$URC" -eq 2 ] && [ "$( UATTR gating )" = "1" ] && [ "$dead" -eq 1 ]; } \
        && ok "(U5) $label: the hidden change STILL gates one dead-code row (exit 2)" \
        || no "(U5) $label: exit $URC gating=$( UATTR gating ) dead rows=$dead — a real regression was swallowed by an index bit"
    # THE REFUSAL IS NAMED ON THE ANSWER, not left to silence. A user whose fast path vanished can read why
    # off the root instead of guessing, and "identity" here would be the bug itself asserting it verified.
    [ "$( UATTR head_basis )" = "archived-index-hidden" ] \
        && ok "(U5) $label: head_basis=archived-index-hidden — the archived HEAD tree answered, and the root says WHY" \
        || no "(U5) $label: head_basis=$( UATTR head_basis ) — the refusal is undisclosed, or the identity basis was claimed over a change git will not read"
    # THE ESCAPE HATCH MUST NOT LAUNDER IT EITHER. --quality-baseline refuses to pin over a tree that already
    # holds gating findings (H11), so a shape that gates must also be a shape the bare pin declines.
    if ( cd "$d" && TMPDIR="$UTMP" "$BIN" "$PWD" --quality-baseline >/dev/null 2>&1 ); then
        no "(U5) $label: --quality-baseline PINNED over the hidden regression — the floor was laundered"
    else
        ok "(U5) $label: --quality-baseline declines to pin over it"
    fi
}
ublind "skip-worktree over an edited caller"          --skip-worktree    edit
ublind "assume-unchanged over an edited caller"       --assume-unchanged edit
# The DELETION half. `git update-index --skip-worktree PATH` followed by `rm PATH` hides a deletion exactly as
# it hides an edit, and the deleted file held the only caller. Round 1 of the fix tested PRESENCE ON DISK and
# was defeated here: the file is gone, so "not present" read as "nothing hidden" and the identity basis was
# taken — reporting gating="0" and ASSERTING head_basis="identity" over a real regression.
ublind "skip-worktree over a DELETED caller"          --skip-worktree    delete
ublind "assume-unchanged over a DELETED caller"       --assume-unchanged delete
# ...and the same deletion INSIDE an active cone-mode sparse checkout that INCLUDES the path. The sparse
# specification says this file belongs here, so its absence is not explained by the spec and the basis must
# still be refused: "a sparse checkout is on" is not by itself an explanation for any flagged path.
ublind "skip-worktree over a DELETED caller inside the cone" --skip-worktree delete "cone:lib app"
# ...and the ANCESTOR-DIRECTORY shape, which is what defeated the hand-written cone rule. Cone mode also
# materializes the direct files of every ANCESTOR of a listed directory: with cone=[app/sub, lib], `app` is not
# listed but `app/other.py` is checked out all the same. A rule that only knew "listed, or under a listed one,
# or a repository-root file" called that path cone-excluded and took the identity basis over a real deletion.
# There is no cone rule here any more, so this arm is the proof that the class is closed rather than narrowed.
uanc(){
    local d="$UROOT/ancestorcone"
    mkdir -p "$d/lib" "$d/app/sub"
    printf 'def zeta_helper(v):\n    return v + 1\n'    > "$d/lib/core.py"
    printf 'def driver():\n    return zeta_helper(1)\n' > "$d/app/other.py"   # the ONLY caller, in the ancestor dir
    printf 'def nested():\n    return 1\n'               > "$d/app/sub/deep.py"
    ( cd "$d" && ug init -q . && ug add -A && ug commit -qm init ) >/dev/null 2>&1
    ( cd "$d" && ug sparse-checkout init --cone && ug sparse-checkout set app/sub lib ) >/dev/null 2>&1 \
        || { no "(U5a) sparse-checkout is unavailable here — the ancestor arm would be vacuous"; return; }
    if [ ! -f "$d/app/other.py" ]; then
        no "(U5a) this git does not materialize the ancestor directory's own files, so the arm does not test the shape it claims"
        return
    fi
    ( cd "$d" && ug update-index --skip-worktree app/other.py ) >/dev/null 2>&1
    rm -f "$d/app/other.py"
    if [ -n "$( cd "$d" && ug status --porcelain )" ]; then
        no "(U5a) git status is NOT clean, so the bit is not hiding the deletion and the arm is vacuous"
        return
    fi
    urun "$d"
    local dead; dead="$( printf '%s' "$UOUT" | grep -c 'kind="dead-code" sym="zeta_helper"' )"
    { [ "$URC" -eq 2 ] && [ "$( UATTR gating )" = "1" ] && [ "$dead" -eq 1 ]; } \
        && ok "(U5a) a flagged+deleted file in an ANCESTOR of a listed cone directory STILL gates one dead-code row (exit 2)" \
        || no "(U5a) exit $URC gating=$( UATTR gating ) dead rows=$dead — the ancestor-directory shape was misjudged as explained"
    [ "$( UATTR head_basis )" = "archived-index-hidden" ] \
        && ok "(U5a) head_basis=archived-index-hidden — the refusal is disclosed on the answer" \
        || no "(U5a) head_basis=$( UATTR head_basis ) — identity was claimed over a deletion in an ancestor directory"
    if ( cd "$d" && TMPDIR="$UTMP" "$BIN" "$PWD" --quality-baseline >/dev/null 2>&1 ); then
        no "(U5a) --quality-baseline PINNED over it — the floor was laundered"
    else
        ok "(U5a) --quality-baseline declines to pin over it"
    fi
}
uanc

# U5c the refusal must not become its own source of noise: a flagged file whose content still IS HEAD's
# reports zero through the archived comparison, and says so.
umk "$UROOT/blindclean"
( cd "$UROOT/blindclean" && ug update-index --skip-worktree app/main.py ) >/dev/null 2>&1
urun "$UROOT/blindclean"
{ [ "$URC" -eq 0 ] && [ "$( UATTR gating )" = "0" ] && [ "$( UATTR head_basis )" = "archived-index-hidden" ]; } \
    && ok "(U5c) a flagged but UNEDITED file reports zero through the archived comparison, with the refusal disclosed" \
    || no "(U5c) exit $URC gating=$( UATTR gating ) head_basis=$( UATTR head_basis ) — refusing the identity basis introduced noise of its own"

# U6 crawl flags that reached ONE side of the delta only.
umk "$UROOT/noignore"
printf 'generated/\n' > "$UROOT/noignore/.gitignore"; mkdir -p "$UROOT/noignore/generated"
printf 'def zeta_helper(v):\n    return v * 3\n' > "$UROOT/noignore/generated/gen.py"
( cd "$UROOT/noignore" && ug add -A && ug commit -qm ignore ) >/dev/null 2>&1
uzero "--no-ignore over a gitignored same-named definition" "$UROOT/noignore" --no-ignore
umk "$UROOT/ignoretests"; mkdir -p "$UROOT/ignoretests/tests"
printf 'def test_it():\n    return zeta_helper(1)\n' > "$UROOT/ignoretests/tests/test_core.py"
( cd "$UROOT/ignoretests" && ug add -A && ug commit -qm tests ) >/dev/null 2>&1
uzero "--ignore-tests with a helper called only from tests/" "$UROOT/ignoretests" --ignore-tests

# U7 THE SENSITIVITY CONTROL: a real edit in the hardest shape must still produce exactly one gating row.
umk "$UROOT/control"
printf 'def zeta_helper(v):\n    return v * 5\n' > "$UROOT/control/scratchdir_dup.py"
printf 'def driver():\n    return 0\n'           > "$UROOT/control/app/main.py"
urun "$UROOT/control"
UDEAD="$( printf '%s' "$UOUT" | grep -c 'kind="dead-code" sym="zeta_helper"' )"
{ [ "$URC" -eq 2 ] && [ "$( UATTR gating )" = "1" ] && [ "$UDEAD" -eq 1 ]; } \
    && ok "(U7) control: deleting the only caller still gates exactly one dead-code row (exit 2) with untracked content present" \
    || no "(U7) control did not fire — exit $URC gating=$( UATTR gating ) dead-code rows on zeta_helper=$UDEAD; every zero above is suspect"

# U8 DETERMINISM: cold (a temp dir that never held a blob), warm, cold again — byte for byte.
umk "$UROOT/determinism"
printf 'def zeta_helper(v):\n    return v * 5\n' > "$UROOT/determinism/scratchdir_dup.py"
urun "$UROOT/determinism"; UD1="$UOUT"
urun "$UROOT/determinism"; UD2="$UOUT"
mkdir -p "$UROOT/scratch2"
# The same shape as the (U) TMPDIR arm above, found by sweeping this file for it as CodeRabbit asked.
# `urun` itself calls no assertion, so nothing was lost here YET — but it is one `no()` away from the same
# silent failure, and UOUT crossing a subshell boundary is exactly why the third run had to be written to a
# file. Save/restore in the parent: the write-to-a-file dance goes with it.
UTMP_SAVED="$UTMP"; UTMP="$UROOT/scratch2"
urun "$UROOT/determinism"; UD3="$UOUT"
UTMP="$UTMP_SAVED"
{ [ "$UD1" = "$UD2" ] && [ "$UD2" = "$UD3" ]; } \
    && ok "(U8) cold / warm / cold-with-a-fresh-TMPDIR are byte-identical" \
    || no "(U8) the unchanged-tree answer moved between cold, warm and a fresh TMPDIR"

# U9 THE ESCAPE HATCH: --quality-baseline refused to pin over the phantom debt. It must pin now.
umk "$UROOT/pin"
printf 'def zeta_helper(v):\n    return v * 5\n' > "$UROOT/pin/scratchdir_dup.py"
if ( cd "$UROOT/pin" && TMPDIR="$UTMP" "$BIN" "$PWD" --quality-baseline >/dev/null 2>&1 ); then
    ok "(U9) --quality-baseline pins on an unchanged tree that holds untracked content"
else
    no "(U9) --quality-baseline still refuses to pin over an unchanged tree's phantom debt"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
