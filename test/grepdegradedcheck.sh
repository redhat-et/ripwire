#!/usr/bin/env bash
# grepdegradedcheck.sh — BX2 FIX 6: --grep never holds a hit back by span tier in a file whose parse DEGRADED
# (search.h grepApplySpanTiers; lane BS1's fzf-02 shape, results/BS1_BLINDSPOT_1118).
#
#   test/grepdegradedcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# fzf's completion.zsh is parsed with the bash grammar and carries ERROR nodes (parse_degraded="1"). --grep's default tier
# served the code hits elsewhere and held its definition and both calls back as "string" (suppressed_string="5"), and the
# answer named no held-back file. A span tier read from a parse that failed is no evidence: such a hit is now unclassified
# (counted in tier_unclassified=, served, never suppressed). A string hit in a CLEAN file is still held back.
#
# Arm classes: [P] positive — RED on the parent binary; [N] near miss — must not change; [C] control.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
has(){ if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else no "$3 — missing: $2"; fi; }
hasnt(){ if printf '%s' "$1" | grep -qF -- "$2"; then no "$3 — present: $2"; else ok "$3"; fi; }
body(){ printf '%s' "$1" | sed 's/^.*-->//'; }

echo "grepdegradedcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── the corpus, written here ─────────────────────────────────────────────────────────────────────────────────────────
# use.c     calls frob_widget() nine times (code-tier hits; eight or more, so no thin-code lift serves strings beside them).
# broken.c  names "frob_widget" in a string AND does not parse (an unbalanced declaration: ERROR nodes, parse_degraded).
# clean.c   names "frob_widget" in a string and parses cleanly: its hit stays held back (suppressed_string=1).
mkdir -p "$DIR/src"
{ printf 'int frob_widget(void);\nint use(void)\n{\n    int n = 0;\n'; for k in 1 2 3 4 5 6 7 8 9; do printf '    n += frob_widget();\n'; done; printf '    return n;\n}\n'; } >"$DIR/src/use.c"
printf 'const char *name = "frob_widget";\nint broken( {\n' >"$DIR/src/broken.c"
printf 'const char *label = "frob_widget";\n' >"$DIR/src/clean.c"
cd "$DIR" || exit 1
export TMPDIR="$DIR/tmp"; mkdir -p "$TMPDIR"
rw(){ "$BIN" "$@" 2>/dev/null; }

a="$( body "$( rw . --grep=frob_widget )" )"
has "$a" 'p="src/use.c"' "[C1] the code-tier hit is served"
has "$a" 'p="src/broken.c" parse_degraded="1"' "[P1] the degraded file's hit is served (its row carries parse_degraded=\"1\")"
has "$a" 'tier_unclassified="1"' "[P2] the degraded file's hit counts as unclassified"
hasnt "$a" 'p="src/clean.c"' "[N1] a string hit in a clean file stays held back"
has "$a" 'suppressed_string="1"' "[N2] suppressed_string= counts the clean file's hit only"
a="$( body "$( rw . --grep=frob_widget --grep-in=any )" )"
has "$a" 'p="src/clean.c"' "[C2] --grep-in=any serves every tier"
if [ "$( rw . --grep=frob_widget )" = "$( rw . --grep=frob_widget )" ]; then ok "[C3] two runs byte-identical"; else no "[C3] two runs differ"; fi

if [ "$fail" -eq 0 ]; then echo "grepdegradedcheck: ALL PASS"; else echo "grepdegradedcheck: FAIL"; fi
exit "$fail"
