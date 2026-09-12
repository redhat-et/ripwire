#!/usr/bin/env bash
# crawlescapecheck.sh — THE CRAWL ROOT IS A BOUNDARY, and a symlink does not get to move it.
#
# THE VULNERABILITY THIS GATE CLOSES (v0.5.0 and main).
# `collectSources()` accepted a file symlink whose LEXICAL path sat inside the selected root even when
# its TARGET sat outside it: `directory_entry::is_regular_file()` and `file_size()` both FOLLOW the link, so a
# repository-controlled tracked symlink made ripwire open and emit any text file the invoking user could read
# — and emit it under the IN-ROOT link path, so the XML/JSON attributed out-of-root bytes to a path inside the
# repository. That second half is its own defect: a reader (or a model) has no way to tell that the bytes did
# not come from where the map says they did.
#
# FIVE serving channels, not the three the report named. The fourth, the independent `--flags` CMake walk,
# was in the report too; the FIFTH was found while fixing it and is the reason
# the boundary test must run BEFORE the extension classification, not after:
#
#   1. --expand           a source-shaped link (.c) — the whole victim body in CDATA
#   2. --recall           a document-shaped link (.md) — the whole victim document as prose
#   3. MCP memory_recall  the same document, this time straight into a connected model's context
#   4. --flags            a linked CMakeLists.txt outside the root: its option() names and defaults
#   5. --grep             a link with an UNINDEXED extension (.txt) never becomes a crawl candidate at all,
#                         so it lands in the `unsupported-ext` class — which grep's aux scan (search.h
#                         grepCollectAux) READS AND SERVES. Classify first and this channel stays open with
#                         every other arm green.
#
# WHAT THE FIX MUST NOT DO. A symlink whose target is INSIDE the root is a legitimate, common repository
# layout and stays indexed (arm P1). The root itself is routinely reached THROUGH a symlink (/tmp on macOS is
# a link to /private/tmp; every worktree this repo's own gates build lives under one), so the rule has to
# canonicalize the root too — a lexical prefix test on an uncanonicalized path is the bug, and arm P2 is what
# stops the fix from being a second one. Arm N3 is the other half of the same trap: `/x/repo` is not a prefix
# of `/x/repo-evil/f.c` at a COMPONENT boundary, and a raw string prefix test says it is.
#
# HONEST REFUSAL, NOT A SILENT DROP (arms D1-D3). "A zero means none found, never none exists" — a corpus
# that quietly shrank is the failure mode the whole --skipped taxonomy exists to prevent, so a refused file
# is COUNTED exactly and ROWED by name, on the map header and in --skipped.
#
# Usage:
#   test/crawlescapecheck.sh                                       # uses build/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/crawlescapecheck.sh         # the RED run (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the MCP arm"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required — the fixture is a git work tree (tracked symlinks)"; exit 2; }
echo "crawlescapecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── the fixture ───────────────────────────────────────────────────────────────────────────────────────────
# VICTIM/ holds the out-of-root files. repo/ is the crawl root and holds ONLY symlinks into VICTIM/ plus one
# real file and one in-root link (the positive control). Everything is git-TRACKED, because that is the
# attack: a link committed to a repository someone clones and points a tool at.
#
# Every victim token is a distinct nonce. A shared marker would let one leaking channel keep another's arm
# green (shape 3 in CONTRIBUTING §2 — "empty equals agreement" wearing a different hat), and the .txt arm in
# particular has to be able to fail on its own.
V="$TMP/VICTIM"; R="$TMP/repo"
mkdir -p "$V" "$R/src" "$R/docs"
printf 'int rw_victim_source_fn( void ) { return 0xCAFE; }  /* VICTIM_SRC_NONCE_A1 */\n'  > "$V/secret.c"
printf '# Victim document\n\nThe recovery phrase is VICTIM_DOC_NONCE_B2 and nothing else.\n' > "$V/secret.md"
printf 'option( RW_VICTIM_CMAKE_NONCE_C3 "not this repo'"'"'s switch" ON )\n'               > "$V/CMakeLists.txt"
# two nonces on ONE line: the QUERY term and, beside it, the PAYLOAD the served line would carry. Asserting
# on the query term alone cannot fail — grep echoes its own pattern on the root element.
printf 'plain text holding VICTIM_TXT_NONCE_D4 beside VICTIM_TXT_PAYLOAD_D4B\n'             > "$V/secret.txt"

printf 'int rw_benign_fn( void ) { return 1; }\n'                                           > "$R/src/benign.c"
printf '# In-root doc\n\nA note about the scheduler and its bounded queue.\n'               > "$R/docs/inroot.md"
# a doc making a claim about a name that exists ONLY inside the victim's CMakeLists — the bait for arm 6
printf '# Claims\n\nThe build switch `RW_VICTIM_CMAKE_NONCE_C3` in `src/CMakeLists.txt:1` selects it.\n' > "$R/docs/claims.md"
( cd "$R" \
  && ln -s ../../VICTIM/secret.c       src/escape.c \
  && ln -s ../../VICTIM/secret.md      docs/escape.md \
  && ln -s ../../VICTIM/CMakeLists.txt src/CMakeLists.txt \
  && ln -s ../../VICTIM/secret.txt     src/escape.txt \
  && ln -s benign.c                    src/inroot_link.c )

# the sibling-prefix trap (arm N3): `<root>-evil` shares a raw string prefix with `<root>` and is NOT inside it
mkdir -p "$TMP/repo-evil"
printf 'int rw_sibling_victim_fn( void ) { return 2; }  /* VICTIM_SIB_NONCE_E5 */\n' > "$TMP/repo-evil/sib.c"
( cd "$R" && ln -s ../../repo-evil/sib.c src/sibling.c )

git -C "$R" init -q .
git -C "$R" add -A
git -C "$R" -c user.email=gate@ripwire -c user.name=gate commit -qm "tracked symlinks" >/dev/null 2>&1

# assert the fixture is what the arms below think it is — a vanishing probe target passes every arm and
# proves nothing (CONTRIBUTING §2).
linkcount="$( find "$R/src" "$R/docs" -type l | wc -l | tr -d ' ' )"
[ "$linkcount" = "6" ] || { echo "fixture broken: expected 6 symlinks under repo/, found $linkcount"; exit 2; }
grep -q VICTIM_SRC_NONCE_A1 "$R/src/escape.c" \
  || { echo "fixture broken: the escaping link does not resolve to the victim (nothing to leak, arms cannot fail)"; exit 2; }

rw(){ "$BIN" "$@" --no-cache 2>/dev/null; }

# ── 1. --expand: a source-shaped escape ───────────────────────────────────────────────────────────────────
rw "$R"                                 > "$TMP/map.xml"
rw "$R" --expand=rw_victim_source_fn    > "$TMP/expand.xml"
if grep -q VICTIM_SRC_NONCE_A1 "$TMP/map.xml" "$TMP/expand.xml"; then
    no "1 --expand: out-of-root source bytes served through an in-root symlink (VICTIM_SRC_NONCE_A1)"
else
    ok "1 --expand: the escaping .c link serves no out-of-root bytes"
fi
if grep -q 'p="src/escape.c"' "$TMP/map.xml"; then
    no "1b map: src/escape.c is still indexed — out-of-root bytes attributed to an in-root path"
else
    ok "1b map: the escaping .c link is not in the corpus"
fi

# ── 2. --recall: a document-shaped escape ─────────────────────────────────────────────────────────────────
rw "$R" --recall="recovery phrase" > "$TMP/recall.txt"
if grep -q VICTIM_DOC_NONCE_B2 "$TMP/recall.txt"; then
    no "2 --recall: out-of-root document bytes served through an in-root symlink (VICTIM_DOC_NONCE_B2)"
else
    ok "2 --recall: the escaping .md link serves no out-of-root bytes"
fi

# ── 3. MCP memory_recall: the same document, into a model's context ───────────────────────────────────────
# One initialize + one tools/call, the reply's text payload written verbatim (same shape as
# test/recallparitycheck.sh's MCP door).
python3 - "$BIN" "$R" "recovery phrase" > "$TMP/mcp.txt" <<'PY'
import json, subprocess, sys
binp, root, task = sys.argv[1], sys.argv[2], sys.argv[3]
msgs = [ { "jsonrpc": "2.0", "id": 1, "method": "initialize" },
         { "jsonrpc": "2.0", "id": 2, "method": "tools/call",
           "params": { "name": "memory_recall", "arguments": { "path": root, "task": task } } } ]
p = subprocess.run( [ binp, "--mcp" ], input = "\n".join( json.dumps( m ) for m in msgs ) + "\n",
                    capture_output = True, text = True, timeout = 180 )
for line in p.stdout.splitlines():
    try:
        d = json.loads( line )
    except ValueError:
        continue
    if d.get( "id" ) == 2 and "error" not in d:
        sys.stdout.write( d[ "result" ][ "content" ][ 0 ][ "text" ] )
PY
if [ ! -s "$TMP/mcp.txt" ]; then
    no "3 MCP memory_recall: no payload came back — the arm cannot reach a verdict"
elif grep -q VICTIM_DOC_NONCE_B2 "$TMP/mcp.txt"; then
    no "3 MCP memory_recall: out-of-root document bytes delivered to a connected model (VICTIM_DOC_NONCE_B2)"
else
    ok "3 MCP memory_recall: the escaping .md link serves no out-of-root bytes"
fi

# ── 4. --flags: the independent CMake walk ────────────────────────────────────────────────────────────────
rw "$R" --flags > "$TMP/flags.xml"
if grep -q RW_VICTIM_CMAKE_NONCE_C3 "$TMP/flags.xml"; then
    no "4 --flags: an out-of-root CMakeLists.txt was parsed and its option reported (RW_VICTIM_CMAKE_NONCE_C3)"
else
    ok "4 --flags: the escaping CMakeLists.txt link is not parsed"
fi

# ── 5. --grep: the unindexed aux scan ─────────────────────────────────────────────────────────────────────
# The channel that survives a fix applied AFTER the extension classification.
rw "$R" --grep=VICTIM_TXT_NONCE_D4 > "$TMP/grep.xml"
if grep -q VICTIM_TXT_PAYLOAD_D4B "$TMP/grep.xml"; then
    no "5 --grep: the unindexed aux scan served out-of-root bytes (VICTIM_TXT_PAYLOAD_D4B)"
else
    ok "5 --grep: the escaping .txt link is not scanned"
fi

# ── 6. --doc-drift: the THIRD walk ────────────────────────────────────────────────────────────────────────
# Not in the report: found while fixing it. docdrift.h::collectRepoPaths is its own prune-aware walk, and it
# does not merely probe for existence — every auxFull path (CMakeLists.txt, *.cmake, *.yml, shader sources)
# is OPENED and its identifiers harvested, then reported under the IN-ROOT path. Narrower than the ingest
# disclosure (facts, not bytes) and the same defect, so it takes the same rule.
rw "$R" --doc-drift > "$TMP/drift.xml"
# The doc's claim can only be "present" if the out-of-root CMakeLists was read. Either verdict is fine as
# long as the name was not harvested FROM the escaping link — so the arm is the disclosure plus the absence
# of a present-because-we-read-it verdict.
desc="$( grep -o 'escaped_root="[0-9]*"' "$TMP/drift.xml" | head -1 | grep -o '[0-9]*' )"
if [ "${desc:-0}" -ge 1 ]; then
    ok "6 --doc-drift: its own walk applies the boundary and discloses it (escaped_root=$desc)"
else
    no "6 --doc-drift: escaped_root=${desc:-absent} — the third walk still reads through escaping links"
fi

# ── N3. the sibling-prefix trap ───────────────────────────────────────────────────────────────────────────
# A containment test written as a raw string prefix admits <root>-evil/. This arm is red for that fix and
# green for a component-boundary one; nothing else in the suite separates the two.
rw "$R" --expand=rw_sibling_victim_fn > "$TMP/sib.xml"
if grep -q VICTIM_SIB_NONCE_E5 "$TMP/map.xml" "$TMP/sib.xml"; then
    no "N3 sibling prefix: <root>-evil/ was admitted as 'inside' <root> (VICTIM_SIB_NONCE_E5)"
else
    ok "N3 sibling prefix: <root>-evil/ is outside <root>, at a component boundary"
fi

# ── P1. POSITIVE CONTROL: an in-root symlink still resolves and is still indexed ──────────────────────────
# Without this arm the whole gate is satisfiable by refusing every symlink, which would break a legitimate
# and common repository layout. This is the arm that makes the rule a BOUNDARY and not a ban.
if grep -q 'p="src/inroot_link.c"' "$TMP/map.xml"; then
    ok "P1 positive control: an in-root symlink is still crawled and indexed"
else
    no "P1 positive control: an in-root symlink was dropped — the rule bans links instead of bounding them"
fi
if grep -q 'p="src/benign.c"' "$TMP/map.xml" && grep -q 'p="docs/inroot.md"' "$TMP/map.xml"; then
    ok "P1b positive control: the real in-root files are untouched"
else
    no "P1b positive control: a real in-root file went missing"
fi

# ── P2. THE ROOT ITSELF REACHED THROUGH A SYMLINK ─────────────────────────────────────────────────────────
# The rule has to canonicalize BOTH sides. Compare the link's target against an uncanonicalized root and
# every file under a symlinked root reads as an escape — the whole corpus vanishes, silently, on a layout
# this project's own worktrees use.
ln -s "$R" "$TMP/rootlink"
rw "$TMP/rootlink" > "$TMP/viaLink.xml"
if grep -q 'p="src/benign.c"' "$TMP/viaLink.xml" && grep -q 'p="src/inroot_link.c"' "$TMP/viaLink.xml"; then
    ok "P2 root via symlink: the corpus survives — both sides of the test are canonicalized"
else
    no "P2 root via symlink: the corpus collapsed when the root was reached through a link (uncanonicalized root)"
fi
if grep -q 'p="src/escape.c"' "$TMP/viaLink.xml"; then
    no "P2b root via symlink: the escape is admitted when the root is itself a link"
else
    ok "P2b root via symlink: the escape is still refused"
fi

# ── D1-D3. HONEST REFUSAL — counted exactly, rowed by name ────────────────────────────────────────────────
rw "$R" --skipped > "$TMP/skipped.xml"
esc="$( grep -o 'escaped_root="[0-9]*"' "$TMP/skipped.xml" | head -1 | grep -o '[0-9]*' )"
if [ "${esc:-0}" -ge 5 ]; then
    ok "D1 --skipped: the refusal is counted (escaped_root=$esc, five links out of root)"
else
    no "D1 --skipped: escaped_root=${esc:-absent} — refused files vanished from the accounting"
fi
# Count ROWS, not the string: the legend clause spells why="escaped-root" too, and a count that includes it
# is satisfied by four rows plus a definition — grep -c counts lines and grep -o over a bare attribute counts
# prose (CONTRIBUTING §2, "a count that counts the wrong unit"). An <f …/> row ends in bytes=/ext=.
rows="$( grep -o '<f p="[^"]*" why="escaped-root" bytes="[0-9]*" ext="[^"]*"/>' "$TMP/skipped.xml" | wc -l | tr -d ' ' )"
if [ "$rows" -ge 5 ]; then
    ok "D2 --skipped: the refused files are ROWED by name ($rows <f why=escaped-root/> rows)"
else
    no "D2 --skipped: $rows escaped-root rows — a count with no names is not a disclosure"
fi
# the --flags walk keeps its OWN count: the two walkers apply one rule and each discloses what IT refused
fesc="$( grep -o 'escaped_root="[0-9]*"' "$TMP/flags.xml" | head -1 | grep -o '[0-9]*' )"
if [ "${fesc:-0}" -ge 1 ]; then
    ok "D2d --flags: its own walk discloses what it refused (escaped_root=$fesc)"
else
    no "D2d --flags: escaped_root=${fesc:-absent} — the CMake walk dropped a file in silence"
fi
if grep -q 'escape.c' "$TMP/skipped.xml" && grep -q 'escape.md' "$TMP/skipped.xml" && grep -q 'escape.txt' "$TMP/skipped.xml"; then
    ok "D2b --skipped: the rows name the links (escape.c / escape.md / escape.txt)"
else
    no "D2b --skipped: a refused link is missing from the rows"
fi
# the row must name the IN-ROOT link, never the out-of-root target: a disclosure that leaks the path it
# refused to read would hand back part of what it just denied.
if grep -q "$V" "$TMP/skipped.xml" || grep -q "$V" "$TMP/map.xml"; then
    no "D2c --skipped: the refusal discloses the out-of-root TARGET path"
else
    ok "D2c --skipped: the rows name the in-root link, never the out-of-root target"
fi
if grep -q 'escaped_root=' "$TMP/map.xml"; then
    ok "D3 map header: the default map discloses the refusal (escaped_root=)"
else
    no "D3 map header: the default map — the surface every agent sees — says nothing about the drop"
fi
# the absent-when-zero half of the same rule: a clean tree's map must stay byte-identical to today's
CLEAN="$TMP/clean"; mkdir -p "$CLEAN"; printf 'int f( void ) { return 0; }\n' > "$CLEAN/a.c"
rw "$CLEAN" > "$TMP/clean.xml"
if grep -q 'escaped_root=' "$TMP/clean.xml"; then
    no "D3b map header: escaped_root= is emitted on a tree with nothing escaping (absent-when-zero broken)"
else
    ok "D3b map header: absent on a clean tree — no byte cost where nothing was refused"
fi

# ── M1. MULTI-ROOT: 'inside the root' means the root that file was crawled under ──────────────────────────
# Two roots, and a link in root A pointing at a file in root B. B's own copy stays indexed under B; A's link
# is refused, because a file is bounded by the root it was CRAWLED under, not by the workspace's union.
A="$TMP/wsA"; B="$TMP/wsB"; mkdir -p "$A/src" "$B/src"
printf 'int rw_a_fn( void ) { return 1; }\n'                                  > "$A/src/a.c"
printf 'int rw_b_fn( void ) { return 2; }  /* CROSSROOT_NONCE_F6 */\n'        > "$B/src/b.c"
( cd "$A" && ln -s ../../wsB/src/b.c src/borrowed.c )
rw "$A" "$B" > "$TMP/ws.xml"
if grep -q 'rw_b_fn' "$TMP/ws.xml"; then
    ok "M1 multi-root: root B's own file is still indexed under B"
else
    no "M1 multi-root: the rule removed a file from the root that legitimately owns it"
fi
if grep -q 'borrowed.c' "$TMP/ws.xml"; then
    no "M1b multi-root: a link in root A to a file in root B was crawled under A (a file has ONE owning root)"
else
    ok "M1b multi-root: the cross-root link is refused — bounded by the root it was crawled under"
fi

# ── X1. determinism + well-formedness on the fixture that exercises the new path ──────────────────────────
rw "$R" > "$TMP/d1.xml"; rw "$R" > "$TMP/d2.xml"
if cmp -s "$TMP/d1.xml" "$TMP/d2.xml"; then ok "X1 determinism on the escaping fixture (byte-identical)"; else no "X1 determinism broken on the escaping fixture"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/skipped.xml" >/dev/null 2>&1; then ok "X2 --skipped with escaped-root rows is well-formed XML"; else no "X2 --skipped with escaped-root rows is not well-formed"; fi
else
    ok "X2 xmllint absent — well-formedness arm skipped (xmlwellformedcheck owns it)"
fi

[ "$fail" = 0 ] && echo "crawlescapecheck: ALL PASS" || echo "crawlescapecheck: FAILURES"
exit "$fail"
