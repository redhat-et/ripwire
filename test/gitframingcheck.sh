#!/usr/bin/env bash
# gitframingcheck.sh — the git-log FRAMING gate: a committed filename can never be read as commit
# metadata, and the NUL frame that guarantees it stays pinned.
#
# THE DEFECT (audit finding #4, Medium). Every `git log --name-only` consumer in src/gitmine.h framed
# its stream with a LINE-based reader and a `__C__` marker matched as a line PREFIX — three spellings
# across five sites — so a path whose name begins with the marker bytes was read as commit metadata.
# Measured on the hostile fixture below with the PRE-CHANGE binary:
#   files="8" of 11 indexed — the four marker-prefixed names (`__C__`, `__C__ 1694000000.cpp`,
#     `__C__.cpp`, `__C__x|1694000000.cpp`) read as forged headers instead of paths
#   five files owned by top="x", an author email that appears in NO commit
#     (`__C__x|1694000000.cpp` sorts before lowercase a..z, so every path after it inherits the
#     forgery; `--dashdash.cpp` and `Alpha.cpp`, sorting before it, keep their true author)
#   zeta.cpp carrying x as a co-author (authors=3), its top owner flipped to quiet2@x.com — the
#     forgery changes the ANSWER, not a detail
#
# THE FIX (lane/git-porcelain-framing-v2). One reader parses the stream for all five consumers:
# `git log -z --name-only --format=%x00__C__%x00%ae%x00%at%x00%ct`. Fields and paths are
# NUL-terminated and RAW (core.quotepath=false), and the marker is a WHOLE-FIELD sentinel a path can
# never spell. An empty field — which only the format can emit, because paths are never empty — is
# the record boundary, read with ONE field of lookahead so a merge's prefix empty is not mistaken
# for one. The five consumers (gitLogFileSets, gitLogNameOnlyRaw, gitFileCommitCountsInDayWindow,
# gitLogDecayedFileMining, gitFileAuthors) became visitors over forEachGitLogRecord.
#
# THE PINNED LAYOUT (specs/git-porcelain-framing/evidence/layout-pin.md, derived empirically — the
# '\n' before a commit's first path, the merge prefix empty and the end-of-stream unterminated field
# are NOT documented git behaviour):
#   \0 __C__ \0 <ae> \0 <at> \0 <ct> [ \0 ] [ \n<path1> | <path1> ] \0 <path2> \0 ...
#   regular commit: metadata, then a '\n'-prefixed first path.   empty commit: metadata only.
#   merge: metadata, a prefix empty, then BARE paths.             clean merge: metadata + prefix empty.
# MINIMUM GIT 2.43.0 (arm 8 refuses below it): a git that changes any of the above fails arm 2
# loudly instead of silently corrupting the first path.
#
# ARMS
#   (a) the spoof is neutralized — every --owners row on the hostile fixture names its TRUE author,
#       and no forged-author row exists anywhere.
#   (b) the newline filename round-trips — a<LF>b.cpp is exactly one path, churn=1, owned.
#   (c) the exact-marker file is a path — a file named exactly `__C__` never opens a record; the
#       indexed file after it in byte order keeps its attribution.
#   (c2) the single-file pathspec seam — --owners=SYM appends a pathspec to the shared command, and a
#       pathspec glued to -z answers EMPTY, which reads as "git unavailable / no history" rather than
#       as a broken command. The pin for the one space that separates them.
#   (f) an empty METADATA field is data, not framing — git accepts an empty author email
#       (--author="No Email <>"), and the boundary rule must not eat a pending-metadata empty as a
#       merge prefix: pre-fix the whole record shifted (email←the %at digits, epochs off by one, the
#       first path's '\n' unstripped) and the commit was left PATHLESS, its file unattributed.
#   (d) the honest tree is byte-identical to the golden RECORDED FROM THE PRE-CHANGE BINARY — the
#       "no behavior change on honest trees" claim, over --owners/--hotspots/--cochange.
#   (e) the marker literal lives ONLY inside the shared helper — five consumer bodies, zero hits.
#   2. the raw-stream digest + structural count (11 records, 13 marker-spelled byte sequences).
#   3. the merge shapes: an ordinary name-bearing merge's files are ATTACHED (the lookahead is
#      load-bearing — a parser without it drops them); the DISCLOSED collision is pinned.
#   4. author-not-committer: ownership answers with the AUTHOR, never the committer.
#   5. non-vacuity: the fixture is what the arms claim (12 tracked, 11 indexed, the extension-less
#      `__C__` unindexed BY DESIGN per layout-pin Finding 1).
#   6. determinism: two runs byte-identical.
#   7. the oracle: the tool's numbers re-derive from its own command (trap #12).
#   8. the git floor, and a shimmed git that rejects -z degrades honestly — no fabricated rows.
#   9. a non-empty stream with no record marker is UNREAD (history_unread="1"), never a clean empty history.
#
# THE DISCLOSED COLLISION (not papered over; full fix = a format sentinel change, follow-on spec
# material): a merge whose FIRST combined path is a file literally named `__C__` reads as pathless —
# its prefix empty is followed by the marker-spelled path, which the boundary rule cannot tell from
# a real record boundary. The fixture carries exactly such a merge (MERGE, resolving `__C__` and
# `__C__.cpp`), and arm 3 pins its observable: the merge's files lose their attribution, and a
# pathless phantom record (whose "author" is the marker-spelled path) is emitted that every consumer
# no-ops on. Note the two miners disagree there BY DESIGN of the disclosure: --for's churn (the
# migrated reader) reads 3 for `__C__.cpp`, while --hotspots' churn rides the unmigrated
# gitCommandLines miner and reads 4.
#
# EXPIRY: like test/mergechurncheck.sh this fixture hardcodes 2026-06 dates; the churn verbs mine a
# HEAD-anchored 12-month window, so the numbers are stable, but a future reader moving the dates
# must re-derive every literal here. The digest pins the exact stream.
#
# Usage:  test/gitframingcheck.sh              # build/ripwire
#         test/gitframingcheck.sh asan/ripwire # positional seam
#         RIPWIRE_BIN=asan/ripwire test/gitframingcheck.sh   # env seam
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
# (5) THE TIMEZONE. The fixture's dates are naive strings ("2026-06-01T12:00:00"), and git reads a
# naive GIT_AUTHOR_DATE in the MACHINE'S zone — so every %at/%ct in the stream moves with the host,
# and with them the digest pin below and the golden. Measured: the same fixture, the same command,
# the same git, reads a823b914… under WEST and 9a112638… under UTC — CI's runners are UTC, a dev Mac
# is not, and the gate failed on exactly that. Pin it HERE rather than in clean-env.sh: that file is
# sourced by gates whose own fixtures (mergechurncheck and its 2026-06 dates) were derived on a
# non-UTC machine, and shifting them is a separate change with its own re-derivation.
export TZ=UTC
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"       # BOTH seams — positional and env
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
GOLD="$ROOT/test/gitframingcheck_golden.txt"
SRC="$ROOT/src/gitmine.h"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
REAL_GIT="$( command -v git )"; export REAL_GIT   # the shim below is a CHILD process: an unexported value would reach it empty (CodeRabbit 4419234625)
echo "gitframingcheck: BIN=$BIN  ROOT=$ROOT  git=$( git --version )"

TMP="$( mktemp -d )"; H="$( mktemp -d )"; G="$( mktemp -d )"; E="$( mktemp -d )"
trap 'rm -rf "$TMP" "$H" "$G" "$E"' EXIT
# The fixtures are FRESH mktemp paths every run, and that is load-bearing beyond tidiness: the tool
# memoizes its history walks under $TMPDIR/ripwire keyed on (repo, HEAD, window) — the repo key is
# path-derived — so a fixed fixture path would let a previous run's cached churn answer this run's
# questions. A fresh path is a cold cache: every number below is computed, never remembered.

mkfn(){ printf 'int %s( int x )\n{\n    if( x > 1 ) return x + 1;\n    return x - 1;\n}\n' "$1"; }
D(){ export GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1"; }
ID(){ export GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME="$3" GIT_COMMITTER_EMAIL="$4"; }
UC(){ unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL; }
# attr_of FILE PATHSUFFIX ATTR — the ATTR value of the row whose p= ends with PATHSUFFIX ("" if no row).
# p= is XML-escaped in the output, so a<LF>b.cpp spells p="a&#10;b.cpp" and q"uote.cpp spells
# p="q&quot;uote.cpp"; callers pass the ESCAPED spelling, which is also the stable one.
psel(){ awk -v s="$1" '{ if( match( $0, /p="[^"]*"/ ) ) { v = substr( $0, RSTART + 3, RLENGTH - 4 );
        if( v == s || ( length(v) > length(s) && substr( v, length(v) - length(s) ) == "/" s ) ) print } }'; }
attr_of(){ tr '>' '\n' < "$1" | psel "$2" | grep -oE "$3=\"[^\"]*\"" | head -1 | sed 's/^[^"]*"//; s/"$//'; }
churn_of_fn(){ tr '>' '\n' < "$1" | grep -F "n=\"$2\"" | grep -oE 'churn="[0-9]+"' | head -1 | tr -cd '0-9'; }
# code_only FILE — FILE with comment-only lines dropped, for "the literal appears in CODE" counts.
# This codebase's block-comment interior lines start with '*', and both code sites carrying the marker
# are plain code lines, so the count is exact for the pins below.
code_only(){ awk '{ l=$0; sub(/^[ \t]+/,"",l); if( l ~ /^\/\// || l ~ /^\*/ || l ~ /^\/\*/ ) next; print }' "$1"; }

# ── THE HOSTILE FIXTURE ─────────────────────────────────────────────────────────────────────────
# History, read commit by commit (these readings ARE the literals asserted below — never computed
# from the tool, never from the same git flag the code uses):
#   c1    Real <real@x.com>  2026-06-01  creates the 12-file battery: Alpha.cpp, zeta.cpp, and the
#                              hostile names `__C__`, `__C__ 1694000000.cpp`, `__C__.cpp`,
#                              `__C__x|1694000000.cpp`, `q"uote.cpp`, `sp ace.cpp`, `back\slash.cpp`,
#                              `pi|pe.cpp`, `--dashdash.cpp`, `a<LF>b.cpp
#   c2    author Real, COMMITTER Committer <committer@x.com> 2026-06-03 — appends zeta.cpp
#                              (the author-not-committer arm: author date 06-02, committer date 06-03)
#   s1    Sidedev <side@x.com> 2026-06-04  on branch `side`: modifies `__C__` and `__C__.cpp`
#   m1    Real 2026-06-05       on main: modifies the same two differently (a conflict on both)
#   MERGE author Real, COMMITTER Mergecommitter <mergecommitter@x.com> 2026-06-07 — resolves BOTH
#                              with content neither parent had, so the combined diff is
#                              [`__C__`, `__C__.cpp`] and its FIRST path is the marker-spelled file:
#                              THE DISCLOSED COLLISION. The merge reads as pathless.
#   c3    Real 2026-06-08       --allow-empty: the path-less record
#   q1    Quietdev <quiet@x.com> 2026-06-09 on branch `quiet`: modifies Alpha.cpp
#   m2    Real 2026-06-10       on main: modifies Alpha.cpp the other way
#   q2    Quietdev <quiet2@x.com> 2026-06-11 on branch `quiet2`: appends zeta.cpp
#   CLEAN Real 2026-06-12       `git merge -s ours --no-ff quiet2`: a real two-parent merge whose
#                              combined diff is EMPTY (the clean-merge shape)
#   M2    author Real, COMMITTER Mergecommitter 2026-06-13 — merges `quiet`, resolves Alpha.cpp
#                              with new content: a name-bearing merge whose first combined path is an
#                              ORDINARY file. The lookahead attaches it; a parser without one drops it.
mkdir -p "$H"
git -C "$H" init -q -b main
C(){ git -C "$H" add -A >/dev/null; git -C "$H" commit -qm "$1"; }

# layout-pin Finding 1: an unindexed hostile name is invisible to every miner, so the forgery is only
# observable where a hostile name sorts BEFORE an indexed file. `__C__` (0x5F) sorts before lowercase
# a..z; `Alpha.cpp` (0x41) sorts before it. The extension-less `__C__` is unindexed BY DESIGN — its
# path-level survival is pinned by the digest (arm 2), and its danger through the files after it.
ID Real real@x.com Real real@x.com; D 2026-06-01T12:00:00
mkfn alphaFn  > "$H/Alpha.cpp"
mkfn zetaFn   > "$H/zeta.cpp"
mkfn cFn      > "$H/__C__"
mkfn spFn     > "$H/__C__ 1694000000.cpp"
mkfn dotFn    > "$H/__C__.cpp"
mkfn spoofFn  > "$H/__C__x|1694000000.cpp"
mkfn qFn      > "$H/q\"uote.cpp"
mkfn spFn2    > "$H/sp ace.cpp"
mkfn bsFn     > "$H/back\\slash.cpp"
mkfn piFn     > "$H/pi|pe.cpp"
mkfn ddFn     > "$H/--dashdash.cpp"
mkfn nlFn     > "$H/a"$'\n'"b.cpp"
C c1

ID Real real@x.com Committer committer@x.com
D 2026-06-02T12:00:00; export GIT_COMMITTER_DATE="2026-06-03T09:00:00"   # author 06-02, committer 06-03
printf '// c2 edit\n' >> "$H/zeta.cpp"
C c2
unset GIT_COMMITTER_DATE

git -C "$H" checkout -q -b side
ID Sidedev side@x.com Sidedev side@x.com; D 2026-06-04T12:00:00
printf 'int cFn( int x )\n{\n    return x + 2;\n}\n'   > "$H/__C__"
printf 'int dotFn( int x )\n{\n    return x + 3;\n}\n' > "$H/__C__.cpp"
C s1

git -C "$H" checkout -q main
ID Real real@x.com Real real@x.com; D 2026-06-05T12:00:00
printf 'int cFn( int x )\n{\n    return x + 4;\n}\n'   > "$H/__C__"
printf 'int dotFn( int x )\n{\n    return x + 5;\n}\n' > "$H/__C__.cpp"
C m1

ID Real real@x.com Mergecommitter mergecommitter@x.com; D 2026-06-06T12:00:00
export GIT_COMMITTER_DATE="2026-06-07T08:00:00"
git -C "$H" merge --no-commit --no-ff side >/dev/null 2>&1 || true   # conflicts on both by construction
printf 'int cFn( int x )\n{\n    return x + 6;\n}\n'   > "$H/__C__"
printf 'int dotFn( int x )\n{\n    if( x > 1 ) return x + 7;\n    return x - 7;\n}\n' > "$H/__C__.cpp"
C "merge side (collision: first combined path is the file named __C__)"
unset GIT_COMMITTER_DATE

ID Real real@x.com Real real@x.com; D 2026-06-08T12:00:00
git -C "$H" commit -q --allow-empty -m c3

git -C "$H" checkout -q -b quiet
ID Quietdev quiet@x.com Quietdev quiet@x.com; D 2026-06-09T12:00:00
printf 'int alphaFn( int x )\n{\n    return x + 8;\n}\n' > "$H/Alpha.cpp"
C q1

git -C "$H" checkout -q main
ID Real real@x.com Real real@x.com; D 2026-06-10T12:00:00
printf 'int alphaFn( int x )\n{\n    return x + 9;\n}\n' > "$H/Alpha.cpp"
C m2

git -C "$H" checkout -q -b quiet2
ID Quietdev quiet2@x.com Quietdev quiet2@x.com; D 2026-06-11T12:00:00
printf '// q2 edit\n' >> "$H/zeta.cpp"
C q2
git -C "$H" checkout -q main
ID Real real@x.com Real real@x.com; D 2026-06-12T12:00:00
git -C "$H" merge -s ours --no-commit --no-ff quiet2 >/dev/null 2>&1 || true   # clean: main's tree wins
C "merge quiet2 (clean: -s ours, empty combined diff)"

ID Real real@x.com Mergecommitter mergecommitter@x.com; D 2026-06-13T12:00:00
git -C "$H" merge --no-commit --no-ff quiet >/dev/null 2>&1 || true   # conflicts on Alpha.cpp by construction
printf 'int alphaFn( int x )\n{\n    if( x > 1 ) return x + 10;\n    return x - 10;\n}\n' > "$H/Alpha.cpp"
C "merge quiet (name-bearing: resolves Alpha.cpp, first combined path is ordinary)"
UC

# ── THE HONEST FIXTURE (arm d) ─────────────────────────────────────────────────────────────────────
# A tree with NO hostile names. The claim under test: the new reader changes NOTHING here — the golden
# was recorded from the PRE-CHANGE binary over exactly this history. The fixture is byte-deterministic
# (every date, identity and message pinned), so its HEAD sha — and the golden's at= — are stable; a
# reader who moves a date must re-record the golden, which is the EXPIRY note above made concrete.
#   b1    Basedev  2026-06-01  Alpha.cpp, zeta.cpp, shared.cpp
#   s1    Sidedev  2026-06-02  on `side`: adds sidefile.cpp, appends shared.cpp
#   m1    Basedev  2026-06-03  on main: appends shared.cpp differently (a conflict on both sides)
#   MERGE author Mergeauthor, COMMITTER Mergecommitter 2026-06-04/05 — a name-bearing merge: resolves
#         the conflict with new content and adds mergeonly.cpp; its first combined path is ORDINARY
#   c2    Basedev  2026-06-06  appends Alpha.cpp and zeta.cpp
mkdir -p "$G"
git -C "$G" init -q -b main
CG(){ git -C "$G" add -A >/dev/null; git -C "$G" commit -qm "$1"; }
ID Basedev base@x.com Basedev base@x.com; D 2026-06-01T12:00:00
mkfn baseFn   > "$G/Alpha.cpp"
mkfn zetaFn   > "$G/zeta.cpp"
mkfn sharedFn > "$G/shared.cpp"
CG b1
git -C "$G" checkout -q -b side
ID Sidedev side@x.com Sidedev side@x.com; D 2026-06-02T12:00:00
mkfn branchFn > "$G/sidefile.cpp"
printf '// s1\n' >> "$G/shared.cpp"
CG s1
git -C "$G" checkout -q main
ID Basedev base@x.com Basedev base@x.com; D 2026-06-03T12:00:00
printf '// m1\n' >> "$G/shared.cpp"
CG m1
ID Mergeauthor mergeauthor@x.com Mergecommitter mergecommitter@x.com; D 2026-06-04T12:00:00
export GIT_COMMITTER_DATE="2026-06-05T08:00:00"   # author 06-04, committer 06-05
git -C "$G" merge --no-commit --no-ff side >/dev/null 2>&1 || true
mkfn mergeOnlyFn > "$G/mergeonly.cpp"
mkfn sharedFn    > "$G/shared.cpp"; printf '// resolved in the merge itself\n' >> "$G/shared.cpp"
CG "merge side (name-bearing)"
unset GIT_COMMITTER_DATE
ID Basedev base@x.com Basedev base@x.com; D 2026-06-06T12:00:00
printf '// c2\n' >> "$G/Alpha.cpp"; printf '// c2\n' >> "$G/zeta.cpp"
CG c2
UC

# ── THE TOOL'S ANSWERS ON THE HOSTILE FIXTURE ──────────────────────────────────────────────────────
"$BIN" --owners --detail=1 --limit=60 "$H" > "$TMP/owners.xml" 2>"$TMP/owners.err"; owners_rc=$?
"$BIN" --hotspots --limit=60 "$H" > "$TMP/hotspots.xml" 2>"$TMP/hotspots.err"
for fn in alphaFn dotFn zetaFn nlFn spoofFn; do
    "$BIN" --for=$fn "$H" > "$TMP/for-$fn.xml" 2>/dev/null
done

# ── ARM (a): the spoof is neutralized ──────────────────────────────────────────────────────────────
echo "arm a: the spoof is neutralized on the hostile fixture"
if [ "$owners_rc" = 0 ]; then ok "--owners exits 0 on the hostile fixture"
else no "--owners exits $owners_rc: $( head -1 "$TMP/owners.err" )"; fi
# rows start with `<f p="` — the schema comment spells `<f p= ` (no quote), so it never counts.
rows=$( tr '>' '\n' < "$TMP/owners.xml" | grep -c '<f p="' )
[ "$rows" = 11 ] && ok "all 11 indexed files get ownership rows (pre-change: 8 — four eaten as forged headers)" \
                 || no "expected 11 ownership rows, got $rows (pre-change: 8)"
# occurrences, not lines: the whole XML answer is ONE line, so grep -c would read 1 for five leaks.
forged=$( grep -o '="x"' "$TMP/owners.xml" | wc -l | tr -d ' ' )
[ "$forged" = 0 ] && ok 'the forged author "x" appears nowhere (pre-change: 5 rows top="x")' \
                 || no "the forged author survived in $forged places"
true_rows=$( tr '>' '\n' < "$TMP/owners.xml" | grep '<f p="' | grep -c 'top="real@x.com"' )
[ "$true_rows" = "$rows" ] && ok "every row names its true author real@x.com" \
                          || no "only $true_rows of $rows rows name real@x.com"
spoof_top=$( attr_of "$TMP/owners.xml" '__C__x|1694000000.cpp' top )
[ "$spoof_top" = "real@x.com" ] \
    && ok "__C__x|1694000000.cpp — the name that BECAME the forgery — is owned by its true author" \
    || no "__C__x|1694000000.cpp is owned by '$spoof_top'"

# ── ARM (b): the newline filename round-trips as ONE path ──────────────────────────────────────────
echo "arm b: the newline filename round-trips as ONE path"
nl_churn=$( churn_of_fn "$TMP/for-nlFn.xml" nlFn )
[ "$nl_churn" = 1 ] \
    && ok "a<LF>b.cpp has churn=1 — one path, one commit (a line frame splits it into 'a' and 'b.cpp')" \
    || no "a<LF>b.cpp churn='$nl_churn', want 1"
nl_top=$( attr_of "$TMP/owners.xml" 'a&#10;b.cpp' top )
[ "$nl_top" = "real@x.com" ] && ok "a<LF>b.cpp is owned by its true author" \
                             || no "a<LF>b.cpp is owned by '$nl_top'"
halves=$( tr '>' '\n' < "$TMP/owners.xml" | grep -cE '<f p="(a|b\.cpp)"' )
[ "$halves" = 0 ] && ok "no phantom rows for the split halves a / b.cpp" \
                  || no "$halves phantom row(s) for the split halves"

# ── ARM (c): the exact-marker file is a path, never a record opener ────────────────────────────────
echo "arm c: the exact-marker file is a path, never a record opener"
after_top=$( attr_of "$TMP/owners.xml" '__C__ 1694000000.cpp' top )
[ "$after_top" = "real@x.com" ] \
    && ok "__C__ 1694000000.cpp — sorting immediately after __C__ — keeps its true author" \
    || no "__C__ 1694000000.cpp is owned by '$after_top'"
dot_top=$( attr_of "$TMP/owners.xml" '__C__.cpp' top )
[ "$dot_top" = "real@x.com" ] && ok "__C__.cpp keeps its true author" \
                             || no "__C__.cpp is owned by '$dot_top'"

# ── ARM (c2): the single-file pathspec seam ─────────────────────────────────────────────────────────
# gitLogRecordsCmd assembles `... -c <extraArgs>-z --name-only ...`, so ANY extraArgs a consumer appends
# must carry its own trailing space. gitFileAuthors' --owners=SYM form appends a pathspec (`-- <relpath>`);
# without that space the shell reads the pathspec and the -z as ONE word (`-- 'shared.cpp'-z`), git matches
# a file that does not exist, and the walk answers EMPTY — which surfaces as "git unavailable / no history",
# not as a broken command. Measured on the seam-broken build: --owners=sharedFn exited 1 with exactly that
# sentence while the all-files form beside it answered normally. This arm is the pin.
echo "arm c2: the single-file pathspec seam — --owners=SYM must reach its file"
"$BIN" --owners=sharedFn --detail=1 --no-cache "$G" > "$TMP/owners-sym.xml" 2>"$TMP/owners-sym.err"; sym_rc=$?
[ "$sym_rc" = 0 ] && ok "--owners=sharedFn exits 0 (the seam-broken build exited 1: 'git unavailable / no history')" \
                  || no "--owners=sharedFn exits $sym_rc: $( head -1 "$TMP/owners-sym.err" )"
grep -q 'git unavailable' "$TMP/owners-sym.err" \
    && no "--owners=SYM answered 'git unavailable / no history' — the pathspec never reached git" \
    || ok "no 'git unavailable' on the SYM form"
grep -q '<owners [^>]*of="sharedFn"' "$TMP/owners-sym.xml" \
    && ok 'the SYM form echoes its selector in of=' \
    || no 'the SYM form does not echo of="sharedFn"'
sym_p=$( tr '>' '\n' < "$TMP/owners-sym.xml" | grep -oE '<f p="[^"]*"' | head -1 )
[ "$sym_p" = '<f p="shared.cpp"' ] && ok 'the SYM form reports shared.cpp — the file holding the definition' \
                                   || no "the SYM form reports '$sym_p', want <f p=\"shared.cpp\""

# ── ARM (f): an empty METADATA field is data, not framing ──────────────────────────────────────────
# PR #433 review (Major): the empty-field branch ran before the metadata state machine, so a
# legitimately empty %ae was eaten as a merge prefix and the record shifted wholesale. The guard:
# an empty is framing only when no marker is pending and no metadata is owed. One-commit fixture,
# empty-email author, ordinary committer — pre-fix the record is pathless and plain.cpp gets no row.
echo "arm f: an empty %ae is metadata — the file keeps its attribution"
mkdir -p "$E"
git -C "$E" init -q -b main
ID Cm cm@x.com Cm cm@x.com; D 2026-06-14T12:00:00
mkfn emptyMailFn > "$E/plain.cpp"
git -C "$E" add -A >/dev/null
git -C "$E" commit -qm "e1: empty-email author" --author="No Email <>" >/dev/null
UC
"$BIN" --owners=emptyMailFn --detail=1 --no-cache "$E" > "$TMP/owners-empty.xml" 2>"$TMP/owners-empty.err"; e_rc=$?
[ "$e_rc" = 0 ] && ok "--owners=emptyMailFn exits 0" \
               || no "--owners=emptyMailFn exits $e_rc: $( head -1 "$TMP/owners-empty.err" )"
e_p=$( tr '>' '\n' < "$TMP/owners-empty.xml" | grep -oE '<f p="[^"]*"' | head -1 )
[ "$e_p" = '<f p="plain.cpp"' ] \
    && ok 'plain.cpp is reported — the empty-email record kept its path (pre-fix: pathless, no row)' \
    || no "the empty-email record lost its path (got '${e_p:-nothing}')"
"$BIN" --for=emptyMailFn --detail=1 --no-cache "$E" > "$TMP/for-empty.xml" 2>/dev/null
e_churn=$( churn_of_fn "$TMP/for-empty.xml" "emptyMailFn" )
[ "$e_churn" = "1" ] \
    && ok 'plain.cpp churn=1 — the empty-email commit counts for its own file' \
    || no "plain.cpp churn='$e_churn', want 1 (pre-fix: no row, no churn)"

# ── ARM (g): a merge whose FIRST combined path only STARTS WITH the marker stays attached ──────────
# rv-pr433 (mutant survivor): the boundary rule compares the field after an empty to the marker as a
# WHOLE field. A merge's prefix empty is the one place a path follows an empty, so a prefix compare
# (the old frame's spelling, `rfind( "__C__", 0 )`) would read a merge whose first combined path is
# `__C__.cpp` as a record boundary and drop the merge's files. The hostile fixture's merges cannot see
# that: MERGE's first path IS `__C__` (the disclosed collision) and M2's is `Alpha.cpp`. Fixture: one
# file `__C__.cpp`, conflicting edits on two branches, a merge that resolves it with new content —
# authors base, side, main, merger (4). Red on a prefix-compare mutant (authors=3, merger missing).
echo "arm g: a merge whose first combined path starts with the marker bytes keeps its files"
P="$( mktemp -d )"; trap 'rm -rf "$TMP" "$H" "$G" "$E" "$P"' EXIT
git -C "$P" init -q -b main
ID Base base@x.com Base base@x.com; D 2026-06-15T12:00:00
mkfn pfxFn > "$P/__C__.cpp"; git -C "$P" add -A >/dev/null; git -C "$P" commit -qm "p1" >/dev/null
git -C "$P" checkout -q -b side
ID Side side@x.com Side side@x.com; D 2026-06-16T12:00:00
echo '// side' >> "$P/__C__.cpp"; git -C "$P" commit -qam "p2 side" >/dev/null
git -C "$P" checkout -q main
ID Main main@x.com Main main@x.com; D 2026-06-17T12:00:00
echo '// main' >> "$P/__C__.cpp"; git -C "$P" commit -qam "p3 main" >/dev/null
ID Merger merger@x.com Merger merger@x.com; D 2026-06-18T12:00:00
git -C "$P" merge -q --no-ff side -m "PM" >/dev/null 2>&1 || true
mkfn pfxFn > "$P/__C__.cpp"; echo '// resolved' >> "$P/__C__.cpp"
git -C "$P" add -A >/dev/null; git -C "$P" commit -qm "PM" >/dev/null
UC
g_first=$( "$REAL_GIT" -C "$P" log -1 -c --no-ext-diff --no-textconv --name-only --format= HEAD | head -1 )
[ "$g_first" = "__C__.cpp" ] && ok "premise: the merge's first combined path is __C__.cpp" \
                              || no "premise lost: the merge's first combined path is '$g_first', want __C__.cpp"
"$BIN" --owners --detail=1 --no-cache "$P" > "$TMP/owners-pfx.xml" 2>"$TMP/owners-pfx.err"; g_rc=$?
g_auth=$( attr_of "$TMP/owners-pfx.xml" '__C__.cpp' authors )
[ "$g_rc" = 0 ] && [ "$g_auth" = 4 ] \
    && ok "__C__.cpp has 4 authors — the merge that resolved it is attached (prefix compare: 3)" \
    || no "__C__.cpp authors='$g_auth' rc=$g_rc, want 4 — the merge's files were dropped"

# ── ARM (d): the honest tree is byte-identical to the pre-change golden ────────────────────────────
echo "arm d: the honest tree is byte-identical to the golden recorded from the PRE-CHANGE binary"
{
    echo "===== owners";   "$BIN" --owners --detail=1 --limit=60 "$G"; echo
    echo "===== hotspots"; "$BIN" --hotspots --limit=60 "$G"; echo
    echo "===== cochange"; "$BIN" --cochange "$G"; echo
} | sed 's/root="[^"]*"/root="FIXTURE"/' > "$TMP/golden.new"
if cmp -s "$GOLD" "$TMP/golden.new"; then
    ok "owners+hotspots+cochange byte-identical to test/gitframingcheck_golden.txt (root= normalized)"
else
    no "honest-tree drift from the golden:"; diff "$GOLD" "$TMP/golden.new" | head -10
fi

# ── ARM (e): the marker literal lives ONLY inside the shared helper ────────────────────────────────
echo "arm e: the marker literal lives ONLY inside the shared helper"
code_hits=$( code_only "$SRC" | grep -o '__C__' | wc -l | tr -d ' ' )
[ "$code_hits" = 2 ] \
    && ok "exactly 2 non-comment __C__ occurrences in src/gitmine.h" \
    || no "$code_hits non-comment __C__ occurrences in src/gitmine.h, want 2"
const_line=$( code_only "$SRC" | grep -c 'kGitLogMarker = "__C__"' )
fmt_line=$( code_only "$SRC" | grep -c 'format=%x00__C__%x00%ae%x00%at%x00%ct' )
if [ "$const_line" = 1 ] && [ "$fmt_line" = 1 ]; then
    ok "the two sites are the kGitLogMarker constant and the shared command's --format= — no consumer body carries the marker"
else
    no "the marker's code sites moved: constant=$const_line format=$fmt_line"
fi
tformat_hits=$( code_only "$SRC" | grep -o 'tformat:' | wc -l | tr -d ' ' )
[ "$tformat_hits" = 0 ] && ok "the old line-frame spellings (tformat:__C__…) are gone from the code" \
                       || no "$tformat_hits tformat: marker(s) remain in code"

# ── ARM 2: the raw stream is byte-pinned ───────────────────────────────────────────────────────────
echo "arm 2: the raw stream the reader parses is byte-pinned"
# The reader's contract is a BYTE layout, so the layout itself is pinned: the exact command
# gitLogRecordsCmd builds (its prefix flags — --no-optional-locks, the fsmonitor/signature pins and the
# driver pins — govern the index and the worktree, never `log` output, so plain git reproduces it).
"$REAL_GIT" -c core.quotepath=false -C "$H" log --no-ext-diff --no-textconv -c \
    -z --name-only --format='%x00__C__%x00%ae%x00%at%x00%ct' 2>/dev/null > "$TMP/raw.z"
digest=$( python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$TMP/raw.z" )
[ "$digest" = 9a11263860e97452932460b72c9eca9020a6ad01b1d29ceba917f1db1167796c ] \
    && ok "the stream is byte-identical to the pinned digest" \
    || no "raw-stream digest drifted: $digest"
# Fields that spell the marker EXACTLY (NUL-delimited, so a '\n'-prefixed first path does not count):
# 11 record openers + 2 paths — c1's mid-list `__C__` (not first in byte order, hence no '\n' prefix)
# and the collision merge's bare first path.
fields=$( python3 -c '
import sys
d = open( sys.argv[1], "rb" ).read()
needle = b"\x00__C__\x00"
n = 0
i = d.find( needle )
while i >= 0:
    n += 1
    i = d.find( needle, i + 1 )
print( n )' "$TMP/raw.z" )
[ "$fields" = 13 ] \
    && ok "13 NUL-delimited fields spell the marker: 11 record openers + 2 marker-spelled paths" \
    || no "marker-spelled fields: $fields, want 13"

# ── ARM 3: the merge shapes — the lookahead is load-bearing, the collision is pinned ────────────────
echo "arm 3: the merge shapes"
alpha_churn=$( churn_of_fn "$TMP/for-alphaFn.xml" alphaFn )
[ "$alpha_churn" = 4 ] \
    && ok "M2's name-bearing merge ATTACHES Alpha.cpp (churn=4; a parser without the one-field lookahead reads the merge's prefix empty as a boundary and drops its files — 3)" \
    || no "alphaFn churn='$alpha_churn', want 4 — the lookahead is not attaching merge paths"
dot_churn=$( churn_of_fn "$TMP/for-dotFn.xml" dotFn )
[ "$dot_churn" = 3 ] \
    && ok "the disclosed collision is pinned: the collision merge's __C__.cpp is dropped (churn=3, not 4)" \
    || no "dotFn churn='$dot_churn', want 3 — the collision's observable moved"
hs_dot=$( attr_of "$TMP/hotspots.xml" '__C__.cpp' churn )
[ "$hs_dot" = 4 ] \
    && ok "the two miners disagree there BY DESIGN: --hotspots rides the unmigrated gitCommandLines miner and still counts the collision merge's file (4)" \
    || no "--hotspots __C__.cpp churn='$hs_dot', want 4 — the documented disagreement moved, re-derive"

# ── ARM 4: ownership answers with the AUTHOR, never the committer ──────────────────────────────────
echo "arm 4: author-not-committer"
zeta_top=$( attr_of "$TMP/owners.xml" 'zeta.cpp' top )
[ "$zeta_top" = "real@x.com" ] \
    && ok "zeta.cpp is owned by its author real@x.com — c2's committer was Committer <committer@x.com> and the merges' Mergecommitter <mergecommitter@x.com>" \
    || no "zeta.cpp is owned by '$zeta_top'"
committers=$( grep -oE 'committer@x\.com|mergecommitter@x\.com' "$TMP/owners.xml" | wc -l | tr -d ' ' )
[ "$committers" = 0 ] && ok "no committer email appears as an owner anywhere" \
                      || no "$committers committer-email leak(s) in the owners output"
zeta_authors=$( attr_of "$TMP/owners.xml" 'zeta.cpp' authors )
[ "$zeta_authors" = 2 ] \
    && ok "zeta.cpp has exactly 2 authors (real + quiet2; the committers of c2 and the merges do not count)" \
    || no "zeta.cpp authors='$zeta_authors', want 2"

# ── ARM 5: non-vacuity — the fixture is what the arms claim ────────────────────────────────────────
echo "arm 5: non-vacuity — the fixture is what the arms claim"
tracked=$( git -C "$H" ls-files | wc -l | tr -d ' ' )
[ "$tracked" = 12 ] \
    && ok "12 tracked files: the 11 indexed plus the extension-less __C__ (unindexed BY DESIGN, layout-pin Finding 1)" \
    || no "tracked files: $tracked, want 12"
marker_tracked=$( git -C "$H" ls-files | grep -cx '__C__' )
[ "$marker_tracked" = 1 ] && ok "a file named exactly __C__ is tracked — the name the frame must survive" \
                          || no "the marker-named file is not tracked ($marker_tracked)"
files_n=$( grep -oE 'files="[0-9]+"' "$TMP/owners.xml" | head -1 | grep -oE '[0-9]+' )
[ "$files_n" = 11 ] \
    && ok "--owners analysed 11 files (files=11)" \
    || no "owners files=$files_n, want 11"
ranked=$( grep -oE 'ranked="[0-9]+"' "$TMP/hotspots.xml" | head -1 | grep -oE '[0-9]+' )
unranked=$( grep -oE 'unranked_no_complexity="[0-9]+"' "$TMP/hotspots.xml" | head -1 | grep -oE '[0-9]+' )
[ "$ranked" = 11 ] && [ "$unranked" = 0 ] \
    && ok "--hotspots ranked all 11 files (every fixture file carries a branch, so nothing is unranked_no_complexity)" \
    || no "--hotspots ranked=$ranked unranked_no_complexity=$unranked, want 11/0"

# ── ARM 6: determinism ─────────────────────────────────────────────────────────────────────────────
echo "arm 6: determinism — the reader's answers do not move between runs"
"$BIN" --owners --detail=1 --limit=60 "$H" > "$TMP/owners2.xml" 2>/dev/null
"$BIN" --hotspots --limit=60 "$H" > "$TMP/hotspots2.xml" 2>/dev/null
if cmp -s "$TMP/owners.xml" "$TMP/owners2.xml" && cmp -s "$TMP/hotspots.xml" "$TMP/hotspots2.xml"; then
    ok "two runs byte-identical (owners + hotspots)"
else
    no "the answers moved between runs"
fi

# ── ARM 7: the oracle — the tool's number re-derived from git's own stream ─────────────────────────
echo "arm 7: the oracle"
# Trap #12: a number the tool agrees with itself about is not evidence. Re-derive Alpha.cpp's churn
# straight from git's own --name-only stream: every combined diff that lists it. (tr turns each NUL
# into a line end, which also splits git's '\n'-prefixed first paths — exactly the fields counted.)
oracle=$( "$REAL_GIT" -c core.quotepath=false -C "$H" log --no-ext-diff --no-textconv -c \
    -z --name-only --format='%x00__C__%x00' 2>/dev/null | tr '\0' '\n' | grep -cx 'Alpha.cpp' )
[ "$oracle" = "$alpha_churn" ] \
    && ok "git's own stream lists Alpha.cpp $oracle times = the --for churn of $alpha_churn" \
    || no "oracle=$oracle, tool=$alpha_churn — the tool's number does not re-derive from git"

# ── ARM 8: the git floor, and a git that cannot frame degrades honestly ────────────────────────────
echo "arm 8: the git floor, and a git that rejects -z degrades honestly"
git_ver=$( git --version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 )
gmaj=${git_ver%%.*}; gmin=${git_ver#*.}; gmin=${gmin%%.*}
if [ "$gmaj" -gt 2 ] || { [ "$gmaj" -eq 2 ] && [ "$gmin" -ge 43 ]; }; then
    ok "git $git_ver >= 2.43.0 — the layout-pin floor (the '\n' separator, the merge prefix empty and the end-of-stream unterminated field are empirical; below the floor the pinned layout is unverified)"
else
    no "git $git_ver is below the 2.43.0 floor — the pinned layout is unverified on this git"
fi
# A git that refuses -z: the reader must degrade HONESTLY — no fabricated rows, no silent half-answer.
SHIM="$TMP/shim"; mkdir -p "$SHIM"
cat > "$SHIM/git" <<'SHIM'
#!/usr/bin/env bash
for a in "$@"; do
    if [ "$a" = "-z" ]; then
        echo "git: the -z flag is not supported here" >&2
        : > "$SHIM_DIR/rejected-z"   # proof the -z rejection itself ran (not some other reason git was unavailable)
        exit 129
    fi
done
exec "$REAL_GIT" "$@"
SHIM
chmod +x "$SHIM/git"
export SHIM_DIR="$SHIM"
# PREMISE: the shim must hand every call WITHOUT -z to the real git (repository discovery, rev-parse), or the
# degrade below could pass because the shim broke git entirely rather than because git rejected -z.
if PATH="$SHIM:$PATH" git -C "$H" rev-parse --git-dir >/dev/null 2>&1 && [ ! -e "$SHIM/rejected-z" ]; then
    ok "premise: the -z-rejecting shim delegates a call without -z to the real git"
else
    no "premise: the -z-rejecting shim does not delegate a plain git call (REAL_GIT not exported to the shim?)"
fi
PATH="$SHIM:$PATH" "$BIN" --owners --detail=1 --limit=60 "$H" > "$TMP/shim.xml" 2>"$TMP/shim.err"; shim_rc=$?
[ -e "$SHIM/rejected-z" ] && ok "the shim saw a -z call and rejected it: the degrade below is the -z rejection, not an unavailable git" \
                          || no "the shim never saw a -z call: the degrade below proves nothing about -z"
[ "$shim_rc" != 0 ] && ok "a git that rejects -z: --owners exits $shim_rc (non-zero)" \
                    || no "a git that rejects -z: --owners exited 0 — a silent half-answer"
shim_rows=$( tr '>' '\n' < "$TMP/shim.xml" | grep -c '<f p="' )
[ "$shim_rows" = 0 ] && ok "no ownership rows are fabricated when the stream cannot be framed" \
                    || no "$shim_rows rows fabricated from an unframable stream"
if grep -q 'git unavailable / no history' "$TMP/shim.err"; then
    ok "the degrade is HONEST: 'git unavailable / no history' on stderr"
else
    no "the degrade is silent: $( head -1 "$TMP/shim.err" )"
fi

# 9. A NON-EMPTY stream with no record marker is UNREAD, not "read, no history" (CodeRabbit 4419234614). A git that
#    exits 0 yet prints bare name-only lines (a PATH shim, a git answering in its default format) leaves the walk
#    with no record to visit; before the fix GitLogWalk::unread stayed false and --for printed a clean answer built on
#    an empty history. The raw-stream consumer (churn=/amp=) carries the flag into history_unread="1"; the four
#    visitor consumers still discard the walk (historyread.h NOT COVERED, a documented K51 deferral).
BSHIM="$TMP/bshim"; mkdir -p "$BSHIM"; BTMP="$TMP/btmp"; BCTL="$TMP/bctl"; mkdir -p "$BTMP" "$BCTL"
cat > "$BSHIM/git" <<'BSHIMEOF'
#!/usr/bin/env bash
want_z=0; want_name_only=0
for a in "$@"; do
    [ "$a" = "-z" ] && want_z=1
    [ "$a" = "--name-only" ] && want_name_only=1
done
if [ "$want_z" = 1 ] && [ "$want_name_only" = 1 ]; then
    : > "$BSHIM_DIR/bare-served"
    printf 'Alpha.cpp\nzeta.cpp\n'      # exit 0, non-empty, no __C__ field anywhere
    exit 0
fi
exec "$REAL_GIT" "$@"
BSHIMEOF
chmod +x "$BSHIM/git"
export BSHIM_DIR="$BSHIM"
TMPDIR="$BCTL" "$BIN" --for=alphaFn --no-cache "$H" > "$TMP/bare-ctl.xml" 2>/dev/null
if grep -q ' churn="[0-9]' "$TMP/bare-ctl.xml" && ! grep -q 'history_unread' "$TMP/bare-ctl.xml"; then
    ok "arm 9 control: with the real git --for prints churn= and no history_unread"
else
    no "arm 9 control: the unshimmed --for answer has no churn= or already says history_unread: $( head -c 200 "$TMP/bare-ctl.xml" )"
fi
TMPDIR="$BTMP" PATH="$BSHIM:$PATH" "$BIN" --for=alphaFn --no-cache "$H" > "$TMP/bare.xml" 2>/dev/null; bare_rc=$?
[ -e "$BSHIM/bare-served" ] && ok "arm 9 premise: the shim served a bare name-only stream (exit 0, non-empty, no marker)" \
                            || no "arm 9 premise: the shim never served a bare stream — the arm below proves nothing"
if [ "$bare_rc" = 0 ] && grep -q ' history_unread="1"' "$TMP/bare.xml"; then
    ok "a non-empty marker-less stream is UNREAD: --for says history_unread=\"1\""
else
    no "a non-empty marker-less stream read as an empty history (rc=$bare_rc): $( head -c 200 "$TMP/bare.xml" )"
fi
grep -q ' churn="[0-9]' "$TMP/bare.xml" \
    && no "a marker-less stream still printed a churn= value" \
    || ok "no churn= value is printed from a marker-less stream"

# ── SUMMARY ────────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" = 0 ]; then
    echo "gitframingcheck: ALL PASS"
else
    echo "gitframingcheck: FAIL"
fi
exit "$fail"
