#!/usr/bin/env bash
# ensembleavailcheck.sh — the LANGUAGE-COVERAGE arm of `--ensemble`'s unavailable/silent contract.
#
# WHAT THIS GATE EXISTS FOR. test/ensemblecheck.sh already proves the git half of that contract: the same
# fixture inside and outside a repository must read fam=4/of=4 and fam=3/of=3 unavail="historical". This gate
# proves the OTHER half, which the wave-2 calibration (docs/EVALS.md §9.6 defect 1) found broken.
#
# Two of the four families are RULE PACKS with a language gate of their own:
#
#   confusion — the atom pack (src/atoms.h) runs ONLY on C/C++/ObjC/CUDA paths. That is a design decision with
#               evidence behind it: atom transfer to other languages is empirically falsified, so the rules are
#               deliberately not run elsewhere. On a pure Rust / Python / Swift / TypeScript corpus the family
#               therefore cannot fire AT ALL — not "found nothing", but "was never applicable".
#   lexical   — the naming pack (src/naminglens.h) skips data and doc languages.
#
# Before the fix this gate was written for, `--ensemble` on a 115-file Rust tree reported unavailable= naming
# only `historical`, and every row counted `confusion` inside its of="3". The verb stated, in its own
# vocabulary, that three families were evaluated and two found nothing, when one of the three could not apply
# to a single file in the corpus. That is precisely the reading the verb's own legend forbids:
#
#     "UNAVAILABLE is never the same as silent: an empty unavailable= means every family was measured, and a
#      family listed there was NOT measured, so its absence from fired= is not evidence of health."
#
# and precisely non-negotiable #3: a zero means "none found", never "none exists".
#
# THE FOUR FIXTURES, and why the set needs all four rather than one:
#
#   RUSTGIT   pure Rust, INSIDE a git repository with 3 commits.
#             The isolating case. History IS minable here, so `historical` is available and the ONLY family
#             that may appear in unavailable= is `confusion`. A gate that tested availability on a non-git
#             Rust tree could not tell the confusion verdict apart from the historical one it already had.
#   CFIX      the same shape in C, inside a git repository, carrying a real atom (a nested ternary).
#             The INVERSE assertion. "confusion is unavailable" is worthless unless the same gate shows the
#             family both available AND firing where it does apply — otherwise a fix that hardcoded every
#             corpus to unavailable would pass.
#   RUSTNOGIT pure Rust, no repository anywhere above it.
#             The BOTH case. Two families unavailable at once is what the pre-fix single-reason slot could not
#             express: one `const char*` keeps whichever wrote last, so one of the two missing measurements
#             would have gone out with an empty reason. of= must drop to 2 and BOTH reasons must be present.
#   MIXED     RUSTGIT plus ONE C file — the MUTATION. Adding a single evaluable file must move `confusion`
#             out of unavailable= and lift of= from 3 to 4. A gate whose verdict does not move when the
#             corpus's language coverage moves is asserting a constant, not a measurement.
#
# Arms:
#   (A) confusion UNAVAILABLE on a git-backed pure-Rust corpus, with a reason, and of= drops to 3
#   (B) every ROW carries unavail= containing confusion — the row must be readable without the root
#   (C) the INVERSE on C: confusion absent from unavailable=, of= is 4, and the family actually FIRES
#   (D) BOTH unavailable at once (non-git Rust): of=2, both names, both reasons
#   (E) lexical stays AVAILABLE on Rust — the audit result, asserted so a later over-broad gate cannot
#       quietly take the naming pack out with the atom pack
#   (F) MUTATION — one added C file flips the confusion verdict and the of= denominator
#   (G) coverage disclosure — cfiles=/cscope=/lscope= are on the root, so the verdict is auditable
#   (H) determinism + well-formedness on every fixture

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "ensembleavailcheck: SKIP — git not on PATH, the isolating arm needs a repository"; exit 0; }
echo "ensembleavailcheck: BIN=$BIN"

# ── the Rust source, hand-derived so its family set is known without reading a run ─────────────────────────
#   compute_the_final_aggregated_result_value_for_each_row( 6 params )
#       structural  6 parameters, and the params bar is 5           -> params=6
#       lexical     10 split tokens, and naming-wordy fires above 5 -> naming-wordy
#       confusion   NOT APPLICABLE — the atom rules do not run on Rust
#   scale_by_two    clean name, trivial body -> no family at all (the control)
mkdir -p "$TMP/src"
cat >"$TMP/src/lib.rs" <<'RS'
pub fn compute_the_final_aggregated_result_value_for_each_row( a: i32, b: i32, c: i32, d: i32, e: i32, f: i32 ) -> i32
{
    let picked = if a != 0 { b } else if c != 0 { d } else { e };
    picked + f
}

pub fn scale_by_two( a: i32 ) -> i32
{
    a * 2
}
RS

# The C twin: the SAME two shapes, plus a real atom so arm (C) can assert the family FIRES and not merely
# that it was available. `( a ? b : ( c ? d : e ) )` is atom-nested-ternary.
cat >"$TMP/src/twin.c" <<'CPP'
int computeTheFinalAggregatedResultValue_forEachRow( int a, int b, int c, int d, int e, int f )
{
    return ( a ? b : ( c ? d : e ) ) + f;
}

int scaleByTwo( int a )
{
    return a * 2;
}
CPP

# ── build the four trees ──────────────────────────────────────────────────────────────────────────────────
mkgit(){   # mkgit <dir> — three commits, so churn is minable and the historical family is AVAILABLE
    local d="$1"
    local g="git -C $d -c user.email=gate@example.invalid -c user.name=gate -c commit.gpgsign=false"
    $g init -q . >/dev/null 2>&1
    $g add -A >/dev/null 2>&1
    $g commit -q -m init >/dev/null 2>&1
    printf '// bump 1\n' >>"$d/$2"; $g commit -q -am bump1 >/dev/null 2>&1
    printf '// bump 2\n' >>"$d/$2"; $g commit -q -am bump2 >/dev/null 2>&1
    [ "$( $g rev-list --count HEAD 2>/dev/null )" = "3" ]
}

RUSTGIT="$TMP/rustgit";   mkdir -p "$RUSTGIT"; cp "$TMP/src/lib.rs"  "$RUSTGIT/"
CFIX="$TMP/cfix";         mkdir -p "$CFIX";    cp "$TMP/src/twin.c"  "$CFIX/"
MIXED="$TMP/mixed";       mkdir -p "$MIXED";   cp "$TMP/src/lib.rs"  "$MIXED/"; cp "$TMP/src/twin.c" "$MIXED/"
if ! mkgit "$RUSTGIT" lib.rs || ! mkgit "$CFIX" twin.c || ! mkgit "$MIXED" lib.rs; then
    echo "ensembleavailcheck: SKIP — could not build a 3-commit git fixture in this environment"
    exit 0
fi

# NON-GIT tree: byte-identical Rust (including the two trailing comments the bumps appended), with no
# repository anywhere above it — mktemp -d is outside the ripwire checkout by construction.
RUSTNOGIT="$TMP/rustnogit"; mkdir -p "$RUSTNOGIT"; cp "$RUSTGIT/lib.rs" "$RUSTNOGIT/"

ensembleOn(){ "$BIN" "$1" --ensemble --no-cache 2>/dev/null; }
rootElem(){ grep -o '<ensemble [^>]*>' "$1" | head -1; }
rootAttr(){ # rootAttr <file> <name> — the value of the FIRST occurrence of name="…" on the root element
    rootElem "$1" | grep -o " $2=\"[^\"]*\"" | head -1 | sed "s/^ $2=\"//; s/\"$//"
}

ensembleOn "$RUSTGIT"   >"$TMP/rustgit.xml"
ensembleOn "$CFIX"      >"$TMP/cfix.xml"
ensembleOn "$RUSTNOGIT" >"$TMP/rustnogit.xml"
ensembleOn "$MIXED"     >"$TMP/mixed.xml"

for f in rustgit cfix rustnogit mixed; do
    if [ ! -s "$TMP/$f.xml" ] || ! grep -q '<ensemble ' "$TMP/$f.xml"; then
        no "(setup) --ensemble produced no report on the $f fixture — the rest of this gate would assert nothing"
        printf '%s\n' "  ---- $f.xml ----"; head -c 400 "$TMP/$f.xml"; printf '\n'
    fi
done
[ "$fail" -eq 0 ] || { echo "ensembleavailcheck: FAIL"; exit 1; }

# ── (A) confusion UNAVAILABLE on a git-backed pure-Rust corpus ────────────────────────────────────────────
unavail="$( rootAttr "$TMP/rustgit.xml" unavailable )"
why="$( rootAttr "$TMP/rustgit.xml" unavailable_why )"
case ",$unavail," in
    *,confusion,*) ok "(A) pure-Rust corpus reports unavailable= containing confusion  [$unavail]" ;;
    *)             no "(A) pure-Rust corpus does NOT report confusion as unavailable — the atom rules cannot run on a single file here, so their silence is not a fact about this code. unavailable=\"$unavail\"" ;;
esac
case ",$unavail," in
    *,historical,*) no "(A) the git-backed Rust fixture reported historical unavailable — the isolating arm needs history MINABLE so the confusion verdict stands alone. unavailable=\"$unavail\"" ;;
    *)              ok "(A) historical stays available on the git-backed fixture, so the confusion verdict is isolated" ;;
esac
case "$why" in
    *confusion*) ok "(A) unavailable_why= names confusion and gives a reason" ;;
    *)           no "(A) unavailable_why= does not name confusion — a family in unavailable= with no reason is half a disclosure. unavailable_why=\"$why\"" ;;
esac

# ── (B) every ROW carries the verdict, so a row is readable without the root ──────────────────────────────
# The report is minified onto ONE line (G4), so `grep -c` would count 1 for any number of rows.
# Every row count below therefore goes through `grep -o … | wc -l`, which counts MATCHES.
rows="$( grep -o '<s ' "$TMP/rustgit.xml" | wc -l | tr -d ' ' )"
if [ "$rows" -lt 1 ]; then
    no "(B) the Rust fixture produced no symbol rows — the 6-parameter function must fire structural"
else
    badOf="$( grep -o '<s [^>]*>' "$TMP/rustgit.xml" | grep -cv 'of="3"' )"
    withConf="$( grep -o '<s [^>]*>' "$TMP/rustgit.xml" | grep -c 'unavail="[^"]*confusion' )"
    if [ "$badOf" -eq 0 ]; then
        ok "(B) all $rows row(s) report of=\"3\" — the denominator drops the family that could not be evaluated"
    else
        no "(B) $badOf of $rows row(s) do not report of=\"3\"; a row that counts confusion in its denominator claims a family was considered when it could not apply"
        grep -o '<s [^>]*>' "$TMP/rustgit.xml" | head -3 | sed 's/^/        /'
    fi
    if [ "$withConf" -eq "$rows" ]; then
        ok "(B) all $rows row(s) carry unavail= naming confusion"
    else
        no "(B) only $withConf of $rows row(s) name confusion in unavail= — the root's verdict must reach the row"
    fi
fi

# ── (C) the INVERSE on C: available, and it actually fires ────────────────────────────────────────────────
cUnavail="$( rootAttr "$TMP/cfix.xml" unavailable )"
case ",$cUnavail," in
    *,confusion,*) no "(C) the C fixture reports confusion UNAVAILABLE — a fix that marks every corpus unavailable is not a fix. unavailable=\"$cUnavail\"" ;;
    *)             ok "(C) the C fixture leaves confusion available  [unavailable=\"$cUnavail\"]" ;;
esac
cOf="$( grep -o '<s [^>]*>' "$TMP/cfix.xml" | grep -cv 'of="4"' )"
if [ "$cOf" -eq 0 ]; then
    ok "(C) every C row reports of=\"4\" — all four families evaluable there"
else
    no "(C) $cOf C row(s) do not report of=\"4\""
    grep -o '<s [^>]*>' "$TMP/cfix.xml" | head -3 | sed 's/^/        /'
fi
if grep -q 'f="confusion" why="[^"]*atom-nested-ternary' "$TMP/cfix.xml"; then
    ok "(C) the confusion family FIRES on the C fixture (atom-nested-ternary) — availability is not vacuous"
else
    no "(C) the confusion family did not fire on a nested ternary in C; 'available' must mean the pack really ran"
    grep -o '<e [^>]*>' "$TMP/cfix.xml" | head -5 | sed 's/^/        /'
fi

# ── (D) BOTH unavailable at once — the case one reason slot cannot express ────────────────────────────────
nUnavail="$( rootAttr "$TMP/rustnogit.xml" unavailable )"
nWhy="$( rootAttr "$TMP/rustnogit.xml" unavailable_why )"
bothOk=1
case ",$nUnavail," in *,confusion,*)  ;; *) bothOk=0 ;; esac
case ",$nUnavail," in *,historical,*) ;; *) bothOk=0 ;; esac
if [ "$bothOk" -eq 1 ]; then
    ok "(D) non-git Rust reports BOTH confusion and historical unavailable  [$nUnavail]"
else
    no "(D) non-git Rust must report BOTH confusion and historical unavailable; got unavailable=\"$nUnavail\""
fi
case "$nWhy" in
    *confusion*historical*|*historical*confusion*) ok "(D) unavailable_why= carries BOTH reasons, not just the last one written" ;;
    *) no "(D) unavailable_why= carries only one family's reason — two missing measurements need two reasons. unavailable_why=\"$nWhy\"" ;;
esac
nOf="$( grep -o '<s [^>]*>' "$TMP/rustnogit.xml" | grep -cv 'of="2"' )"
nRows="$( grep -o '<s ' "$TMP/rustnogit.xml" | wc -l | tr -d ' ' )"
if [ "$nRows" -ge 1 ] && [ "$nOf" -eq 0 ]; then
    ok "(D) all $nRows non-git Rust row(s) report of=\"2\" — two families evaluable, and the row says so"
else
    no "(D) non-git Rust rows must report of=\"2\" ($nOf of $nRows do not)"
    grep -o '<s [^>]*>' "$TMP/rustnogit.xml" | head -3 | sed 's/^/        /'
fi

# ── (E) lexical stays AVAILABLE on Rust ───────────────────────────────────────────────────────────────────
case ",$unavail," in
    *,lexical,*) no "(E) the Rust fixture reports lexical UNAVAILABLE — the naming pack reads Rust, and an over-broad coverage rule that takes it out with the atom pack is a new lie in the same place" ;;
    *)           ok "(E) lexical stays available on Rust" ;;
esac
if grep -q 'f="lexical" why="[^"]*naming-' "$TMP/rustgit.xml"; then
    ok "(E) the lexical family FIRES on the Rust fixture"
else
    no "(E) the lexical family did not fire on a 10-token Rust name; arm (E) would be vacuous"
    grep -o '<e [^>]*>' "$TMP/rustgit.xml" | head -5 | sed 's/^/        /'
fi

# ── (F) MUTATION: one added C file moves the verdict and the denominator ──────────────────────────────────
mUnavail="$( rootAttr "$TMP/mixed.xml" unavailable )"
case ",$mUnavail," in
    *,confusion,*) no "(F) adding ONE C file to the Rust corpus did not move confusion out of unavailable= — a verdict that does not track the corpus's language coverage is a constant, not a measurement. unavailable=\"$mUnavail\"" ;;
    *)             ok "(F) adding one C file makes confusion available again  [unavailable=\"$mUnavail\"]" ;;
esac
mOf="$( grep -o '<s [^>]*>' "$TMP/mixed.xml" | grep -cv 'of="4"' )"
if [ "$mOf" -eq 0 ]; then
    ok "(F) the mixed corpus lifts every row's of= back to 4"
else
    no "(F) $mOf mixed-corpus row(s) do not report of=\"4\" after the language coverage widened"
fi

# ── (G) coverage disclosure — the verdict must be auditable from the output ───────────────────────────────
for pair in "rustgit:0" "mixed:1"; do
    f="${pair%%:*}"; want="${pair##*:}"
    got="$( rootAttr "$TMP/$f.xml" cfiles )"
    if [ "$got" = "$want" ]; then
        ok "(G) $f discloses cfiles=\"$got\" — the reader can check the availability decision"
    else
        no "(G) $f should disclose cfiles=\"$want\" (indexed files the atom pack can read); got \"$got\""
    fi
done
rscope="$( rootAttr "$TMP/rustgit.xml" cscope )"
lscope="$( rootAttr "$TMP/rustgit.xml" lscope )"
if [ "$rscope" = "0" ]; then
    ok "(G) the Rust corpus discloses cscope=\"0\" — no eligible symbol is in the atom pack's reach"
else
    no "(G) the Rust corpus should disclose cscope=\"0\"; got \"$rscope\""
fi
if [ "$lscope" = "2" ]; then
    ok "(G) the Rust corpus discloses lscope=\"2\" — both eligible symbols are in the naming pack's reach"
else
    no "(G) the Rust corpus should disclose lscope=\"2\" (both eligible Rust fns); got \"$lscope\""
fi

# ── (H) determinism + well-formedness ─────────────────────────────────────────────────────────────────────
for pair in "rustgit:$RUSTGIT" "cfix:$CFIX" "rustnogit:$RUSTNOGIT" "mixed:$MIXED"; do
    f="${pair%%:*}"; d="${pair#*:}"
    ensembleOn "$d" >"$TMP/$f.again"
    if cmp -s "$TMP/$f.xml" "$TMP/$f.again"; then
        ok "(H) $f is byte-identical across two --no-cache runs"
    else
        no "(H) $f is not deterministic across two identical runs"
    fi
    if command -v xmllint >/dev/null 2>&1; then
        if xmllint --noout "$TMP/$f.xml" 2>"$TMP/$f.lint"; then
            ok "(H) $f parses as XML"
        else
            no "(H) $f emitted a document xmllint rejects"
            sed 's/^/        /' "$TMP/$f.lint"
        fi
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "ensembleavailcheck: PASS"
    exit 0
fi
echo "ensembleavailcheck: FAIL"
exit 1
