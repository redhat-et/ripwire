#!/usr/bin/env bash
# nestedimportcheck.sh — an import written anywhere other than the top level is still a dependency.
#
# ── THE DEFECT ────────────────────────────────────────────────────────────────────────────────────────
# src/ingest.cpp::captureIncludes scanned the file root's DIRECT children. test/preproccondcheck.sh
# covers the C-family half of that bug (directives under `#if`); this gate covers the rest, where the
# wrapper is an ordinary language construct rather than a preprocessor conditional:
#
#   Python  `if TYPE_CHECKING: import x` · `try: import ujson / except ImportError: import json` ·
#           every function-, method- and class-body import. The first two are THE canonical Python
#           spellings of a conditional dependency — the direct analogue of `#ifdef` — and a file using
#           either handed --cochange's StaticIncludeCoupling an empty import list.
#   Rust    `use` inside `mod x { … }` (incl. `#[cfg(unix)] mod plat`, the Rust platform guard), inside
#           a fn / impl / trait body, and inside any block expression.
#   C#      `using` inside a BLOCK-scoped `namespace Foo { … }` — the pre-2021 house style of most C#
#           trees. (The file-scoped form `namespace Foo;` does not nest and was never affected: it is
#           this gate's negative control, test/nestedimportfix/filescoped.cs.)
#   TS/JS   kParserVer 72 (fnbody-require lane): CommonJS `require( … )` / dynamic `import( … )` written
#           INSIDE a function body — a getter, an arrow function passed as a call argument, an if-guarded
#           lazy-init — the shape webpack's own lib/index.js lazy-getter barrel uses. Distinct from the
#           other three rows above: neither spelling is an `import_statement` at all (both are
#           call_expression), so this row is gated by src/ingest.cpp's jsModuleLoadTarget, not by a grammar
#           rule that only fires at the top level.
#
# ── WHY THE CONTAINER ALLOWLIST IS KEYED BY LANGUAGE ─────────────────────────────────────────────────
# `block` and `declaration_list` are node-type names in half a dozen of our grammars. A SHARED list
# would make the walk descend into every C++/TypeScript/Java function body hunting a directive form
# those languages do not have there — cost with no recall. So each language names only the containers
# ITS directives actually appear in. test/nestedimportfix/scope_control.ts is STILL that control, but its
# claim flipped at kParserVer 72: through 71 it proved a TS function body holding a dynamic `import( … )`
# and a `require( … )` reported exactly ONE include (the language was NOT widened); from 72 it proves the
# OPPOSITE — those two calls (plus a third, guarded one) ARE captured, each lazy="1" on --impact's import
# tier — while a computed specifier and a member-expression callee inside those SAME function bodies still
# report NOTHING, because jsModuleLoadTarget's three guards do not relax with depth. The C-family side is
# pinned independently by test/preproccondcheck.sh's exact per-file counts, which move if C++ ever picks up
# a body container.
#
# ── HOW THE EXPECTED NUMBERS WERE CHOSEN ─────────────────────────────────────────────────────────────
# Every count below is a LITERAL hand count off the fixture — one distinct module name per arm, counted
# in the source — cross-checked against tree-sitter node counts obtained with `--match` BEFORE the
# extractor changed (guarded.py: 18 import_statement + 1 import_from_statement = 19; guarded.rs: 15
# use_declaration + 1 body-less `mod` = 16). None is derived from the container table, so a wrong table
# cannot make this gate agree with itself.
#
# ── ARMS ──────────────────────────────────────────────────────────────────────────────────────────────
#   0.  PRESENCE   — the fixture spells each arm, and every fixture file parses with ZERO ERROR nodes
#                    (a fixture that fails to parse drops arms silently and the gate would pass inert).
#   1.  CAPTURE    — one named assertion per container node kind, per language.
#   1b. CONTROLS   — top-level imports still captured; a body-LESS Rust `mod x;` still emits `mod:x`
#                    (the same node kind must be both READ and DESCENDED INTO — a walk that swallowed
#                    it would silently drop every module-file declaration); the two negative controls.
#   1c. NO SPRAY   — exact per-file counts, plus an explicit assertion that a COMPUTED TS specifier and a
#                    member-expression `require` appear NOWHERE in the output (the genuinely-captured
#                    function-body require/dynamic-import calls are asserted separately in 1e').
#   2.  USE-SITES  — a function-local import's ref carries the DIRECTIVE's own line, not its container's.
#   3.  COCHANGE   — end to end: a Python module whose only import of its sibling sits under
#                    `if TYPE_CHECKING:` must not be reported `surprising="1"`. Positive control in the
#                    same repo, so this arm cannot pass by suppressing the signal wholesale.
#   4.  DEGRADE    — a pathologically nested Python body does not crash, hang, or emit malformed XML.
#   5.  HYGIENE    — determinism, warm == cold (the change is behind kParserVer), well-formed XML.
#   6.  MONOTONIC  — against a binary built from git HEAD, over this repo's own src/: no import that was
#                    captured before may be lost, and `surprising="1"` may only ever be SUPPRESSED.
#
# Usage:
#   bash test/nestedimportcheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/nestedimportcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/nestedimportcheck.sh
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/nestedimportfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }
echo "nestedimportcheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

# ══ 0. PRESENCE GUARD ════════════════════════════════════════════════════════════════════════════════
presence(){ # presence <file> <literal> <label>
    if grep -qF -- "$2" "$FIX/$1"; then ok "presence: $3"; else no "presence: $3 — fixture drifted, arms below cannot assert"; fi
}
presence guarded.py 'if TYPE_CHECKING:'   'python `if TYPE_CHECKING:` arm present'
presence guarded.py 'except ImportError:' 'python try/except-ImportError arm present'
presence guarded.py 'except* ValueError:' 'python except* group arm present'
presence guarded.py 'match value:'        'python match/case arm present'
presence guarded.rs '#[cfg(unix)]'        'rust `#[cfg]` platform-guard mod arm present'
presence guarded.rs 'extern "C"'          'rust extern block arm present'
presence guarded.rs 'pub mod sibling_decl;' 'rust body-LESS `mod x;` control present'
presence Nested.cs  'namespace Outer'     'C# block-scoped namespace arm present'
presence filescoped.cs 'namespace FileScopedNs;' 'C# file-scoped namespace negative control present'
presence scope_control.ts 'await import(' 'TS dynamic-import-in-a-function-body arm present'
presence scope_control.ts 'dyn_computed'  'TS computed-specifier negative control present'
presence scope_control.ts 'fakeModule.require' 'TS member-expression negative control present'

# A fixture that does not PARSE drops arms silently. Assert zero ERROR nodes per file before asserting
# anything about what was extracted from it.
for f in guarded.py guarded.rs Nested.cs filescoped.cs scope_control.ts; do
    mkdir -p "$TMP/parse/$f.d" && cp "$FIX/$f" "$TMP/parse/$f.d/"
    errs="$( "$BIN" "$TMP/parse/$f.d" --match='(ERROR) @e' --no-cache 2>/dev/null | grep -oE 'hits="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
    [ "${errs:-1}" = "0" ] && ok "presence: $f parses with zero ERROR nodes" || no "presence: $f has ${errs:-?} ERROR node(s) — arms on it prove nothing"
done

# ══ 1. CAPTURE ═══════════════════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --deps --no-cache --limit=500 >"$TMP/deps" 2>"$TMP/deps.err"
rc=$?
[ "$rc" -eq 0 ] && ok "--deps exits 0" || { no "--deps exits $rc"; head -3 "$TMP/deps.err"; }
[ -s "$TMP/deps" ] || { echo "nestedimportcheck: empty --deps output, cannot proceed"; exit 2; }

inc(){ # inc <target> <label>
    if grep -qF "<inc t=\"$1\"" "$TMP/deps"; then ok "captured: $2"; else no "DROPPED: $2 (no <inc t=\"$1\"> in --deps)"; fi
}
noinc(){ # noinc <target> <label>
    if grep -qF "$1" "$TMP/deps"; then no "OVER-CAPTURED: $2 ($1 must not appear)"; else ok "not captured: $2"; fi
}

# 1a. Python — one arm per container node kind.
inc mod_if             'python: import under if_statement (`if TYPE_CHECKING:`)'
inc mod_elif           'python: import under elif_clause'
inc mod_else           'python: import under else_clause'
inc mod_try            'python: import under try_statement'
inc mod_except         'python: import under except_clause (`except ImportError:`)'
inc mod_except_group   'python: import under except_group_clause (`except*`)'
inc mod_finally        'python: import under finally_clause'
inc mod_with           'python: import under with_statement'
inc mod_for            'python: import under for_statement'
inc mod_while          'python: import under while_statement'
inc mod_class          'python: import under class_definition'
inc mod_method         'python: import in a method body'
inc mod_func           'python: import in a function body'
inc pkg.deep           'python: FROM-import in a function body'
inc mod_nested_in_func 'python: import two containers deep (function_definition → if_statement)'
inc mod_inner_func     'python: import in a nested function body'
inc mod_decorated      'python: import under decorated_definition'
inc mod_case           'python: import under match_statement → case_clause'

# 1b. Rust — one arm per container node kind.
inc crate::unix_inner          'rust: use under `#[cfg(unix)] mod plat { … }` (the platform guard)'
inc crate::deeper_inner        'rust: use two mod levels down'
inc crate::foreign_inner       'rust: use under foreign_mod_item (`extern "C" { … }`)'
inc crate::fn_local            'rust: use in a fn body (function_item → block)'
inc crate::impl_local          'rust: use in an impl method body (impl_item → declaration_list)'
inc crate::trait_default_local 'rust: use in a trait default-method body (trait_item → declaration_list)'
inc crate::if_local            'rust: use under if_expression'
inc crate::else_local          'rust: use under else_clause'
inc crate::loop_local          'rust: use under loop_expression'
inc crate::while_local         'rust: use under while_expression'
inc crate::for_local           'rust: use under for_expression'
inc crate::match_local         'rust: use under match_expression → match_block → match_arm'
inc crate::unsafe_local        'rust: use under unsafe_block'
inc crate::async_local         'rust: use under async_block'

# 1c. C#.
inc Outer.Inner.Ns   'C#: using inside a block-scoped namespace'
inc Deeper.Inner.Ns  'C#: using inside a NESTED block-scoped namespace'

# 1d. CONTROLS — what already worked must still work; the descent is purely additive.
inc mod_toplevel      'CONTROL: python module-level import'
inc std::fmt          'CONTROL: rust crate-root use'
inc mod:sibling_decl  'CONTROL: rust body-LESS `mod x;` still emits mod:x (node is READ *and* descended into)'
inc Top.Ns            'CONTROL: C# compilation-unit-level using'
inc FileScoped.Before 'CONTROL: C# using before a FILE-scoped namespace (does not nest)'
inc FileScoped.After  'CONTROL: C# using after a FILE-scoped namespace (still a compilation-unit child)'
inc ./mod_toplevel    'CONTROL: TypeScript top-level ESM import'

# 1e'. kParserVer 72 (fnbody-require lane) — TS/JS function-body require()/dynamic-import() arms.
inc ./req_in_function 'TS: `require( … )` guarded by an if_statement inside a function body'
inc ./dyn_in_function 'TS: dynamic `import( … )` under an await_expression inside a function body'
inc ./mod_in_function 'TS: `require( … )` as a bare return_statement inside a DIFFERENT function'

# 1e. NEGATIVE CONTROLS — the language scoping really is scoped. Widening WHERE the walk looks (kParserVer
# 72) never widened WHAT counts as a hit — jsModuleLoadTarget's three guards (bare callee, one arg, a
# string literal) still apply at any depth.
noinc dyn_computed   'TS: a CONCATENATED require/import specifier is dropped, never guessed, at any depth'
noinc req_member     'TS: `fakeModule.require( … )` is a member expression, not a bare callee, at any depth'

# 1f. NO SPRAY — exact per-file counts (hand-read; see the header).
count(){ # count <file> <expected> <label>
    local got
    # RE-PINNED 2026-08-19 (R-E CORRECTION): p= is root-relative, so a fixture file at the crawl root
    # spells p="guarded.py" and the mandatory "/" before $1 matched nothing (every count read <no row>).
    got="$( tr '>' '\n' <"$TMP/deps" | grep -E "<f p=\"([^\"]*/)?$1\" .*includes=" | grep -oE 'includes="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
    if [ "${got:-}" = "$2" ]; then ok "count: $3 (includes=$2)"; else no "count: $3 — expected includes=$2, got includes=${got:-<no row>}"; fi
}
count guarded.py       19 'guarded.py: 18 import + 1 from-import, each captured exactly once'
count guarded.rs       16 'guarded.rs: 15 use + 1 body-less mod, each captured exactly once'
count Nested.cs         3 'Nested.cs: one compilation-unit using + two namespace-scoped'
count filescoped.cs     2 'filescoped.cs: UNCHANGED (file-scoped namespace does not nest)'
count scope_control.ts  4 'scope_control.ts: 1 top-level ESM import + 3 function-body require/dynamic-import (kParserVer 72), each captured exactly once — the two computed/member negative controls contribute nothing'

# The <inc> listing serialize.h emits is capped at 40 children per file (the rest disclosed as `+more`),
# and every `inc`/`noinc` assertion above reads that listing. Assert the cap was not reached, or those
# arms could go red for a truncation rather than for a lost capture.
if grep -q '+more' "$TMP/deps"; then
    no "fixture outgrew the 40-per-file <inc> display cap (+more present) — the capture arms above are unsound"
else
    ok "no fixture file reaches the 40-per-file <inc> display cap (the capture arms read a COMPLETE listing)"
fi

# ══ 2. USE-SITES — the ref carries the DIRECTIVE's line, not its container's ══════════════════════════
IMPLINE="$(   grep -nF 'import mod_nested_in_func' "$FIX/guarded.py" | cut -d: -f1 )"
GUARDLINE="$( grep -nF 'if NESTED_FLAG:'           "$FIX/guarded.py" | cut -d: -f1 )"
FUNCLINE="$(  grep -nF 'def func():'               "$FIX/guarded.py" | cut -d: -f1 )"
if [ -n "$IMPLINE" ] && [ -n "$GUARDLINE" ] && [ -n "$FUNCLINE" ] && [ "$IMPLINE" != "$GUARDLINE" ] && [ "$IMPLINE" != "$FUNCLINE" ]; then
    ok "presence: directive line $IMPLINE differs from its if ($GUARDLINE) and its def ($FUNCLINE) — the line arm can discriminate"
else
    no "presence: could not locate three distinct lines in guarded.py — the line arm below is inert"
fi
"$BIN" "$FIX" --uses=mod_nested_in_func --no-cache >"$TMP/uses" 2>/dev/null
if grep -q 'guarded.py' "$TMP/uses"; then
    ok "--uses reports the two-containers-deep import site"
    if grep -qE "guarded\.py:$IMPLINE\b" "$TMP/uses"; then
        ok "--uses line = the DIRECTIVE line $IMPLINE (not the enclosing if/def line)"
    else
        no "--uses line is not the directive line $IMPLINE"; grep -o 'guarded\.py:[0-9]*' "$TMP/uses" | head -3
    fi
else
    no "--uses does not report the nested import site"; head -c 400 "$TMP/uses"; echo
fi

# ══ 3. COCHANGE — the end-to-end false positive ══════════════════════════════════════════════════════
# Throwaway git repo, self-contained (behaves the same on a fresh clone and a shallow CI checkout).
# One co-change wave touches every file, so every pair has identical together=/deg= support and the ONLY
# variable is whether the import predicate can see the guarded import.
#   pkg/consumer.py  imports pkg/model.py ONLY under `if TYPE_CHECKING:`  → must NOT be surprising
#   pkg/lone.py / pkg/other.py — no import path either way                → must STILL be surprising
CO="$TMP/cofix"
mkCoFixture(){
    mkdir -p "$CO/pkg" || return 1
    printf 'def model_value():\n    return 1\n'                                                    >"$CO/pkg/model.py"
    printf 'from typing import TYPE_CHECKING\nif TYPE_CHECKING:\n    import model\n\ndef use():\n    return 2\n' >"$CO/pkg/consumer.py"
    printf 'def other_value():\n    return 3\n'                                                    >"$CO/pkg/other.py"
    printf 'def lone_value():\n    return 4\n'                                                     >"$CO/pkg/lone.py"
    (
        cd "$CO" || exit 1
        git init -q .                                     || exit 1
        git config user.email nestedimport@example.invalid || exit 1
        git config user.name  'nestedimport gate'          || exit 1
        git config commit.gpgsign false                    || exit 1
        for i in 1 2 3 4 5; do
            for f in pkg/consumer.py pkg/model.py pkg/lone.py pkg/other.py; do printf '# wave %s\n' "$i" >>"$f"; done
            git add -A                                              || exit 1
            git commit -q -m "wave $i" --date="2024-01-0$i 12:00:00" || exit 1
        done
    )
}
if ! command -v git >/dev/null 2>&1; then
    skip "cochange arm: git not on PATH"
elif ! mkCoFixture >"$TMP/cofix.log" 2>&1; then
    skip "cochange arm: fixture repo could not be built ($( head -1 "$TMP/cofix.log" ))"
else
    "$BIN" "$CO" --cochange --pack-top-n=1000 >"$TMP/co" 2>/dev/null
    row(){ tr '>' '\n' <"$TMP/co" | grep -F "$1" | grep -F "$2" | head -1; }
    CM="$( row 'consumer.py' 'model.py' )"
    LO="$( row 'lone.py'     'other.py' )"
    if [ -z "$CM" ]; then
        skip "cochange: the (consumer.py, model.py) pair is absent — fixture history did not register"
    elif printf '%s' "$CM" | grep -q 'surprising="1"'; then
        no "cochange: (consumer.py, model.py) still surprising=\"1\" — the TYPE_CHECKING import is invisible to StaticIncludeCoupling"
        printf '        %s\n' "$CM"
    else
        ok "cochange: an `if TYPE_CHECKING:` import defeats surprising=\"1\" (the false positive is gone)"
    fi
    if [ -z "$LO" ]; then
        skip "cochange positive control: the (lone.py, other.py) pair is absent from the emitted rows"
    elif printf '%s' "$LO" | grep -q 'surprising="1"'; then
        ok "cochange positive control: a genuinely uncoupled dep-capable pair is STILL surprising=\"1\""
    else
        no "cochange positive control LOST: (lone.py, other.py) no longer surprising=\"1\" — the fix suppressed the signal wholesale"
        printf '        %s\n' "$LO"
    fi
fi

# ══ 4. DEGRADE — a pathological container nest must not crash, hang, or emit malformed XML ════════════
# Python nests two AST levels per indent (statement + block), so 400 indents is ~800 container levels —
# past any plausible bound. Exceeding it DEGRADES (deeper imports not captured), never fails.
DEEP="$TMP/deep"; mkdir -p "$DEEP"
python3 - "$DEEP/deep.py" <<'PYEOF' 2>/dev/null || printf 'import deep_mod\n' >"$DEEP/deep.py"
import sys
levels = 400
with open( sys.argv[1], "w" ) as fh:
    for i in range( levels ):
        fh.write( "    " * i + "if C%d:\n" % i )
    fh.write( "    " * levels + "import deep_mod\n" )
PYEOF
if "$BIN" "$DEEP" --deps --no-cache >"$TMP/deep.out" 2>"$TMP/deep.err"; then
    ok "400-deep container nest: exits 0 (degrades, does not fail)"
else
    no "400-deep container nest: non-zero exit"; head -3 "$TMP/deep.err"
fi
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/deep.out" 2>/dev/null && ok "400-deep container nest: XML well-formed" || no "400-deep container nest: XML malformed"
else
    skip "400-deep container nest: xmllint absent"
fi

# ══ 5. HYGIENE ═══════════════════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --deps --no-cache --limit=500 >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --deps --no-cache --limit=500 >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic (two --no-cache runs identical)" || no "non-deterministic"

"$BIN" "$FIX" --deps --limit=500 --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --limit=500 --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" && ok "warm == cold (nested imports survive the extraction cache)" || { no "warm != cold"; diff "$TMP/cold" "$TMP/warm" | head -4; }
cmp -s "$TMP/cold" "$TMP/d1"   && ok "cached run == --no-cache run" || no "cached run differs from --no-cache run"

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    skip "xml well-formedness (xmllint absent)"
fi

# ══ 6. MONOTONICITY on a real corpus — the descent is PURELY ADDITIVE ════════════════════════════════
# Same invariants and the same shared HEAD-binary cache as test/preproccondcheck.sh: an import captured
# before must still be captured, and `surprising="1"` may only ever be SUPPRESSED (StaticIncludeCoupling
# is monotone in the import set). Both binaries run over the SAME input, so the extractor is the only
# variable. This repo's own src/ is C++, so the *interesting* corpus for these two languages is the
# fixture tree — but the src/ sweep is what catches a container list that accidentally widened C++.
monotonicity_check()
{
    command -v git   >/dev/null 2>&1 || { skip "monotonicity: git absent";   return; }
    command -v cmake >/dev/null 2>&1 || { skip "monotonicity: cmake absent"; return; }
    ( cd "$ROOT" && git rev-parse --verify HEAD >/dev/null 2>&1 ) || { skip "monotonicity: not a git repo"; return; }
    . "$ROOT/test/lib/headbinlib.sh"

    local WT="$TMP/head"
    ( cd "$ROOT" && git worktree add -q --detach "$WT" HEAD ) 2>"$TMP/wt.err" \
        || { skip "monotonicity: cannot create HEAD worktree ($( head -1 "$TMP/wt.err" ))"; return; }
    trap '( cd "$ROOT" && git worktree remove --force "'"$WT"'" >/dev/null 2>&1 ); rm -rf "$TMP"' EXIT

    local OLDBIN
    OLDBIN="$( ripwire_head_binary "$ROOT" "$TMP" )" || { skip "monotonicity: pre-change build failed"; return; }

    local IN="$WT/src"
    # (a) captured includes — compare the PER-FILE COUNT, never the emitted <inc> rows. serialize.h caps
    #     a file's <inc> children at 40 and discloses the rest as `+more`, so a file that GAINS imports
    #     pushes later ones out of the listing: an <inc>-row diff would read that display truncation as a
    #     lost capture and this arm would red on a correct change. `includes=` in the <f> header is the raw
    #     uncapped statement count (serialize.h says so explicitly), which is the number that must not drop.
    inccounts(){ "$1" "$IN" --deps --no-cache --limit=5000 2>/dev/null | tr '>' '\n' \
                     | grep -oE '<f p="[^"]*" includes="[0-9]+"' | sed -E 's/<f p="([^"]*)" includes="([0-9]+)"/\1 \2/' | sort; }
    inccounts "$OLDBIN" >"$TMP/inc.old"
    inccounts "$BIN"    >"$TMP/inc.new"
    if [ ! -s "$TMP/inc.old" ]; then
        skip "monotonicity(a): pre-change binary captured no includes on $IN — cannot compare"
    else
        local dropped
        dropped="$( join "$TMP/inc.old" "$TMP/inc.new" | awk '$3 < $2 { print $1 " was=" $2 " now=" $3 }' )"
        # a file that had includes before and has NO row at all now is also a loss
        local vanished
        vanished="$( join -v1 "$TMP/inc.old" "$TMP/inc.new" | awk '$2 > 0 { print $1 " was=" $2 " now=<no row>" }' )"
        if [ -z "$dropped" ] && [ -z "$vanished" ]; then
            ok "monotonicity(a): no file's include COUNT dropped on src/ (descent is purely additive)"
        else
            no "monotonicity(a): includes LOST on src/ — the descent traded away earlier captures"
            printf '%s\n%s\n' "$dropped" "$vanished" | grep -v '^$' | head -5
        fi
    fi

    # (b) surprising="1" — the NEW set must be a SUBSET of the OLD set.
    surpset(){ "$1" "$IN" --cochange --pack-top-n=5000 --no-cache 2>/dev/null | tr '>' '\n' | grep 'surprising="1"' | grep -oE 'a="[^"]*" b="[^"]*"' | sort; }
    surpset "$OLDBIN" >"$TMP/surp.old"
    surpset "$BIN"    >"$TMP/surp.new"
    if [ ! -s "$TMP/surp.old" ] && [ ! -s "$TMP/surp.new" ]; then
        skip "monotonicity(b): no surprising= rows on $IN in either binary (needs git history — shallow clone?)"
    elif [ "$( comm -13 "$TMP/surp.old" "$TMP/surp.new" | wc -l | tr -d ' ' )" = "0" ]; then
        ok "monotonicity(b): surprising=\"1\" only ever SUPPRESSED, never added"
    else
        no "monotonicity(b): NEW surprising=\"1\" rows appeared — an import edge was LOST"
        comm -13 "$TMP/surp.old" "$TMP/surp.new" | head -5
    fi
}
monotonicity_check

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
