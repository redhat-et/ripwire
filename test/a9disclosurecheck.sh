#!/usr/bin/env bash
# a9disclosurecheck.sh —, lane G: the five disclosure gaps whose owning
# gates could not hold them, plus the Wave-1 verifier's V1-4 empty-value class.
#
# Every arm here pins an ABSENCE that used to read as an ANSWER. That is the class §A9 collects: a bare
# reaches="0" on a harness the graph cannot follow, a review bundle whose first screen invites the backwards
# caption, an interface whose methods were suppressed with no tell, a git-history ranking byte-shaped like a
# PageRank map, and sixteen verbs that answered an EMPTY question with a 6302-symbol atlas at exit 0.
#
# What each arm covers (and why it is not in the owning gate):
#   §A9.1  --exercises harness=  — exercisescheck.sh predates the disclosure and pins the row schema; this
#                                 is a NEW attribute with a positive AND a negative (.cpp harness) arm.
#   §A9.2  --pr-context direction= / <no-ref-work> — needs a purpose-built git fixture with BOTH a merged
#                                 ref and a divergent one; prcontextcheck.sh runs against the live repo,
#                                 where (this round) every branch happens to be an ancestor of HEAD.
#   §A9.4  --lego caveat=        — legocheck.sh asserts Vehicle's IMPLEMENTORS; the finding is about the
#                                 method contract's silent absence, an orthogonal axis on the same row.
#   §A9.6  --rank-by=churn hdr   — rankbycheck.sh pins ordering, not header identity.
#   V1-4   empty-value refusals  — argvdiffcheck.sh is a differential harness vs a BASE binary, so an
#                                 INTENTIONALLY diverging vector cannot live there; it must be pinned
#                                 absolutely. (argvdiffcheck stayed green through this change precisely
#                                 because its 356-vector matrix contains no empty-value vector — which is
#                                 how the class shipped in the first place.)
#
# Usage:  bash test/a9disclosurecheck.sh   |   RIPWIRE_BIN=build_base/ripwire bash test/a9disclosurecheck.sh (must FAIL)
# Exits non-zero on any failure. Does NOT edit test/regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "a9disclosurecheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# §A9.1 — --exercises on a SCRIPT harness discloses that the walk cannot see subprocess coverage
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# In a corpus whose gates are all shell scripts the verb's MODAL answer was `reaches="0"` — a bare zero
# indistinguishable from "this test covers nothing". Its sibling --affected has carried
# script_gates_unmodelled= for exactly this blindness since §P16; the inverse verb shipped without it.
# Read the ROOT ELEMENT, never the whole document: the verb's legend comment now NAMES harness=, so a
# document-wide grep would report the legend and pass the negative arm for the wrong reason.
exerciseRoot(){ perl -e 'alarm 120; exec @ARGV' "$BIN" "$ROOT" "--exercises=$1" 2>/dev/null | grep -oE '<exercises [^>]*>' | head -1; }
SH="$( exerciseRoot test/grepcheck.sh )"
case "$SH" in
    *'harness="script"'*) ok '§A9.1 --exercises=test/grepcheck.sh carries harness="script"' ;;
    *)                    no "§A9.1 --exercises on a shell gate has NO harness= tell (bare reaches= zero): $SH" ;;
esac
case "$SH" in
    *'note="a shell gate invokes the compiled binary as a subprocess'*)
        ok '§A9.1 the harness row carries the note= saying WHY reach is blind' ;;
    *)  no '§A9.1 harness= present but unexplained (no note= stating the unmodelled edge)' ;;
esac
# NEGATIVE: a .cpp harness's calls ARE modelled, so its root element must stay exactly as it was.
CPPH="$( exerciseRoot test/verify_csr.cpp )"
case "$CPPH" in
    *'harness='*) no "§A9.1 a .cpp harness wrongly carries harness= (the caveat must be script-only): $CPPH" ;;
    *'reaches='*) ok '§A9.1 --exercises on a .cpp harness carries NO harness= (unchanged bytes)' ;;
    *)            no "§A9.1 --exercises=test/verify_csr.cpp emitted no root element at all: $CPPH" ;;
esac

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# §A9.2 — --pr-context says WHICH SIDE it reviews, and calls out a ref with no divergent work
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# The BASEREF bundle is HEAD's-work-since-fork (correct, and documented mid-header). When the ref carries no
# commits of its own — merge-scout reports changed="0" for it — the first screen invites the backwards
# caption "this is the ref's diff". Fixture: one ref that IS the fork point, one that diverges.
if ! command -v git >/dev/null 2>&1; then
    printf '  SKIP  §A9.2 --pr-context arms (no git)\n'
else
    G="$TMP/prfix"; mkdir -p "$G/src"
    printf 'int leaf() { return 1; }\n'                                  > "$G/src/core.cpp"
    ( cd "$G" && git init -q . && git config user.email g@e && git config user.name g \
        && git add -A && git commit -qm base ) >/dev/null 2>&1
    # `merged` sits AT the fork point: an ancestor of HEAD, tip == merge-base(merged, HEAD).
    ( cd "$G" && git branch merged ) >/dev/null 2>&1
    # `diverged` gets a commit of its OWN, then HEAD moves on independently.
    ( cd "$G" && git checkout -q -b diverged && printf 'int theirs() { return 2; }\n' > src/theirs.cpp \
        && git add -A && git commit -qm theirs && git checkout -q - ) >/dev/null 2>&1
    printf 'int mid() { return leaf(); }\n'                             >> "$G/src/core.cpp"
    ( cd "$G" && git add -A && git commit -qm ours ) >/dev/null 2>&1

    prc(){ perl -e 'alarm 60; exec @ARGV' "$BIN" "$G" "$@" --no-cache 2>/dev/null; }

    WT="$( prc --pr-context )"
    case "$WT" in
        *'direction="worktree-since-head"'*) ok '§A9.2 --pr-context (no ref) carries direction="worktree-since-head"' ;;
        *)                                   no '§A9.2 --pr-context default form has no direction= at all' ;;
    esac
    MG="$( prc --pr-context=merged )"
    case "$MG" in
        *'direction="head-since-fork"'*) ok '§A9.2 --pr-context=REF carries direction="head-since-fork"' ;;
        *)                               no '§A9.2 --pr-context=REF has no direction= (the backwards caption stands)' ;;
    esac
    # the no-ref-work ROW must appear for `merged` — grep the ELEMENT, not the legend text that names it
    if printf '%s' "$MG" | grep -q '<no-ref-work '; then
        ok '§A9.2 a ref whose tip IS the merge base emits the <no-ref-work> row'
    else
        no '§A9.2 a ref with no divergent work emits NO <no-ref-work> row'
    fi
    DV="$( prc --pr-context=diverged )"
    if printf '%s' "$DV" | grep -q '<no-ref-work '; then
        no '§A9.2 a ref WITH divergent work wrongly emits <no-ref-work> (the row must be exact, not decorative)'
    else
        ok '§A9.2 a ref with divergent work emits NO <no-ref-work> row (exactly when tip==merge-base)'
    fi
    case "$DV" in
        *'direction="head-since-fork"'*) ok '§A9.2 direction= is present on the divergent-ref bundle too' ;;
        *)                               no '§A9.2 direction= missing on the divergent-ref bundle' ;;
    esac
    # the protected r26 disclosures must be untouched by all of the above
    case "$MG" in *'anchor="merge-base"'*'base_moved="0"'*) ok '§A9.2 anchor=/base_moved= disclosures unchanged' ;;
                  *) no '§A9.2 the protected anchor=/base_moved= disclosures moved or vanished' ;; esac
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$MG" | xmllint --noout - 2>/dev/null && ok '§A9.2 no-ref-work bundle xml well-formed' \
                                                          || no '§A9.2 no-ref-work bundle xml malformed'
    fi
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# §A9.4 — --lego on a language with no method extraction SAYS so
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# The Rust trait Vehicle declares two methods; legoMethodContractSound suppresses <m> for every language
# whose interface members this surface does not capture soundly. Suppression stays (a correct empty contract
# beats a broad wrong one) — but silence read as "this interface declares no methods".
V="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$ROOT" --lego=Vehicle 2>/dev/null )"
case "$V" in
    *'methods="0" caveat="not-extracted-for-lang"'*) ok '§A9.4 --lego=Vehicle (Rust) carries methods="0" caveat="not-extracted-for-lang"' ;;
    *)                                               no '§A9.4 --lego=Vehicle emits zero <m> rows with NO caveat (false zero)' ;;
esac
case "$V" in *'<impl n="Car"'*) ok '§A9.4 --lego=Vehicle still lists its implementors' ;;
             *) no '§A9.4 the caveat cost Vehicle its <impl> rows' ;; esac
S="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$ROOT" --lego=Shape 2>/dev/null )"
# RE-PINNED 2026-09-04 (capture-audit wave-2 merge, lane L10b finding 12): the lego LEGEND now DEFINES
# caveat="not-extracted-for-lang" (it was emitted undefined), so the whole-document substring test above
# matched the definition and read a C++ interface as carrying the caveat. The contract is about the
# <iface> ELEMENT: the attribute must be absent from the open tag, while the legend may — must — name it.
S_IFACE="$( printf '%s' "$S" | sed -e 's/<!--.*-->//g' | grep -o '<iface [^>]*>' | head -1 )"
case "$S_IFACE" in
    ''|*'caveat='*) no "§A9.4 --lego=Shape (C++, contract IS extracted) wrongly carries a caveat on <iface>: ${S_IFACE:-<no iface tag>}" ;;
    *)              ok '§A9.4 --lego=Shape carries NO caveat on its <iface> element (the legend defines the attribute, the element does not carry it)' ;;
esac
case "$S" in *'<m pure="1">'*) ok '§A9.4 --lego=Shape keeps its <m> contract rows' ;;
             *) no '§A9.4 --lego=Shape lost its <m> rows' ;; esac

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# §A9.6 — --rank-by=churn's map header is no longer byte-shaped like a PageRank map
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# A ranking mined ENTIRELY from git history emitted `<r est_tokens="…">`: identical in shape to the default
# structural map. --map-diff (the other git-derived map) already carried at=; churn carried nothing.
CH="$( perl -e 'alarm 180; exec @ARGV' "$BIN" "$ROOT" --rank-by=churn --top-k=5 2>/dev/null | grep -oE '<r [^>]*>' | head -1 )"
case "$CH" in *'rank_by="churn"'*) ok '§A9.6 --rank-by=churn <r> carries rank_by="churn"' ;;
              *) no "§A9.6 --rank-by=churn <r> has no rank_by=: $CH" ;; esac
# F1 (round C): the DEFAULT window is anchored on HEAD's committer date, and the stamp names the anchor —
# "18mo@HEAD" — so a reader can tell a HEAD-anchored window from a wall-clock one. The `@HEAD` half is
# CONDITIONAL on git being present, which it is for this arm (it runs against $ROOT), so both halves are pinned.
case "$CH" in *'window="18mo@HEAD"'*) ok '§A9.6 --rank-by=churn <r> carries window="18mo@HEAD" (width + anchor)' ;;
              *) no "§A9.6 --rank-by=churn <r> has no anchored window=: $CH" ;; esac
case "$CH" in *'at="'*)            ok '§A9.6 --rank-by=churn <r> carries the at= stamp (map-diff precedent)' ;;
              *) no "§A9.6 --rank-by=churn <r> has no at= stamp: $CH" ;; esac
# --since must relabel the window rather than keep advertising the default.
# The rev is the ROOT COMMIT, not a fixed HEAD~N. A depth-relative rev makes this arm assert a property of
# the CHECKOUT (does it have N ancestors?) on top of the property it means to assert (does an ACTIVE
# --since relabel window=?), and an unresolvable rev refuses before the header is ever emitted — so a young
# or shallow clone reddens the gate while the disclosure it guards is perfectly correct. Every git
# repository has a root commit, so this resolves everywhere and exercises the same code path.
SINCEREV="$( git -C "$ROOT" rev-list --max-parents=0 HEAD 2>/dev/null | head -1 )"
if [ -z "$SINCEREV" ]; then
    no '§A9.6 could not resolve a root commit to exercise --since (git history unavailable)'
else
    CS="$( perl -e 'alarm 180; exec @ARGV' "$BIN" "$ROOT" --rank-by=churn --since="$SINCEREV" --top-k=5 2>/dev/null | grep -oE '<r [^>]*>' | head -1 )"
    case "$CS" in *"window=\"$SINCEREV\""*) ok '§A9.6 an ACTIVE --since relabels window= (no stale 18mo claim)' ;;
                  *) no "§A9.6 --since did not relabel window=: $CS" ;; esac
fi
# NEGATIVE: pagerank is byte-identical to the plain map — the disclosure must cost the default path nothing.
perl -e 'alarm 180; exec @ARGV' "$BIN" "$ROOT" --rank-by=pagerank --top-k=5 >"$TMP/pr" 2>/dev/null
perl -e 'alarm 180; exec @ARGV' "$BIN" "$ROOT" --top-k=5                    >"$TMP/plain" 2>/dev/null
if cmp -s "$TMP/pr" "$TMP/plain"; then
    ok '§A9.6 --rank-by=pagerank stays byte-identical to the plain map'
else
    no '§A9.6 --rank-by=pagerank diverged from the plain map (the churn disclosure leaked into the default path)'
fi
grep -q 'rank_by=' "$TMP/plain" && no '§A9.6 the plain map wrongly carries rank_by=' \
                                || ok '§A9.6 the plain map carries no rank_by= (attribute is churn-only)'

# ════════════════════════════════════════════════════════════════════════════════════════════════════
# V1-4 — an EMPTY value is a mistyped verb, not a request for the default map
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# `--grep=` (a shell variable that expanded to nothing is the usual author) fell through to the ranked map
# at exit 0 on sixteen value-taking flags. Five siblings already refused; this pins all twenty-one.
emptyRefuses(){
    local flag="$1"
    local out; out="$( perl -e 'alarm 60; exec @ARGV' "$BIN" "$ROOT" "--$flag=" 2>&1 >/dev/null )"
    local rc=$?
    if [ "$rc" -ne 1 ]; then
        no "V1-4 --$flag= exits $rc (want 1) — an empty value still produces output"
        return
    fi
    case "$out" in
        *"--$flag"*) ok "V1-4 --$flag= refuses (exit 1) and names the flag" ;;
        *)           no "V1-4 --$flag= exits 1 but the message does not name the flag: $out" ;;
    esac
}
for f in grep for callers impact uses regex expand match lego exemplar recall path connect affected mentions graph-query; do
    emptyRefuses "$f"
done
# the five that already refused must keep refusing (the shared helper must not have displaced them)
for f in whereis pack-task community zoom exercises; do
    emptyRefuses "$f"
done
# and a NON-empty value on the same flags must still work — the refusal is about emptiness, nothing else
perl -e 'alarm 120; exec @ARGV' "$BIN" "$ROOT" --grep=parseArgs >"$TMP/g" 2>/dev/null
[ -s "$TMP/g" ] && ok 'V1-4 --grep=parseArgs (non-empty) still answers' || no 'V1-4 the empty-value guard broke a real --grep'

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
