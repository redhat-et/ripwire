#!/usr/bin/env bash
# selectorscopecheck.sh — every spelling the tool PRINTS is a selector it ACCEPTS: the Scope::name tier.
#
# The map prints id="path::Scope::name" and --edit-check prints sym="Scope::name" — but no SYM-taking
# verb accepted the Scope::name spelling back (measured 2026-08-30 on this repo: --expand/--callers/
# --uses/--impact/--edit-check all refused `NoteIndex::empty` while the map printed exactly that id
# tail). An agent pastes what the tool showed it; the tool must resolve its own output. The resolver
# gains ONE new tier — a "::"-boundary scope-suffix match, probed AFTER the canonical-id tier and
# BEFORE the file:name fallthrough — in the SAME shared functions every SYM verb routes through
# (resolveAllByName / resolveAllByNameQualified / resolveFocus), so all of them inherit it at once.
# Purely additive: a spec containing "::" resolved to NOTHING before this tier (the last-colon split
# made the file half "Scope:", which no path contains), so no previously-working query can change.
#
# RED-FIRST: recorded 2026-08-30 against the pre-tier binary — arms (a)-(e) FAIL (each selector
# refused); arms (f)/(g)/(h) already PASS and are PINS: (f) the canonical-id spelling --around
# already accepted, (g) the bare-name union, (h) the wrong-scope refusal.
#
# Fixture test/selectorscopefix/: Box::lid and Crate::lid — the same method name under two scopes in
# two files, so only the scope spelling can name one of them; each lid calls its own scope's helper,
# which is the discriminator the arms grep for.
#
# Usage:  test/selectorscopecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/selectorscopecheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/selectorscopefix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "selectorscopecheck: BIN=$BIN  FIX=$FIX"

# ── (a)/(b) Scope::name picks ONE scope's definition on the graph verbs ─────────────────────────────
OUTA="$( "$BIN" "$FIX" --no-cache --callees=Box::lid 2>&1 )"
if printf '%s' "$OUTA" | grep -q 'n="boxHelper"' && ! printf '%s' "$OUTA" | grep -q 'n="crateHelper"'; then
    ok "(a) --callees=Box::lid resolves and names boxHelper only"
else
    no "(a) --callees=Box::lid did not resolve to Box's definition"; printf '%s\n' "$OUTA" | tail -2
fi
OUTB="$( "$BIN" "$FIX" --no-cache --callees=Crate::lid 2>&1 )"
if printf '%s' "$OUTB" | grep -q 'n="crateHelper"' && ! printf '%s' "$OUTB" | grep -q 'n="boxHelper"'; then
    ok "(b) --callees=Crate::lid resolves and names crateHelper only"
else
    no "(b) --callees=Crate::lid did not resolve to Crate's definition"; printf '%s\n' "$OUTB" | tail -2
fi

# ── (c) --expand accepts the spelling ───────────────────────────────────────────────────────────────
OUTC="$( "$BIN" "$FIX" --no-cache --expand=Box::lid 2>&1 )"
if printf '%s' "$OUTC" | grep -q 'boxHelper' && printf '%s' "$OUTC" | grep -q 'p="box.h"'; then
    ok "(c) --expand=Box::lid returns Box's body"
else
    no "(c) --expand=Box::lid refused or wrong body"; printf '%s\n' "$OUTC" | tail -2
fi

# ── (d) --edit-check accepts the spelling it itself prints as sym= ──────────────────────────────────
OUTD="$( cd "$ROOT" && "$BIN" test/selectorscopefix --no-cache --edit-check=Box::lid 2>&1 )"
if printf '%s' "$OUTD" | grep -q '<edit-check sym="lid"' && printf '%s' "$OUTD" | grep -q 'box.h'; then
    ok "(d) --edit-check=Box::lid resolves to box.h's lid"
else
    no "(d) --edit-check=Box::lid refused"; printf '%s\n' "$OUTD" | tail -2
fi

# ── (e)/(f) resolveFocus parity: --around takes Scope::name AND a pasted canonical id ───────────────
OUTE="$( "$BIN" "$FIX" --no-cache --around=Crate::lid 2>&1 )"
if printf '%s' "$OUTE" | grep -q 'crate.h'; then
    ok "(e) --around=Crate::lid resolves"
else
    no "(e) --around=Crate::lid refused — resolveFocus lacks the tier"; printf '%s\n' "$OUTE" | tail -2
fi
OUTF="$( "$BIN" "$FIX" --no-cache --around=box.h::Box::lid 2>&1 )"
if printf '%s' "$OUTF" | grep -q 'box.h'; then
    ok "(f) --around accepts the map's own id= spelling (box.h::Box::lid)"
else
    no "(f) --around=box.h::Box::lid refused — resolveFocus lacks the canonical-id probe"; printf '%s\n' "$OUTF" | tail -2
fi

# ── (g) additivity: the bare name still unions across scopes, byte-for-byte semantics unchanged ─────
OUTG="$( "$BIN" "$FIX" --no-cache --callees=lid 2>&1 )"
if printf '%s' "$OUTG" | grep -q 'n="boxHelper"' && printf '%s' "$OUTG" | grep -q 'n="crateHelper"'; then
    ok "(g) bare --callees=lid still unions both scopes (the pre-tier contract)"
else
    no "(g) the bare-name union changed — the tier is not additive"; printf '%s\n' "$OUTG" | tail -2
fi

# ── (h) a WRONG scope refuses — it must never silently degrade to the bare-name match ───────────────
OUTH="$( "$BIN" "$FIX" --no-cache --callees=Nope::lid 2>&1 )"
if printf '%s' "$OUTH" | grep -qE 'not found|matched no|no symbol'; then
    ok "(h) --callees=Nope::lid refuses (a wrong scope is an error, not a fallback)"
else
    no "(h) a wrong scope silently resolved — the tier leaks into bare-name matching"; printf '%s\n' "$OUTH" | tail -2
fi

exit $fail
