#!/usr/bin/env bash
# notecanoncheck.sh — H1 (capture-audit 2026-09-04, lens 0/1/2/3): a NOTE TARGET IS A SELECTOR, and every
# selector spelling a READ verb resolves must resolve identically on the WRITE side.
#
# THE DEFECT, measured on the audited binary. `--note-add="uniqueOnlyHere: text"` — the bare-name spelling
# ~/.claude/CLAUDE.md's own protocol teaches (`--note-add="SYM_or_path: text"`), and 4 of 4 real --note-add
# calls in the routing log — stored the target VERBATIM. The note index keys on the canonical id
# (serialize.h::symbolNoteTarget = canonicalIdRelTo), so the row landed as
#
#   <target id="uniqueOnlyHere" dangling="1">…</target>
#
# and rode on NOTHING: --for and --expand of that very symbol emitted zero <note> children. The write
# succeeded, exit 0, stderr carried only the "add the why" tip. A write-side memory that silently stores
# dead entries is worse than no memory: the agent believes it recorded the gotcha.
#
# Only `src/a.cpp::Widget::uniqueOnlyHere` worked — a spelling nothing teaches and no verb prints as its
# primary handle. Meanwhile --expand/--for/--callers/--uses/--edit-check all accept FIVE spellings of the
# same definition (bare name, file:name, Scope::name, canonical id, @FILE:LINE) through ONE resolver,
# resolveAllByNameQualified. The write side simply never called it.
#
# THE RULE THIS GATE ASSERTS (the family, not the instance):
#
#   R1  RESOLVE — for EVERY selector spelling a read verb accepts, `--note-add=<spelling>: t` stores a
#       target that --notes reports dangling="0", and the note RIDES on --expand=<spelling> and on --for.
#       Enumerated from the resolver's own tiers, not from the one spelling the lens happened to type.
#   R2  ECHO — when the stored target differs from what was typed, the write says so on stderr in one line
#       (naming both spellings) and still prints the STORED line on stdout. A silent rewrite of a caller's
#       input is the other half of the same dishonesty.
#   R3  AMBIGUOUS — a NAME matching N>1 definitions is REFUSED (exit 1), naming N and the disambiguating
#       spellings, and NOTHING is written. Same posture as --slice / --edit-check / the edit verbs over the
#       same resolver ("an ambiguous selector is refused, never silently narrowed").
#   R4  UNRESOLVABLE NAME — a symbol-shaped target that resolves to nothing is REFUSED with the read verbs'
#       did-you-mean, and nothing is written.
#   R5  PATH — a PATH target keeps writing (a note on a file that does not exist yet is legal — that is the
#       "leave this for the file I am about to add" case), but when it matches no indexed file the write
#       prints a LOUD dangling warning on stderr. A path that IS indexed writes silently.
#   R6  DETERMINISM + WELL-FORMEDNESS on --notes and on the surfacing verbs.
#
# RED-FIRST EVIDENCE: arms R1(bare / file:name / Scope::name / @FILE:LINE), R2, R3, R4 and R5(warning) all
# FAIL against the pre-fix binary — every one of those spellings wrote dangling="1" at exit 0. Run
#   bash test/notecanoncheck.sh /path/to/prefix/build/ripwire
# to see it red on the shipped behaviour. R1(canonical id) and R5(indexed path) pass before and after: they
# are the two spellings that already worked, and they are here so the fix is proven not to break them.
#
# Operates on a private temp git repo (never touches the real repo — --note-add WRITES). Needs git.
# Usage:  bash test/notecanoncheck.sh [BIN]   |   RIPWIRE_BIN=build/ripwire bash test/notecanoncheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "notecanoncheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
SEED="$TMP/seed"; mkdir -p "$SEED/src"

# The fixture. `uniqueOnlyHere` is scoped (so its canonical id is NOT its bare name — the whole defect) and
# defined exactly ONCE. `compute` is defined TWICE, in two files, which is R3's ambiguity. The filler keeps
# a.cpp above --expand's whole-file threshold so the expanded answer is a BUNDLE with per-symbol rows, which
# is where a <note> child can attach at all.
{
  echo 'struct Widget'
  echo '{'
  echo '    int uniqueOnlyHere( int x ) { int t = x; for( int i = 0; i < 10; ++i ) { t += helper( i ); } return t; }'
  echo '    int compute( int x ) { return x + 1; }'
  echo '};'
  echo 'int helper( int x ) { return x + 1; }'
  for i in $( seq 1 80 ); do echo "int filler$i( int x ) { return x + $i; }"; done
} > "$SEED/src/a.cpp"
cat > "$SEED/src/b.cpp" <<'EOF'
struct Gadget
{
    int compute( int x ) { return x + 2; }
};
EOF
( cd "$SEED" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )

# The line `uniqueOnlyHere` is defined on — discovered, never hard-coded, so the fixture can grow a line.
UNIQ_LINE="$( grep -n 'int uniqueOnlyHere' "$SEED/src/a.cpp" | head -1 | cut -d: -f1 )"
CANON="src/a.cpp::Widget::uniqueOnlyHere"

# Each arm runs in its OWN copy of the seed repo, so one arm's .ripwire_notes can never leak into the next.
fresh(){ local d="$TMP/$1"; rm -rf "$d"; cp -R "$SEED" "$d"; printf '%s' "$d"; }

echo
echo "── R1/R2 — every read-verb spelling resolves on the write side ─────────────────────────────────"

# spelling → the label used in messages. The five tiers resolveAllByNameQualified probes, in its own order:
# canonical id, Scope::name, file:name, bare name, and the @FILE:LINE line seed.
i=0
for SPELL in "$CANON" "Widget::uniqueOnlyHere" "src/a.cpp:uniqueOnlyHere" "uniqueOnlyHere" "@src/a.cpp:$UNIQ_LINE"; do
    i=$(( i + 1 ))
    D="$( fresh "r1_$i" )"
    # PRECONDITION: the READ side really does accept this spelling — an arm that asserts write/read parity is
    # vacuous if the read half never resolved it either.
    if ! ( cd "$D" && "$BIN" . --no-cache --expand="$SPELL" 2>/dev/null ) | grep -q 'n="uniqueOnlyHere"'; then
        no "R1[$SPELL]: the READ side does not resolve this spelling — arm is vacuous, fix the fixture"
        continue
    fi
    ADD_ERR="$D/add.err"
    LINE="$( cd "$D" && "$BIN" . --no-cache --note-add="$SPELL: watch the loop bound here" 2>"$ADD_ERR" )"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        no "R1[$SPELL]: --note-add refused a spelling the read side accepts (rc=$rc): $( cat "$ADD_ERR" )"
        continue
    fi
    STORED="$( printf '%s' "$LINE" | cut -f1 )"
    NOTES="$( cd "$D" && "$BIN" . --no-cache --notes 2>/dev/null )"
    if printf '%s' "$NOTES" | grep -q 'dangling="1"'; then
        no "R1[$SPELL]: stored target '$STORED' is DANGLING — the note surfaces nowhere"
    else
        ok "R1[$SPELL]: stored '$STORED', dangling=\"0\""
    fi
    if [ "$STORED" != "$CANON" ]; then
        no "R1[$SPELL]: stored target '$STORED' != the canonical id '$CANON' the note index keys on"
    fi
    if ( cd "$D" && "$BIN" . --no-cache --expand="$SPELL" 2>/dev/null ) | grep -q '<note '; then
        ok "R1[$SPELL]: the note rides on --expand"
    else
        no "R1[$SPELL]: --expand of the same spelling carries NO <note> child"
    fi
    if ( cd "$D" && "$BIN" . --no-cache --for="uniqueOnlyHere loop bound" 2>/dev/null ) | grep -q '<note '; then
        ok "R1[$SPELL]: the note rides on --for"
    else
        no "R1[$SPELL]: --for carries NO <note> child for this target"
    fi
    # R2 — a rewrite is disclosed; a spelling that was ALREADY canonical says nothing (no noise).
    if [ "$SPELL" = "$CANON" ]; then
        if grep -q 'canonicalised' "$ADD_ERR"; then
            no "R2[$SPELL]: an already-canonical target must not claim it was canonicalised"
        else
            ok "R2[$SPELL]: already canonical — no rewrite line"
        fi
    else
        if grep -q "canonicalised" "$ADD_ERR" && grep -q "$CANON" "$ADD_ERR"; then
            ok "R2[$SPELL]: the rewrite is disclosed on stderr, naming the stored id"
        else
            no "R2[$SPELL]: the target was rewritten to '$STORED' with no stderr disclosure: $( cat "$ADD_ERR" )"
        fi
    fi
done

echo
echo "── R3 — an ambiguous NAME is refused, and nothing is written ───────────────────────────────────"
D="$( fresh r3 )"
OUT="$( cd "$D" && "$BIN" . --no-cache --note-add="compute: which one?" 2>"$D/e" )"; rc=$?
if [ "$rc" -eq 0 ]; then
    no "R3: an ambiguous target was ACCEPTED (rc=0, stored '$( printf '%s' "$OUT" | cut -f1 )')"
else
    ok "R3: ambiguous target refused (rc=$rc)"
fi
grep -q '2' "$D/e" && grep -qi 'ambiguous' "$D/e" \
    && ok "R3: the refusal says ambiguous and names the count" \
    || no "R3: refusal does not name the ambiguity/count: $( cat "$D/e" )"
grep -q 'a.cpp:compute' "$D/e" && grep -q 'b.cpp:compute' "$D/e" \
    && ok "R3: the refusal lists BOTH disambiguating spellings" \
    || no "R3: the refusal does not list every candidate: $( cat "$D/e" )"
[ -f "$D/.ripwire_notes" ] \
    && no "R3: the refusal still wrote .ripwire_notes" \
    || ok "R3: nothing was written"

echo
echo "── R4 — an unresolvable symbol-shaped target is refused with did-you-mean ──────────────────────"
D="$( fresh r4 )"
( cd "$D" && "$BIN" . --no-cache --note-add="uniqueOnlyHer: typo" >/dev/null 2>"$D/e" ); rc=$?
[ "$rc" -ne 0 ] && ok "R4: a name that resolves to nothing is refused (rc=$rc)" \
                || no "R4: a dead name was accepted at exit 0"
grep -q "uniqueOnlyHere" "$D/e" \
    && ok "R4: the refusal offers the near-miss ('uniqueOnlyHere')" \
    || no "R4: no did-you-mean in the refusal: $( cat "$D/e" )"
[ -f "$D/.ripwire_notes" ] \
    && no "R4: the refusal still wrote .ripwire_notes" \
    || ok "R4: nothing was written"
# The mistyped CANONICAL ID is the same fault wearing a path (it carries '/'), so it must take the same
# route — this is the arm a naive "contains a slash ⇒ it is a path" classifier fails.
D="$( fresh r4b )"
( cd "$D" && "$BIN" . --no-cache --note-add="src/a.cpp::Widget::uniqueOnlyHer: typo" >/dev/null 2>"$D/e" ); rc=$?
[ "$rc" -ne 0 ] && ok "R4: a mistyped canonical id is refused, not stored as a path (rc=$rc)" \
                || no "R4: a mistyped canonical id was written as if it were a file path"

echo
echo "── R5 — a PATH target still writes; a dangling one warns loudly ────────────────────────────────"
D="$( fresh r5 )"
( cd "$D" && "$BIN" . --no-cache --note-add="src/a.cpp: the filler block is generated" >/dev/null 2>"$D/e" ); rc=$?
[ "$rc" -eq 0 ] && ok "R5: an INDEXED path target writes (rc=0)" || no "R5: an indexed path target was refused (rc=$rc): $( cat "$D/e" )"
grep -qi 'dangling' "$D/e" \
    && no "R5: an indexed path target warned about dangling: $( cat "$D/e" )" \
    || ok "R5: an indexed path target warns about nothing"
D="$( fresh r5b )"
( cd "$D" && "$BIN" . --no-cache --note-add="src/not_written_yet.cpp: the parser lives here once it exists" >/dev/null 2>"$D/e" ); rc=$?
[ "$rc" -eq 0 ] \
    && ok "R5: a path that does not exist yet still writes (rc=0) — that case is legal" \
    || no "R5: a not-yet-existing path was refused (rc=$rc) — a forward-looking note is legal: $( cat "$D/e" )"
grep -qi 'dangling' "$D/e" \
    && ok "R5: the not-yet-existing path warns loudly that the note is dangling" \
    || no "R5: a dangling path target was written SILENTLY: $( cat "$D/e" )"
( cd "$D" && "$BIN" . --no-cache --notes 2>/dev/null ) | grep -q 'dangling="1"' \
    && ok "R5: --notes reports it dangling=\"1\" (the warning and the listing agree)" \
    || no "R5: --notes disagrees with the write-time dangling warning"

echo
echo "── R6 — determinism + well-formedness ──────────────────────────────────────────────────────────"
D="$( fresh r6 )"
( cd "$D" && "$BIN" . --no-cache --note-add="uniqueOnlyHere: chose the loop over recursion because the depth is unbounded" >/dev/null 2>/dev/null )
( cd "$D" && "$BIN" . --no-cache --notes > n1 2>/dev/null; "$BIN" . --no-cache --notes > n2 2>/dev/null )
cmp -s "$D/n1" "$D/n2" && ok "R6: --notes is byte-identical across runs" || no "R6: --notes is not deterministic"
if command -v xmllint >/dev/null 2>&1; then
    for V in "--notes" "--expand=uniqueOnlyHere"; do
        if ( cd "$D" && "$BIN" . --no-cache $V 2>/dev/null ) | xmllint --noout - 2>/dev/null; then
            ok "R6: $V is well-formed XML"
        else
            no "R6: $V is not well-formed XML"
        fi
    done
else
    echo "  SKIP  xmllint not installed — well-formedness arm skipped"
fi
# A second add on the SAME target must not re-canonicalise into a second key (one target, two notes).
( cd "$D" && "$BIN" . --no-cache --note-add="Widget::uniqueOnlyHere: and the bound is exclusive" >/dev/null 2>/dev/null )
TCOUNT="$( ( cd "$D" && "$BIN" . --no-cache --notes 2>/dev/null ) | grep -o '<target ' | wc -l | tr -d ' ' )"
[ "$TCOUNT" = "1" ] \
    && ok "R6: two spellings of one symbol collapse to ONE target group" \
    || no "R6: two spellings of one symbol produced $TCOUNT target groups"

echo
[ "$fail" -eq 0 ] && echo "notecanoncheck: ALL PASS" || echo "notecanoncheck: FAILURES"
exit "$fail"
