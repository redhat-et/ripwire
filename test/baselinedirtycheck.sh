#!/usr/bin/env bash
# baselinedirtycheck.sh — H11 (capture-audit 2026-09-04, lens 8 #2 / lens 3 H4): --quality-baseline PINNED ON
# A DIRTY TREE SILENTLY ABSORBS THE DEBT ALREADY IN IT.
#
# THE DEFECT, reproduced in the capture's own sandbox. A regression was introduced, then a baseline was
# pinned on that regressed tree. The next --quality-delta read
#
#   <quality-delta baseline="sidecar" regressions="0" gating="0" …>
#
# — a green report — while --edit-check on the SAME tree said `contract-change incompatible="4"` and --dmm
# scored `bad="139"`. Nothing anywhere said a floor had been moved. That is the worst sentence this verb can
# say ("you're clean") produced by the verb whose whole job is to say when you are not, and the quality-bar
# skill's own advice ("run --quality-baseline FIRST") walks an agent straight into it: pin at the start of a
# task on a tree that is already mid-edit, and every finding in that tree is now the floor, forever.
#
# THE RULE THIS GATE ASSERTS:
#
#   R1  PRECONDITION — a dirty tree with a real regression really does gate (gating>=1 vs HEAD). Without
#       this arm every arm below could pass on a fixture that had nothing to absorb.
#   R2  REFUSE — --quality-baseline on that tree exits NON-ZERO, names the COUNT it would absorb, names the
#       FIRST row, and names the escape hatch (--allow-dirty). No sidecar is written.
#   R3  ESCAPE HATCH — --quality-baseline --allow-dirty writes the sidecar (exit 0) and STAMPS what it
#       absorbed into it, so the fact survives the process that knew it.
#   R4  CARRY — a --quality-delta honoring such a sidecar carries baseline_absorbed="N" on its ROOT, and the
#       legend DEFINES it (a green exit beside it means "clean SINCE THE PIN", never "clean").
#   R5  CLEAN TREE — none of this fires on a clean tree: --quality-baseline exits 0 with no absorbed stamp,
#       and the delta root carries NO baseline_absorbed= (absent means none, the house rule).
#   R6  MODIFIER — --allow-dirty alone (no --quality-baseline) refuses, naming both flags; it is a modifier
#       and the accept-and-ignore class is what validateModifierGuards exists to prevent.
#   R7  DETERMINISM + WELL-FORMEDNESS on the delta that carries the new attribute.
#
# RED-FIRST EVIDENCE: R2, R3, R4 and R6 all FAIL against the pre-fix binary — the baseline was written
# silently at exit 0, --allow-dirty was not a flag at all, and the delta root carried nothing. Run
#   bash test/baselinedirtycheck.sh /path/to/prefix/build/ripwire
# to see it red on the shipped behaviour. R1/R5/R7 pass before and after (they are the control).
#
# Operates on a private temp git repo (never touches the real repo — --quality-baseline WRITES). Needs git.
# Usage:  bash test/baselinedirtycheck.sh [BIN]   |   RIPWIRE_BIN=build/ripwire bash test/baselinedirtycheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "baselinedirtycheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
SEED="$TMP/seed"; mkdir -p "$SEED/src"

# HEAD: a small, low-complexity function that plainly EXISTS at the baseline (so the regression below is
# preexisting-worse, i.e. it gates — a new-symbol finding never would).
cat > "$SEED/src/engine.cpp" <<'EOF'
int classify( int x )
{
    return x;
}
int other( int x )
{
    return x + 1;
}
EOF
( cd "$SEED" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )

# The DIRTY edit: same symbol, thirty decision points. Complexity, verbosity and nesting all worsen on a
# symbol that existed at HEAD — exactly the debt a baseline pinned here would swallow.
dirty(){
    {
      echo 'int classify( int x )'
      echo '{'
      echo '    int acc = 0;'
      for i in $( seq 1 30 ); do
          echo "    if( x > $i ) { if( x % $i == 0 ) { acc += $i; } else { acc -= $i; } }"
      done
      echo '    return acc;'
      echo '}'
      echo 'int other( int x )'
      echo '{'
      echo '    return x + 1;'
      echo '}'
    } > "$1/src/engine.cpp"
}

fresh(){ local d="$TMP/$1"; rm -rf "$d"; cp -R "$SEED" "$d"; printf '%s' "$d"; }
root_of(){ grep -oE '<quality-delta[^>]*>' "$1" | head -1; }

echo
echo "── R1 — the fixture really does gate against HEAD ──────────────────────────────────────────────"
D="$( fresh r1 )"; dirty "$D"
( cd "$D" && "$BIN" . --no-cache --quality-delta > "$D/d.xml" 2>"$D/d.err" ); rc=$?
GATING="$( root_of "$D/d.xml" | grep -oE 'gating="[0-9]+"' | tr -dc '0-9' )"
[ -n "$GATING" ] && [ "$GATING" -ge 1 ] \
    && ok "R1: the dirty fixture gates vs HEAD (gating=\"$GATING\", rc=$rc)" \
    || { no "R1: the fixture does NOT gate (gating='$GATING', rc=$rc) — every arm below would be vacuous"; root_of "$D/d.xml"; }

echo
echo "── R2 — --quality-baseline on that tree REFUSES, names N and the first row, writes nothing ─────"
D="$( fresh r2 )"; dirty "$D"
( cd "$D" && "$BIN" . --no-cache --quality-baseline > "$D/b.out" 2>"$D/b.err" ); rc=$?
[ "$rc" -ne 0 ] \
    && ok "R2: --quality-baseline on a dirty tree refuses (rc=$rc)" \
    || no "R2: --quality-baseline SILENTLY absorbed the debt (rc=0): $( cat "$D/b.err" )"
grep -qE '[0-9]+ ' "$D/b.err" && grep -qi 'absorb' "$D/b.err" \
    && ok "R2: the refusal says what would be absorbed, with a count" \
    || no "R2: the refusal does not name the absorbed count: $( cat "$D/b.err" )"
grep -q 'classify' "$D/b.err" \
    && ok "R2: the refusal names the first row's symbol" \
    || no "R2: the refusal does not name a row: $( cat "$D/b.err" )"
grep -q 'allow-dirty' "$D/b.err" \
    && ok "R2: the refusal names the escape hatch (--allow-dirty)" \
    || no "R2: the refusal offers no way forward: $( cat "$D/b.err" )"
[ -f "$D/.ripwire_quality_baseline" ] \
    && no "R2: the refusal still wrote the sidecar" \
    || ok "R2: no sidecar was written"

echo
echo "── R3/R4 — --allow-dirty writes, STAMPS what it absorbed, and the delta carries it ─────────────"
D="$( fresh r3 )"; dirty "$D"
( cd "$D" && "$BIN" . --no-cache --quality-baseline --allow-dirty > "$D/b.out" 2>"$D/b.err" ); rc=$?
[ "$rc" -eq 0 ] && ok "R3: --allow-dirty writes the baseline (rc=0)" \
                || no "R3: --allow-dirty did not write (rc=$rc): $( cat "$D/b.err" )"
[ -f "$D/.ripwire_quality_baseline" ] && ok "R3: the sidecar exists" || no "R3: no sidecar on disk"
ABS="$( grep -E '^absorbed ' "$D/.ripwire_quality_baseline" 2>/dev/null | awk '{print $2}' )"
{ [ -n "$ABS" ] && [ "$ABS" -ge 1 ]; } \
    && ok "R3: the sidecar records what it absorbed (absorbed $ABS)" \
    || no "R3: the sidecar carries no absorbed stamp — the fact died with the process"
grep -qE '^dirty 1' "$D/.ripwire_quality_baseline" 2>/dev/null \
    && ok "R3: the sidecar records that it was pinned on a dirty tree (dirty 1)" \
    || no "R3: the sidecar does not record the dirty pin"
( cd "$D" && "$BIN" . --no-cache --quality-delta > "$D/d.xml" 2>"$D/d.err" ); rc=$?
R="$( root_of "$D/d.xml" )"
printf '%s' "$R" | grep -q 'baseline="sidecar"' \
    && ok "R4: the sidecar is honored (baseline=\"sidecar\")" \
    || no "R4: the sidecar was not honored — the arm below measures nothing: $R"
CARRIED="$( printf '%s' "$R" | grep -oE 'baseline_absorbed="[0-9]+"' | tr -dc '0-9' )"
# both-empty must NOT read as agreement — that is how this arm passed vacuously on the pre-fix binary.
{ [ -n "$CARRIED" ] && [ "$CARRIED" = "$ABS" ]; } \
    && ok "R4: the delta root carries baseline_absorbed=\"$CARRIED\", equal to the sidecar's stamp" \
    || no "R4: the delta root's baseline_absorbed ('$CARRIED') does not match the sidecar ('$ABS'): $R"
grep -q 'baseline_absorbed' "$D/d.xml" && grep -q 'since the pin' "$D/d.xml" \
    && ok "R4: the legend DEFINES baseline_absorbed and says a green exit means \"clean since the pin\"" \
    || no "R4: baseline_absorbed is emitted with no legend definition (legendcoveragecheck's rule)"

echo
echo "── R5 — a CLEAN tree is untouched by all of it ─────────────────────────────────────────────────"
D="$( fresh r5 )"
( cd "$D" && "$BIN" . --no-cache --quality-baseline > "$D/b.out" 2>"$D/b.err" ); rc=$?
[ "$rc" -eq 0 ] && ok "R5: --quality-baseline on a clean tree still just writes (rc=0)" \
                || no "R5: a clean tree was refused (rc=$rc): $( cat "$D/b.err" )"
grep -qE '^absorbed |^dirty 1' "$D/.ripwire_quality_baseline" 2>/dev/null \
    && no "R5: a clean pin stamped an absorbed/dirty record" \
    || ok "R5: a clean pin stamps nothing (absent means none)"
( cd "$D" && "$BIN" . --no-cache --quality-delta > "$D/d.xml" 2>/dev/null )
root_of "$D/d.xml" | grep -q 'baseline_absorbed' \
    && no "R5: a clean-pin delta root carries baseline_absorbed=" \
    || ok "R5: a clean-pin delta root carries no baseline_absorbed= (absent means none)"

echo
echo "── R6 — --allow-dirty is a MODIFIER, and refuses alone ─────────────────────────────────────────"
D="$( fresh r6 )"
( cd "$D" && "$BIN" . --no-cache --allow-dirty > /dev/null 2>"$D/e" ); rc=$?
[ "$rc" -ne 0 ] && ok "R6: bare --allow-dirty refuses (rc=$rc)" \
                || no "R6: bare --allow-dirty was accepted and silently ignored (rc=0)"
grep -q 'allow-dirty' "$D/e" && grep -q 'quality-baseline' "$D/e" \
    && ok "R6: the refusal names both flags" \
    || no "R6: the refusal does not name both flags: $( cat "$D/e" )"

echo
echo "── R7 — determinism + well-formedness ──────────────────────────────────────────────────────────"
D="$( fresh r7 )"; dirty "$D"
( cd "$D" && "$BIN" . --no-cache --quality-baseline --allow-dirty >/dev/null 2>&1 )
( cd "$D" && "$BIN" . --no-cache --quality-delta > q1 2>/dev/null; "$BIN" . --no-cache --quality-delta > q2 2>/dev/null )
cmp -s "$D/q1" "$D/q2" && ok "R7: --quality-delta is byte-identical across runs" || no "R7: --quality-delta is not deterministic"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$D/q1" 2>/dev/null && ok "R7: the carrying delta is well-formed XML" || no "R7: the carrying delta is not well-formed"
else
    echo "  SKIP  xmllint not installed"
fi

echo
[ "$fail" -eq 0 ] && echo "baselinedirtycheck: ALL PASS" || echo "baselinedirtycheck: FAILURES"
exit "$fail"
