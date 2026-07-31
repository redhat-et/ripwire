#!/usr/bin/env bash
# flagsnoisecheck.sh — the SIGNAL/NOISE gate for --flags' env lane (r27 P5).
#
#   test/flagsnoisecheck.sh
#   CTXPACK_BIN=asan/ctxpack test/flagsnoisecheck.sh
#
# `--flags` answers "what is built but dark here". A gate it INVENTED is worse than a gate it missed: the
# reader has no way to tell the two apart, and one bogus row costs the same hand-verification the verb exists
# to remove. Measured on this repo before the filter landed, 8 of 45 reported gates (~18%) were invented —
# from a doc comment (`NAME`, harvested out of darkflags.h's OWN header, which then accrued 33 read sites),
# from the commas separating the probe SPELLINGS in the probe table (`,` and `, `), from a single-quoted
# shell fragment (`" sym="`), from markdown prose (`CANYON_*`, `env`, `…`), and from a heredoc inside a gate
# script (`SYNFIX_FEATURE`, a "compile gate" that is really a fixture the script writes at run time).
#
# Three rules now decide whether a probe hit is a declaration:
#   1. it must sit in CODE — outside every comment and every string literal;
#   2. it must wear the CALL shape `probe ( "…" )` — not "the next quoted run anywhere to the right";
#   3. the harvested name must be identifier-shaped, because nothing else can name an environment variable.
# …and a PROSE file (markdown, or an extracted-doc format) contributes nothing at all: a doc writing
# `getenv("X")` documents a switch, it does not declare one.
#
# The gate is symmetric on purpose. Over-filtering is the failure mode a noise fix invites, so every NEGATIVE
# below is paired with a POSITIVE in the same syntactic neighbourhood: a real `getenv` two lines from a
# commented one, a real Python `os.environ.get` in a file whose comments use the same `#` the C preprocessor
# uses for directives, a real header gate in a file that also contains a block comment naming a fake one.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "flagsnoisecheck: BIN=$BIN"

FIX="$TMP/fix"; mkdir -p "$FIX"

# ── the corpus ────────────────────────────────────────────────────────────────────────────────────────
# C++: real reads beside every shape that only LOOKS like one.
cat >"$FIX/reader.cpp" <<'EOF'
#include <cstdlib>
#include <string_view>

// A doc comment that spells the call: getenv("NOISE_LINE_COMMENT") — documentation, not a declaration.
/* A block comment that spells it too: getenv("NOISE_BLOCK_COMMENT")
   and keeps spelling it across a line break: getenv("NOISE_BLOCK_SECOND_LINE") */

// The probe TABLE: the loose reader used to walk from one literal's closing quote into the next literal's
// opening quote and harvest the comma between them as a gate name.
static constexpr std::string_view kProbeTable[] = { "getenv", "environ.get", "environ[" };

// A string literal that quotes the call verbatim, the way a help text or an error message does.
static const char* kHelpLine = "set getenv(\"NOISE_INSIDE_STRING\") to change this";

const char* readReal( const char* computedName )
{
    const char* a = std::getenv( "REAL_CPP_GATE" );      // the plain call, spaced the way this repo writes it
    const char* b = getenv("REAL_CPP_TIGHT");            // and with no spaces at all
    const char* c = getenv( computedName );              // a computed name is not a gate anyone can name
    const char* d = getenv( "NOT AN ENV NAME" );         // not identifier-shaped: no shell can set it
    const char* e = my_getenv( "NOISE_PREFIXED_CALL" );  // not our probe: `getenv` here opens no identifier
    (void)kProbeTable; (void)kHelpLine; (void)b; (void)c; (void)d; (void)e;
    return a;
}
EOF

# C++ header: a real compile gate in a file that also names a fake one from inside a block comment.
cat >"$FIX/gates.h" <<'EOF'
#pragma once

/* The idiom, described rather than used:
   #ifndef NOISE_COMMENTED_GATE
   #define NOISE_COMMENTED_GATE 0
   #endif */

#ifndef REAL_COMPILE_GATE
#define REAL_COMPILE_GATE 0
#endif

#if REAL_COMPILE_GATE
int realGuardedThing = 1;
#endif
EOF

# Python: `#` is a COMMENT here, and the real reads must still be found.
cat >"$FIX/tool.py" <<'EOF'
import os

# os.getenv("NOISE_PY_COMMENT") is how you would read it
#ifndef NOISE_PY_LOOKS_LIKE_A_DIRECTIVE
HELP = 'pass os.environ.get("NOISE_PY_IN_STRING") to override'

def read():
    a = os.getenv("REAL_PY_GATE")
    b = os.environ.get("REAL_PY_ENVIRON_GET")
    c = os.environ["REAL_PY_SUBSCRIPT"]
    return a, b, c
EOF

# Shell: single-quoted fragments and heredocs are text, not declarations.
cat >"$FIX/run.sh" <<'EOF'
#!/usr/bin/env bash
# getenv("NOISE_SH_COMMENT") — a comment describing the C call
printf '%s' "$O" | grep -q 'via="getenv" sym="shellGate"'
cat >"$TMPDIR/generated.h" <<'INNER'
#ifndef NOISE_HEREDOC_GATE
#define NOISE_HEREDOC_GATE 0
#endif
INNER
EOF

# Markdown: prose about gates, including someone else's.
cat >"$FIX/NOTES.md" <<'EOF'
# Notes

Compile-dark features are `#ifndef F / #define F 0` header gates, CMake `option()`, and
`getenv("NOISE_MD_CANYON")` reads.

    #ifndef NOISE_MD_COMPILE_GATE
    #define NOISE_MD_COMPILE_GATE 0
    #endif
EOF

"$BIN" "$FIX" --flags --no-cache >"$TMP/o" 2>/dev/null
rc=$?
[ "$rc" = "0" ] && ok "exits 0 (a report, not a gate)" || no "--flags exited $rc, expected 0"

names(){ tr '<' '\n' <"$TMP/o" | sed -n 's/^gate name="\([^"]*\)".*/\1/p'; }
has(){ names | grep -qx "$1"; }

# ── 1) every real gate is still found ─────────────────────────────────────────────────────────────────
for g in REAL_CPP_GATE REAL_CPP_TIGHT REAL_PY_GATE REAL_PY_ENVIRON_GET REAL_PY_SUBSCRIPT REAL_COMPILE_GATE; do
    has "$g" && ok "kept: $g (a real declaration survives the filter)" || no "OVER-FILTERED: $g is gone"
done

# ── 2) nothing invented ───────────────────────────────────────────────────────────────────────────────
for g in NOISE_LINE_COMMENT NOISE_BLOCK_COMMENT NOISE_BLOCK_SECOND_LINE NOISE_INSIDE_STRING \
         NOISE_COMMENTED_GATE NOISE_PY_COMMENT NOISE_PY_IN_STRING NOISE_PY_LOOKS_LIKE_A_DIRECTIVE \
         NOISE_SH_COMMENT NOISE_HEREDOC_GATE NOISE_MD_CANYON NOISE_MD_COMPILE_GATE NOISE_PREFIXED_CALL; do
    has "$g" && no "INVENTED: $g is reported as a gate (it is a comment, a string, prose or a heredoc)" \
              || ok "not invented: $g"
done

# the shapes with no name at all: a comma harvested between two probe spellings, a non-identifier name,
# a computed argument. None of these can be a gate, whatever the lane thought it saw.
names | grep -qx ',' && no "INVENTED: a gate literally named ',' (read across two string literals)" \
                     || ok "not invented: ',' (the probe table's own separators)"
names | grep -qx ', ' && no "INVENTED: a gate literally named ', '" || ok "not invented: ', '"
names | grep -q 'NOT AN ENV NAME' && no "INVENTED: a gate name with spaces in it" \
                                  || ok "not invented: a non-identifier env name"
names | grep -q 'computedName' && no "INVENTED: a gate named after a computed argument" \
                               || ok "not invented: a computed getenv argument"
names | grep -q ' sym=' && no "INVENTED: a gate harvested out of a quoted shell fragment" \
                        || ok "not invented: a quoted shell fragment"

# ── 3) the header count agrees with the rows, and the kinds are right ─────────────────────────────────
declared="$( sed -n 's/.*<flags gates="\([0-9]*\)".*/\1/p' "$TMP/o" )"
rows="$( names | grep -c . || true )"
[ "$declared" = "$rows" ] && ok "header gates=\"$declared\" equals the number of <gate/> rows" \
                          || no "header says gates=\"$declared\" but $rows rows were printed"

envcount="$( sed -n 's/.*<flags [^>]*env="\([0-9]*\)".*/\1/p' "$TMP/o" )"
[ "$envcount" = "5" ] && ok "env=\"5\" — exactly the five real environment reads" \
                      || no "env=\"$envcount\", expected 5 (the five real reads in the fixture)"

# ── 4) determinism + G4 ───────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --flags --no-cache >"$TMP/o2" 2>/dev/null
cmp -s "$TMP/o" "$TMP/o2" && ok "byte-identical run to run" || no "--flags is non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/o" 2>/dev/null && ok "G4 xmllint clean" || no "output is not well-formed XML"
fi

# ── 5) the regression that started this: the verb must not read its OWN help text ──────────────────────
# darkflags.h's header comment contains `getenv("NAME")`. Running the verb on this repo's own src/ must not
# produce a gate called NAME — the self-referential case, and the one that produced the loudest wrong row.
"$BIN" "$ROOT/src" --flags --no-cache >"$TMP/self" 2>/dev/null
tr '<' '\n' <"$TMP/self" | sed -n 's/^gate name="\([^"]*\)".*/\1/p' | grep -qx 'NAME' \
    && no "INVENTED: --flags on src/ reports a gate named NAME, out of darkflags.h's own doc comment" \
    || ok "self-reference: --flags on src/ does not harvest a gate from its own documentation"

[ $fail -eq 0 ] && echo "flagsnoisecheck: ALL PASS" || echo "flagsnoisecheck: FAILURES"
exit $fail
