#!/usr/bin/env bash
# slicediffcheck.sh — gate for --slice=SYM:VAR --since=REV: the def-use slice as it was at REV versus as
# it is now, so a regression review reads the DEPENDENCE change and not the textual diff (card A4, from
# COMMITGUARD arXiv:2608.17401). The band, the output contract and the 57-row labelled set are registered
# in docs/EVALS.md under "--slice=SYM:VAR --since=REV" and in test/slicediffix/labels.tsv — both were
# written before this feature existed.
#
# RED-FIRST PROOF SHAPE: every arm asserts diff-SPECIFIC bytes — the <since> element, its status= values,
# an <sd>/<se> row, a legend sentence this block alone prints, or a refusal sentence this pairing alone
# prints. A baseline binary refuses `--since` beside `--slice` at exit 1 with none of those bytes, so each
# arm fails against it; asserting "nonzero exit" alone would be green-while-inert (CONTRIBUTING §2).
#
# Arms:
#   (1)  0 NEW BYTES without --since: the same argv minus --since is byte-identical to the pre-feature form
#   (2)  a commit that ADDS a statement using VAR: <since status="ok"> with an <sd op="+"> row
#   (3)  a commit that only edits COMMENTS inside the sliced symbol: added=removed=edges_*=0, no rows
#   (4)  a commit that only RE-WRAPS a statement of VAR across lines: still empty (statement grain, not line)
#   (5)  a commit that only inserts lines ABOVE the symbol (every line number moves): still empty
#   (6)  a value-only edit (`v = 111;` -> `v = 222;`): EMPTY, and the legend says why that is correct
#   (7)  edges: a def inserted BETWEEN a def and its use moves the reaching def -> <se op="+"> and <se op="-">
#   (8)  status="sym_absent_at_rev": the file existed, the definition did not — every row reads "+"
#   (9)  status="var_absent_at_rev": the definition existed, the variable did not — every row reads "+"
#   (10) status="file_absent_at_rev": comparable="0", NO rows, and the legend disclaims the emptiness
#   (11) a RENAMED file is followed once and disclosed as renamed_from=
#   (12) refusals: a --since that resolves to no commit, and a non-git root — both exit 1, no XML
#   (13) the --since legend restates the slice's own limits (name-based / no alias analysis / no flow
#        sensitivity) plus the statement grain and the comparable="0" reading
#   (14) determinism x2 byte-identical, and cold (--no-cache) == warm
#   (15) xmllint well-formedness on a diff-bearing run
#   (16) a DATE --since resolves to a commit and discloses resolved=
#   (17) THE BAND: replay test/slicediffix/labels.tsv in a private clone of the repo under test —
#        dependence rows must be NON-EMPTY on >= 18 of 20, reformat rows EMPTY on >= 19 of 20
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/slicediffcheck.sh   |   bash test/slicediffcheck.sh path/to/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT

G(){ git -C "$1" -c user.email=g@t -c user.name=g -c commit.gpgsign=false -c init.defaultBranch=main "${@:2}"; }

# ── a two-commit fixture repo: $1 = dir, then commit bodies are written by the caller ─────────────────
newrepo(){
  mkdir -p "$1/src"
  git init -q "$1" 2>/dev/null
  G "$1" config user.email g@t
  G "$1" config user.name g
}
commitall(){ G "$1" add -A; G "$1" commit -q -m "$2"; }

# ═══ fixture A: the four shapes that must be EMPTY plus the two that must not ════════════════════════
A="$WORK/a"; newrepo "$A"
cat > "$A/src/a.cpp" <<'EOF'
void sink( int v );

int worker( int limit )
{
    // the seed
    int v = 111;
    sink( v );
    return v + limit;
}
EOF
commitall "$A" "base"
BASE_A="$( G "$A" rev-parse HEAD )"

before="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --no-cache 2>/dev/null )"

# (2) a commit that ADDS a statement using v
cat > "$A/src/a.cpp" <<'EOF'
void sink( int v );

int worker( int limit )
{
    // the seed
    int v = 111;
    sink( v );
    sink( v + 1 );
    return v + limit;
}
EOF
commitall "$A" "add a statement using v"
ADD_A="$( G "$A" rev-parse HEAD )"
out="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$BASE_A" --no-cache 2>/dev/null )"
case "$out" in
  *'<since '*'status="ok"'*'<sd op="+"'*) ok '(2) an added statement using VAR rows as <sd op="+"> under status="ok"' ;;
  *) no '(2) an added statement using VAR did not produce an <sd op="+"> row' ;;
esac

# (1) 0 NEW BYTES without --since — the same argv minus the flag is byte-identical to the pre-feature form
now="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --no-cache 2>/dev/null )"
case "$now" in
  *'<since'*) no '(1) a run WITHOUT --since emitted <since> bytes' ;;
  *) ok '(1) a run without --since carries no <since> bytes' ;;
esac
[ -n "$before" ] || no '(1) the pre-change slice was empty — fixture broken'

# helper: is the <since> of $1 empty (no added/removed rows and no added/removed edges)?
empty_diff(){
  case "$1" in
    *'added="0" removed="0" edges_added="0" edges_removed="0"'*) return 0 ;;
    *) return 1 ;;
  esac
}

# (3) a COMMENT-only edit inside the sliced symbol
cat > "$A/src/a.cpp" <<'EOF'
void sink( int v );

int worker( int limit )
{
    // the seed — reworded, and a second comment line added
    // (nothing executable moved)
    int v = 111;
    sink( v );
    sink( v + 1 );
    return v + limit;
}
EOF
commitall "$A" "comments only"
out="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$ADD_A" --no-cache 2>/dev/null )"
if empty_diff "$out" && case "$out" in *'<sd '*|*'<se '*) false ;; *) true ;; esac
then ok '(3) a comment-only edit inside the symbol is an EMPTY dependence diff'
else no '(3) a comment-only edit inside the symbol was not empty'; fi
C3="$( G "$A" rev-parse HEAD )"

# (4) a RE-WRAP of a statement of v across two lines — line grain would call this a change
cat > "$A/src/a.cpp" <<'EOF'
void sink( int v );

int worker( int limit )
{
    // the seed — reworded, and a second comment line added
    // (nothing executable moved)
    int v = 111;
    sink( v );
    sink(
        v + 1 );
    return v + limit;
}
EOF
commitall "$A" "re-wrap one statement"
out="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$C3" --no-cache 2>/dev/null )"
if empty_diff "$out"
then ok '(4) re-wrapping a statement of VAR across lines is an EMPTY dependence diff'
else no '(4) a re-wrap was reported as a dependence change (line grain leaked into the key)'; fi
C4="$( G "$A" rev-parse HEAD )"

# (5) lines inserted ABOVE the symbol: every line number of the slice moves
cat > "$A/src/a.cpp" <<'EOF'
void sink( int v );

int unrelated( int q )
{
    int r = q + 1;
    return r;
}

int worker( int limit )
{
    // the seed — reworded, and a second comment line added
    // (nothing executable moved)
    int v = 111;
    sink( v );
    sink(
        v + 1 );
    return v + limit;
}
EOF
commitall "$A" "insert a function above"
out="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$C4" --no-cache 2>/dev/null )"
if empty_diff "$out"
then ok '(5) an insertion above the symbol (every line number moves) is an EMPTY dependence diff'
else no '(5) a pure line shift was reported as a dependence change'; fi
C5="$( G "$A" rev-parse HEAD )"

# (6) a VALUE-only edit: the def stays a def, the uses stay uses — correct answer is EMPTY
sed -i.bak 's/int v = 111;/int v = 222;/' "$A/src/a.cpp"; rm -f "$A/src/a.cpp.bak"
commitall "$A" "change the literal"
out="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$C5" --no-cache 2>/dev/null )"
if empty_diff "$out"
then ok '(6) a value-only edit of the def is an EMPTY dependence diff'
else no '(6) a value-only edit moved a dependence edge'; fi
case "$out" in
  *'but not its role'*) ok '(6b) the legend states the value-edit reading' ;;
  *) no '(6b) the legend does not state that a same-shape edit is an empty diff by design' ;;
esac
C6="$( G "$A" rev-parse HEAD )"

# ═══ fixture B: an inserted DEF between a def and its use — the edge must move ═══════════════════════
B="$WORK/b"; newrepo "$B"
cat > "$B/src/b.cpp" <<'EOF'
void sink( int v );

int chain( int limit )
{
    int v = 1;
    sink( v );
    return v;
}
EOF
commitall "$B" "base"
BASE_B="$( G "$B" rev-parse HEAD )"
cat > "$B/src/b.cpp" <<'EOF'
void sink( int v );

int chain( int limit )
{
    int v = 1;
    v = limit;
    sink( v );
    return v;
}
EOF
commitall "$B" "insert a second def of v"
out="$( "$BIN" "$B" --slice=src/b.cpp:chain:v --since="$BASE_B" --no-cache 2>/dev/null )"
case "$out" in
  *'<se op="+"'*) ok '(7a) an inserted def adds a def-use edge (<se op="+">)' ;;
  *) no '(7a) an inserted def did not add a def-use edge row' ;;
esac
case "$out" in
  *'<se op="-"'*) ok '(7b) the edge the inserted def displaced is reported removed (<se op="-">)' ;;
  *) no '(7b) the displaced def-use edge was not reported removed' ;;
esac

# ═══ fixture C: the absence statuses ═════════════════════════════════════════════════════════════════
C="$WORK/c"; newrepo "$C"
cat > "$C/src/c.cpp" <<'EOF'
void sink( int v );

int present( int limit )
{
    int p = limit;
    sink( p );
    return p;
}
EOF
commitall "$C" "base"
BASE_C="$( G "$C" rev-parse HEAD )"
cat >> "$C/src/c.cpp" <<'EOF'

int newcomer( int limit )
{
    int n = limit;
    sink( n );
    return n;
}
EOF
commitall "$C" "a new definition"
out="$( "$BIN" "$C" --slice=src/c.cpp:newcomer:n --since="$BASE_C" --no-cache 2>/dev/null )"
case "$out" in
  *'status="sym_absent_at_rev"'*'<sd op="+"'*) ok '(8) a definition that did not exist at REV: status="sym_absent_at_rev", every row "+"' ;;
  *) no '(8) a definition absent at REV was not disclosed as sym_absent_at_rev with all-added rows' ;;
esac
case "$out" in *'<sd op="-"'*) no '(8b) sym_absent_at_rev emitted a removed row' ;; *) ok '(8b) sym_absent_at_rev emits no removed row' ;; esac
NEW_C="$( G "$C" rev-parse HEAD )"

# (9) the definition existed, the VARIABLE did not
cat > "$C/src/c.cpp" <<'EOF'
void sink( int v );

int present( int limit )
{
    int p = limit;
    int fresh = p + 1;
    sink( fresh );
    return p;
}

int newcomer( int limit )
{
    int n = limit;
    sink( n );
    return n;
}
EOF
commitall "$C" "a new local in an old function"
out="$( "$BIN" "$C" --slice=src/c.cpp:present:fresh --since="$NEW_C" --no-cache 2>/dev/null )"
case "$out" in
  *'status="var_absent_at_rev"'*'<sd op="+"'*) ok '(9) a variable that did not exist at REV: status="var_absent_at_rev"' ;;
  *) no '(9) a variable absent at REV was not disclosed as var_absent_at_rev' ;;
esac

# (10) the FILE did not exist at REV — comparable="0", no rows
D="$WORK/d"; newrepo "$D"
cat > "$D/src/keep.cpp" <<'EOF'
int keeper( int a ) { return a; }
EOF
commitall "$D" "base"
BASE_D="$( G "$D" rev-parse HEAD )"
cat > "$D/src/later.cpp" <<'EOF'
void sink( int v );

int later( int limit )
{
    int l = limit;
    sink( l );
    return l;
}
EOF
commitall "$D" "a whole new file"
out="$( "$BIN" "$D" --slice=src/later.cpp:later:l --since="$BASE_D" --no-cache 2>/dev/null )"
case "$out" in
  *'status="file_absent_at_rev"'*'comparable="0"'*) ok '(10) a path absent at REV: status="file_absent_at_rev" comparable="0"' ;;
  *) no '(10) a path absent at REV was not disclosed with comparable="0"' ;;
esac
case "$out" in *'<sd '*|*'<se '*) no '(10b) comparable="0" still emitted diff rows' ;; *) ok '(10b) comparable="0" emits no diff rows' ;; esac
case "$out" in
  *'comparable="0"'*'not evidence'*) ok '(10c) the legend says an empty comparable="0" diff is not evidence of no change' ;;
  *) no '(10c) the legend does not disclaim the comparable="0" emptiness' ;;
esac

# (11) a RENAMED file is followed once and disclosed
E="$WORK/e"; newrepo "$E"
cat > "$E/src/old.cpp" <<'EOF'
void sink( int v );

int mover( int limit )
{
    int m = limit;
    sink( m );
    return m;
}
EOF
commitall "$E" "base"
BASE_E="$( G "$E" rev-parse HEAD )"
G "$E" mv src/old.cpp src/new.cpp
commitall "$E" "rename the file"
out="$( "$BIN" "$E" --slice=src/new.cpp:mover:m --since="$BASE_E" --no-cache 2>/dev/null )"
case "$out" in
  *'renamed_from="src/old.cpp"'*'status="ok"'*) ok '(11) a renamed file is followed once and disclosed as renamed_from=' ;;
  *) no '(11) a renamed file was not followed/disclosed' ;;
esac
if empty_diff "$out"
then ok '(11b) a pure rename is an EMPTY dependence diff' ; else no '(11b) a pure rename was reported as a dependence change' ; fi

# (12) refusals
"$BIN" "$A" --slice=src/a.cpp:worker:v --since=zzqq9nope --no-cache >"$WORK/o12" 2>"$WORK/e12"; rc=$?
if [ $rc -ne 0 ] && [ ! -s "$WORK/o12" ] && grep -q -- 'zzqq9nope' "$WORK/e12"; then
  ok '(12a) a --since that resolves to no commit refuses at exit 1 with no XML'
else no '(12a) an unresolvable --since did not refuse loudly'; fi
mkdir -p "$WORK/nogit/src"; cp "$A/src/a.cpp" "$WORK/nogit/src/a.cpp"
"$BIN" "$WORK/nogit" --slice=src/a.cpp:worker:v --since=HEAD --no-cache >"$WORK/o12b" 2>"$WORK/e12b"; rc=$?
if [ $rc -ne 0 ] && [ ! -s "$WORK/o12b" ] && grep -qi 'git' "$WORK/e12b"; then
  ok '(12b) --since on a non-git root refuses at exit 1 with no XML'
else no '(12b) --since on a non-git root did not refuse'; fi

# (13) the legend restates the slice's own limits inside the --since block
out="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$C6" --no-cache 2>/dev/null )"
leg="${out%%<slice *}"
miss=""
for phrase in 'no alias analysis' 'no flow sensitivity' 'STATEMENT' 'comparable="0"'; do
  case "$leg" in *"$phrase"*) : ;; *) miss="$miss [$phrase]" ;; esac
done
[ -z "$miss" ] && ok '(13) the --since legend restates the slice limits plus its own grain' \
               || no "(13) the --since legend omits:$miss"

# (14) determinism x2, and cold == warm
d1="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$BASE_A" --no-cache 2>/dev/null )"
d2="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$BASE_A" --no-cache 2>/dev/null )"
[ "$d1" = "$d2" ] && ok '(14a) determinism: two cold runs byte-identical' || no '(14a) two cold runs differ'
w1="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$BASE_A" 2>/dev/null )"
w2="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="$BASE_A" 2>/dev/null )"
[ "$w1" = "$w2" ] && [ "$w1" = "$d1" ] && ok '(14b) cold == warm, and warm is stable' || no '(14b) cold and warm disagree'

# (15) well-formedness
if command -v xmllint >/dev/null 2>&1; then
  printf '%s' "$d1" | xmllint --noout - 2>"$WORK/xml" && ok '(15) xmllint: the diff-bearing document is well-formed' \
    || no "(15) xmllint rejected the diff-bearing document: $( head -1 "$WORK/xml" )"
else
  ok '(15) xmllint absent — skipped (environment)'
fi

# (16) a DATE --since resolves and discloses resolved=
out="$( "$BIN" "$A" --slice=src/a.cpp:worker:v --since="1 second ago" --no-cache 2>/dev/null )"
case "$out" in
  *'<since '*'resolved="'*) ok '(16) a DATE --since resolves to a commit and discloses resolved=' ;;
  *) no '(16) a DATE --since did not resolve/disclose' ;;
esac

# ═══ (17) THE BAND — replay the labelled set in a private clone ══════════════════════════════════════
LAB="$ROOT/test/slicediffix/labels.tsv"
if [ ! -f "$LAB" ]; then
  no '(17) test/slicediffix/labels.tsv is missing — the band cannot be scored'
elif ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  ok '(17) the repo under test is not a git checkout — band arm skipped (environment)'
else
  CLONE="$WORK/replay"
  if ! git clone -q --local --no-checkout "$ROOT" "$CLONE" 2>/dev/null; then
    ok '(17) could not make a local clone of the repo under test — band arm skipped (environment)'
  else
    dep_tot=0; dep_hit=0; ref_tot=0; ref_hit=0; skipped=0
    while IFS=$'\t' read -r label sha file sym var why; do
      case "$label" in ''|'#'*) continue ;; esac
      if ! git -C "$CLONE" cat-file -e "$sha^{commit}" 2>/dev/null; then skipped=$(( skipped + 1 )); continue; fi
      git -C "$CLONE" checkout -q -f "$sha" 2>/dev/null || { skipped=$(( skipped + 1 )); continue; }
      o="$( "$BIN" "$CLONE" --slice="$file:$sym:$var" --since="$sha^" --no-cache 2>/dev/null )"
      if empty_diff "$o"; then verdict=empty; else verdict=nonempty; fi
      case "$o" in *'<since '*) : ;; *) verdict=noanswer ;; esac
      if [ "$label" = dependence ]; then
        dep_tot=$(( dep_tot + 1 )); [ "$verdict" = nonempty ] && dep_hit=$(( dep_hit + 1 ))
      elif [ "$label" = reformat ]; then
        ref_tot=$(( ref_tot + 1 )); [ "$verdict" = empty ] && ref_hit=$(( ref_hit + 1 ))
      fi
      [ "$verdict" = noanswer ] && printf '        no <since> for %s %s:%s:%s @ %s\n' "$label" "$file" "$sym" "$var" "${sha:0:9}"
      [ "$label" = dependence ] && [ "$verdict" != nonempty ] && printf '        MISS(dep) %s:%s:%s @ %s\n' "$file" "$sym" "$var" "${sha:0:9}"
      [ "$label" = reformat ] && [ "$verdict" != empty ] && printf '        MISS(ref) %s:%s:%s @ %s\n' "$file" "$sym" "$var" "${sha:0:9}"
    done < "$LAB"
    printf '        labelled replay: dependence %d/%d non-empty, reformat %d/%d empty, %d skipped (absent from this checkout)\n' \
      "$dep_hit" "$dep_tot" "$ref_hit" "$ref_tot" "$skipped"
    if [ "$dep_tot" -eq 0 ] && [ "$ref_tot" -eq 0 ]; then
      ok '(17) no labelled commit is present in this checkout — band arm skipped (environment)'
    else
      if [ "$dep_tot" -lt 20 ] || [ "$ref_tot" -lt 20 ]; then
        no "(17) fewer than 20 labelled commits survived per bucket (dep=$dep_tot ref=$ref_tot) — a short set is not the band"
      fi
      # the registered floors are 18-of-20 and 19-of-20; scored proportionally on the surviving set
      dep_need=$(( ( dep_tot * 18 + 19 ) / 20 ))
      ref_need=$(( ( ref_tot * 19 + 19 ) / 20 ))
      [ "$dep_hit" -ge "$dep_need" ] && ok "(17a) dependence bucket: $dep_hit/$dep_tot non-empty (floor $dep_need)" \
                                     || no "(17a) dependence bucket: $dep_hit/$dep_tot non-empty, below the floor $dep_need"
      [ "$ref_hit" -ge "$ref_need" ] && ok "(17b) reformat bucket: $ref_hit/$ref_tot empty (floor $ref_need)" \
                                     || no "(17b) reformat bucket: $ref_hit/$ref_tot empty, below the floor $ref_need"
    fi
  fi
fi

[ $fail -eq 0 ] && echo "slicediffcheck: ALL PASS" || echo "slicediffcheck: FAILURES"
exit $fail
