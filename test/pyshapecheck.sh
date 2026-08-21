#!/usr/bin/env bash
# pyshapecheck.sh — the gate for Python DEFINITION SHAPES that only a real repo produces.
#
#   test/pyshapecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/pyshapecheck.sh
#
# WHY THIS EXISTS. langcheck proves Python ingest works at all; it cannot prove COVERAGE — the
# vendored tags.scm carried only THREE def-patterns (module assignment, class, function) for a
# language whose surface lives in decorators, dataclasses, Enum tables and typed class attributes.
# This gate was derived the tsshapecheck/jsshapecheck way: ripwire was run over django
# (github.com/django/django) and pydantic (github.com/pydantic/pydantic), the maps' `n="` sets were
# diffed against a ground truth enumerated with CPython's own ast module (an AST walk cannot be
# polluted by strings/comments — the blanked-grep trap solved at the root), and every shape was
# confirmed with SINGLE-capture `--match` queries (hits= counts CAPTURES, not matches; parse the
# <match> element, never grep the stream — its legend contains the literal string hits_capped="1",
# and --match's own collection budget caps a subtree at 5 000 captures, so a big corpus must be
# counted per-subtree and summed).
#
# RE-MEASURED 2026-08-10 at kParserVer 59, on the checkouts named below. The 2026-08-04 column is
# the original round's figure at kParserVer 39 on DIFFERENT checkouts; extraction moved ~20 versions
# and both corpora moved too, so the numbers are quoted side by side rather than inherited.
#
#   django   @c334c1a8ff — 2 791 .py, 0 .pyi      (2026-08-04 round: @7d75c0b — 2 928 .py)
#   pydantic @8898b8f    —   280 .py, 0 .pyi      (2026-08-04 round: @2e5f0e2 —   433 .py)
#
#   shape (capture SITES)                     django  pydantic  | 2026-08-04 django/pydantic   §
#   annotated class attribute  x: T [= v]          2     5 653  |     31 / 6 199              §1
#     (= the pydantic model field, dataclass field, TypedDict/NamedTuple member, ClassVar)
#   Enum-family member  NAME = value             132       108  |  60+91 / 245                §2
#   class attr bound to a lambda                   0        26  |      0 / 11                 §3
#   one-guard-deep module binding                144       198  |    150 / 203                §4
#   tuple-unpack module binding  A, B = 1, 2       2         0  |      6 / —                  §4
#   plain un-annotated class attr (stays OUT) 12 131     1 242  | 12 987 / —                  §6
#   .pyi stub files                                0         0  |      — / 1 (1 115 lines)    §5
#
# EXCLUSIVE recall of every target shape above was 0.0% on BOTH corpora before the fix, where
# EXCLUSIVE means the (path, name) pair could be in the map for no other reason — a name that is
# also a method, a class, or the same constant bound again outside the guard is removed from the
# denominator, so a collision cannot be scored as recall. The control in the same run: the vendored
# unguarded module-binding pattern reads 100.0% (pydantic) / 99.9% (django) on the same instrument.
#
# The two instruments reconcile EXACTLY once the single-capture query's blind spots are subtracted:
# CPython's ast enumerates every target of `a = b = v` and every element of a tuple-unpack, while a
# direct-child `left: (identifier)` capture sees one node. django 12 263 ast targets − 1 chained
# class-body assign = 12 262 captures; guarded bindings 150 − 6 = 144 (django) and 205 − 7 = 198
# (pydantic). Those unseen targets are therefore a real, disclosed limit of the ported patterns.
#
# .pyi is the one row this port could not re-measure: neither checkout carries a single .pyi file
# (the 2026-08-04 figure came from a tree that had pydantic-core's _pydantic_core.pyi in it). §5's
# fixture is the whole pin for that row.
#
# 100% on BOTH corpora at HEAD, pinned unchanged in §7: decorated functions/classes (incl.
# stacked), @property/@x.setter/@staticmethod/@classmethod, async def, nested defs,
# @abstractmethod, Protocol members, __all__, unguarded module constants (case-BLIND — see
# constcheck.sh §5), guarded function/class defs.
#
# §6 pins the BY-DESIGN non-goals in BOTH directions (a limit that quietly becomes a capture is as
# much a surprise as the reverse): `from x import y` re-exports mint NO def (the def lives in the
# source module — the jsshapecheck §4 attachPort rule), and plain UN-annotated data attrs stay out
# (django carries 12 131 such sites — `field = models.CharField()` et al. — a map-burying floor,
# the same scope line tsshapecheck §1 / jsshapecheck §1 draw for data fields). Enum members and
# lambda attrs are the two measured carve-INS through that line. A class whose enum-ness is not
# visible in its base NAME (subclass-of-a-subclass under a local alias, e.g. EnumLike here) stays
# out — base names are checked statically, not resolved.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/pyshapefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "pyshapecheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map" 2>/dev/null
MAP="$( cat "$TMP/map" )"

has(){ printf '%s' "$MAP" | grep -q "n=\"$1\""; }
rows(){ printf '%s' "$MAP" | grep -o "n=\"$1\"" | wc -l | tr -d ' '; }

# ── 1) annotated class attributes — the typed field surface ───────────────────────────────────────
# `x: T [= v]` in a class body IS the API of a pydantic model / dataclass / TypedDict / NamedTuple:
# 5 653 sites in pydantic alone were invisible. The `type:` field on the assignment node is the
# structural discriminant — plain un-annotated data attrs stay out (§6).
for sym in backoff_ms max_attempts registry frame_kind payload_len host_name port_num; do
    has "$sym" && ok "annotated class attr extracted: $sym" \
                || no "annotated class attr MISSING: $sym (assignment with type: field in class body)"
done
has plain_slot && no "over-capture: plain data attr 'plain_slot' became a symbol (the pattern must require the type: field — 12 131 django sites)" \
               || ok "plain data attr correctly NOT a symbol: plain_slot"

# ── 2) Enum-family members — the value tables agents grep for ─────────────────────────────────────
# Plain `NAME = value` assigns, structurally identical to plain_slot — only the enclosing class's
# base NAME (stdlib enum family + django Choices family, checked in dropGatedCapture) tells them
# apart. tags-pass predicates never run, so this is a C++ gate, not a .scm test.
for sym in CRIMSON TEAL URGENT_FIRST BULK_LAST GOLD_TIER SILVER_TIER; do
    has "$sym" && ok "enum member extracted: $sym" \
                || no "enum member MISSING: $sym (plain class-body assign gated on enum base name)"
done
has HIDDEN_VAL && no "KNOWN LIMIT CHANGED: member of Custom(EnumLike) extracted — enum-ness is checked by base NAME, not resolution; update the gate only if that deepened deliberately" \
               || ok "KNOWN LIMIT holds: unknown base name (EnumLike) does not make an enum: HIDDEN_VAL"

# ── 3) lambda bound to a class attribute is callable surface ──────────────────────────────────────
printf '%s' "$MAP" | grep -q 't="fn" n="formatter"' && ok "class lambda attr extracted as fn: formatter" \
                                                    || no "class lambda attr MISSING or wrong kind: formatter (right: (lambda) pattern, t=\"fn\")"
[ "$( rows formatter )" = "1" ] && ok "class lambda attr stays ONE row: formatter" \
                               || no "formatter has $( rows formatter ) rows (0 = lost, 2 = double-captured against the enummember pattern)"

# ── 4) guarded + tuple-unpack module bindings ─────────────────────────────────────────────────────
# ONE guard level (if/elif/else, try/except/else/finally) is in scope: TYPE_CHECKING blocks,
# platform switches and import-fallback try are where real repos put module config. Case-BLIND,
# same as the unguarded vendored pattern (constcheck.sh §5).
for sym in TypeHintAlias HAS_FAST_JSON JSON_BACKEND JSON_PROBED spool_path; do
    has "$sym" && ok "guarded module binding extracted: $sym" \
                || no "guarded module binding MISSING: $sym (one guard level deep)"
done
[ "$( rows LOCK_MODE )" = "1" ] && ok "three-arm guarded binding merges to ONE row: LOCK_MODE" \
                               || no "LOCK_MODE has $( rows LOCK_MODE ) rows (if/elif/else arms are one definition set — dedup must merge)"
for sym in MAJOR_VER MINOR_VER first_low second_low; do
    has "$sym" && ok "tuple-unpack module binding extracted: $sym" \
                || no "tuple-unpack module binding MISSING: $sym (pattern_list identifiers)"
done
for sym in LOCAL_CONST GUARDED_LOCAL DOUBLE_NESTED; do
    has "$sym" && no "over-capture: '$sym' became a symbol (function-local / two-guard-deep bindings are pinned OUT)" \
                || ok "correctly NOT a symbol: $sym"
done

# ── 5) .pyi stubs — a stub is often a library's ONLY Python-visible API ───────────────────────────
# Neither re-measured checkout carries a .pyi file, so this fixture IS the pin: before the
# kLangTable row a .pyi produced zero symbols, whatever its size.
for sym in SchemaGate validate_frame build_gate GATE_DEFAULT poll_interval; do
    has "$sym" && ok ".pyi shape extracted: $sym" \
                || no ".pyi shape MISSING: $sym (.pyi must route to tree-sitter-python)"
done

# ── 6) BY-DESIGN non-goals, pinned in BOTH directions ─────────────────────────────────────────────
has ColorAlias && no "KNOWN LIMIT CHANGED: 'from models import Color as ColorAlias' minted a def — re-exports were a by-design non-goal (jsshapecheck §4 attachPort rule)" \
               || ok "BY-DESIGN holds: import re-export mints no def: ColorAlias"
[ "$( rows RetryPolicy )" = "1" ] && ok "re-exported class stays ONE row (the models.py def): RetryPolicy" \
                                 || no "RetryPolicy has $( rows RetryPolicy ) rows — the __init__.py import must not mint a second def"
[ "$( rows __all__ )" = "1" ] && ok "__all__ still a symbol (exactly the __init__.py row)" \
                             || no "__all__ has $( rows __all__ ) rows (expected 1)"

# ── 7) no adoption outside the target — the shapes measured at 100% stay at 100% ──────────────────
for sym in endpoint_url parse_headers from_env resolve_route resolve_route_stacked stream_frames \
           outer_task inner_step make_key Service RetryPolicy Color next_delay css_name \
           SESSION_LIMIT cache_dir RATE_TABLE; do
    has "$sym" && ok "pre-existing shape untouched: $sym" \
                || no "REGRESSION: previously-extracted symbol lost: $sym"
done

# ── 8) determinism + well-formedness on this fixture ──────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --top-k=500 >"$TMP/map2" 2>/dev/null
cmp -s "$TMP/map" "$TMP/map2" && ok "two cold runs byte-identical" || no "cold runs DIFFER on the Python shape fixture"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/map" 2>/dev/null && ok "map is well-formed XML" || no "map is not well-formed XML"
else
    ok "xmllint absent — well-formedness check skipped"
fi

exit "$fail"
