#!/usr/bin/env bash
# readmedriftcheck.sh — README.md's "N flags" claim must not drift from the binary's own --help table.
#
# WHY. README.md:15 states a flag count in prose ("Around that core sit N flags across seven
# families…"). Nothing else in the suite checks that number against reality, so it silently goes
# stale the moment a flag is added, renamed, or removed — the exact failure showcasecapturecheck's
# caption arm exists to catch for a different document. This gate is that same discipline applied to
# the README's own flag-count sentence.
#
# DERIVATION. `<bin> --help` lists each flag on a 4-space-indented line starting "--" (the help
# table's own layout — see e.g. "    --top-k=N ..."). Some flags are documented more than once
# because a later section restates them with a different focus (--arch, --plan-lanes, --doc-drift,
# --format each appear 2-3 times in different clauses of the help text) — the true flag SURFACE is
# the count of DISTINCT flag names, not the count of lines, so this gate dedupes by name before
# comparing.
#
# Arms:
#   (A) derive the distinct flag count from --help and confirm it is a sane positive number
#   (B) the DRIFT arm — README.md's stated count must equal the derived count
#   (C) MUTATION CONTROL for (B) — a copy of README.md with a deliberately wrong count must be
#       caught red by the same comparison, proving the arm can actually see a mismatch
#
# Usage:  bash test/readmedriftcheck.sh      [RIPWIRE_BIN=path/to/binary]
# Exit:   0 = clean · 1 = at least one arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
README="$ROOT/README.md"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "readmedriftcheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$README" ] || { echo "readmedriftcheck: missing $README"; exit 2; }

HELP="$( "$BIN" --help 2>&1 )"

# ── (A) derive the distinct flag count from --help ──────────────────────────────────────────────────
derived="$( printf '%s\n' "$HELP" | grep -E '^    --' | sed -E 's/^    (--[A-Za-z0-9_-]+).*/\1/' | sort -u | wc -l | tr -d ' ' )"
if [ -z "$derived" ] || [ "$derived" -lt 50 ]; then
    no "(A) derived flag count from --help looks implausible ('$derived') — --help table layout may have changed"
else
    ok "(A) derived $derived distinct flags from --help (4-space-indented '--name' lines, deduped by name)"
fi

# ── (B) README's stated count must equal the derived count ──────────────────────────────────────────
stated="$( grep -oE '[0-9]+ flags across' "$README" | head -1 | grep -oE '^[0-9]+' )"
if [ -z "$stated" ]; then
    no "(B) could not find a '<N> flags across' sentence in README.md to check"
elif [ "$stated" = "$derived" ]; then
    ok "(B) README.md states $stated flags, matching the derived count"
else
    no "(B) README.md states $stated flags but --help currently has $derived distinct flags — update README.md:15"
fi

# ── (C) mutation control — a wrong count in a COPY must be caught ───────────────────────────────────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
wrong=$(( derived + 7 ))
sed -E "s/[0-9]+ flags across/${wrong} flags across/" "$README" > "$TMP/README_bad.md"
bad_stated="$( grep -oE '[0-9]+ flags across' "$TMP/README_bad.md" | head -1 | grep -oE '^[0-9]+' )"
if [ "$bad_stated" = "$derived" ]; then
    no "(C) mutation control: injected wrong count ($bad_stated) was not actually different from derived ($derived) — control is vacuous"
elif [ -n "$bad_stated" ]; then
    ok "(C) mutation control: a fabricated count ($bad_stated) is correctly seen as disagreeing with the derived count ($derived)"
else
    no "(C) mutation control: could not parse the injected wrong count at all"
fi

if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
