#!/usr/bin/env bash
# patterncheck.sh — R2 gate: `--pattern='foo($X, ...)'`, the code-shaped structural search.
#
# --match makes you write tree-sitter s-expressions and know each grammar's node-kind vocabulary.
# --pattern takes CODE and compiles it, per grammar, into a shape to match — the ast-grep idea, done
# deterministically and with ripwire's honesty contract attached.
#
# The invariants this gate pins, in the order they were designed:
#
#   1. ONE pattern, MANY grammars. `foo($A, $B)` is a call in eleven languages; the same string must find
#      it in all eleven, and the header must NAME which grammars it resolved for (grammars=) and WHAT node
#      kind it became in each (shapes=). A zero that is really "no grammar could ask the question" is the
#      §P0.1 defect wearing a different hat.
#   2. The NODE-KIND GUARD. A clean parse is NOT sufficient (E1 spike, 2026-08-14: ruby's bare `new` and
#      bash's bare `try` both parse clean into the wrong node kind). A pattern that collapses to a single
#      bare token is refused, loudly, and never scanned.
#   3. The ELLIPSIS IS BOUNDED, and the bound is DISCLOSED. `...` may not mean "unbounded backtracking we
#      never tell you about": the match is a single left-to-right FIRST-MATCH-WINS probe (ast-grep recon
#      §3 — no backtracking), under a hard per-ellipsis node cap. Both facts land on the element as
#      ellipsis="first-match" and ellipsis_bound=N whenever the pattern uses one.
#   4. REFUSE, never a silent zero. An unparseable pattern, or one no supported grammar resolves, exits 1
#      with a message — it must not print a confident hits="0" it did not measure.
#   5. Metavariable CONSISTENCY: `$X` twice in one pattern means the same text twice.
#   6. Determinism + well-formedness, like every other emitting verb.
#
#   RIPWIRE_BIN=build/ripwire      bash test/patterncheck.sh
#   RIPWIRE_BIN=../ripwire-wt-wave3/build/ripwire bash test/patterncheck.sh   # must FAIL (pre-feature binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "patterncheck: BIN=$BIN  ROOT=$ROOT"

attrOf(){ grep -oE " $2=\"[^\"]*\"" "$1" | head -1 | sed -E "s/^ $2=\"//; s/\"$//"; }
# Element-scoped read. attrOf greps the WHOLE document, and the legend that precedes the element names
# several attributes in prose (ellipsis_capped, hits_capped, ...) — a naive grep reads the legend's example
# instead of the run's own value. Anything the legend spells must be read through this.
patAttrOf(){ grep -oE '<pattern [^>]*>' "$1" | head -1 | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E "s/^ $2=\"//; s/\"$//"; }
hitsOf(){ attrOf "$1" hits; }

# ── the multi-language fixture, built in a temp dir ───────────────────────────────────────────────────
# NOT committed under test/: eleven new source files inside the repo would shift every gate that pins a
# corpus-wide count (symbol totals, lint tallies, clone groups). The corpus is the point here, not the
# location, so it is generated per run and thrown away.
FIX="$TMP/fix"; mkdir -p "$FIX"
printf 'void g(void){ foo(1, 2); }\n'                          > "$FIX/a.c"
printf 'void g(){ foo(1, 2); }\n'                              > "$FIX/a.cpp"
printf 'void g(void){ foo(1, 2); }\n'                          > "$FIX/a.m"
printf 'class A { void g(){ foo(1, 2); } }\n'                  > "$FIX/A.java"
printf 'class A { void G(){ foo(1, 2); } }\n'                  > "$FIX/a.cs"
printf 'function g(){ foo(1, 2); }\n'                          > "$FIX/a.js"
printf 'function g(): void { foo(1, 2); }\n'                   > "$FIX/a.ts"
printf 'def g():\n    foo(1, 2)\n'                             > "$FIX/a.py"
printf 'package p\n\nfunc g() { foo(1, 2) }\n'                 > "$FIX/a.go"
printf 'fn g() { foo(1, 2); }\n'                               > "$FIX/a.rs"
printf 'func g() { foo(1, 2) }\n'                              > "$FIX/a.swift"
FIXCOUNT=11
# presence guard (CONTRIBUTING §2, "green while inert"): the fixture must really hold 11 files with the
# call in them, or every count assertion below would pass for the wrong reason.
n="$( grep -lF 'foo(1, 2)' "$FIX"/* | wc -l | tr -d ' ' )"
[ "$n" = "$FIXCOUNT" ] && ok "fixture presence guard: $FIXCOUNT files carry the call" \
    || { no "fixture presence guard: $n files carry the call, expected $FIXCOUNT"; }

# ── 1. one pattern, eleven grammars ───────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --pattern='foo($A, $B)' >"$TMP/all" 2>"$TMP/allerr"; rc=$?
[ "$rc" -eq 0 ] && ok "two-metavar call pattern: exit 0" || no "two-metavar call pattern: exit $rc ($( head -c 200 "$TMP/allerr" ))"
h="$( hitsOf "$TMP/all" )"
[ "${h:-0}" = "$FIXCOUNT" ] && ok "foo(\$A, \$B) found the call in all $FIXCOUNT languages (hits=$h)" \
    || no "foo(\$A, \$B) hits=${h:-<none>}, expected $FIXCOUNT — per-language rows: $( grep -oE '<m p="[^"]*"' "$TMP/all" | tr '\n' ' ' )"

# grammars= / shapes= — the §L3 applicability disclosure, in --pattern's own vocabulary
g="$( patAttrOf "$TMP/all" grammars )"
for lang in c cpp objc java csharp javascript typescript python go rust swift; do
    case ",$g," in
        *",$lang,"*) ok "grammars= names $lang" ;;
        *)           no "grammars= omits $lang (got: $g)" ;;
    esac
done
s="$( attrOf "$TMP/all" shapes )"
[ -n "$s" ] && ok "shapes= discloses the node kind the pattern became per grammar: $s" \
    || no "shapes= missing — the reader cannot tell what the pattern was interpreted as"
case "$s" in *"python:call"*) ok "shapes= python:call (the pattern really resolved, not just parsed)" ;;
             *) no "shapes= has no python:call entry (got: $s)" ;; esac
[ -n "$( patAttrOf "$TMP/all" eligible_files )" ] && ok "eligible_files= present" || no "eligible_files= missing"
[ -n "$( attrOf "$TMP/all" of_files )" ]       && ok "of_files= present"       || no "of_files= missing"

# ── 2. the node-kind guard: a clean parse is not enough ───────────────────────────────────────────────
# `foo` parses clean in every grammar (an identifier / a bash command / a ruby method call) and means
# nothing structural. E1's ruby-`new` and bash-`try` traps are this shape. `$$$X` / `...` as the WHOLE
# pattern is ast-grep's gh#2697 (RootMultiMetaVar): a pattern matches one node, a multi-capture matches a
# LIST, so it cannot legally be the root — refuse syntactically instead of accepting wrong semantics.
for bare in 'foo' '$X' 'new' '...' '$$$X' '$$$'; do
    "$BIN" "$FIX" --pattern="$bare" >"$TMP/bare.out" 2>"$TMP/bare.err"; rcb=$?
    # "unknown flag" is NOT a refusal of the pattern — without this clause the arm passes on a binary
    # that has no --pattern at all (CONTRIBUTING §2, a gate that cannot observe what it asserts).
    if grep -q 'unknown flag' "$TMP/bare.err"; then
        no "bare-token pattern '$bare': the binary has no --pattern flag"
    elif [ "$rcb" -eq 1 ] && ! grep -q '<pattern' "$TMP/bare.out" && [ -s "$TMP/bare.err" ]; then
        ok "bare-token pattern '$bare' refused (exit 1, no element, message on stderr)"
    else
        no "bare-token pattern '$bare': want exit 1 + no <pattern> element, got exit $rcb"
    fi
done

# ── 3. the ellipsis is bounded and the bound is disclosed ─────────────────────────────────────────────
"$BIN" "$FIX" --pattern='foo($A, ...)' >"$TMP/ell" 2>"$TMP/ellerr"; rce=$?
[ "$rce" -eq 0 ] && ok "ellipsis pattern: exit 0" || no "ellipsis pattern: exit $rce ($( head -c 200 "$TMP/ellerr" ))"
eb="$( attrOf "$TMP/ell" ellipsis_bound )"
[ -n "$eb" ] && [ "$eb" -gt 0 ] 2>/dev/null && ok "ellipsis_bound=\"$eb\" disclosed on the element" \
    || no "ellipsis_bound= missing or non-numeric on an ellipsis pattern (got '$eb')"
# The recon suggested spelling this ellipsis="greedy"; the emitted value is "first-match" because that is
# what the probe DOES — it takes the FIRST split that works, which is the lazy end of greedy, not the
# longest. Naming it greedy would be a small fabrication in an attribute whose whole job is disclosure.
[ "$( attrOf "$TMP/ell" ellipsis )" = "first-match" ] && ok "ellipsis=\"first-match\" discloses the probe is not an exhaustive search" \
    || no "ellipsis= does not name the probe (got '$( attrOf "$TMP/ell" ellipsis )')"
he="$( hitsOf "$TMP/ell" )"
[ "${he:-0}" = "$FIXCOUNT" ] && ok "foo(\$A, ...) matched the same $FIXCOUNT call sites" \
    || no "foo(\$A, ...) hits=${he:-<none>}, expected $FIXCOUNT"
# `$$$` is ast-grep's spelling of the same idea; the two must agree, so a user's muscle memory works
h3="$( "$BIN" "$FIX" --pattern='foo($A, $$$)' 2>/dev/null | grep -oE ' hits="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
[ "${h3:-x}" = "${he:-y}" ] && ok "\$\$\$ is accepted as a synonym for ... (hits=$h3)" \
    || no "foo(\$A, \$\$\$) hits=${h3:-<none>} disagrees with foo(\$A, ...) hits=${he:-<none>}"
# absent when the pattern has no ellipsis — the attribute is a FACT about this pattern, not decoration
grep -oE '<pattern [^>]*>' "$TMP/all" | grep -q 'ellipsis_bound=' \
    && no "ellipsis_bound= emitted on a pattern that uses no ellipsis" \
    || ok "ellipsis_bound= absent when the pattern uses no ellipsis"

# ── 3b. the ellipsis in a STATEMENT position, not only in an argument list ────────────────────────────
# `if ($C) { ... }` is the shape users reach for, and in a semicolon language the substituted ellipsis is
# a bare expression statement that does not parse without its `;`. The normalizer has to try both.
mkdir -p "$TMP/stmt"
printf 'void g(int c){ if (c) { h(); k(); } }\n'                 > "$TMP/stmt/s.c"
printf 'class A { void g(boolean c){ if (c) { h(); k(); } } }\n' > "$TMP/stmt/S.java"
printf 'function g(c){ if (c) { h(); k(); } }\n'                 > "$TMP/stmt/s.js"
hst="$( "$BIN" "$TMP/stmt" --pattern='if ($C) { ... }' 2>/dev/null | grep -oE ' hits="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
[ "${hst:-0}" = "3" ] && ok "an ellipsis in a statement position resolves in c/java/js alike (hits=3)" \
    || no "statement-position ellipsis: hits=${hst:-<none>}, expected 3"

# ── 4. refuse, never a silent zero ────────────────────────────────────────────────────────────────────
for badpat in '}{' 'if if if )( }' '@@@@'; do
    "$BIN" "$FIX" --pattern="$badpat" >"$TMP/bad.out" 2>"$TMP/bad.err"; rcx=$?
    if grep -q 'unknown flag' "$TMP/bad.err"; then
        no "unresolvable pattern '$badpat': the binary has no --pattern flag"
    elif [ "$rcx" -eq 1 ] && ! grep -q '<pattern' "$TMP/bad.out"; then
        ok "unresolvable pattern refused (exit 1, no element): $badpat"
    else
        no "unresolvable pattern '$badpat': want exit 1 + no <pattern> element, got exit $rcx / $( head -c 120 "$TMP/bad.out" )"
    fi
done
# an empty value is the table's own EmptyValue::Refuse contract
# The `unknown flag` guard is the same one the refusal loop above uses, and for the same reason: without
# it a binary that has no --pattern flag at all satisfies this arm (exit 1 + non-empty stderr) and passes
# for the wrong reason. Measured against the ba3a716 reference binary, 2026-08-20 (V-4).
"$BIN" "$FIX" --pattern= >/dev/null 2>"$TMP/empty.err"; rcz=$?
if grep -q 'unknown flag' "$TMP/empty.err"; then
    no "--pattern= (empty): the binary has no --pattern flag — this arm cannot observe the refusal contract"
elif [ "$rcz" -ne 0 ] && [ -s "$TMP/empty.err" ]; then
    ok "--pattern= (empty) refuses"
else
    no "--pattern= (empty) did not refuse (exit $rcz)"
fi

# ── 4b. the SOFT tier: a zero that a partly-unresolved pattern could explain must say so ──────────────
# ast-grep's PatternHasError (recon §4): fires ONLY when hits=0 AND the pattern failed to resolve
# somewhere — never as noise on a run that still worked. `if ($C) { ... }` is a C-family/JS/Java shape
# that python's grammar cannot spell, and the fixture holds no if-statement at all, so both halves hold.
"$BIN" "$FIX" --pattern='if ($C) { ... }' >"$TMP/soft" 2>/dev/null; rcs=$?
[ "$rcs" -eq 0 ] && ok "partly-resolvable pattern still runs (exit 0)" || no "partly-resolvable pattern exit $rcs"
[ "$( hitsOf "$TMP/soft" )" = "0" ] && ok "if (\$C) { ... } finds nothing in the fixture (hits=0)" \
    || no "fixture unexpectedly matched if (\$C) { ... } — pick a different soft-tier probe"
pe="$( attrOf "$TMP/soft" unresolved_in )"
[ -n "$pe" ] && ok "unresolved_in=\"$pe\" explains the zero instead of presenting it as absence" \
    || no "hits=0 with grammars left unresolved and no unresolved_in= — the zero reads as 'none exists'"
# ...and it is SILENT on a run that found something AND read every file it serves (never nag when the run
# was useful and complete). V-3 narrowed this claim: "hits>0" alone is NOT the withholding condition, and
# believing it was is what let a matched .tsx sit beside a silently unread .ts. skipped_files= is the other
# half of the condition, and arm 4e below is the case that separates them.
sk_all="$( patAttrOf "$TMP/all" skipped_files )"
[ "${sk_all:-x}" = "0" ] && ok "control: the all-languages run scanned every served file (skipped_files=0)" \
    || no "control: the all-languages fixture has skipped_files=${sk_all:-<none>} — arm 4b's withholding claim is testing the wrong case"
grep -oE '<pattern [^>]*>' "$TMP/all" | grep -q 'unresolved_in=' \
    && no "unresolved_in= leaked onto a run with hits>0 and skipped_files=0 (nothing there could mislead)" \
    || ok "unresolved_in= absent when the run found matches and skipped nothing"

# ── 4d. V-2: the ellipsis sibling cap must SAY when it bit ────────────────────────────────────────────
# Found 2026-08-20 by adversarial verification. `foo(0,…,399, zzz)` LITERALLY matches `foo(...)`, but the
# first-match-wins probe abandons the node once the sibling run exceeds ellipsis_bound — and the run
# reported hits="1" with hits_capped="0" capped="0", presenting a floor as a total. ellipsis_bound=
# disclosed the limit statically; nothing said "it bit HERE". Non-negotiable 3: every truncation is
# disclosed in the header.
#
# The bound counts SIBLINGS and an argument list interleaves separators (children = 2*args + 1), so the
# real argument ceiling is ~128 — the fixture straddles it deliberately: 10 args under, 400 args over.
mkdir -p "$TMP/elldir"
printf 'void g(){ foo(%s, zzz); }\n' "$( seq -s, 0 9 )"   > "$TMP/elldir/small.c"
printf 'void g(){ foo(%s, zzz); }\n' "$( seq -s, 0 399 )" > "$TMP/elldir/big.c"
# presence guard: both files must really carry the call, or the arm proves nothing
[ "$( grep -lF 'foo(' "$TMP/elldir"/*.c | wc -l | tr -d ' ' )" = "2" ] \
    && ok "(4d) presence guard: both the under-cap and over-cap files carry the call" \
    || no "(4d) presence guard: the ellipsis fixture did not write two files carrying foo("
"$BIN" "$TMP/elldir" --pattern='foo(...)' >"$TMP/ell.out" 2>/dev/null
he="$( patAttrOf "$TMP/ell.out" hits )"
[ "${he:-x}" = "1" ] && ok "(4d) the over-cap call is NOT matched (hits=1, the under-cap one) — the cap is real" \
    || no "(4d) ellipsis fixture hits=${he:-<none>}, expected 1 — the cap no longer bites and this arm is inert"
ec="$( patAttrOf "$TMP/ell.out" ellipsis_capped )"
es="$( patAttrOf "$TMP/ell.out" ellipsis_skipped )"
[ "${ec:-x}" = "1" ] && ok "(4d) ellipsis_capped=\"1\" discloses that the bound bit on THIS run" \
    || no "(4d) UNDISCLOSED TRUNCATION: a literal match was dropped at the ellipsis bound and ellipsis_capped=\"${ec:-<none>}\" — hits= is a floor presenting itself as a total"
[ "${es:-0}" -ge 1 ] 2>/dev/null && ok "(4d) ellipsis_skipped=\"$es\" says how many nodes went unevaluated" \
    || no "(4d) ellipsis_skipped=\"${es:-<none>}\" — the magnitude of the drop is not disclosed"
# ...and the flag is HONEST in the other direction: a run the cap never touched must say 0, or the
# disclosure is noise a reader learns to skim.
mkdir -p "$TMP/ellok" && cp "$TMP/elldir/small.c" "$TMP/ellok/"
"$BIN" "$TMP/ellok" --pattern='foo(...)' >"$TMP/ellok.out" 2>/dev/null
[ "$( patAttrOf "$TMP/ellok.out" ellipsis_capped )" = "0" ] && [ "$( patAttrOf "$TMP/ellok.out" ellipsis_skipped )" = "0" ] \
    && ok "(4d) a run under the bound reports ellipsis_capped=\"0\" ellipsis_skipped=\"0\"" \
    || no "(4d) FALSE ALARM: an under-cap run claims the bound bit ($( grep -oE 'ellipsis_[a-z]+="[0-9]+"' "$TMP/ellok.out" | tr '\n' ' ' ))"
# ...and it is absent entirely on a pattern with no ellipsis (a fact about nothing is decoration)
"$BIN" "$FIX" --pattern='foo($A, $B)' 2>/dev/null | grep -oE '<pattern [^>]*>' | grep -q 'ellipsis_capped=' \
    && no "(4d) ellipsis_capped= emitted on a pattern that has no ellipsis" \
    || ok "(4d) ellipsis_capped= absent on a pattern with no ellipsis"

# ── 4e. V-3: dialect-split grammars must not contradict the legend ───────────────────────────────────
# Two file extensions can share a querySub (the tags.scm TEMPLATE key) while using different grammar
# OBJECTS: .cu/.cuh ride tree_sitter_cuda under "cpp", .tsx rides tree_sitter_tsx under "typescript".
# Before this arm, grammars= printed the shared NAME, so a CUDA-only pattern reported grammars="cpp" while
# the one .cpp file in the corpus went unscanned and unnamed in unresolved_in= — two attributes on one
# element contradicting each other and the legend. Every disclosed set is now keyed per OBJECT.
mkdir -p "$TMP/cu"
printf 'void kern(int a){}
void host(){ kern(3); }
' > "$TMP/cu/b.cpp"
"$BIN" "$TMP/cu" --pattern='kern<<<$G, $B>>>($A)' >"$TMP/cu.out" 2>"$TMP/cu.err"; rccu=$?
if grep -q 'unknown flag' "$TMP/cu.err"; then
    no "(4e) the binary has no --pattern flag — this arm cannot observe the dialect contract"
else
    [ "$rccu" -eq 0 ] && ok "(4e) a CUDA-only launch pattern runs (exit 0) — it resolves for the cuda grammar" \
        || no "(4e) CUDA launch pattern exit $rccu ($( head -c 160 "$TMP/cu.err" ))"
    gcu="$( patAttrOf "$TMP/cu.out" grammars )"
    ucu="$( patAttrOf "$TMP/cu.out" unresolved_in )"
    case ",$gcu," in
        *",cpp,"*) no "(4e) grammars=\"$gcu\" claims the C++ grammar resolved — only the CUDA object did, and the .cpp file was never scanned" ;;
        *)         ok "(4e) grammars=\"$gcu\" names the dialect apart from the grammar it borrows templates from" ;;
    esac
    case ",$ucu," in
        *",cpp,"*) ok "(4e) unresolved_in=\"$ucu\" names cpp — the grammar the unscanned .cpp file needed" ;;
        *)         no "(4e) unresolved_in=\"${ucu:-<none>}\" omits cpp, yet the .cpp file went unscanned — the disclosure erased the failing object" ;;
    esac
    [ "$( patAttrOf "$TMP/cu.out" eligible_files )" = "0" ] && ok "(4e) eligible_files=\"0\" — consistent with grammars=, which no longer claims cpp" \
        || no "(4e) eligible_files=\"$( patAttrOf "$TMP/cu.out" eligible_files )\" disagrees with grammars=\"$gcu\""
    [ "$( patAttrOf "$TMP/cu.out" skipped_files )" = "1" ] && ok "(4e) skipped_files=\"1\" names the cost: one served-language file was never read" \
        || no "(4e) skipped_files=\"$( patAttrOf "$TMP/cu.out" skipped_files )\" — the unscanned .cpp file is still unannounced"
fi
# the hits>0 half: a matched .tsx must not hide a silently unread .ts sibling
mkdir -p "$TMP/tsx"
printf 'export const Foo = (p: any) => null;
export function util(){ return 1; }
' > "$TMP/tsx/util.ts"
printf 'export const Page = () => <Foo bar={1} />;
' > "$TMP/tsx/page.tsx"
"$BIN" "$TMP/tsx" --pattern='<Foo bar={$V} />' >"$TMP/tsx.out" 2>/dev/null
htsx="$( patAttrOf "$TMP/tsx.out" hits )"
[ "${htsx:-0}" -ge 1 ] 2>/dev/null && ok "(4e) the JSX pattern matches in page.tsx (hits=$htsx)" \
    || no "(4e) the JSX pattern found nothing — the arm below would pass for the wrong reason"
[ "$( patAttrOf "$TMP/tsx.out" skipped_files )" = "1" ] && ok "(4e) skipped_files=\"1\" on a run WITH hits — util.ts was never read and says so" \
    || no "(4e) skipped_files=\"$( patAttrOf "$TMP/tsx.out" skipped_files )\" — util.ts went unscanned on a hits>0 run with nothing to say so"
[ -n "$( patAttrOf "$TMP/tsx.out" unresolved_in )" ] && ok "(4e) unresolved_in= is emitted despite hits>0, because a served file was skipped" \
    || no "(4e) unresolved_in= withheld on a hits>0 run that skipped a served file — the withholding rule is still 'hits>0' alone"

# ── 4f. V-6: --pattern honors paging, so the disclosure list must name it ─────────────────────────────
# honorsPaging() includes --pattern and --limit demonstrably windows it, but kPagingHonoringVerbs — spliced
# into four refusal messages — omitted it, so `--pattern … --token-budget=200` told the user to narrow with
# --limit while pointing at a set that excluded the verb they were on.
mkdir -p "$TMP/pg" && printf 'void g(){ foo(1); foo(2); foo(3); }
' > "$TMP/pg/a.c"
"$BIN" "$TMP/pg" --pattern='foo($A)' --limit=1 >"$TMP/pg.out" 2>/dev/null
[ "$( patAttrOf "$TMP/pg.out" hits )" = "3" ] && [ "$( patAttrOf "$TMP/pg.out" shown )" = "1" ] \
    && ok "(4f) --pattern honors --limit (hits=3 shown=1) — the premise of the disclosure below" \
    || no "(4f) --pattern did not window under --limit=1: $( grep -oE '<pattern [^>]*' "$TMP/pg.out" | head -c 200 )"
"$BIN" "$TMP/pg" --pattern='foo($A)' --token-budget=200 >/dev/null 2>"$TMP/pg.err"
if grep -q 'unknown flag' "$TMP/pg.err"; then
    no "(4f) the binary has no --pattern flag — this arm cannot observe the disclosure"
else
    grep -q -- '--pattern' "$TMP/pg.err" \
        && ok "(4f) the paging-honored list in the refusal message names --pattern" \
        || no "(4f) the refusal message redirects to --limit through a list that omits --pattern: $( head -c 300 "$TMP/pg.err" )"
fi

# ── 4c. a modifier that cannot be honored is refused, not silently dropped ────────────────────────────
# --sarif serializes --lint/--lint-rules findings. --pattern returns from runLint with its own element
# before any finding exists, so a --sarif that looked accepted would never take effect — the same silent
# no-op --match already refuses.
"$BIN" "$FIX" --lint --pattern='foo($A, $B)' --sarif >"$TMP/sar.out" 2>"$TMP/sar.err"; rcsar=$?
[ "$rcsar" -ne 0 ] && grep -q -- '--sarif' "$TMP/sar.err" && ok "--sarif with a pattern refuses instead of silently no-oping" \
    || no "--sarif + pattern: want a non-zero exit naming --sarif, got exit $rcsar / $( head -c 160 "$TMP/sar.err" )"
# control: the same run without --sarif is a normal, working pattern search
"$BIN" "$FIX" --pattern='foo($A, $B)' >/dev/null 2>&1 && ok "control: the same pattern without --sarif still runs" \
    || no "control arm broke — the refusal above may be firing for the wrong reason"

# ── 5. metavariable consistency ───────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/mv"
printf 'function g(){ eq(a, a); eq(a, b); }\n' > "$TMP/mv/m.js"
hs="$( "$BIN" "$TMP/mv" --pattern='eq($X, $X)' 2>/dev/null | grep -oE ' hits="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
[ "${hs:-x}" = "1" ] && ok "\$X twice binds the SAME text (eq(a,a) matched, eq(a,b) did not)" \
    || no "metavariable consistency broken: eq(\$X, \$X) hits=${hs:-<none>}, expected 1"
hd="$( "$BIN" "$TMP/mv" --pattern='eq($X, $Y)' 2>/dev/null | grep -oE ' hits="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
[ "${hd:-x}" = "2" ] && ok "distinct metavariables bind independently (hits=2)" \
    || no "eq(\$X, \$Y) hits=${hd:-<none>}, expected 2"

# ── 6. structure, not text: a different node kind must not match ──────────────────────────────────────
mkdir -p "$TMP/shape"
printf 'function g(){ foo(1, 2); }\nfunction h(){ let foo = [1, 2]; }\n' > "$TMP/shape/s.js"
hsh="$( "$BIN" "$TMP/shape" --pattern='foo($A, $B)' 2>/dev/null | grep -oE ' hits="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
[ "${hsh:-x}" = "1" ] && ok "a call pattern does not match an array literal with the same tokens" \
    || no "structural discrimination broken: hits=${hsh:-<none>}, expected 1"

# ── 6b. comments inside a candidate are transparent (ast-grep's Smart default, recon §3) ──────────────
mkdir -p "$TMP/triv"
printf 'function g(){ foo(1 /* note */, 2); }\n' > "$TMP/triv/t.js"
ht="$( "$BIN" "$TMP/triv" --pattern='foo($A, $B)' 2>/dev/null | grep -oE ' hits="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
[ "${ht:-x}" = "1" ] && ok "an inline comment inside the call does not defeat the match" \
    || no "comment transparency broken: hits=${ht:-<none>}, expected 1"

# ── 7. the enclosing symbol, like --match ─────────────────────────────────────────────────────────────
grep -q '<m p="[^"]*" in="g"' "$TMP/all" && ok "rows carry the enclosing symbol (in=\"g\")" \
    || no "rows are missing the in= enclosing symbol: $( grep -oE '<m [^>]*>' "$TMP/all" | head -1 )"

# ── 8. determinism + well-formedness ──────────────────────────────────────────────────────────────────
"$BIN" "$ROOT/src" --pattern='ts_node_child($A, $B)' >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT/src" --pattern='ts_node_child($A, $B)' >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "determinism: two runs byte-identical" || no "determinism: two runs differ"
hr="$( hitsOf "$TMP/d1" )"
[ "${hr:-0}" -ge 1 ] 2>/dev/null && ok "found ts_node_child(\$A, \$B) in ripwire's own src (hits=$hr)" \
    || no "ts_node_child(\$A, \$B) found nothing in src/ — it is called there (presence guard below)"
grep -qF 'ts_node_child(' "$ROOT/src/ingest.cpp" && ok "presence guard: src/ingest.cpp really calls ts_node_child(" \
    || no "presence guard: src/ingest.cpp no longer calls ts_node_child( — pick another probe"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/d1" 2>"$TMP/xmlerr" && ok "output is well-formed XML" || no "xmllint rejected the output: $( head -c 200 "$TMP/xmlerr" )"
else
    ok "xmllint not installed — well-formedness arm skipped"
fi

# ── 9. the coverage contract is DISCLOSED, not implied ────────────────────────────────────────────────
"$BIN" --help >"$TMP/help" 2>&1
grep -q -- '--pattern=' "$TMP/help" && ok "--help documents --pattern=" || no "--help does not mention --pattern="
grep -q 'pattern' "$TMP/all" && ok "the emitted element/legend names the verb" || no "no legend on the pattern output"
# unsupported families are NAMED, so a user of ruby/bash learns it from the tool and not from a zero
"$BIN" "$FIX" --pattern='foo($A, $B)' 2>/dev/null | grep -q 'unsupported=' \
    && ok "unsupported= names the families --pattern deliberately does not serve" \
    || no "unsupported= missing — the coverage limit is undisclosed"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
