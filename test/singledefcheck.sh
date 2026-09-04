#!/usr/bin/env bash
# singledefcheck.sh — H6 (capture-audit 2026-09-04, lens 6 F2/F3): a verb that reads exactly ONE definition
# must never answer a bare FIRST PICK for a name that has several.
#
# THE DEFECT. `--lego=size` — 6 definitions across 4 files — resolved through resolveFocus's lowest-id pick
# and printed `<iface n="size" p="src/infra/dynamic_map.hpp" implementors="0">`, with nothing on the row to
# say a pick had happened. A genuine "this interface has no implementors" and a "you got the wrong `size`"
# zero rendered identically, and the reader had no way to tell which they were holding. Its siblings over
# the SAME resolver had already decided the question two different but honest ways:
#
#   REFUSE  — --slice ("a slice reads exactly ONE body, so an ambiguous selector is refused, never silently
#             narrowed"), --edit-check, and the three edit verbs: list every definition, name the
#             `file:name` / `@FILE:LINE` disambiguator, exit non-zero.
#   DISCLOSE— --owners (`defs="6"`), --layout (`defs="4"`), --field-affinity (`structs="2" shown="2"` — it
#             models every match rather than picking one): answer, but carry the count so the reader can see
#             a pick was made.
#
# Either is honest. A bare first-pick is not. THE PROPERTY THIS GATE ASSERTS is therefore the disjunction:
# for a name with N>1 definitions, every single-definition verb either exits non-zero naming N (and the
# disambiguator), or emits a count attribute equal to N. `--lego` satisfied neither before this gate.
#
# The fixture is built here (two headers defining the SAME struct name and the SAME function name), so N is
# a property of the fixture and not of whatever the repo happens to contain today. It is git-init'ed because
# --owners is a history verb, and it lives in a temp dir because the edit-verb arms are refusals that must
# be shown NOT to write.
#
# RED-FIRST: arm (lego) fails on the pre-fix binary — exit 0, no defs= and no refusal. Every other arm
# passes before and after; they are here because the property is the family's, not --lego's.
#
# Usage:  bash test/singledefcheck.sh [BIN]   |   RIPWIRE_BIN=build_base/ripwire bash test/…
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "singledefcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"

cat > "$R/one.h" <<'EOF'
#pragma once
struct Box
{
    int  wide;
    int  tall;
    virtual double area() const = 0;
    virtual ~Box() = default;
};
struct WideBox : Box { double area() const { return 1.0; } };
inline int size( int q ) { return q + 1; }
EOF

cat > "$R/two.h" <<'EOF'
#pragma once
struct Box
{
    double deep;
    double high;
    virtual double area() const = 0;
    virtual ~Box() = default;
};
struct DeepBox : Box { double area() const { return 2.0; } };
inline int size( double q ) { return int( q ) + 2; }
EOF

# Two translation units, one per header: the same struct name and the same function name are defined twice
# WITHOUT a redefinition, and each Box gets two field-touching functions so --field-affinity models both
# (its own min_fns floor is 2 — a struct one function touches is not an affinity question).
cat > "$R/use_one.cpp" <<'EOF'
#include "one.h"
int spanOne( const Box& b ) { return b.wide + b.tall; }
int areaOne( const Box& b ) { return b.tall * b.wide; }
int useOne() { return size( 1 ) + spanOne( *(Box*)0 ) + areaOne( *(Box*)0 ); }
EOF

cat > "$R/use_two.cpp" <<'EOF'
#include "two.h"
double spanTwo( const Box& b ) { return b.deep + b.high; }
double areaTwo( const Box& b ) { return b.high * b.deep; }
double useTwo() { return size( 2.0 ) + spanTwo( *(Box*)0 ) + areaTwo( *(Box*)0 ); }
EOF

printf 'payload\n' > "$TMP/payload.txt"

( cd "$R" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1

N=2   # both `Box` and `size` are defined exactly twice, by construction above

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== the DISCLOSE branch: a count attribute equal to N on the answer ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
discloses(){ # $1 = label, $2 = attribute name, $3.. = args
    local label="$1" attr="$2"; shift 2
    local out; out="$( "$BIN" "$R" "$@" --no-cache 2>/dev/null )"
    if printf '%s' "$out" | grep -qF "$attr=\"$N\""; then
        ok "$label: carries $attr=\"$N\""
    else
        no "$label: no $attr=\"$N\" — a first pick with no count reads as a complete answer: $( printf '%s' "$out" | head -c 300 )"
    fi
}
discloses "--lego=Box"            defs    --lego=Box
discloses "--layout=Box"          defs    --layout=Box
discloses "--owners=Box"          defs    --owners=Box
discloses "--field-affinity=Box"  structs --field-affinity=Box

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== the REFUSE branch: exit non-zero, name N, name the file:name disambiguator ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
refuses(){ # $1 = label, $2.. = args
    local label="$1"; shift
    local out; out="$( "$BIN" "$R" "$@" --no-cache 2>&1 1>/dev/null )"; local rc=$?
    if [ "$rc" -eq 0 ]; then
        no "$label: exit 0 on an ambiguous selector (expected a refusal)"
        return
    fi
    if printf '%s' "$out" | grep -qE "(^|[^0-9])$N( |-)" && printf '%s' "$out" | grep -qF "one.h"; then
        ok "$label: refuses naming $N definitions and a file-qualified retry"
    else
        no "$label: refusal names neither the count nor a qualified retry: $out"
    fi
}
refuses "--slice=size"                  --slice=size
refuses "--edit-check=size"             --edit-check=size
refuses "--replace-symbol-body=size"    --replace-symbol-body=size --edit-payload="$TMP/payload.txt"
refuses "--insert-before-symbol=size"   --insert-before-symbol=size --edit-payload="$TMP/payload.txt"
refuses "--insert-after-symbol=size"    --insert-after-symbol=size  --edit-payload="$TMP/payload.txt"

# the refusals must not have written anything
if [ -z "$( cd "$R" && git status --porcelain )" ]; then
    ok "the edit-verb refusals wrote nothing (git status clean)"
else
    no "an edit-verb refusal modified the tree: $( cd "$R" && git status --porcelain )"
fi

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== the negative: an UNAMBIGUOUS name is not reported as ambiguous ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
OUT="$( "$BIN" "$R" --lego=WideBox --no-cache 2>/dev/null )"
if printf '%s' "$OUT" | grep -qF 'defs="1"'; then
    ok "--lego=WideBox (one definition): defs=\"1\""
else
    no "--lego=WideBox: expected defs=\"1\": $( printf '%s' "$OUT" | head -c 300 )"
fi
"$BIN" "$R" --slice=useOne --no-cache >/dev/null 2>&1 \
  && ok "--slice=useOne (one definition): still answers" \
  || no "--slice=use: an unambiguous selector must not be refused"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
