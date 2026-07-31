#!/usr/bin/env bash
# prnestedcapcheck.sh — §B3 gate (PLAN_outputAudit3_2026-07-29.md): --pr-context silently capped every
# nested list at the L0 default (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12,
# tests <test> at 40, owners <author> at 5) with NO shown=/capped= disclosure on any of them, while the
# legend and a source comment (prcontext.h:717-718, pre-fix) both claimed the row count was "exactly
# disclosed". Observed live on the real showcase capture: files_other="38" over 20 <f> rows, callers="66"
# over 12 <caller> rows, partners="59" over 12 <partner> rows.
#
# Fix (this round): every capped nested list gets the house shown=/capped= pair (pageview.h, THE
# TRUNCATION VOCABULARY — the same convention --seams' <seam untested= shown= capped=> already uses), the
# legend states the fixed caps + the max-tokens-only-lowers-never-raises truth + the untrimmed-list escape
# hatches, and the false prcontext.h:717-718 comment is corrected. Numbers (files_other=/callers=/
# partners=/count=/authors=) are UNCHANGED — only shown=/capped= are new attributes.
#
# This gate builds a deterministic synthetic git repo where one changed symbol (hub, in src/base.cpp) has
# 25 direct callers across 25 files (> the 20/12 caps) and 15 co-change partners with >=3 shared commits
# each (> the 12 cochange cap), so --pr-context's default (L0, no --max-tokens) run trips BOTH the
# <impact>/<f> cap and the per-symbol <caller> cap and the <cochange>/<partner> cap in one call. For each
# nested list found in the output it asserts: shown= equals the actual printed row count, the listing's own
# total attribute >= shown, capped= is "1" iff total>shown else "0", and the legend names the fixed caps.
#
# Usage:  bash test/prnestedcapcheck.sh [path/to/ripwire]
#         RIPWIRE_BIN=build_base/ripwire bash test/prnestedcapcheck.sh   # red-first: must FAIL (no disclosure)
# Exits non-zero on any failure. Does NOT edit regression.sh (test/pargates.py auto-discovers *check.sh).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # house convention: the suite passes the binary via RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "prnestedcapcheck: BIN=$BIN"
[ -x "$BIN" ] || { no "binary not executable: $BIN"; echo "FAILURES ABOVE"; exit 1; }
command -v python3 >/dev/null 2>&1 || { no "python3 is REQUIRED (nested-element row/attr extraction) — not found"; echo "FAILURES ABOVE"; exit 1; }
command -v git     >/dev/null 2>&1 || { no "git is REQUIRED (the fixture is a synthetic repo) — not found"; echo "FAILURES ABOVE"; exit 1; }

# ── build the fixture: hub() in src/base.cpp, called by 25 callerNN(), co-changed with 15 partNN.cpp ────
REPO="$TMP/repo"
mkdir -p "$REPO/src"
( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t ) \
    || { no "git init failed in fixture repo"; echo "FAILURES ABOVE"; exit 1; }

printf 'int hub() { return 1; }\n' > "$REPO/src/base.cpp"
for i in $( seq -w 1 25 ); do
    printf 'extern int hub();\nint caller%s() { return hub(); }\n' "$i" > "$REPO/src/caller$i.cpp"
done
for i in $( seq -w 1 15 ); do
    printf '// part note %s v0\n' "$i" > "$REPO/src/part$i.cpp"
done
( cd "$REPO" && git add -A >/dev/null && git commit -qm init >/dev/null ) \
    || { no "fixture init commit failed"; echo "FAILURES ABOVE"; exit 1; }

# 3 more commits touching base.cpp + all 15 partner files together ⇒ each partner gets together>=3 (kSupport)
for c in 1 2 3; do
    printf '// touch %s\n' "$c" >> "$REPO/src/base.cpp"
    for i in $( seq -w 1 15 ); do printf '// part note %s v%s\n' "$i" "$c" >> "$REPO/src/part$i.cpp"; done
    ( cd "$REPO" && git add -A >/dev/null && git commit -qm "touch$c" >/dev/null ) \
        || { no "fixture touch$c commit failed"; echo "FAILURES ABOVE"; exit 1; }
done
# final UNCOMMITTED edit to base.cpp only — this is the diff --pr-context (default, working-tree) reviews;
# the 25 callers and 15 partners are deliberately left untouched (they must stay OUT of the diff).
printf '// final uncommitted edit\n' >> "$REPO/src/base.cpp"

OUT="$TMP/out.xml"
"$BIN" "$REPO" --pr-context --no-cache >"$OUT" 2>"$TMP/err.txt"
RC=$?
[ "$RC" = 0 ] || { no "--pr-context exited $RC: $( cat "$TMP/err.txt" )"; echo "FAILURES ABOVE"; exit 1; }
[ -s "$OUT" ]  || { no "--pr-context produced empty output"; echo "FAILURES ABOVE"; exit 1; }

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$OUT" 2>"$TMP/lint.err" && ok "output is well-formed XML" \
        || no "output is malformed XML: $( cat "$TMP/lint.err" )"
else
    no "xmllint is REQUIRED (G4 well-formedness) — not found"
fi

# ── the per-list disclosure check, run once per (element-regex, total-attr-name, child-tag) triple ──────
python3 - "$OUT" > "$TMP/verdict.txt" <<'PY'
import re, sys

xml = open(sys.argv[1]).read()

def check(label, elem_open_re, total_attr, child_tag, elem_close, min_expected_total=None):
    m = re.search(elem_open_re, xml)
    if not m:
        print(f"FAIL  {label}: element not found (regex {elem_open_re!r})")
        return
    open_tag = m.group(0)
    start = m.end()
    if elem_close:
        end = xml.find(elem_close, start)
        if end == -1:
            print(f"FAIL  {label}: opening tag has children but no matching {elem_close!r} found")
            return
        body = xml[start:end]
    else:
        body = ""   # self-closed — no children possible

    total_m = re.search(total_attr + r'="(\d+)"', open_tag)
    shown_m = re.search(r'shown="(\d+)"', open_tag)
    capped_m = re.search(r'capped="(\d+)"', open_tag)
    if not total_m:
        print(f"FAIL  {label}: no {total_attr}= attribute on {open_tag[:80]}")
        return
    if not shown_m:
        print(f"FAIL  {label}: no shown= attribute on {open_tag[:80]} (the §B3 defect — undisclosed cap)")
        return
    if not capped_m:
        print(f"FAIL  {label}: no capped= attribute on {open_tag[:80]} (the §B3 defect — undisclosed cap)")
        return

    total = int(total_m.group(1))
    shown = int(shown_m.group(1))
    capped = capped_m.group(1)
    actual_rows = len(re.findall(r'<' + re.escape(child_tag) + r'[ />]', body))

    if min_expected_total is not None and total < min_expected_total:
        print(f"FAIL  {label}: fixture did not exceed the cap as designed ({total_attr}={total} < {min_expected_total})")
        return
    if shown != actual_rows:
        print(f"FAIL  {label}: shown={shown} but {actual_rows} <{child_tag}> rows actually printed")
        return
    if total < shown:
        print(f"FAIL  {label}: {total_attr}={total} < shown={shown} (total must be >= shown)")
        return
    expect_capped = "1" if total > shown else "0"
    if capped != expect_capped:
        print(f"FAIL  {label}: capped={capped} but total={total} shown={shown} implies capped={expect_capped}")
        return
    print(f"PASS  {label}: total={total} shown={shown} capped={capped} rows={actual_rows} (consistent)")

# <impact ...>...</impact> — files_other= is the total, <f> are the rows; fixture drives it to 25 > cap 20.
check("impact/<f>", r'<impact [^>]*files_other="25"[^>]*>', "files_other", "f", "</impact>", min_expected_total=21)

# per-symbol <s n="hub" ...>...</s> — callers= is the total, <caller> are the rows; fixture drives it to 25 > cap 12.
check("caller/<caller>", r'<s [^>]*n="hub"[^>]*>', "callers", "caller", "</s>", min_expected_total=13)

# <cochange ...>...</cochange> — partners= is the total, <partner> are the rows; fixture drives it to 15 > cap 12.
check("cochange/<partner>", r'<cochange [^>]*>', "partners", "partner", "</cochange>", min_expected_total=13)

# <tests ...> — not driven over its cap by this fixture (no test-path files in the blast radius), but must
# still carry a self-consistent shown=/capped= pair (the uncapped, shown==total==0 case).
check("tests/<test>", r'<tests [^>]*>', "count", "test", "</tests>")

# <owners ...> — one real author (the fixture's single git identity), also the uncapped case.
check("owners/<author>", r'<owners [^>]*authors="1"[^>]*>', "authors", "author", "</owners>")
PY

while IFS= read -r line; do
    case "$line" in
        PASS*) ok "${line#PASS  }" ;;
        FAIL*) no "${line#FAIL  }" ;;
        *)     [ -n "$line" ] && no "unexpected verdict line: $line" ;;
    esac
done < "$TMP/verdict.txt"
[ -s "$TMP/verdict.txt" ] || no "python3 verdict pass produced no output at all"

# ── the legend names the fixed caps (not just the shown=/capped= mechanics) ──────────────────────────────
LEGEND="$( grep -o '<!--.*-->' "$OUT" | head -1 )"
for needle in 'impact <f> at 20' 'per-symbol <caller> at 12' 'cochange <partner> at 12' 'tests <test> at 40' 'owners <author> at 5' 'shown=/capped=' 'max-tokens'; do
    printf '%s' "$LEGEND" | grep -qF -- "$needle" \
        && ok "legend names \"$needle\"" \
        || no "legend does not name \"$needle\" — cap disclosure without a legend clause is still opaque"
done

# ── raise mechanism is stated HONESTLY: max-tokens only lowers the caps further, nothing raises them ─────
printf '%s' "$LEGEND" | grep -qF 'nothing raises them past L0' \
    && ok "legend states there is no raise mechanism past L0 (honest — max-tokens only lowers)" \
    || no "legend does not say max-tokens cannot raise the caps"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
