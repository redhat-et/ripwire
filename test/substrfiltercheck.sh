#!/usr/bin/env bash
# substrfiltercheck.sh — H7 (capture-audit 2026-09-04, lens 6 F9, lens 7 F-DYM-1): a SCOPING FILTER that
# selects nothing refuses; it never reports the empty selection as a measurement of the repo.
#
# THE DEFECT. `--flags=zzzznosuch` answered `<flags gates="0" dark_gates="0" … files="1550">` at exit 0, and
# `--stray-content=zzzznosuchref` answered `<stray-content refs="0" … unknown="0">` at exit 0. Both zeros
# read identically to the true and interesting facts "this repo has no dark gates" and "no branch carries
# stray work" — which is exactly the reading an agent takes, because the root even carries the scan
# denominator (files="1550", 189 refs scanned) to prove the sweep really ran. Two of their siblings had
# already been fixed and carry the wording this gate pins:
#
#   --dead-code=nosuchdir → "matches no indexed path — a zero here would be a failure, not a measurement"
#   --doc-drift=zzz       → "matches no document — an exit 0 under a filter that owns nothing is a failure"
#   --scope=zzz/**        → "matches no indexed path — an exit 0 under a scope that owns nothing is a failure"
#
# THE FAMILY. A `--verb=SUBSTR` scoping filter is a verb whose argument NARROWS what the verb would
# otherwise sweep repo-wide (the bare spelling runs everything). Enumerated from the flag table: --dead-code,
# --doc-drift, --scope, --flags, --stray-content. All five are asserted here; --dead-code / --doc-drift /
# --scope pass before and after, and are in the gate because the property is the family's, not the two
# broken members'.
#
# NOT in the family, deliberately, and each for a stated reason:
#   --grep=STR / --regex   a literal text scan over file bytes IS the measurement; hits="0" is its answer.
#   --for / --recall       ranked queries whose every name resolved; they disclose reason="no_candidates".
#   --exclude=GLOB         a SUBTRACTIVE filter — matching nothing is a no-op, not an empty selection.
#
# ARM D covers the same standing rule on the text-selector side (lens 6 F5): `--whereis=<one-edit typo>`
# answered hits="0" with no did-you-mean while every other symbol verb one keystroke away offers one, and
# `--whereis=@src/graph.h:999999` searched the literal string "@src/graph.h:999999" across every blob
# instead of resolving the documented @FILE:LINE seed grammar the sibling selectors resolve.
#
# RED-FIRST (base binary ec5e3c3): A/B fail on --flags and --stray-content, D fails on both whereis arms.
#
# ARM E (MAIN-LOCAL-REDS, 2026-11-13; CROSSREF-MAXREFS) covers the sweep verbs past 512 local branches (crossref kMaxRefs).
# They refused there ("is not a git repository", then the cap's name); now they read the newest 512 by committer date and the
# root's refs_omitted= counts the rest. ARM H is the same at 4,096 branches. RED-FIRST (c6802ebdc): E1, E3-E7 and H1-H4 fail;
# E0, E2 and H0 hold on both binaries.
#
# Usage:  bash test/substrfiltercheck.sh [BIN]   |   RIPWIRE_BIN=build_base/ripwire bash test/…
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "substrfiltercheck: BIN=$BIN  CORPUS=$ROOT"

MISS="zzzznosuchfilterxyz"

# R3 (verify-wave1): the --stray-content probes run against a THROWAWAY repo with a known `lane/probe` ref
# (test/lib/strayfixture.sh), never against this checkout — `lives --stray-content lane` on the operator's own
# branches was green only where a lane/* head happened to exist. refuses_empty/lives take the corpus from
# $CORPUS, which defaults to this repo and is pointed at the fixture for that one flag.
. "$ROOT/test/lib/strayfixture.sh"
SFIX="$( mktemp -d )"; EFIX="$( mktemp -d )"; trap 'rm -rf "$SFIX" "$EFIX"' EXIT
mkStrayFixture "$SFIX"
strayFixtureHasRef "$SFIX" \
    && ok "fixture: throwaway repo carries a lane/* ref for --stray-content=lane to select" \
    || { no "fixture: no lane/* ref in the throwaway repo — the --stray-content arms below would prove nothing"; echo "FAILURES ABOVE"; exit 1; }
CORPUS="$ROOT"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== A/B: a scoping filter that owns nothing REFUSES, naming the flag and the value ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
refuses_empty(){ # $1 = flag, $2 = value, $3.. = the host verb, when the filter is a modifier rather than a verb
    local flag="$1" val="$2"; shift 2
    local out rc
    out="$( "$BIN" "$CORPUS" "$flag=$val" "$@" --no-cache 2>&1 1>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ]; then
        ok "A $flag=$val → exit $rc"
    else
        no "A $flag=$val → exit 0 — an empty SELECTION was reported as a measurement of the repo"
    fi
    if printf '%s' "$out" | grep -qF -- "$flag" && printf '%s' "$out" | grep -qF -- "$val"; then
        ok "B $flag: refusal names the flag and echoes the value"
    else
        no "B $flag: refusal names neither flag nor value: $out"
    fi
    if printf '%s' "$out" | grep -qiE "not a (measurement|clean tree)|is a failure"; then
        ok "C $flag: says WHY a zero would not have been an answer"
    else
        no "C $flag: no 'a zero here would be a failure' clause (the wording --dead-code/--doc-drift set): $out"
    fi
}
refuses_empty --dead-code     "$MISS"
refuses_empty --doc-drift     "$MISS"
refuses_empty --scope         "$MISS/**" --quality-delta   # a MODIFIER, so it is probed on its host verb
refuses_empty --flags         "$MISS"
CORPUS="$SFIX" refuses_empty --stray-content "$MISS"
# wave-3 close (2026-09-05): --stray-content=SUBSTR is also the FILTER of two host verbs, --plan and --abi. Both
# already refused a no-match filter (exit 1) but with the WRONG sentence — "more than 512 refs match — narrow it"
# for a filter that matched ZERO refs (the zero-hit case fell into the else of a two-way ok/nonGitRoot split;
# only the bare verb had H7's branch). Found by the close regen: `--stray-content=r27 --plan` on a tree with no
# r27 ref. RED on 41d831b: B (the value is not echoed) and C (no "not a measurement" clause) for both hosts.
CORPUS="$SFIX" refuses_empty --stray-content "$MISS" --plan
CORPUS="$SFIX" refuses_empty --stray-content "$MISS" --abi

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== the negative: a filter that DOES own something still answers ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
lives(){ # $1 = flag, $2 = value, $3.. = host verb / expected-exit override
    local flag="$1" val="$2"; shift 2
    local rc
    "$BIN" "$CORPUS" "$flag=$val" "$@" --no-cache >/dev/null 2>&1; rc=$?
    # --quality-delta's own exit code is its gate (2 = gating findings), so only the REFUSAL code is a failure
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
        ok "$flag=$val → exit $rc (a real selection still answers)"
    else
        no "$flag=$val → exit $rc; the refusal swallowed a working filter"
    fi
}
lives --dead-code     src
lives --doc-drift     README
lives --scope         'src/**' --quality-delta
lives --flags         RIPWIRE
CORPUS="$SFIX" lives --stray-content lane
CORPUS="$SFIX" lives --stray-content lane --plan
CORPUS="$SFIX" lives --stray-content lane --abi

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== D: --whereis is a SYM selector — near-miss suggestion + @FILE:LINE seed resolution ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# --whereis scans every ref's TREE, so it would find this script's own text if the probes ran against this
# repo: the typo below is a literal in this file, and the repo IS the corpus. A throwaway git fixture keeps
# the arm about the verb instead of about the gate.
WFIX="$( mktemp -d )"
printf 'int helperOne( int x ) { return x + 1; }\nint sturdyTeleport( int x ) { return helperOne( x ); }\nint tailer( int x ) { return sturdyTeleport( x ); }\n' > "$WFIX/one.cpp"
( cd "$WFIX" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1

# (a) a one-edit typo of an indexed symbol names it. The lexical tree scan is a legitimate measurement for a
#     name this repo never had, so the ZERO stays an answer — but the index knows the near-miss and every
#     other SYM verb says so, and a hits="0" the reader cannot distinguish from a typo is worth one clause.
OUT="$( "$BIN" "$WFIX" --whereis=sturdyTeleporr --no-cache 2>&1 )"
if printf '%s' "$OUT" | grep -qE "did you mean 'sturdyTeleport'|retry=\"sturdyTeleport\""; then
    ok "D --whereis=<one-edit typo> names the near-miss sturdyTeleport"
else
    no "D --whereis=<one-edit typo>: hits=0 with no did-you-mean, and the index knows the name: $( printf '%s' "$OUT" | grep -o '<whereis [^>]*>' )"
fi

# (b) the documented @FILE:LINE seed grammar is RESOLVED, not searched as a literal. A bad line refuses with
#     the shared seed message (--owners/--mentions/--edit-check already do); it must never come back as a
#     true-but-useless hits="0" over every blob.
OUT="$( "$BIN" "$WFIX" '--whereis=@one.cpp:999999' --no-cache 2>&1 1>/dev/null )"; RC=$?
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -qF "one.cpp"; then
    ok "D --whereis=@one.cpp:999999 refuses on the bad line, naming the file"
else
    no "D --whereis=@one.cpp:999999 → exit $RC; the seed was searched as a literal string instead of resolved: $OUT"
fi

# (c) a REAL @FILE:LINE seed resolves to the enclosing definition and is answered under that name.
OUT="$( "$BIN" "$WFIX" '--whereis=@one.cpp:2' --no-cache 2>/dev/null )"
if printf '%s' "$OUT" | grep -qF 'sym="sturdyTeleport"'; then
    ok "D --whereis=@one.cpp:2 resolves to sym=\"sturdyTeleport\""
else
    no "D --whereis=@one.cpp:2 did not resolve the seed: $( printf '%s' "$OUT" | grep -o '<whereis [^>]*>' )"
fi
rm -rf "$WFIX"

# ── E: a repository with more than 512 local branches IS a git repository, and its sweep answers ─────────────────────────
# A long-lived clone with hundreds of lane branches passes the ref window (the operator's checkout this was found in: 518
# heads), and a linked worktree shares its branches. The sweep verbs refused there (#651 named the cap instead of "not a git
# repository"); CROSSREF-MAXREFS made them ANSWER: past crossref kMaxRefs (512) they read the newest refs by committer date and
# the root's refs_omitted= counts the rest. The fixture: 513 branches with DISTINCT tips, b001 the oldest and b513 the newest
# (a branch at HEAD's sha is not swept, so it would not count), asked from the main checkout and from a linked worktree (.git
# a file). RED-FIRST (c6802ebdc, the refusal): E1 and E3-E7 fail; E0 and E2 hold on both binaries.
EGIT(){ git -c user.name=Dev -c user.email=dev@x.com -c commit.gpgsign=false "$@"; }
EGIT -C "$EFIX" init -q main
printf 'int capProbe( int x ) { return x + 1; }\n' >"$EFIX/main/cap.cpp"
EGIT -C "$EFIX/main" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" EGIT -C "$EFIX/main" commit -qm init
ETREE="$( git -C "$EFIX/main" rev-parse 'HEAD^{tree}' )"; EHEAD="$( git -C "$EFIX/main" rev-parse HEAD )"
for i in $( seq -w 1 513 ); do
    edate="$(( 1780318800 + 60 * 10#$i )) +0000"   # 2026-06-01T13:00Z plus i minutes: b001 the oldest branch, b513 the newest
    tip="$( GIT_AUTHOR_NAME=Dev GIT_AUTHOR_EMAIL=dev@x.com GIT_COMMITTER_NAME=Dev GIT_COMMITTER_EMAIL=dev@x.com \
            GIT_AUTHOR_DATE="$edate" GIT_COMMITTER_DATE="$edate" git -C "$EFIX/main" commit-tree "$ETREE" -p "$EHEAD" -m "b$i" )"
    printf 'create refs/heads/b%s %s\n' "$i" "$tip"
done | git -C "$EFIX/main" update-ref --stdin
EGIT -C "$EFIX/main" worktree add -q "$EFIX/linked" b001 2>/dev/null
# E0 the premise, counted: more than 512 branches whose tip is not HEAD's, and the linked root's .git is a FILE.
ESWEPT="$( git -C "$EFIX/main" for-each-ref refs/heads --format='%(objectname)' | grep -vcF "$EHEAD" )"
if [ "$ESWEPT" -gt 512 ] && [ -f "$EFIX/linked/.git" ]; then
    ok "E0 fixture: $ESWEPT branches off HEAD's sha (window 512), and a linked worktree whose .git is a file"
else
    no "E0 fixture: $ESWEPT branches off HEAD's sha, linked .git a file: $( [ -f "$EFIX/linked/.git" ] && echo yes || echo no ) — E1-E6 would prove nothing"
fi
# The root element of an answer (its first <whereis / <stray-content / <stray-eval tag).
eroot(){ printf '%s' "$1" | grep -o "<$2 [^>]*>" | head -1; }
# E1 the CLI --whereis answers from both roots: 513 refs besides HEAD, 511 read with HEAD in the window of 512, 2 counted.
for eroot_dir in main linked; do
    OUT="$( "$BIN" "$EFIX/$eroot_dir" --whereis=capProbe --no-cache 2>"$EFIX/e1.err" )"; RC=$?
    ROOTEL="$( eroot "$OUT" whereis )"
    if [ "$RC" -eq 0 ] && printf '%s' "$ROOTEL" | grep -qF 'refs_scanned="511"' && printf '%s' "$ROOTEL" | grep -qF 'refs_omitted="2"' \
       && ! printf '%s' "$ROOTEL" | grep -qF 'complete="1"' && printf '%s' "$OUT" | grep -qF 'refs_omitted=K'; then
        ok "E1 --whereis over 513 branches ($eroot_dir root) answers: refs_scanned=511 refs_omitted=2, no complete=, the reading rides"
    else
        no "E1 --whereis over 513 branches ($eroot_dir root) → exit $RC: ${ROOTEL:-$( head -c 300 "$EFIX/e1.err" )}"
    fi
done
# One fresh MCP session per call (initialize, then tools/call); prints the tools/call reply line.
emcp(){ printf '%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
        | "$BIN" --mcp 2>/dev/null | grep -F '"id":2'; }   # status: the tools/call reply line is the verdict (error vs document), asserted by each caller
# E2 control: the MCP whereis kind= filter narrows under the window, so nothing is omitted (holds on both binaries).
OUT="$( emcp whereis "{\"path\":\"$EFIX/linked\",\"symbol\":\"capProbe\",\"kind\":\"b007\"}" )"
if printf '%s' "$OUT" | grep -qF '<whereis ' && printf '%s' "$OUT" | grep -qF 'filter=\"b007\"' && ! printf '%s' "$OUT" | grep -qF 'refs_omitted='; then
    ok "E2 MCP whereis kind=b007 (linked root) answers under the window, nothing omitted"
else
    no "E2 MCP whereis kind=b007 (linked root): $( printf '%s' "$OUT" | head -c 300 )"
fi
# E3/E4 the MCP twins answer a document with refs_omitted=, never an error ("not a git repository" or the old cap refusal).
for etool in whereis stray_content; do
    eargs="{\"path\":\"$EFIX/linked\"}"; ewant='refs_omitted=\"1\"'
    [ "$etool" = whereis ] && { eargs="{\"path\":\"$EFIX/linked\",\"symbol\":\"capProbe\"}"; ewant='refs_omitted=\"2\"'; }
    OUT="$( emcp "$etool" "$eargs" )"
    if ! printf '%s' "$OUT" | grep -qF '"error"' && printf '%s' "$OUT" | grep -qF "$ewant"; then
        ok "E3/E4 MCP $etool over 513 branches answers, disclosing $ewant"
    else
        no "E3/E4 MCP $etool over 513 branches: $( printf '%s' "$OUT" | head -c 300 )"
    fi
done
# E5 the CLI --stray-content answers: 512 read (refs=), the oldest one counted.
OUT="$( "$BIN" "$EFIX/linked" --stray-content --no-cache 2>"$EFIX/e5.err" )"; RC=$?
ROOTEL="$( eroot "$OUT" stray-content )"
if [ "$RC" -eq 0 ] && printf '%s' "$ROOTEL" | grep -qF 'refs="512"' && printf '%s' "$ROOTEL" | grep -qF 'refs_omitted="1"'; then
    ok "E5 --stray-content over 513 branches answers: refs=512 refs_omitted=1"
else
    no "E5 --stray-content over 513 branches → exit $RC: ${ROOTEL:-$( head -c 300 "$EFIX/e5.err" )}"
fi
# E6 --eval-stray scores that sweep, and a LABELLED ref is read even when it is the oldest (the window keeps labels first):
# b001, from the main root, is the one ref the newest-512 rule would leave out.
printf 'b001\tmerged\n' >"$EFIX/labels.tsv"
OUT="$( "$BIN" "$EFIX/main" --eval-stray="$EFIX/labels.tsv" --no-cache 2>"$EFIX/e6.err" )"; RC=$?
ROOTEL="$( eroot "$OUT" stray-eval )"
if [ "$RC" -eq 0 ] && printf '%s' "$ROOTEL" | grep -qF 'cases="1"' && ! printf '%s' "$ROOTEL" | grep -qF 'labels_omitted=' \
   && printf '%s' "$OUT" | grep -qF '<case ref="b001" want="merged" got="merged"'; then
    ok "E6 --eval-stray over 513 branches scores the oldest branch when it is labelled (cases=1, b001 read)"
else
    no "E6 --eval-stray over 513 branches → exit $RC: ${ROOTEL:-$( head -c 300 "$EFIX/e6.err" )}"
fi

# E7 the sweep's two other hosts, --stray-content --plan and --stray-content --abi, read the same window and say so on their roots.
for ev in --plan --abi; do
    etag=landing-plan; [ "$ev" = --abi ] && etag=abi
    OUT="$( "$BIN" "$EFIX/linked" --stray-content "$ev" --no-cache 2>"$EFIX/e7.err" )"; RC=$?
    ROOTEL="$( eroot "$OUT" "$etag" )"
    if [ "$RC" -eq 0 ] && printf '%s' "$ROOTEL" | grep -qF 'refs="512"' && printf '%s' "$ROOTEL" | grep -qF 'refs_omitted="1"'; then
        ok "E7 --stray-content $ev over 513 branches answers: refs=512 refs_omitted=1 on <$etag>"
    else
        no "E7 --stray-content $ev over 513 branches → exit $RC: ${ROOTEL:-$( head -c 300 "$EFIX/e7.err" )}"
    fi
done

# ── H: 4,096 branches — the window reads the NEWEST and names how many it left out ─────────────────────────────────────────
# Eight commits off HEAD, t1 the oldest and t8 the newest, each adding tier.cpp with its own probe name, and 512 branches on
# each (4,096). Past the window the sweep reads t8's branches only; t1-t7's probes are on no read tree. RED-FIRST (c6802ebdc):
# H1-H4 fail (refused); H0 holds on both binaries.
HFIX="$EFIX/h4096"
EGIT -C "$EFIX" init -q h4096
cp "$EFIX/main/cap.cpp" "$HFIX/cap.cpp"
EGIT -C "$HFIX" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" EGIT -C "$HFIX" commit -qm init
HHEAD="$( git -C "$HFIX" rev-parse HEAD )"; HCAP="$( git -C "$HFIX" rev-parse HEAD:cap.cpp )"
for k in 1 2 3 4 5 6 7 8; do
    hblob="$( printf 'int tierProbe%s( void ) { return %s; }\n' "$k" "$k" | git -C "$HFIX" hash-object -w --stdin )"
    htree="$( printf '100644 blob %s\tcap.cpp\n100644 blob %s\ttier.cpp\n' "$HCAP" "$hblob" | git -C "$HFIX" mktree )"
    hdate="$(( 1780318800 + 3600 * k )) +0000"
    htip="$( GIT_AUTHOR_NAME=Dev GIT_AUTHOR_EMAIL=dev@x.com GIT_COMMITTER_NAME=Dev GIT_COMMITTER_EMAIL=dev@x.com \
             GIT_AUTHOR_DATE="$hdate" GIT_COMMITTER_DATE="$hdate" git -C "$HFIX" commit-tree "$htree" -p "$HHEAD" -m "t$k" )"
    for n in $( seq -w 0 511 ); do printf 'create refs/heads/t%s_%s %s\n' "$k" "$n" "$htip"; done
done | git -C "$HFIX" update-ref --stdin
# H0 the premise, counted: 4,096 branches off HEAD's sha.
HSWEPT="$( git -C "$HFIX" for-each-ref refs/heads --format='%(objectname)' | grep -vcF "$HHEAD" )"
if [ "$HSWEPT" -eq 4096 ]; then
    ok "H0 fixture: $HSWEPT branches off HEAD's sha on 8 commits (window 512)"
else
    no "H0 fixture: $HSWEPT branches off HEAD's sha, want 4096 — H1-H4 would prove nothing"
fi
# H1 --whereis answers and names the omitted count: 511 read beside HEAD, 3,585 counted, and the newest tier is the one read.
OUT="$( "$BIN" "$HFIX" --whereis=tierProbe8 --no-cache 2>"$EFIX/h1.err" )"; RC=$?
ROOTEL="$( eroot "$OUT" whereis )"
if [ "$RC" -eq 0 ] && printf '%s' "$ROOTEL" | grep -qF 'refs_scanned="511"' && printf '%s' "$ROOTEL" | grep -qF 'refs_omitted="3585"' \
   && ! printf '%s' "$ROOTEL" | grep -qF 'hits="0"'; then
    ok "H1 --whereis over 4,096 branches answers: refs_scanned=511 refs_omitted=3585, the newest tier's probe found"
else
    no "H1 --whereis=tierProbe8 over 4,096 branches → exit $RC: ${ROOTEL:-$( head -c 300 "$EFIX/h1.err" )}"
fi
# H2 an older tier's probe lives only on omitted refs: hits="0" beside refs_omitted=, never complete="1" (the zero is windowed).
OUT="$( "$BIN" "$HFIX" --whereis=tierProbe7 --no-cache 2>"$EFIX/h2.err" )"; RC=$?
ROOTEL="$( eroot "$OUT" whereis )"
if [ "$RC" -eq 0 ] && printf '%s' "$ROOTEL" | grep -qF 'hits="0"' && printf '%s' "$ROOTEL" | grep -qF 'refs_omitted="3585"' \
   && ! printf '%s' "$ROOTEL" | grep -qF 'complete="1"'; then
    ok "H2 --whereis=tierProbe7 (only on omitted refs): hits=0 beside refs_omitted=3585, no complete="
else
    no "H2 --whereis=tierProbe7 over 4,096 branches → exit $RC: ${ROOTEL:-$( head -c 300 "$EFIX/h2.err" )}"
fi
# H3 the widening lever the reading names: the MCP whereis kind=t7_ picks tier 7's branches to fill the window, and finds it.
OUT="$( emcp whereis "{\"path\":\"$HFIX\",\"symbol\":\"tierProbe7\",\"kind\":\"t7_\"}" )"
if printf '%s' "$OUT" | grep -qF '<whereis ' && ! printf '%s' "$OUT" | grep -qF 'hits=\"0\"' && printf '%s' "$OUT" | grep -qF 'refs_omitted=\"1\"'; then
    ok "H3 MCP whereis kind=t7_ reads tier 7 (512 match, 511 read beside HEAD, 1 counted) and finds tierProbe7"
else
    no "H3 MCP whereis kind=t7_ over 4,096 branches: $( printf '%s' "$OUT" | head -c 300 )"
fi
# H4 --stray-content answers over 4,096 branches: 512 read, 3,584 counted.
OUT="$( "$BIN" "$HFIX" --stray-content --no-cache 2>"$EFIX/h4.err" )"; RC=$?
ROOTEL="$( eroot "$OUT" stray-content )"
if [ "$RC" -eq 0 ] && printf '%s' "$ROOTEL" | grep -qF 'refs="512"' && printf '%s' "$ROOTEL" | grep -qF 'refs_omitted="3584"'; then
    ok "H4 --stray-content over 4,096 branches answers: refs=512 refs_omitted=3584"
else
    no "H4 --stray-content over 4,096 branches → exit $RC: ${ROOTEL:-$( head -c 300 "$EFIX/h4.err" )}"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
