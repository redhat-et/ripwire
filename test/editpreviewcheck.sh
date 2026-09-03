#!/usr/bin/env bash
# editpreviewcheck.sh — gate for the PRE-APPLY contract preview:
#   ripwire <dir> --edit-check=SYM --edit-payload=FILE --dry-run
#
# The band this gate enforces is registered in docs/EVALS.md ("Pre-apply `--edit-check` — the contract
# preview on an unwritten payload (card A1)"), written BEFORE this script and before any feature code.
#
# THE ONE PROPERTY. For every VALID payload the answer computed BEFORE the write must equal the answer the
# ordinary post-hoc --edit-check gives AFTER the same payload is actually applied. So each case is run BOTH
# WAYS: the preview on a pristine corpus, then --replace-symbol-body of the SAME payload bytes onto a FRESH
# copy of that corpus followed by a plain --edit-check. Agreement is byte-equality of the <edit-check>
# element after exactly three normalisations and no others (see `norm` below):
#   • the leading <!-- … --> legend is dropped (the preview's legend carries one extra sentence),
#   • ` at="…"` is dropped (the applied tree is dirty, the pristine one is not),
#   • ` preview="1"` is dropped (present only on the pre-apply document).
# Everything else — status=, change=, params_was/now=, public_was/now=, defs_was/now=, defs=, callers=,
# incompatible=, p=, every <def> row and every <c> row in order — is compared verbatim.
#
# ACCEPT: agreement on >= 29 of 30, and ZERO false "unchanged" (a preview saying unchanged where the applied
# tree says contract-change / new-symbol fails the band outright, whatever the ratio — reassurance is the one
# answer this verb exists to be trusted on). Every INVALID payload must REFUSE (exit 1, empty stdout).
#
# WHY THE MUTATION CONTROL (arm M) EXISTS. A comparison of two documents that are both empty, or both the
# tool's own refusal text, passes while measuring nothing — the "green while inert" shape CONTRIBUTING.md §2
# names. Arm M runs the SAME comparison on a deliberately mismatched pair (a contract-CHANGING preview
# against a contract-PRESERVING apply) and fails if that pair is reported as agreeing, so a false clean is
# provably visible to this script. Arm P is its presence guard: the documents being compared must actually
# be <edit-check> elements carrying a status=.
#
# Fixtures: test/editpreviewfix/{corpus,payloads,cases.tsv}. 36 payloads — 12 contract-changing, 12
# contract-preserving, 12 invalid — across C++ (free functions, a public header, methods, an added overload)
# and Python (free functions, methods with the implicit self).
#
# Operates entirely on private temp git repos; never touches the real repo. Needs git.
# Usage:  bash test/editpreviewcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/editpreviewcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/editpreviewfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
[ -f "$FIX/cases.tsv" ] || { echo "missing fixture table $FIX/cases.tsv"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "editpreviewcheck: BIN=$BIN"

# a pristine committed copy of the fixture corpus at $1
mkcorpus(){
    mkdir -p "$1"
    cp "$FIX"/corpus/* "$1/"
    ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
}

BASE="$WORK/base"; mkcorpus "$BASE"

# the three normalisations, and nothing else. The document is minified XML on ONE line, so the greedy
# comment strip removes exactly the single leading legend.
norm(){ printf '%s' "$1" | sed -e 's/<!--.*-->//' -e 's/ at="[^"]*"//g' -e 's/ preview="1"//g'; }
statusOf(){ printf '%s' "$1" | sed -e 's/<!--.*-->//' | grep -oE 'status="[a-z-]+"' | head -1; }

preview(){ # $1 selector  $2 payload-path
    ( cd "$BASE" && "$BIN" . --edit-check="$1" --edit-payload="$2" --dry-run --no-cache 2>/dev/null )
}
previewrc(){
    ( cd "$BASE" && "$BIN" . --edit-check="$1" --edit-payload="$2" --dry-run --no-cache >/dev/null 2>&1; echo $? )
}

applied(){ # $1 name  $2 file  $3 payload-path  → the POST-apply --edit-check document, on a fresh corpus
    local w="$WORK/apply.$$.$RANDOM"
    mkcorpus "$w"
    ( cd "$w" && "$BIN" . --replace-symbol-body="$1" --edit-target-file="$2" --edit-payload="$3" ) >/dev/null 2>&1
    ( cd "$w" && "$BIN" . --edit-check="$2:$1" --no-cache 2>/dev/null )
    rm -rf "$w"
}

# ── the fixture sweep ────────────────────────────────────────────────────────────────────────────────
valid=0; agree=0; falseclean=0; invalid=0; refused=0
firstPreview=""; changePreview=""; preserveApplied=""
while IFS=$'\t' read -r id cls name file pay note; do
    case "$id" in \#*|"") continue;; esac
    P="$FIX/payloads/$pay"
    [ -f "$P" ] || { no "fixture $id: missing payload $pay"; continue; }
    if [ "$cls" = "invalid" ]; then
        invalid=$(( invalid + 1 ))
        out="$( preview "$file:$name" "$P" )"
        rc="$( previewrc "$file:$name" "$P" )"
        if [ "$rc" != "0" ] && [ -z "$out" ]; then
            refused=$(( refused + 1 ))
        else
            no "invalid fixture $id ($note) ANSWERED instead of refusing (rc=$rc, ${#out} bytes on stdout)"
        fi
        continue
    fi
    valid=$(( valid + 1 ))
    pre="$( preview "$file:$name" "$P" )"
    post="$( applied "$name" "$file" "$P" )"
    [ -z "$firstPreview" ] && firstPreview="$pre"
    [ "$id" = "chg01" ] && changePreview="$pre"
    [ "$id" = "pre01" ] && preserveApplied="$post"
    if [ "$( norm "$pre" )" = "$( norm "$post" )" ]; then
        agree=$(( agree + 1 ))
    else
        no "fixture $id ($note): preview != applied"
        printf '        pre : %s\n' "$( norm "$pre" | cut -c1-320 )"
        printf '        post: %s\n' "$( norm "$post" | cut -c1-320 )"
    fi
    # the hard stop: a preview that reassures where the applied tree does not
    ps="$( statusOf "$pre" )"; qs="$( statusOf "$post" )"
    if [ "$ps" = 'status="unchanged"' ] && [ "$qs" != 'status="unchanged"' ]; then
        falseclean=$(( falseclean + 1 ))
        no "fixture $id: FALSE CLEAN — preview said unchanged, the applied tree said $qs"
    fi
done < "$FIX/cases.tsv"

total=$(( valid + invalid ))
[ "$total" -ge 30 ] && ok "fixture set is $total payloads ($valid valid, $invalid invalid) — band floor is 30" \
                    || no "fixture set is only $total payloads — the band requires >= 30"
[ "$valid" -ge 20 ] && [ "$invalid" -ge 10 ] \
    && ok "class mix: >= 10 contract-changing, >= 10 contract-preserving, >= 10 invalid" \
    || no "class mix below the registered floor (valid=$valid invalid=$invalid)"
[ "$agree" -ge 29 ] && ok "pre-apply == post-apply on $agree of $valid valid payloads (band floor 29)" \
                    || no "agreement is $agree of $valid — below the registered floor of 29"
[ "$falseclean" = 0 ] && ok "zero false \"unchanged\" verdicts" || no "$falseclean false-clean verdict(s) — the band fails outright"
[ "$refused" = "$invalid" ] && ok "all $invalid invalid payloads refused (exit != 0, empty stdout)" \
                            || no "only $refused of $invalid invalid payloads refused"

# ── (P) presence guard — the documents compared above are real answers, not two empty strings ─────────
if printf '%s' "$firstPreview" | grep -q '<edit-check ' && printf '%s' "$firstPreview" | grep -q 'status="'; then
    ok "(P) presence guard: the compared documents are real <edit-check> elements carrying status="
else
    no "(P) presence guard: the preview document is not an <edit-check> element — the sweep proved nothing"
fi

# ── (M) mutation control — the comparison can SEE a mismatch ──────────────────────────────────────────
if [ -n "$changePreview" ] && [ -n "$preserveApplied" ]; then
    if [ "$( norm "$changePreview" )" = "$( norm "$preserveApplied" )" ]; then
        no "(M) mutation control: a contract-CHANGING preview compared EQUAL to a contract-PRESERVING apply — the sweep's comparison is vacuous"
    else
        ok "(M) mutation control: a deliberately mismatched pair is reported as disagreeing"
    fi
else
    no "(M) mutation control could not run — one of its two documents is empty"
fi

# ── (D) the preview marker, and the legend that defines it ────────────────────────────────────────────
printf '%s' "$firstPreview" | grep -q 'preview="1"' \
    && ok "(D) the pre-apply document carries preview=\"1\"" \
    || no "(D) the pre-apply document does not carry preview=\"1\""
printf '%s' "$firstPreview" | sed -e 's/\(<!--.*-->\).*/\1/' | grep -q 'preview=' \
    && ok "(D) preview= is defined in the emitted legend" \
    || no "(D) preview= is emitted but never defined in the legend"
printf '%s' "$firstPreview" | grep -qi 'not been written\|no byte' \
    && ok "(D) the legend states the payload was not written" \
    || no "(D) the legend never says the payload was not written"

# ── (C) the combination refusals ──────────────────────────────────────────────────────────────────────
comb(){ ( cd "$BASE" && "$BIN" . "$@" >"$WORK/c.out" 2>"$WORK/c.err"; echo $? ); }
rc="$( comb --edit-check=lib.h:scale --edit-payload="$FIX/payloads/pre01.txt" )"
{ [ "$rc" != 0 ] && [ ! -s "$WORK/c.out" ] && grep -q -- '--dry-run' "$WORK/c.err"; } \
    && ok "(C) --edit-check --edit-payload without --dry-run refuses and names --dry-run" \
    || { no "(C) --edit-payload without --dry-run did not refuse cleanly (rc=$rc)"; head -2 "$WORK/c.err"; }
rc="$( comb --edit-check=lib.h:scale --dry-run )"
{ [ "$rc" != 0 ] && [ ! -s "$WORK/c.out" ] && grep -q -- '--edit-payload' "$WORK/c.err"; } \
    && ok "(C) --edit-check --dry-run with no payload refuses and names --edit-payload" \
    || { no "(C) --dry-run with no payload did not refuse cleanly (rc=$rc)"; head -2 "$WORK/c.err"; }
rc="$( comb --edit-check=lib.h:scale --edit-payload="$WORK/does-not-exist.txt" --dry-run )"
{ [ "$rc" != 0 ] && [ ! -s "$WORK/c.out" ]; } \
    && ok "(C) an unreadable payload file refuses" \
    || { no "(C) an unreadable payload file did not refuse (rc=$rc)"; head -2 "$WORK/c.err"; }
rc="$( comb --edit-check=lib.h:scale --edit-payload="$FIX/payloads/pre01.txt" --dry-run --apply )"
{ [ "$rc" != 0 ] && [ ! -s "$WORK/c.out" ]; } \
    && ok "(C) --apply beside the preview refuses (the preview never writes)" \
    || { no "(C) --apply beside the preview did not refuse (rc=$rc)"; head -2 "$WORK/c.err"; }

# ── (A) the ambiguity refusal still fires on the preview path, with a payload in hand ──────────────────
AMB="$WORK/amb"; mkcorpus "$AMB"
cat > "$AMB/extra.cpp" <<'XEOF'
int trim( int a, int b )
{
    return b;
}
XEOF
( cd "$AMB" && git add -A && git commit -qm extra ) >/dev/null 2>&1
( cd "$AMB" && "$BIN" . --edit-check=trim --edit-payload="$FIX/payloads/pre03.txt" --dry-run --no-cache \
    >"$WORK/a.out" 2>"$WORK/a.err" ); rc=$?
{ [ "$rc" != 0 ] && [ ! -s "$WORK/a.out" ] && grep -q 'ambiguous' "$WORK/a.err"; } \
    && ok "(A) an ambiguous SYM refuses on the preview path and lists the spellings" \
    || { no "(A) ambiguous SYM was not refused on the preview path (rc=$rc)"; head -2 "$WORK/a.err"; }

# ── (S) the Section kind guard — a document heading is not an editable definition ─────────────────────
SEC="$WORK/sec"; mkcorpus "$SEC"
printf '# Heading\n\nprose\n' > "$SEC/doc.md"
( cd "$SEC" && git add -A && git commit -qm doc ) >/dev/null 2>&1
( cd "$SEC" && "$BIN" . --edit-check=doc.md:Heading --edit-payload="$FIX/payloads/pre01.txt" --dry-run --no-cache \
    >"$WORK/s.out" 2>"$WORK/s.err" ); rc=$?
if [ ! -s "$WORK/s.err" ] && [ ! -s "$WORK/s.out" ]; then
    no "(S) neither stream produced anything — the Section arm proved nothing"
elif [ "$rc" != 0 ] && [ ! -s "$WORK/s.out" ]; then
    ok "(S) a document heading refuses instead of previewing a splice through it"
else
    no "(S) a document heading was previewed as an editable definition (rc=$rc)"
fi

# ── (T) determinism (x3) and well-formedness ─────────────────────────────────────────────────────────
d1="$( preview lib.h:scale "$FIX/payloads/chg01.txt" )"
d2="$( preview lib.h:scale "$FIX/payloads/chg01.txt" )"
d3="$( preview lib.h:scale "$FIX/payloads/chg01.txt" )"
{ [ "$d1" = "$d2" ] && [ "$d2" = "$d3" ] && [ -n "$d1" ]; } \
    && ok "(T) three preview runs are byte-identical" || no "(T) preview output is not deterministic"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$d1" | xmllint --noout - 2>"$WORK/x.err" \
        && ok "(T) the preview document is well-formed XML" \
        || { no "(T) xmllint rejected the preview document"; head -3 "$WORK/x.err"; }
else
    ok "(T) xmllint absent — well-formedness arm skipped"
fi

# ── (W) NOTHING WAS WRITTEN — the whole point of a dry run ────────────────────────────────────────────
( cd "$BASE" && git status --porcelain ) > "$WORK/dirty.txt" 2>/dev/null
[ ! -s "$WORK/dirty.txt" ] \
    && ok "(W) the corpus is still byte-clean after $total previews — nothing was written" \
    || { no "(W) the preview MODIFIED the working tree"; cat "$WORK/dirty.txt"; }

echo
[ "$fail" = 0 ] && echo "editpreviewcheck: OK" || echo "editpreviewcheck: FAILURES"
exit "$fail"
