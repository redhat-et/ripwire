#!/usr/bin/env bash
# bashsourcecheck.sh — kParserVer 81 gate: BASH `source FILE` / `. FILE` is a physical dependency.
#
# Before this round a .sh file emitted NO Include record on any tree: `source` parsed as an ordinary
# `command` whose name happened to be `source`, was captured as a call to an undefined function, and was
# dropped. lintrules.h then called Bash dependency-INcapable, which was a true statement about the
# extractor and a false one about the language. This gate is the whole claim, stated as measurements.
#
# Bash is the one of the four new languages with NO name->path convention to model — the argument IS the
# path — and the one whose specifier is almost always built from a VARIABLE. In ripwire's own test/ tree,
# 29 of 29 `source` lines are `$ROOT/...`, so the variable case is the ordinary case and a resolver that
# only handled literals would resolve zero of them.
#
# Fixture test/bashsourcefix:
#   main.sh     ./lib/helper.sh                  -> lib/helper.sh      (literal, file-relative)
#               "$ROOT/lib/helper.sh"            -> lib/helper.sh      ($VAR anchor, literal tail)
#               "$LIBDIR/util.sh"                -> util.sh            (bare tail)
#               "$( dirname "$0" )/util.sh"      -> util.sh            (command substitution as anchor)
#               "$1"                             -> FLOOR, no edge     (the whole path is a parameter)
#               "$d/$n.sh"                       -> FLOOR, no edge     (the FILENAME is a variable)
#               /etc/profile                     -> no edge            (absolute, outside the crawl)
#   nested.sh   one `source` per container kind (if / function / for / while / case / group / subshell /
#               &&-list) -> eight distinct lib/*.sh files: the container-table arms, one file each
#   sub/inner.sh "$SOMEDIR/shared.sh"            -> AMBIGUOUS (sub/shared.sh and shared.sh both answer)
#                                                   -> unique-or-degrade must yield NO edge
#   decoy/helper.sh                              -> a same-BASENAME file a path-precise resolver never sees
#
# Usage:  test/bashsourcecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/bashsourcecheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/bashsourcefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/bashsourcefix — fixture missing"; exit 2; }
echo "bashsourcecheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --deps --no-cache >"$TMP/deps" 2>/dev/null
DEPS="$( cat "$TMP/deps" )"

# ── 1. CAPTURE: every spelling of the directive becomes an Include record ─────────────────────────────
for t in './lib/helper.sh' '$ROOT/lib/helper.sh' '$LIBDIR/util.sh' '$1' '$d/$n.sh' '/etc/profile'; do
    if printf '%s' "$DEPS" | grep -qF "<inc t=\"$t\"/>"; then
        ok "capture: <inc t=\"$t\"/>"
    else
        no "capture: no <inc t=\"$t\"/> row — the directive was dropped, not floored"
    fi
done
printf '%s' "$DEPS" | grep -q '<inc t="\$( dirname &quot;\$0&quot; )/util.sh"/>' \
    && ok 'capture: the command-substitution anchor is recorded verbatim, quotes escaped' \
    || no "capture: the \$( dirname ... ) specifier is missing: $( printf '%s' "$DEPS" | grep -oE '<inc t="[^"]*"/>' | tr '\n' ' ' )"

# ── 2. RESOLUTION: the edges that must exist, by afferent count ───────────────────────────────────────
# lib/helper.sh is named THREE times (main.sh literal + main.sh "$ROOT/..." + nested.sh's if-arm) and
# util.sh twice ("$LIBDIR/..." + the command substitution). afferent counts edge OCCURRENCES, so these
# are exact: they fail both if a directive stops resolving AND if one starts resolving twice.
printf '%s' "$DEPS" | grep -q '<f p="lib/helper.sh" afferent="3"/>' \
    && ok 'resolve: lib/helper.sh afferent="3" (literal + $VAR-anchored + inside an if)' \
    || no "resolve: lib/helper.sh afferent wrong: $( printf '%s' "$DEPS" | grep -oE '<f p="lib/helper.sh" afferent="[0-9]*"/>' )"
printf '%s' "$DEPS" | grep -q '<f p="util.sh" afferent="2"/>' \
    && ok 'resolve: util.sh afferent="2" ($LIBDIR anchor + $( dirname "$0" ) anchor both land)' \
    || no "resolve: util.sh afferent wrong: $( printf '%s' "$DEPS" | grep -oE '<f p="util.sh" afferent="[0-9]*"/>' )"

# every container arm resolves to its OWN file — eight arms, eight files, so a walk that stopped entering
# one container kind loses exactly one row here and names which.
for d in loopdep whiledep casedep groupdep subdep anddep util; do
    printf '%s' "$DEPS" | grep -q "<f p=\"lib/$d.sh\" afferent=\"1\"/>" \
        && ok "container arm: nested.sh reaches lib/$d.sh" \
        || no "container arm: lib/$d.sh has no importer — the walk did not enter that container kind"
done
printf '%s' "$DEPS" | grep -q '<f p="nested.sh" includes="8"' \
    && ok 'container walk: nested.sh carries all 8 directives (if/fn/for/while/case/group/subshell/&&)' \
    || no "container walk: nested.sh directive count wrong: $( printf '%s' "$DEPS" | grep -oE '<f p="nested.sh" includes="[0-9]*"' )"

# ── 3. THE FLOOR, and it is a floor rather than a zero ────────────────────────────────────────────────
# `"$1"` and `"$d/$n.sh"` cannot be resolved by anything short of running the script. They must still be
# VISIBLE (arm 1 asserted the rows) and must produce NO edge. main.sh's transitive cone is therefore
# exactly {itself, lib/helper.sh, util.sh} = 3.
printf '%s' "$DEPS" | grep -q '<f p="main.sh" includes="7" afferent="0" instab="1.00" transitive="3">' \
    && ok 'floor: main.sh has 7 directives and a 3-file cone — the 3 unresolvable ones added no edge' \
    || no "floor: main.sh cone wrong: $( printf '%s' "$DEPS" | grep -oE '<f p="main.sh"[^>]*>' )"

# ── 4. MUTATION CONTROL — unique-or-degrade, and no basename matching ─────────────────────────────────
# (a) sub/inner.sh's "$SOMEDIR/shared.sh" is answered by TWO distinct files (sub/shared.sh next to it,
#     shared.sh at the root). A resolver that picked the first probe instead of degrading passes every
#     arm above and fails only here.
printf '%s' "$DEPS" | grep -q '<f p="sub/inner.sh" includes="1" afferent="0" instab="0.00" transitive="1">' \
    && ok 'mutation control: an ambiguous $VAR tail degrades to NO edge (instab=0.00, cone=1)' \
    || no "mutation control: the ambiguous specifier resolved anyway: $( printf '%s' "$DEPS" | grep -oE '<f p="sub/inner.sh"[^>]*>' )"
printf '%s' "$DEPS" | grep -qE '<f p="(sub/)?shared.sh" afferent=' \
    && no "mutation control: one of the two shared.sh files took the ambiguous edge" \
    || ok 'mutation control: neither shared.sh gained an importer'
# (b) decoy/helper.sh shares a BASENAME with lib/helper.sh and is never named. A basename fallback — the
#     one shortcut this resolver forbids — would give it an importer.
printf '%s' "$DEPS" | grep -q '<f p="decoy/helper.sh" afferent=' \
    && no "mutation control: decoy/helper.sh gained an importer — a basename fallback crept in" \
    || ok 'mutation control: decoy/helper.sh has no importer (path-precise, never basename)'

# ── 5. CAPABILITY: .sh files count in the dependency denominator now ──────────────────────────────────
printf '%s' "$DEPS" | grep -q '<health files="15" dep_files="15"' \
    && ok 'capability: all 15 .sh files are dependency-capable (dep_files == files)' \
    || no "capability: dep_files wrong: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"
printf '%s' "$DEPS" | grep -qE 'dep_langs="[^"]*,sh[,"]' \
    && ok 'capability: <health dep_langs=> discloses sh in the capable set' \
    || no "capability: dep_langs= does not name sh: $( printf '%s' "$DEPS" | grep -oE 'dep_langs="[^"]*"' )"

# ── 6. ROOT-SPELLING INDEPENDENCE — the defect that motivated probeUpward ─────────────────────────────
# A `$VAR`-anchored specifier resolves by walking the includer's ancestors. An earlier implementation
# probed an EMPTY base instead, which is the crawl root only when the root was written as `.`: the same
# tree scanned as `ripwire /abs/path` resolved half as many directives. Both spellings must agree, byte
# for byte, or the feature works only for people who cd first.
( cd "$FIX" && "$BIN" . --deps --no-cache 2>/dev/null ) | sed 's/ root="[^"]*"//' >"$TMP/dots"
"$BIN" "$FIX" --deps --no-cache 2>/dev/null | sed 's/ root="[^"]*"//' >"$TMP/abs"
cmp -s "$TMP/dots" "$TMP/abs" \
    && ok 'root spelling: `ripwire .` from inside the tree == `ripwire /abs/path` (identical edges)' \
    || { no 'root spelling: an absolute crawl root resolves differently from a relative one'; diff "$TMP/dots" "$TMP/abs" | head -4; }

# ── 7. determinism, warm == cold, well-formed XML ─────────────────────────────────────────────────────
"$BIN" "$FIX" --deps --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --deps --no-cache >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic (two --no-cache runs identical)" || no "non-deterministic"
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" && ok "warm == cold (directives survive the cache round-trip)" || no "warm != cold"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
