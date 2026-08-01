#!/usr/bin/env bash
# readmedriftcheck.sh — README.md's "N flags" claim must not drift from the binary's own --help table.
#
# WHY. README.md:15 states a flag count in prose ("Around that core sit N long flags advertised in
# `--help`…"). Nothing else in the suite checks that number against reality, so it silently goes
# stale the moment a flag is added, renamed, or removed — the exact failure showcasecapturecheck's
# caption arm exists to catch for a different document. This gate is that same discipline applied to
# the README's own flag-count sentence.
#
# DERIVATION. Reuses flagsurfacecheck.sh's own harvest idiom verbatim: `--help` text scraped with
# `grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u`, i.e. anchored on the "--name" TOKEN, not on its column
# position. An earlier version of this gate anchored on a 4-space-indented line start (`^    --`),
# which undercounts — --help writes optional/alternative forms as "[--around-depth=N]" or
# "(--regex)", which a whitespace anchor misses entirely, and flagsurfacecheck.sh's own header
# comment warns against exactly this trap. Three in-tree derivations of "the flag count" existed at
# once (this gate's old 104, docs/docs_commands_build.py's 102, flagsurfacecheck.sh's 123) because
# each scraped --help slightly differently; arm (D) below pins this gate's derivation to
# flagsurfacecheck.sh's so the two can never drift apart again. (docs_commands_build.py's 102 counts
# a different, deliberately narrower thing — its own documented-vs-binary set — and is left alone;
# see CLAUDE.md.)
#
# Arms:
#   (A) derive the distinct flag count from --help and confirm it is a sane positive number
#   (B) the DRIFT arm — README.md's stated count must equal the derived count
#   (C) MUTATION CONTROL for (B) — a copy of README.md with a deliberately wrong count must be
#       caught red by the same comparison, proving the arm can actually see a mismatch
#   (D) CROSS-CHECK — this gate's derived count must equal flagsurfacecheck.sh's own harvested count
#       of the SAME --help text, so the two scripts' notions of "the flag count" can never disagree
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
# Reuses flagsurfacecheck.sh's own harvest idiom verbatim (see its "the advertised surface" comment).
# A 4-space-anchored `^    --` scrape undercounts: --help writes optional/alternative forms as
# "[--around-depth=N]" or "(--regex)", which a whitespace anchor misses entirely — flagsurfacecheck.sh's
# own header comment warns against exactly this trap. Anchoring on the "--name" TOKEN instead of its
# column position catches those forms too, which is why the two scripts disagreed (104 vs 123).
derived="$( printf '%s\n' "$HELP" | grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u | wc -l | tr -d ' ' )"
if [ -z "$derived" ] || [ "$derived" -lt 50 ]; then
    no "(A) derived flag count from --help looks implausible ('$derived') — --help table layout may have changed"
else
    ok "(A) derived $derived distinct flags from --help ('--name' tokens, deduped by name, flagsurfacecheck.sh idiom)"
fi

# ── (B) README's stated count must equal the derived count ──────────────────────────────────────────
stated="$( grep -oE '[0-9]+ long flags advertised' "$README" | head -1 | grep -oE '^[0-9]+' )"
if [ -z "$stated" ]; then
    no "(B) could not find a '<N> long flags advertised' sentence in README.md to check"
elif [ "$stated" = "$derived" ]; then
    ok "(B) README.md states $stated flags, matching the derived count"
else
    no "(B) README.md states $stated flags but --help currently has $derived distinct flags — update README.md:15"
fi

# ── (C) mutation control — a wrong count in a COPY must be caught ───────────────────────────────────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
wrong=$(( derived + 7 ))
sed -E "s/[0-9]+ long flags advertised/${wrong} long flags advertised/" "$README" > "$TMP/README_bad.md"
bad_stated="$( grep -oE '[0-9]+ long flags advertised' "$TMP/README_bad.md" | head -1 | grep -oE '^[0-9]+' )"
if [ "$bad_stated" = "$derived" ]; then
    no "(C) mutation control: injected wrong count ($bad_stated) was not actually different from derived ($derived) — control is vacuous"
elif [ -n "$bad_stated" ]; then
    ok "(C) mutation control: a fabricated count ($bad_stated) is correctly seen as disagreeing with the derived count ($derived)"
else
    no "(C) mutation control: could not parse the injected wrong count at all"
fi

# ── (D) cross-check — must equal flagsurfacecheck.sh's own harvest of the same --help text ──────────
# Runs the sibling gate itself (not a hand-copied re-derivation) so a future edit to EITHER script's
# scrape regex shows up here as a disagreement instead of two silently-diverging notions of "the count".
FLAGSURFACE_OUT="$( bash "$ROOT/test/flagsurfacecheck.sh" 2>&1 )"
flagsurface_count="$( printf '%s\n' "$FLAGSURFACE_OUT" | grep -oE 'harvested [0-9]+ advertised long flags' | head -1 | grep -oE '[0-9]+' )"
if [ -z "$flagsurface_count" ]; then
    no "(D) could not find flagsurfacecheck.sh's 'harvested N advertised long flags' line — did its output format change?"
elif [ "$flagsurface_count" = "$derived" ]; then
    ok "(D) this gate's derived count ($derived) matches flagsurfacecheck.sh's harvested count ($flagsurface_count)"
else
    no "(D) this gate derived $derived flags but flagsurfacecheck.sh harvested $flagsurface_count — the two scrapes have diverged again"
fi

if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
