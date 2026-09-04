#!/usr/bin/env bash
# qualitycheck.sh — gate for --quality-baseline / --quality-delta (the convergence-loop oracle). Snapshot the
# code-quality state, make a change, and assert --quality-delta reports ONLY what got worse (new complexity
# over the ccx bar, new duplication, newly-dead), exit 2 on new debt / 0 when clean / 1 with no baseline.
#
# Operates entirely in a temp dir (the baseline sidecar lands in CWD), so the repo is never touched.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/qualitycheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"
# clean baseline state: one trivial fn + a caller (so nothing is dead)
printf 'int simple(){ return 1; }\nint useit(){ return simple(); }\n' > "$WORK/src/a.cpp"
cd "$WORK"                                            # so .ripwire_quality_baseline is written HERE, not in the repo
echo "qualitycheck: BIN=$BIN  (temp corpus)"

dq(){ "$BIN" . --quality-delta --no-cache 2>/dev/null; }
ec(){ "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $?; }

# ── 1) snapshot the clean state ───────────────────────────────────────────────────────────────────────
"$BIN" . --quality-baseline --no-cache >/dev/null 2>&1
[ -f .ripwire_quality_baseline ] && ok "--quality-baseline writes the sidecar" || no "no .ripwire_quality_baseline written"

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
[ "$OUT" = "$( dq )" ] && ok "deterministic (delta byte-identical run-to-run)" || no "non-deterministic delta"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
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
[ "$( ecd )" = 0 ] && ok "Q1 sub-corpus: unchanged → exit 0" || { no "Q1 sub-corpus should start clean (exit $( ecd ))"; dqd; }

# now regress each kind at once: grow() LOC over kLocBar(60), deepen() nesting over kNestBar(4),
# widen() params over kParamBar(5), and add a NEW public header symbol (contract drift).
{ printf 'int grow( int a ){\n'; for i in $( seq 1 70 ); do printf '  a = a + %d;\n' "$i"; done; printf '  return a;\n}\n'
  printf 'int deepen( int a ){ if(a>0){ if(a>1){ if(a>2){ if(a>3){ if(a>4){ return a; } } } } } return 0; }\n'
  printf 'int widen( int a, int b, int c, int d, int e, int f ){ return a+b+c+d+e+f; }\n'
  printf 'int drive(){ return grow(1)+deepen(1)+widen(1,2,3,4,5,6); }\n'
} > "$QD/src/g.cpp"
printf 'int existing_public( int a );\nint newly_public( int a );\n' > "$QD/src/api.h"
OD="$( dqd )"
[ "$( ecd )" = 2 ] && ok "Q1 regressions → exit 2" || no "Q1 regressions should exit 2 (got $( ecd ))"
printf '%s' "$OD" | grep -q 'kind="verbosity" sym="grow" was="' \
    && ok "verbosity regression: grow flagged (LOC grew over the bar)"  || { no "verbosity regression missing"; printf '%s\n' "$OD" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OD" | grep -q 'kind="nesting" sym="deepen" was="' \
    && ok "nesting regression: deepen flagged (nesting grew over the bar)" || no "nesting regression missing"
printf '%s' "$OD" | grep -q 'kind="params" sym="widen" was="' \
    && ok "params regression: widen flagged (param count grew over the bar)" || no "params regression missing"
printf '%s' "$OD" | grep -q 'kind="api-surface" sym="newly_public"' \
    && ok "api-surface regression: newly_public flagged (new exported symbol)" || no "api-surface regression missing"
# precision: the pre-existing public decl must NOT be reported (it was in the baseline set)
printf '%s' "$OD" | grep -q 'kind="api-surface" sym="existing_public"' \
    && no "existing_public wrongly flagged (it was already public in the baseline)" || ok "pre-existing public not re-flagged (precision)"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OD" | xmllint --noout - 2>/dev/null && ok "Q1 delta xml well-formed" || no "Q1 delta xml malformed"
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
[ "$( ec )" = 1 ] && ok "no baseline → exit 1 (tells you to run --quality-baseline first)" || no "missing baseline should exit 1"

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
    *"predates the pathQualifiedKey scheme"*) ok "the pre-v4 sidecar is REFUSED by name, not silently misread" ;;
    *) no "a pre-v4 sidecar was consumed without a refusal — every symbol would read as new debt: $( printf '%s' "$V1OUT" | head -c 160 )" ;;
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
    [ "$( ecgh )" = 2 ] && ok "T0.1: uncommitted regression vs HEAD → exit 2" || no "T0.1: regression vs HEAD should exit 2 (got $( ecgh ))"
    printf '%s' "$RGH" | grep -q 'kind="verbosity" sym="simple"' \
        && ok "T0.1: verbosity regression on simple() flagged vs HEAD" || { no "T0.1: verbosity regression missing"; printf '%s\n' "$RGH" | tr '>' '\n' | grep '<r '; }
    printf '%s' "$RGH" | grep -q 'kind="nesting" sym="simple"' \
        && ok "T0.1: nesting regression on simple() flagged vs HEAD" || no "T0.1: nesting regression missing"

    # 7c) determinism: HEAD content is fixed → byte-identical run-to-run.
    [ "$RGH" = "$( dgh )" ] && ok "T0.1: auto-vs-HEAD delta byte-identical run-to-run (deterministic)" || no "T0.1: non-deterministic auto-vs-HEAD delta"
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$RGH" | xmllint --noout - 2>/dev/null && ok "T0.1: auto-vs-HEAD xml well-formed" || no "T0.1: auto-vs-HEAD xml malformed"
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

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
