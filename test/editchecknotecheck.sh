#!/usr/bin/env bash
# editchecknotecheck.sh — gate for L3 field-note surfacing ON --edit-check=SYM (paper-noteedit,
# arXiv 2606.13174's "enforcement at the moment of highest leverage": a note is most useful right when an
# agent is about to CHECK or CHANGE the exact symbol it targets, not only when that symbol turns up in a
# --for/--expand ranked bundle).
#
# The matching + row rendering are REUSED verbatim from the --for/--expand seam (serialize.h's
# renderNoteChildren/symbolNoteTarget/fileNoteTarget via editcheck.h's editCheckBundleText `ni` parameter)
# — this gate is NOT re-testing note matching/escaping (notescheck.sh already owns that in full); it only
# proves the NEW seam wires the shared machinery in correctly.
#
# Covers, per the plan's gate spec:
#   (a) a note targeting SYM appears in --edit-check output with the documented <note> row shape
#   (b) a note targeting a DIFFERENT symbol does not leak into SYM's --edit-check output
#   (b2) a note targeting SYM's FILE also surfaces (the "(or its file)" half of the feature)
#   (c) a NO-NOTES run is byte-identical to the pre-change baseline binary's output (purely additive;
#       set RIPWIRE_BASE_BIN=<path to the pre-change ripwire> to run this arm — it SKIPs, loudly, when unset)
#   (d) determinism x3 with notes present
#   (e) xmllint on the note-bearing output
#
# Operates on a private temp git repo (never touches the real repo). Needs git.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/editchecknotecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
#         RIPWIRE_BASE_BIN=/path/to/pre-change/ripwire bash test/editchecknotecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
BASE="${RIPWIRE_BASE_BIN:-}"
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"
cat > "$WORK/src/a.cpp" <<'EOF'
int helper( int x ) { return x + 1; }
int useit( int a ) { return helper( a ); }
EOF
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )

echo "editchecknotecheck: BIN=$BIN  (temp git repo)"

ec(){ ( cd "$WORK" && "$BIN" . --edit-check="$1" --no-cache 2>/dev/null ); }
add(){ ( cd "$WORK" && "$BIN" . --no-cache --note-add="$1" >/dev/null 2>&1 ); }

# ── (c) FIRST, before any note exists — the no-notes baseline-identity arm, red-first-friendly: this must
#     pass BEFORE this round's binary is even asked to render a note. ─────────────────────────────────────
NO_NOTES_NEW="$( ec helper )"
if [ -n "$BASE" ]; then
    [ -x "$BASE" ] || { echo "RIPWIRE_BASE_BIN=$BASE is not executable"; exit 2; }
    NO_NOTES_BASE="$( cd "$WORK" && "$BASE" . --edit-check=helper --no-cache 2>/dev/null )"
    [ "$NO_NOTES_NEW" = "$NO_NOTES_BASE" ] \
        && ok "(c) no-notes --edit-check output is byte-identical to the pre-change baseline binary" \
        || { no "(c) no-notes --edit-check output DIFFERS from the baseline binary"; diff <( printf '%s\n' "$NO_NOTES_NEW" ) <( printf '%s\n' "$NO_NOTES_BASE" ) | head -c 800; }
else
    skip "(c) byte-identity vs pre-change binary (set RIPWIRE_BASE_BIN=<path>)"
fi
# an inertness self-check that always runs regardless of BASE: a no-notes run must carry no <note> element.
printf '%s' "$NO_NOTES_NEW" | grep -q '<note ' \
    && no "(c) no-notes --edit-check output unexpectedly contains a <note> element" \
    || ok "(c) no-notes --edit-check output carries no <note> element (self-check)"

# ── set up notes: one on SYM (helper), one on a DIFFERENT symbol (useit), one on SYM's FILE ────────────────
add "helper: watch the off-by-one lives here"
add "useit: this note must never appear on helper's edit-check"
add "src/a.cpp: file-level note for a.cpp"

GIT_DATE="$( cd "$WORK" && git log -1 --format=%cs HEAD )"
GIT_SHA_FULL="$( cd "$WORK" && git rev-parse HEAD )"
GIT_SHA="${GIT_SHA_FULL:0:7}"
GIT_BRANCH="$( cd "$WORK" && git rev-parse --abbrev-ref HEAD )"
NOTE_OPEN='<note d="'"$GIT_DATE"'" sha="'"$GIT_SHA"'" branch="'"$GIT_BRANCH"'">'   # same shape notescheck.sh asserts for --for/--expand

OUT="$( ec helper )"

# ── (a) SYM's own note surfaces, documented row shape (identical to the --for/--expand <note> grammar) ────
printf '%s' "$OUT" | grep -qF "$NOTE_OPEN"'<![CDATA[watch the off-by-one lives here]]></note>' \
    && ok "(a) --edit-check surfaces a note targeting SYM, same <note> row shape as --for/--expand" \
    || { no "(a) --edit-check did not surface the SYM-targeted note"; printf '%s\n' "$OUT" | tail -c 800; echo; }

# ── (b) a DIFFERENT symbol's note does not leak in ──────────────────────────────────────────────────────
printf '%s' "$OUT" | grep -qF "this note must never appear on helper's edit-check" \
    && no "(b) a note targeting a DIFFERENT symbol (useit) leaked into helper's --edit-check output" \
    || ok "(b) a note targeting a different symbol does not appear"

# ── (b2) SYM's FILE note also surfaces ("(or its file)" half of the feature) ────────────────────────────
printf '%s' "$OUT" | grep -qF "$NOTE_OPEN"'<![CDATA[file-level note for a.cpp]]></note>' \
    && ok "(b2) --edit-check surfaces a note targeting SYM's FILE" \
    || { no "(b2) --edit-check did not surface the file-targeted note"; printf '%s\n' "$OUT" | tail -c 800; echo; }

# the note(s) ride as children of <edit-check>, after the opening tag and before the def/c rows — assert the
# element still opens/closes correctly around them (well-formedness is (e) below; this pins PLACEMENT).
printf '%s' "$OUT" | grep -qE '<edit-check [^>]*>(<note[^/]*</note>){2}' \
    && ok "notes ride as <edit-check> children, right after the opening tag" \
    || { no "notes are not placed as the first children of <edit-check>"; printf '%s\n' "$OUT" | tail -c 800; echo; }

# ── (d) determinism x3 with notes present ───────────────────────────────────────────────────────────────
D1="$( ec helper )"; D2="$( ec helper )"; D3="$( ec helper )"
{ [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; } \
    && ok "(d) --edit-check with notes is deterministic (byte-identical x3)" \
    || no "(d) --edit-check with notes is non-deterministic"

# ── (e) xmllint ──────────────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "(e) --edit-check with notes is xmllint-clean" || no "(e) --edit-check with notes is not well-formed"
else
    printf '  SKIP  (e) xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
