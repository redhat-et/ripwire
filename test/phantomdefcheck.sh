#!/usr/bin/env bash
# No indexed symbol is a PHANTOM: a reserved keyword, or a "definition" whose parameter list cannot be one.
#
# THE DEFECT, measured 2026-11-17 on `--dead-code` over six corpora. Five of six cells reported
# `count="0"`, and the ONE non-empty answer was 10 of 10 WRONG — tmux, listing seven symbols named
# `printflike` and three named `return`:
#
#   repos/tmux/arguments.c:504        static void printflike(3, 4)
#   repos/tmux/window-customize.c:332         return (0);
#
# `printflike(a, b)` is tmux's `__attribute__((format(printf,a,b)))` macro, so the "parameter list" is two
# integer literals. `return (0);` is a return statement. Neither is a function and neither is dead code.
# The verb's rule (internal linkage + zero callers) is sound; its INPUT is phantoms.
#
# This matters more than the bytes it costs. `--dead-code` tells an agent what is safe to DELETE, and a
# wrong row there is the most expensive kind of wrong answer this tool can give. It is also the same family
# as the paren-init phantom already recorded in this project (`std::string file( x );` minting a symbol
# named `file`), so the shape is known and recurring rather than novel.
#
# TWO VETOES, both FACTS rather than heuristics — which is why they are gateable:
#   (K) A reserved keyword can never be a function name. `return`, `if`, `while`, `for`, `switch`,
#       `sizeof`, `goto`, `break`, `continue`, `else`, `do`, `case`, `default`, `typedef`, `struct`,
#       `union`, `enum`, `static`, `extern`, `const`, `volatile`, `inline`, `register`, `auto`, `signed`,
#       `unsigned`, `void`, `char`, `short`, `int`, `long`, `float`, `double`, `return`.
#   (L) A function definition's parameter list cannot consist only of INTEGER LITERALS. `f(3, 4)` at
#       definition position is an attribute macro, a vexing parse, or a call — never a definition.
#
# Arms:
#   (K1) no symbol in any indexed corpus is named a C/C++ reserved keyword
#   (K2) the specific tmux rows are gone: no `return` and no `printflike` symbol
#   (L1) no symbol is minted from an all-integer-literal parameter list
#   (N)  NON-VACUITY: the fixtures below DO contain both shapes, so a pass means the veto fired and not
#        that the shapes were absent
#   (C)  CONTROL: a real function whose name merely CONTAINS a keyword (`returnValue`, `printflikeFmt`)
#        is still indexed — the veto is exact, not a substring match
#   (D)  --dead-code on tmux reports no phantom row
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
fail=0
ok(){ printf '  PASS  %s\n' "$1"; }
no(){ printf '  FAIL  %s\n' "$1"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "phantomdefcheck: BIN=$BIN"

# ---------------------------------------------------------------------------------------------------
# The fixture carries BOTH phantom shapes and both controls, so every arm below is answered on a corpus
# this gate owns rather than on whatever a vendored tree happens to contain.
# ---------------------------------------------------------------------------------------------------
mkdir -p "$WORK/c"
cat >"$WORK/c/fix.c" <<'EOF'
#include <stdio.h>

/* (L) the attribute-macro shape: tmux's printflike(a,b) expands to __attribute__((format(printf,a,b))).
   The "parameter list" is two integer literals, so this is not a definition of anything. */
#define printflike(a, b) __attribute__((format(printf, a, b)))

/* THE REAL SHAPE, copied from tmux window-customize.c:320. The attribute macro sits on its own line
   BETWEEN the return type and the function name, so the parser takes `printflike(7, 8)` as the declarator:
   the real function is never indexed, the phantom takes its place, and the phantom then owns the real
   body — which is where symbols named `return` come from. My first fixture put the macro AFTER the
   parameter list and reproduced only half the defect, so (K1) was passing vacuously. */
static int printflike(7, 8)
realwriter(const char *fmt, int n)
{
	if (n == 0)
		return (0);
	return (n + 1);
}

/* (C) a real function whose name CONTAINS a keyword, and one that contains the macro's name. Both must
   stay indexed: the veto is on the exact name, never on a substring. */
static int returnValue(int x) { return (x); }
static int printflikeFmt(int x) { return (x + 1); }

/* (K) the keyword shape: a bare parenthesised return. A naive declarator pattern reads `return (0)` as a
   function declarator named `return`. */
static int pick(int x)
{
	if (x > 0) {
		return (0);
	}
	return (1);
}

int main(void) { return returnValue(pick(2)) + printflikeFmt(1); }
EOF

run(){ "$BIN" "$WORK/c" --legend=compact 2>/dev/null; }
MAP="$( run )"
[ -n "$MAP" ] || { no "(A0) the fixture produced no map"; echo "FAILURES"; exit 1; }
ok "(A0) the fixture indexed ($( printf '%s' "$MAP" | wc -c | tr -d ' ' ) B)"

names(){ printf '%s' "$MAP" | grep -o 'n="[^"]*"' | sed 's/n="//; s/"$//' | sort -u; }

# (N) NON-VACUITY FIRST. If the fixture's phantom shapes are not even present in the source, every arm
# below passes for the wrong reason. Assert the source carries them.
# The shape is the macro ON ITS OWN LINE between the return type and the name, followed by the real name
# and a body containing a bare `return (0);`. An earlier version of this arm grepped for the macro with
# different arguments than the fixture used and so went stale silently — a non-vacuity arm that does not
# track its own fixture is the one arm that must never be approximate.
if grep -qE '^static int printflike\(7, 8\)$' "$WORK/c/fix.c" \
   && grep -qE '^realwriter\(' "$WORK/c/fix.c" \
   && grep -q 'return (0);' "$WORK/c/fix.c"; then
    ok "(N) the fixture carries the real shape: an attribute macro on its own line, the real name below it, and a bare return (0) in the body"
else
    no "(N) the fixture no longer carries the real shape; every arm below would pass vacuously"
fi

# (C) THE CONTROL, before the vetoes: the real functions must be indexed. A veto that also removes these
# is worse than the defect, and this arm is what tells the two apart.
missing=""
for want in pick main returnValue printflikeFmt; do
    names | grep -qx "$want" || missing="$missing $want"
done
if [ -z "$missing" ]; then
    ok "(C) every real function is indexed, including returnValue and printflikeFmt (name CONTAINS a keyword / the macro name)"
else
    no "(C) the index LOST a real function:$missing — a veto must not reach these"
fi

# (K1) no reserved keyword is a symbol name, anywhere in the fixture.
KEYWORDS="return if while for switch sizeof goto break continue else do case default typedef struct union enum static extern const volatile inline register auto signed unsigned void char short int long float double"
hit=""
for kw in $KEYWORDS; do
    names | grep -qx "$kw" && hit="$hit $kw"
done
if [ -z "$hit" ]; then
    ok "(K1) no indexed symbol is named a reserved keyword ($( printf '%s' "$KEYWORDS" | wc -w | tr -d ' ' ) checked)"
else
    no "(K1) indexed symbols named a reserved keyword:$hit — a keyword can never be a function name"
fi

# (L2) THE HALF THAT MATTERS MORE THAN THE PHANTOM: the real definition must be indexed. A phantom is
# noise; a MISSING definition makes every call to it unresolved, and on the corpus where this was found the
# phantom had absorbed the real function's body (`--defs` answered found="0" while `--grep` attributed the
# definition line to `in="printflike"`).
if names | grep -qx "realwriter"; then
    ok "(L2) the real definition behind the attribute macro is indexed"
else
    no "(L2) 'realwriter' is NOT indexed — the attribute macro cost a real function, not just added a phantom"
fi

# (L1) no symbol minted from the all-literal parameter list.
if names | grep -qx "printflike"; then
    no "(L1) 'printflike' is indexed as a definition — its parameter list is two integer literals, which no definition has"
else
    ok "(L1) no symbol minted from an all-integer-literal parameter list"
fi

# (D) THE REAL CORPUS, which is where the defect was found. Skipped loudly rather than silently when the
# tree is absent, because a silent skip here would read as a pass.
TMUX="/Users/qgames/m5-work/repos/tmux"
if [ -d "$TMUX" ]; then
    DC="$( "$BIN" "$TMUX" --dead-code --legend=compact 2>/dev/null )"
    ph="$( printf '%s' "$DC" | grep -o 'n="\(return\|printflike\)"' | sort -u | tr '\n' ' ' )"
    tot="$( printf '%s' "$DC" | grep -o 'count="[0-9]*"' | head -1 )"
    if [ -z "$ph" ]; then
        ok "(D) --dead-code on tmux reports no phantom row ($tot)"
    else
        no "(D) --dead-code on tmux still reports phantom rows: $ph ($tot) — a wrong row here tells an agent to delete live code"
    fi
else
    printf '  SKIP  (D) the tmux corpus is absent at %s — the fixture arms above still ran\n' "$TMUX"
fi

if [ "$fail" -ne 0 ]; then echo "phantomdefcheck: FAILURES"; exit 1; fi
echo "phantomdefcheck: ALL PASS"
