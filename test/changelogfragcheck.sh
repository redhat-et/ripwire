#!/usr/bin/env bash
# changelogfragcheck.sh — changelog entries are one file per change under changelog.d/, and the release fold is
# deterministic.
#
# WHY. Every merge to main used to make every open PR CONFLICTING on CHANGELOG.md's [Unreleased] hunk (2026-10-21:
# three PRs re-merged by hand in one day), because each PR appended to the same lines. A change now adds one new file
# under changelog.d/; scripts/changelog_assemble.py folds the files under a dated heading at release. This gate keeps
# the three halves of that true:
#   (A) THE TREE: every fragment in changelog.d/ is well formed and CHANGELOG.md's [Unreleased] is the stub only —
#       a PR that still writes its entry there fails here with a message naming the fragment to write instead.
#   (B) GOLDEN: folding test/changelogfragfix/tree under 1.1.0 reproduces test/changelogfragfix/golden.md byte for byte,
#       deletes the folded fragments (README.md stays), and a second fold of a fresh copy is identical.
#   (C) CAN-GO-RED, drift: a fixture whose fragment text moved after the golden was written assembles to a DIFFERENT
#       file, and the comparison reports it.
#   (D) CAN-GO-RED, format: each malformed fragment shape is refused by `check` with its own message, and `release`
#       refuses the tree without touching CHANGELOG.md.
#   (E) NEAR-MISS negatives pass: the shapes a too-strict rule would refuse (credit in either house order, `(thanks
#       @h)` under a heading that names the PR, a `#### ` sub-heading, a Windows drive path in prose).
# Pure source text: it does not build or run the ripwire binary. Every arm works on temp copies, never in this tree.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
ASM="$ROOT/scripts/changelog_assemble.py"
FIX="$ROOT/test/changelogfragfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "changelogfragcheck: assembler=$ASM (no ripwire binary: pure source text)"

command -v python3 >/dev/null 2>&1 || { no "python3 is required by changelogfragcheck"; echo "FAILURES ABOVE"; exit 1; }
[ -f "$ASM" ] || { no "scripts/changelog_assemble.py is missing"; echo "FAILURES ABOVE"; exit 1; }
[ -f "$FIX/golden.md" ] && [ -d "$FIX/tree/changelog.d" ] || { no "fixture test/changelogfragfix is missing"; echo "FAILURES ABOVE"; exit 1; }
TMP="$( mktemp -d "${TMPDIR:-/tmp}/changelogfragcheck.XXXXXX" )" || { no "mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

freshTree(){  # freshTree <dir>: a copy of the fixture tree
    rm -rf "$1"; mkdir -p "$1" && cp -R "$FIX/tree/." "$1/"
}

# ── (A) the real tree ─────────────────────────────────────────────────────────────────────────────────────────
if out="$( python3 "$ASM" check "$ROOT" 2>&1 )"; then
    ok "(A) real tree: $out"
else
    no "(A) real tree: changelog.d/ or CHANGELOG.md [Unreleased] is malformed:"
    printf '%s\n' "$out" | sed 's/^/          /'
fi
if python3 "$ASM" print "$ROOT" >"$TMP/print.md" 2>"$TMP/print.err"; then
    n="$( ls "$ROOT/changelog.d" | grep -vx README.md | wc -l | tr -d ' ' )"
    h="$( grep -c '^### ' "$TMP/print.md" )"
    [ "$n" = "$h" ] && ok "(A) print: the assembled [Unreleased] carries one entry per fragment ($h)" \
                    || no "(A) print: $n fragment(s) but $h entry heading(s) assembled"
else
    no "(A) print failed: $( head -3 "$TMP/print.err" )"
fi

# ── (B) golden ────────────────────────────────────────────────────────────────────────────────────────────────
for run in 1 2; do
    freshTree "$TMP/g$run"
    python3 "$ASM" release 1.1.0 2030-02-02 "$TMP/g$run" >/dev/null 2>"$TMP/g$run.err" \
        || no "(B) run $run: release refused the fixture: $( head -3 "$TMP/g$run.err" )"
done
if cmp -s "$TMP/g1/CHANGELOG.md" "$FIX/golden.md"; then
    ok "(B) golden: the fold of test/changelogfragfix/tree under 1.1.0 is golden.md byte for byte"
else
    no "(B) golden: the fold differs from golden.md:"; diff "$FIX/golden.md" "$TMP/g1/CHANGELOG.md" | head -20 | sed 's/^/          /'
fi
cmp -s "$TMP/g1/CHANGELOG.md" "$TMP/g2/CHANGELOG.md" && ok "(B) determinism: two folds of fresh copies are identical" \
                                                       || no "(B) determinism: two folds of the same tree differ"
left="$( ls "$TMP/g1/changelog.d" | tr '\n' ' ' )"
[ "$left" = "README.md " ] && ok "(B) the fold deleted every fragment and kept changelog.d/README.md" \
                           || no "(B) after the fold changelog.d/ holds: $left"
# Order is byte order of the names (12-alpha before 3-beta before zeta-slug), versions.md last — read off the golden.
order="$( grep '^### ' "$FIX/golden.md" | sed -n '1,4p' | cut -d' ' -f2 | tr '\n' ' ' )"
[ "$order" = "Fixed Added Removed Changed " ] && ok "(B) golden order: file-name byte order, versions.md last" \
                                              || no "(B) golden order unexpected: $order"
python3 "$ASM" release 1.1.1 2030-02-03 "$TMP/g2" >/dev/null 2>"$TMP/empty.err" \
    && no "(B) a release with no fragments left was accepted" \
    || { grep -q 'nothing to release' "$TMP/empty.err" && ok "(B) a release with no fragments is refused ('nothing to release')" \
                                                       || no "(B) empty release refused for the wrong reason: $( head -2 "$TMP/empty.err" )"; }
# (B) CR #434 (4364224289): a version that already has a section is refused BEFORE anything is written — CHANGELOG.md byte-identical,
# every fragment still there; control: a fresh version on the same tree folds. $TMP/g1 holds the folded 1.1.0 section.
freshTree "$TMP/dv"; cp "$TMP/g1/CHANGELOG.md" "$TMP/dv/CHANGELOG.md"
before="$( cksum <"$TMP/dv/CHANGELOG.md" )"; nfrag="$( ls "$TMP/dv/changelog.d" | wc -l | tr -d ' ' )"
python3 "$ASM" release 1.1.0 2030-02-04 "$TMP/dv" >/dev/null 2>"$TMP/dv.err" \
    && no "(B) a release of a version that already has a changelog section was accepted" \
    || { grep -q 'already has a' "$TMP/dv.err" && ok "(B) a duplicate version is refused ('already has a ## [1.1.0] section')" \
                                                || no "(B) duplicate version refused for the wrong reason: $( head -2 "$TMP/dv.err" )"; }
[ "$( cksum <"$TMP/dv/CHANGELOG.md" )" = "$before" ] && [ "$( ls "$TMP/dv/changelog.d" | wc -l | tr -d ' ' )" = "$nfrag" ] \
    && ok "(B) the refused duplicate wrote nothing: CHANGELOG.md and every fragment untouched" \
    || no "(B) the refused duplicate still rewrote CHANGELOG.md or deleted fragments"
python3 "$ASM" release 1.1.2 2030-02-04 "$TMP/dv" >/dev/null 2>&1 && grep -q '^## \[1.1.2\]' "$TMP/dv/CHANGELOG.md" \
    && ok "(B) control: a version without a section folds on the same CHANGELOG.md" \
    || no "(B) control: a fresh version was refused on a CHANGELOG.md that holds another version's section"

# ── (C) drift ─────────────────────────────────────────────────────────────────────────────────────────────────
freshTree "$TMP/d"
printf '### Changed — the versions this release moves, stated once\n\n`kParserVer` 1 → 3.\n' >"$TMP/d/changelog.d/versions.md"
python3 "$ASM" release 1.1.0 2030-02-02 "$TMP/d" >/dev/null 2>&1
if cmp -s "$TMP/d/CHANGELOG.md" "$FIX/golden.md"; then
    no "(C) drift: a fragment edited after the golden still folds to golden.md (the comparison cannot fail)"
else
    ok "(C) drift: a fragment edited after the golden folds to a different file, and the comparison says so"
fi
freshTree "$TMP/d2"
mv "$TMP/d2/changelog.d/zeta-slug.md" "$TMP/d2/changelog.d/0-zeta-slug.md"
python3 "$ASM" release 1.1.0 2030-02-02 "$TMP/d2" >/dev/null 2>&1
cmp -s "$TMP/d2/CHANGELOG.md" "$FIX/golden.md" && no "(C) drift: a renamed fragment (new order) still folds to golden.md" \
                                               || ok "(C) drift: renaming a fragment reorders the fold (order is by name, and the golden sees it)"

# ── (D) malformed fragments, each refused for its own reason ─────────────────────────────────────────────────
badCase(){  # badCase <label> <file name> <expected message fragment> <printf body…>
    label="$1"; name="$2"; want="$3"; shift 3
    freshTree "$TMP/b"
    printf "$@" >"$TMP/b/changelog.d/$name"
    before="$( cksum <"$TMP/b/CHANGELOG.md" )"
    if out="$( python3 "$ASM" check "$TMP/b" 2>&1 )"; then
        no "(D) $label: check accepted it"
    elif printf '%s' "$out" | grep -qF -- "$want"; then
        ok "(D) $label: refused ($want)"
    else
        no "(D) $label: refused for another reason: $( printf '%s' "$out" | head -2 )"
    fi
    python3 "$ASM" release 1.1.0 2030-02-02 "$TMP/b" >/dev/null 2>&1 && no "(D) $label: release accepted the tree"
    [ "$( cksum <"$TMP/b/CHANGELOG.md" )" = "$before" ] || no "(D) $label: a refused release still rewrote CHANGELOG.md"
}
badCase "unknown section"        x.md     "unknown section 'Improved'"   '### Improved — x\n\nbody\n'
badCase "no heading"             x.md     "line 1 must be"               'Fixed: x\n\nbody\n'
badCase "hyphen not em dash"     x.md     "line 1 must be"               '### Fixed - x\n\nbody\n'
badCase "no blank line 2"        x.md     "line 2 must be blank"         '### Fixed — x\nbody\n'
badCase "heading only"           x.md     "line 2 must be blank"         '### Fixed — x\n\n\n'
badCase "empty file"             x.md     "empty fragment"               '\n'
badCase "two changes"            x.md     "one change per file"          '### Fixed — x\n\nbody\n\n### Added — y\n\nbody\n'
badCase "release heading inside" x.md     "break CHANGELOG.md"           '### Fixed — x\n\nbody\n\n## [9.9.9]\n'
badCase "private path"           x.md     "private absolute path"        '### Fixed — x\n\nsee /Use''rs/someone/x\n'
badCase "home path"              x.md     "private absolute path"        '### Fixed — x\n\nsee /home/someone/x\n'
badCase "Windows home path"      x.md     "private absolute path"        '### Fixed — x\n\nsee C:\\Use''rs\\someone\n'
badCase "bare credit"            x.md     "a credit must read"           '### Fixed — x (#5)\n\nthanks @someone for this\n'
badCase "credit, no PR"          x.md     "names no PR"                  '### Fixed — x\n\nbody (thanks @someone)\n'
badCase "credit, bad handle"     x.md     "a credit must read"           '### Fixed — x\n\nbody (thanks @-bad, #5)\n'
badCase "upper-case name"        Fix.md   "file name must match"         '### Fixed — x\n\nbody\n'
badCase "not markdown"           x.txt    "file name must match"         '### Fixed — x\n\nbody\n'
badCase "CR line endings"        x.md     "CR line ending"               '### Fixed — x\r\n\r\nbody\r\n'
badCase "not UTF-8"              x.md     "not UTF-8"                    '### Fixed — x\n\nbody \377\n'
# An old-style PR: its entry written under [Unreleased] instead of a fragment.
freshTree "$TMP/u"
python3 - "$TMP/u/CHANGELOG.md" <<'PY'
import sys
p = sys.argv[1]; t = open( p, encoding = "utf-8" ).read()
t = t.replace( "\n## [1.0.0]", "\n### Fixed — written the old way\n\nbody\n\n## [1.0.0]", 1 )
open( p, "w", encoding = "utf-8" ).write( t )
PY
if out="$( python3 "$ASM" check "$TMP/u" 2>&1 )"; then
    no "(D) an entry written under [Unreleased] was accepted"
elif printf '%s' "$out" | grep -qF 'Add your entry as a new file changelog.d/'; then
    ok "(D) an entry written under [Unreleased] is refused with the 'add a changelog.d/ file instead' message"
else
    no "(D) an [Unreleased] entry refused for another reason: $( printf '%s' "$out" | head -2 )"
fi
freshTree "$TMP/r"; rm "$TMP/r/changelog.d/README.md"
python3 "$ASM" check "$TMP/r" >/dev/null 2>&1 && no "(D) a changelog.d/ without its README.md was accepted" \
                                              || ok "(D) a changelog.d/ without its README.md is refused"

# ── (E) near-miss negatives ───────────────────────────────────────────────────────────────────────────────────
goodCase(){  # goodCase <label> <printf body…>
    label="$1"; shift
    freshTree "$TMP/n"
    printf "$@" >"$TMP/n/changelog.d/near.md"
    if out="$( python3 "$ASM" check "$TMP/n" 2>&1 )"; then ok "(E) $label: accepted"
    else no "(E) $label: refused: $( printf '%s' "$out" | head -2 )"; fi
}
goodCase "credit, PR first"            '### Fixed — x (#5, thanks @some-one)\n\nbody\n'
goodCase "credit, handle first"        '### Fixed — x\n\nbody (thanks @someone, #5)\n'
goodCase "two PRs then the credit"     '### Fixed — x (#5, #6, thanks @someone)\n\nbody\n'
goodCase "bare (thanks @h), PR in head" '### Fixed — x (#5)\n\n- a bullet (thanks @someone).\n'
goodCase "#### sub-heading in the body" '### Documented — x\n\nbody\n\n#### detail\n\nmore\n'
goodCase "Windows drive path in prose" '### Fixed — x\n\n`C:\\…` and `C:\\Program Files`\n'
goodCase "every known section (Security)" '### Security — x\n\nbody\n'

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
