#!/usr/bin/env bash
# taskroutecheck.sh — deterministic task -> one safe Ripwire command contract.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
REPO="$TMP/router repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email ripwire@example.invalid
git -C "$REPO" config user.name ripwire-gate
cat >"$REPO/router.cpp" <<'SRC'
int alphaNode() { return 1; }
int betaNode() { return alphaNode(); }
int gammaNode() { return betaNode(); }
int targetSymbol() { return gammaNode(); }
int classify() { return targetSymbol(); }
int report() { return classify(); }
int summary() { return report(); }
int patch() { return summary(); }
int computeBudget( int rawBytes )
{
    int budget = rawBytes / 2;
    int reserve = rawBytes - budget;
    return budget + reserve;
}
// Single-word CAPITALIZED classes, no camel seam, no underscore, no scope — the exact collision class the
// routing-noise round found in ripwire's own fixture corpora (real symbols happen to be named A, E, Fix,
// Report, Summary, Lane, WORK, Split), and the reason a leading capital alone used to be "strong" evidence.
class A {};
class E {};
class Fix {};
class Report {};
class Summary {};
class Lane {};
class WORK {};
class Split {};
SRC
# A config file is part of the fixture on purpose: its keys index as t="sec" symbols with names that are
# ordinary English words, which is the collision class the weak symbol tier draws its false positives from
# (an English word meets a JSON key far more often than a function). Without a t="sec" row in the fixture
# the kind-filter arms below cannot fail, and the class stayed invisible to this gate until 2026-09-10.
cat >"$REPO/package.json" <<'JSON'
{
  "name": "router-fixture",
  "version": "1.2.3",
  "license": "MIT",
  "notes": "fixture package for the router gate"
}
JSON
# A SUBDIRECTORY with code in it, because a directory is the one thing the recency route below needs and
# a flat fixture cannot provide: "what changed recently in storage" may only compose a scope when the
# directory really is in the corpus. Its two names are camelCase and appear in no other arm's prompt, so
# nothing above can start resolving a symbol it did not resolve before.
mkdir -p "$REPO/storage"
cat >"$REPO/storage/queue.cpp" <<'SRC'
int flushPending() { return 1; }
int drainPending() { return flushPending(); }
SRC
# A4 follow-up (review round, found-items 2026-09-17): a .hxx file, so the at-line FILE:LINE token
# recognizer (taskroute.h::kCodeExtensions) has one to name — cheap, since the routing fixture already
# exists; this is the one extra file plus one extra route() call it costs.
cat >"$REPO/widget.hxx" <<'SRC'
int widgetInit() { return 1; }
int widgetTick() { return widgetInit(); }
SRC
# CodeRabbit round (PR #292, 2026-09-19): a TOML nested table indexes as a t="sec" symbol whose NAME is
# the dotted path itself — literally "tool.poetry" — all-lowercase, no underscore/colon/dollar/uppercase.
# `hasMark` (symbolMention's gate for even TRYING the strong shape test) used to test for ':' but not
# '.', although identifierMentionShape treats "::" and "." as the SAME scoped-seam evidence. A dotted
# Section-kind symbol therefore could never resolve at all: Section is excluded from the weak tier
# (weakEvidenceKind), and the strong path — including its backtick override — was unreachable without
# hasMark seeing the mark first. See the LTA/LTB arms below.
cat >"$REPO/pyproject.toml" <<'TOML'
[tool.poetry]
name = "router-fixture"
TOML
# Round-1 L4 (first-verb cards for test-coverage/change-impact/reach-flow): the round's own mining and
# paraphrase questions name file paths this fixture must actually index, or --affected/--situ's own
# refusal on an unindexed path (measured: exit 1) would make every positive arm below red for the wrong
# reason. Paths echo the round's rocksdb-flavoured mining/paraphrase corpus (PLAN_OUTPUT_ROUTING_LOOP
# 11_round1_PREREG.md §E) so the SAME task strings this round measured against a real checkout also route
# here; the symbol names are fresh (no collision with router.cpp/storage/queue.cpp/widget.hxx above).
mkdir -p "$REPO/db/db_impl" "$REPO/db/wide" "$REPO/table" "$REPO/cache" "$REPO/util"
cat >"$REPO/db/write_batch.cc" <<'SRC'
int writeBatchAppend() { return 1; }
SRC
cat >"$REPO/db/wal_manager.cc" <<'SRC'
int walManagerFlush() { return 1; }
SRC
cat >"$REPO/db/db_impl/db_impl.cc" <<'SRC'
int dbImplWriteRow() { return 1; }
SRC
cat >"$REPO/db/db_iter.cc" <<'SRC'
int dbIterNextRow() { return 1; }
SRC
cat >"$REPO/db/wide/wide_columns_helper.h" <<'SRC'
int wideColumnsConvert();
SRC
cat >"$REPO/table/get_context.cc" <<'SRC'
int getContextLookup() { return 1; }
SRC
cat >"$REPO/table/block_fetcher.cc" <<'SRC'
int blockFetcherFetch() { return 1; }
SRC
cat >"$REPO/table/iter_heap.h" <<'SRC'
int iterHeapUse();
SRC
cat >"$REPO/cache/lru_cache.cc" <<'SRC'
int lruCacheGet() { return 1; }
SRC
cat >"$REPO/util/heap.h" <<'SRC'
int heapPushEntry();
SRC
git -C "$REPO" add router.cpp package.json storage/queue.cpp widget.hxx pyproject.toml \
    db/write_batch.cc db/wal_manager.cc db/db_impl/db_impl.cc db/db_iter.cc db/wide/wide_columns_helper.h \
    table/get_context.cc table/block_fetcher.cc table/iter_heap.h cache/lru_cache.cc util/heap.h
git -C "$REPO" commit -qm base
routeRaw(){ "$BIN" "$REPO" --no-cache --help-task="$1" 2>"$TMP/err"; }
# The document opens with its LEGEND, and the legend names the attributes it defines (next=, <run>, …).
# Every arm below is about the DATA, so route() hands them the document with that comment removed — a
# legend that mentions an attribute must never be able to satisfy an assertion about a row carrying one.
# The legend has arms of its own, at the end of this file.
route(){ routeRaw "$1" | python3 -c 'import sys
s=sys.stdin.read()
a=s.find("<!--"); b=s.find("-->", a)
sys.stdout.write( s[:a] + s[b+3:] if a >= 0 and b >= 0 else s )'; }

if "$BIN" --help=all 2>&1 | grep -q -- '--help-task='; then ok "--help advertises --help-task="; else no "--help does not advertise --help-task="; fi
V="$( route 'calls(betaNode, alphaNode)' )"
case "$V" in *'status="recommend"'*'intent="verify-claim"'*'--verify='*) ok "closed claim -> --verify";; *) no "closed claim route wrong: $V";; esac
C="$( route 'How do alphaNode, betaNode, and gammaNode connect?' )"
case "$C" in *'status="recommend"'*'intent="connect-symbols"'*'--connect='*'alphaNode,betaNode,gammaNode'*) ok "three resolved symbols -> --connect";; *) no "three-symbol route wrong: $C";; esac
U="$( route 'Help me understand the implementation of targetSymbol' )"
case "$U" in *'status="recommend"'*'intent="understand-symbol"'*'--expand='*'targetSymbol'*) ok "one resolved symbol -> --expand";; *) no "one-symbol route wrong: $U";; esac
XG="$( route 'Find every exact occurrence of "return alphaNode()" with nearby context' )"
case "$XG" in *'status="recommend"'*'intent="exact-grep"'*'--grep='*'--grep-context=2'*) ok "quoted exact literal -> context-aware --grep";; *) no "exact grep route wrong: $XG";; esac
# Prose apostrophes are NOT quotes: possessives must never mint a grep literal out of the words between
# them ("s config and the team" was the pre-fix extraction here), while a REAL quoted literal in the same
# apostrophe-laden sentence still routes. The mangled-literal assertion is the red-first arm vs a pre-fix binary.
AP="$( route "Search for the user's config and the team's settings for the flag" )"
case "$AP" in *'--grep='*'s config'*) no "possessive apostrophes minted a bogus grep literal: $AP";; *) ok "possessive apostrophes mint no grep literal";; esac
AQ="$( route "Search for the exact literal 'flag_name' somewhere in the user's config handling" )"
case "$AQ" in *'status="recommend"'*'intent="exact-grep"'*'--grep='*'flag_name'*) ok "real quoted literal survives surrounding apostrophes";; *) no "quoted literal lost among apostrophes: $AQ";; esac
EC="$( route 'I just edited targetSymbol; did I change its contract?' )"
case "$EC" in *'status="recommend"'*'intent="edit-contract"'*'--edit-check='*'targetSymbol'*) ok "post-edit exact symbol -> --edit-check";; *) no "edit contract route wrong: $EC";; esac
# ── all-lowercase symbol names are reachable, but only from a symbol SLOT ──────────────────────────────
# An indexed name with no capital and no separator (`classify`) used to be discarded by a casing filter,
# so NO symbol-gated route could ever reach it. Casing was a proxy for "is this a symbol mention or just a
# word"; sentence POSITION is the real discriminator, so these arms assert both directions of it. The two
# recall arms are red against a pre-fix binary (both abstained, resolved_symbols="0"); the four precision
# arms are the guard that the relaxation did not buy recall with prose false-positives.
LW="$( route 'Explain the implementation of classify' )"
case "$LW" in *'status="recommend"'*'intent="understand-symbol"'*'--expand='*'classify'*) ok "lowercase name in an understand slot -> --expand";; *) no "lowercase understand route wrong: $LW";; esac
LE="$( route 'I just edited classify; did I change its contract?' )"
case "$LE" in *'status="recommend"'*'intent="edit-contract"'*'--edit-check='*'classify'*) ok "lowercase name in a post-edit slot -> --edit-check";; *) no "lowercase edit-contract route wrong: $LE";; esac
# Same words, no slot: an ordinary noun phrase must stay unresolved even though `report` IS indexed here.
LN="$( route 'did I change the report that goes out on Friday?' )"
case "$LN" in *'--edit-check='*) no "a determiner-led noun phrase minted a symbol route: $LN";; *) ok "prose noun phrase resolves no lowercase symbol";; esac
LN2="$( route 'how does the report look this quarter?' )"
case "$LN2" in *'--expand='*) no "a determiner-led noun phrase minted an --expand route: $LN2";; *) ok "prose noun phrase mints no --expand";; esac
# The stop list keeps the router from arguing with itself: `summary` is indexed, but the router's own
# intent vocabulary must never double as a symbol mention.
LS="$( route 'How does classify work? I just edited classify and report and summary too' )"
case "$LS" in *'--connect='*) no "several lowercase words minted a --connect route: $LS";; *) ok "several lowercase words never mint --connect";; esac
LC="$( route 'how do classify, report and summary connect?' )"
case "$LC" in *'--connect='*) no "three lowercase words minted a --connect route: $LC";; *) ok "three lowercase words never satisfy the three-symbol --connect";; esac

# ── an all-lowercase dotted name still carries scoped SHAPE (CodeRabbit round, PR #292, 2026-09-19) ─────
# `hasMark` used to test for ':' (the "::" scope spelling) but not '.' (the OTHER spelling
# identifierMentionShape treats identically as `scoped`), so a real indexed dotted name — a TOML nested
# table, t="sec" symbol named literally "tool.poetry" — could never even reach the strong shape test.
# Section-kind symbols are excluded from the weak tier (weakEvidenceKind), so the name could not resolve
# AT ALL, not even backtick-marked (the override identifierMentionShape's step 1 grants is itself gated
# behind hasMark). Both arms are RED against a pre-fix binary (abstain, resolved_symbols="0").
LTA="$( route 'Explain the implementation of tool.poetry' )"
case "$LTA" in *'status="recommend"'*'intent="understand-symbol"'*'--expand='*'tool.poetry'*) ok "bare dotted name resolves as a strong mention -> --expand";; *) no "bare dotted-name route wrong: $LTA";; esac
LTB="$( route 'Explain the implementation of `tool.poetry`' )"
case "$LTB" in *'status="recommend"'*'intent="understand-symbol"'*'--expand='*'tool.poetry'*) ok "backtick-marked dotted name resolves -> --expand";; *) no "backtick dotted-name route wrong: $LTB";; esac

# ── a leading capital is not a camel seam (the routing-noise round, 2026-09-19) ─────────────────────────
# `symbolMention`'s old "strong" test was ANY uppercase/underscore/colon/dollar byte anywhere in the name,
# so a single-word capitalized class name (`Fix`, `Report`, `Summary`, `Lane`, `Split`, `WORK`, a bare `A`
# or `E`) passed on a leading capital alone — no interior camel SEAM, no underscore, no scope. Ripwire's
# own fixture corpora define real symbols with exactly these names (test fixtures written for unrelated
# rounds), so a background-task report quoting ordinary prose like "Summary: A, Fix, Report" minted a
# spurious >=3-resolved-symbol --connect route out of text that never named a task at all. These arms are
# RED against a pre-change binary (both NOISE1/NOISE2 recommended connect-symbols).
NOISE1='Split-out lane: edit-hint finished. Real-fix NO. Summary: A, Fix, Report'
N1="$( route "$NOISE1" )"
case "$N1" in *'--connect='*) no "capitalized-but-shapeless prose minted a --connect route: $N1";; *) ok "capitalized-but-shapeless prose never satisfies the three-symbol --connect";; esac
NOISE2='run the next round of ripwire improvements as an orchestrator. continuation_notes.md Lane E WORK'
N2="$( route "$NOISE2" )"
case "$N2" in *'--connect='*) no "a SCREAMING word and single letters minted a --connect route: $N2";; *) ok "a SCREAMING word and single letters never satisfy the three-symbol --connect";; esac
# The positive control: real identifier SHAPE (a camel seam) still routes on exactly the same three-symbol
# gate — the fix narrows what counts as evidence, it does not disable the route.
N3="$( route 'how do alphaNode, betaNode and gammaNode all come together' )"
case "$N3" in *'status="recommend"'*'intent="connect-symbols"'*'--connect='*'alphaNode,betaNode,gammaNode'*) ok "genuine camelCase shape still routes --connect";; *) no "camelCase connect-symbols regressed: $N3";; esac
# Explicit code-marking (backticks) is evidence even when the name itself has no seam: a user who writes
# `` `Report` `` has said, unambiguously, "this is code" — the override the shape test carves out for it.
N4="$( route 'how do `Fix`, `Report` and `Summary` relate to each other' )"
case "$N4" in *'status="recommend"'*'intent="connect-symbols"'*'--connect='*) ok "backtick-marked shapeless names still route --connect";; *) no "backtick override did not route: $N4";; esac

# ── harness/system events never route (the routing-noise round, 2026-09-19) ─────────────────────────────
# Claude Code delivers a background-task completion and an injected reminder to UserPromptSubmit through
# the SAME channel a real prompt arrives on. hooks/ripwire-claude-route.sh and hooks/ripwire-codex-route.sh
# skip calling this classifier at all on such input (test/routehookcheck.sh's (N) section), but --help-task
# is directly callable too, so the same guard lives in the classifier itself (looksLikeSystemEvent). These
# arms are RED against a pre-change binary.
SYS1="$( routeRaw '<task-notification>
<task-id>bn211i65j</task-id>
<status>completed</status>
<summary>Split-out lane: edit-hint finished. Real-fix NO. Summary: A, Fix, Report</summary>
</task-notification>' )"
case "$SYS1" in *'status="abstain"'*'resolved_symbols="0"'*) ok "a <task-notification>-shaped task abstains, and nothing below it is even evaluated";; *) no "task-notification-shaped task did not abstain cleanly: $SYS1";; esac
SYS2="$( routeRaw '<system-reminder>
run the next round of ripwire improvements as an orchestrator. continuation_notes.md Lane E WORK
</system-reminder>' )"
case "$SYS2" in *'status="abstain"'*'resolved_symbols="0"'*) ok "a <system-reminder>-shaped task abstains, and nothing below it is even evaluated";; *) no "system-reminder-shaped task did not abstain cleanly: $SYS2";; esac
# Leading whitespace before the marker still counts (the harness may deliver it after a blank line).
SYS3="$( routeRaw '
	<task-notification>
foo
</task-notification>' )"
case "$SYS3" in *'status="abstain"'*) ok "leading whitespace before the marker still abstains";; *) no "leading-whitespace variant did not abstain: $SYS3";; esac
# The negative control: a real prompt that merely MENTIONS the marker mid-sentence must still route
# normally — this is a shape test on the harness's own wake-up marker, not a ban on the words.
SYS4="$( route 'what does <task-notification> mean in the hook? also, help me understand the implementation of targetSymbol' )"
case "$SYS4" in *'status="recommend"'*'intent="understand-symbol"'*'--expand='*'targetSymbol'*) ok "a real prompt merely mentioning the marker mid-sentence still routes normally";; *) no "mid-sentence mention wrongly suppressed a real route: $SYS4";; esac

# ── the weak tier may not confirm itself, and may not read a config key as code (2026-09-10) ───────────
# Two independent defects, two independent arms each; all four recommend-side arms are RED against a
# pre-change binary (each recommended understand-symbol with an --expand).
#
# (1) SELF-CONFIRMATION. `does` was a symbol-slot cue AND `how does` is the understand-symbol gate, so
#     "how does <indexed-word> …?" minted the very symbol the gate then required — the words are the same
#     two words. Same for `understand` as cue and `understand` as gate. An intent word is evidence about
#     what the user WANTS; it may never double as the positional evidence that they NAMED something.
#     Cost, stated plainly: the bare "How does classify work?" spelling no longer routes. That recall is
#     reachable through any cue the gate does not itself consume — the LW arm above ("the implementation
#     of classify") is that same weak lowercase name, still resolving, still routing to --expand.
# (2) KIND. A t="sec" row is a markdown heading or a JSON/TOML/YAML key. `version` is a config key here
#     and in most repos; --expand='version' then answers with `"version": "1.2.3"` at exit 0. A weak
#     reading must be backed by a CODE definition; a strong (camel/snake/scoped) mention is untouched.
SC1="$( route 'how does patch Tuesday affect our support load?' )"
case "$SC1" in *'--expand='*) no "the understand gate minted its own symbol out of 'how does': $SC1";; *) ok "'how does <word>' never mints the symbol its own gate requires";; esac
SC2="$( route 'How does classify work?' )"
case "$SC2" in *'--expand='*) no "self-confirming 'how does' route still fires on a real function: $SC2";; *) ok "'how does <fn>' abstains — the gate word may not be the cue (recall via the slot arm above)";; esac
SC3="$( route 'I want to understand summary writing for the leadership review' )"
case "$SC3" in *'--expand='*) no "the understand gate minted its own symbol out of 'understand': $SC3";; *) ok "'understand <word>' never mints the symbol its own gate requires";; esac
KF1="$( route 'Explain the implementation of version' )"
case "$KF1" in *'--expand='*) no "a t=sec config key resolved as a weak symbol: $KF1";; *) ok "a config-key-only name never resolves from the weak tier";; esac
# The kind filter is scoped to the WEAK tier: an identifier-shaped mention still resolves whatever it names.
KF2="$( route 'Explain the implementation of targetSymbol' )"
case "$KF2" in *'status="recommend"'*'intent="understand-symbol"'*'--expand='*'targetSymbol'*) ok "an identifier-shaped mention still resolves (kind filter is weak-tier only)";; *) no "kind filter leaked into strong mentions: $KF2";; esac
# And --expand on the config key is the answer the router would have handed over: still a real command,
# just never one the router mints out of prose. (Run it: the honesty is that this is what it returns.)
KF3="$( "$BIN" "$REPO" --no-cache --expand='version' )"
case "$KF3" in *'"version": "1.2.3"'*) ok "the refused route's own command really does answer with a JSON key";; *) no "the kind-filter premise no longer holds: --expand=version returned something else";; esac

# ── paraphrase tolerance: neither intent may recognise only the wording it was written against ─────────
# exact-grep and edit-contract shipped as fixed OR-chains of four or five literal phrases. These six are
# the realistic paraphrases that missed; all six abstained against a pre-fix binary. The two guard arms
# below are why widening the vocabulary is safe: the floor is never the whole gate — exact-grep still
# needs a literal the user QUOTED, and edit-contract still needs exactly one resolved symbol.
for P in 'I need every place that says "targetSymbol" verbatim' \
         'look for occurrences of "cacheValue" across the repo' \
         'where does the string "alphaNode" show up in the codebase'; do
    G="$( route "$P" )"
    case "$G" in *'status="recommend"'*'intent="exact-grep"'*'--grep='*) ok "exact-grep paraphrase routes: ${P:0:44}";; *) no "exact-grep paraphrase missed [$P]: $G";; esac
done
for P in "did targetSymbol's contract change after my patch" \
         'I modified targetSymbol - is it still compatible with callers' \
         'just finished editing targetSymbol, could this break anyone'; do
    E="$( route "$P" )"
    case "$E" in *'status="recommend"'*'intent="edit-contract"'*'--edit-check='*'targetSymbol'*) ok "edit-contract paraphrase routes: ${P:0:44}";; *) no "edit-contract paraphrase missed [$P]: $E";; esac
done
XW="$( route 'where does the team stand on the quarterly plan and every place it slipped' )"
case "$XW" in *'--grep='*) no "exact-search wording alone minted a grep with no quoted literal: $XW";; *) ok "widened exact-grep wording still needs a quoted literal";; esac
EW="$( route 'i modified the slide deck after my patch of the agenda, did i change anything' )"
case "$EW" in *'--edit-check='*) no "post-edit wording alone minted an --edit-check with no resolved symbol: $EW";; *) ok "widened post-edit wording still needs one resolved symbol";; esac

T="$( route $'AddressSanitizer: heap-use-after-free\n#0 0x123 in targetSymbol router.cpp:4' )"
case "$T" in *'status="recommend"'*'intent="trace-debug"'*'--from-trace=-'*) ok "trace shape -> --from-trace=-";; *) no "trace route wrong: $T";; esac

printf '\n// dirty\n' >>"$REPO/router.cpp"
D="$( route 'Review my current changes before I push' )"
case "$D" in *'status="recommend"'*'intent="review-diff"'*'<run>'*'--situ'*) ok "dirty pre-push review -> --situ";; *) no "dirty diff route wrong: $D";; esac
git -C "$REPO" restore router.cpp
D0="$( route 'Review my current changes before I push' )"
case "$D0" in *'status="recommend"'*'intent="review-diff"'*) no "clean worktree recommended dirty-diff route: $D0";; *) ok "clean worktree rejects dirty-only review route";; esac
P="$( route 'Plan the implementation and scope of a new cache feature' )"
case "$P" in *'status="recommend"'*'intent="plan-feature"'*'--pack-task='*) ok "prospective feature -> --pack-task";; *) no "feature plan route wrong: $P";; esac
E="$( route 'I am about to write one helper function for cache keys' )"
case "$E" in *'status="recommend"'*'intent="reuse-one-symbol"'*'--exemplar='*) ok "one new symbol -> --exemplar";; *) no "reuse route wrong: $E";; esac
F="$( route 'Find the code responsible for this retry timeout bug' )"
case "$F" in *'status="recommend"'*'intent="locate-task"'*'--for='*) ok "locate/debug symptom -> --for";; *) no "locate route wrong: $F";; esac
WT="$( route 'Find a small untested command-line behavior and add a regression gate for it' )"
case "$WT" in *'status="recommend"'*'intent="write-tests"'*'--seams'*) ok "missing regression coverage -> --seams";; *) no "write-tests route wrong: $WT";; esac
WT0="$( route 'The quarterly report mentions untested assumptions' )"
case "$WT0" in *'intent="write-tests"'*) no "untested wording without a test-writing action routed to --seams: $WT0";; *) ok "untested prose alone does not route to --seams";; esac

# ── the five surfaces that shipped without any routing coverage ────────────────────────────────────────
# Each is asked for close to its own vocabulary, so each needs conjunctive evidence (the surface word AND
# an intent word) and the two that carry a user-supplied value fire only when the task supplies it — the
# router may not substitute a placeholder, because --edit-plan/--grep would then refuse the command it was
# handed. All ten arms are red against a pre-fix binary: every one of these abstained with score="0".
EP="$( route 'Apply the edits in refactor.json as a multi-edit transaction' )"
case "$EP" in *'status="recommend"'*'intent="apply-edit-plan"'*'--edit-plan='*'refactor.json'*'--dry-run'*) ok "edit-plan wording + named plan -> --edit-plan --dry-run";; *) no "edit-plan route wrong: $EP";; esac
EP0="$( route 'how do I run a transactional multi-edit against this repo?' )"
case "$EP0" in *'--edit-plan='*) no "edit-plan route invented a plan file the task never named: $EP0";; *) ok "edit-plan abstains rather than invent a plan path";; esac
HD="$( route 'Find every occurrence of "targetSymbol" and give me safe-edit handles' )"
case "$HD" in *'status="recommend"'*'intent="grep-handles"'*'--grep='*'--handles'*) ok "handle wording + quoted literal -> --grep --handles";; *) no "grep-handles route wrong: $HD";; esac
# --handles is a MODIFIER on --grep/--regex; without a literal to anchor it there is no command to make.
HD0="$( route 'give me safe-edit handles for the grep hits' )"
case "$HD0" in *'--handles'*) no "grep-handles emitted a --handles with no literal to anchor it: $HD0";; *) ok "grep-handles abstains without a quoted literal";; esac
# The word-bounded arm: "config handling" is NOT a handles request, and must leave exact-grep alone.
HD1="$( route "Search for the exact literal 'flag_name' somewhere in the user's config handling" )"
case "$HD1" in *'intent="exact-grep"'*) ok "'handling' does not steal exact-grep from its own route";; *) no "substring 'handle' hijacked exact-grep: $HD1";; esac
CL="$( route 'I want the compact legend on this map' )"
case "$CL" in *'status="recommend"'*'intent="compact-legend"'*'--legend=compact'*) ok "compact-legend wording -> --legend=compact";; *) no "compact-legend route wrong: $CL";; esac
CX="$( route 'set up the codex integration and tell me if it is wired correctly' )"
case "$CX" in *'status="recommend"'*'intent="codex-doctor"'*'--doctor --agent=codex'*) ok "codex + integration wording -> --doctor --agent=codex";; *) no "codex-doctor route wrong: $CX";; esac
CX0="$( route 'codex is a nice name, should we use it for the new project?' )"
case "$CX0" in *'--agent=codex'*) no "a passing mention of codex minted a doctor route: $CX0";; *) ok "codex alone never mints a doctor route";; esac
TG="$( route 'why did the test-gate pick those shell gates - show me the evidence' )"
case "$TG" in *'status="recommend"'*'intent="gate-evidence"'*'--test-gate'*) ok "shell-gate evidence wording -> --test-gate";; *) no "gate-evidence route wrong: $TG";; esac
TG0="$( route 'i want a sanity pass over my diff — which tests do i even need here?' )"
case "$TG0" in *'intent="gate-evidence"'*) no "'which tests' alone minted a gate-evidence route: $TG0";; *) ok "'which tests' alone is not a shell-gate evidence request";; esac

# ── data-flow / at-line / who-writes: the router-coverage gap for "where did this value come from" ─────
# Today's abstains this round closes: a FILE:LINE seed named in the task (structural, no symbol needed),
# one resolved symbol plus writer-attribution wording (--uses=SYM; the Owner.field dotted form is lane
# E's and stays deliberately uncoupled — the router resolves only the owner symbol and says so), and one
# resolved symbol plus data-flow wording (--slice=SYM, upgraded to --slice=SYM:VAR --slice-flow=back when
# a variable-slot cue also names a variable). All arms below are red against a pre-fix binary (abstain).
DF1="$( route 'trace the flow of budget inside computeBudget' )"
case "$DF1" in *'status="recommend"'*'intent="data-flow"'*'--slice='*'computeBudget:budget'*'--slice-flow=back'*) ok "symbol + variable-slot cue -> --slice=SYM:VAR --slice-flow=back";; *) no "data-flow SYM:VAR route wrong: $DF1";; esac
DF2="$( route 'where does this value come from inside computeBudget' )"
case "$DF2" in *'status="recommend"'*'intent="data-flow"'*'--slice='*'computeBudget'*) case "$DF2" in *'--slice-flow'*) no "data-flow with no variable cue still emitted --slice-flow: $DF2";; *) ok "symbol only, no variable cue -> bare --slice=SYM (lists locals)";; esac;; *) no "data-flow SYM-only route wrong: $DF2";; esac
DF0="$( route 'which statements feed the pending value' )"
case "$DF0" in *'--slice='*) no "data-flow wording with no resolved symbol invented a --slice command: $DF0";; *) ok "data-flow wording alone (no resolved symbol) abstains rather than invent a SYM";; esac
AL1="$( route 'what defines the value assigned at router.cpp:10' )"
case "$AL1" in *'status="recommend"'*'intent="at-line"'*'--slice='*'@router.cpp:10'*) ok "literal FILE:LINE token -> --slice=@FILE:LINE";; *) no "at-line literal-token route wrong: $AL1";; esac
AL2="$( route 'walk me through line 10 of router.cpp' )"
case "$AL2" in *'status="recommend"'*'intent="at-line"'*'--slice='*'@router.cpp:10'*) ok "prose 'line N of FILE' -> --slice=@FILE:LINE";; *) no "at-line prose-form route wrong: $AL2";; esac
AL3="$( route 'what defines the value assigned at widget.hxx:2' )"
case "$AL3" in *'status="recommend"'*'intent="at-line"'*'--slice='*'@widget.hxx:2'*) ok "A4: a .hxx FILE:LINE token -> --slice=@FILE:LINE (kCodeExtensions)";; *) no "A4: .hxx at-line route wrong: $AL3";; esac
AL0="$( route 'what happens around line 10 in the budget calculation' )"
case "$AL0" in *'--slice='*'@'*) no "'line N' with no code-file token minted an at-line route: $AL0";; *) ok "'line N' alone (no file extension) mints no at-line route";; esac
WW1="$( route 'who writes to targetSymbol these days' )"
case "$WW1" in *'status="recommend"'*'intent="who-writes"'*'--uses='*'targetSymbol'*) ok "who-writes wording + one resolved symbol -> --uses=SYM";; *) no "who-writes route wrong: $WW1";; esac
WW2="$( route 'who modifies targetSymbol.contract these days' )"
case "$WW2" in *'status="recommend"'*'intent="who-writes"'*'--uses='*'targetSymbol'*) ok "Owner.field phrasing resolves the OWNER symbol only, uncoupled from the field";; *) no "who-writes Owner.field route wrong: $WW2";; esac
WW0="$( route 'who writes the release notes each week' )"
case "$WW0" in *'--uses='*) no "who-writes wording with no resolved symbol invented a --uses command: $WW0";; *) ok "who-writes wording alone (no resolved symbol) abstains rather than invent a SYM";; esac
# Execution check: the SYM:VAR and @FILE:LINE commands the router just emitted are not placeholders —
# strip the recommended argv's quoting and actually run it through the shipped --slice verb.
DFRUN="$( "$BIN" "$REPO" --no-cache --slice='computeBudget:budget' --slice-flow=back )"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$DFRUN" | grep -q '<slice '; } \
    && ok "the emitted data-flow SYM:VAR command runs and returns a <slice> root" \
    || no "the emitted data-flow SYM:VAR command failed to run (rc=$rc)"
ALRUN="$( "$BIN" "$REPO" --no-cache --slice='@router.cpp:10' )"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$ALRUN" | grep -q 'seed="router.cpp:10"'; } \
    && ok "the emitted at-line @FILE:LINE command runs and seeds at the named line" \
    || no "the emitted at-line @FILE:LINE command failed to run (rc=$rc)"

# ── the catalog tier: verbs and skills the router could not name at all (2026-09-10) ──────────────────
# F-R1-08: --help-task recommended on 3 of 39 phrasings of the 13 surfaces added since 2026-08-28, and
# three of the unrouted ones were VERBS — --handoff (which has its own shipped skill), --plan-lint, and
# the PROSE form of --from-trace (looksLikeTrace matches a PASTED artifact; "I have a sanitizer report"
# contains none of its literals). F-R1-09: the router could name 8 of the 16 shipped skills.
# Every recommend arm below is red against a pre-change binary: all of them abstained with score="0".
HO="$( route 'I am going on leave next week - put together a brief on the scheduler for whoever takes it over' )"
case "$HO" in *'status="recommend"'*'intent="handoff-brief"'*'skill="ripwire-handoff"'*'--handoff'*) ok "briefing a second party -> --handoff";; *) no "handoff route wrong: $HO";; esac
HO0="$( route 'we handed the account off to support last week, any update on the customer?' )"
case "$HO0" in *'--handoff'*) no "an account handover minted a --handoff route: $HO0";; *) ok "prose about handing over anything else mints no --handoff";; esac
PL="$( route 'check that docs/next-plan.md is well-formed as a plan document' )"
case "$PL" in *'status="recommend"'*'intent="plan-lint"'*'--plan-lint='*'docs/next-plan.md'*) ok "plan-structure wording + a named markdown file -> --plan-lint=FILE";; *) no "plan-lint route wrong: $PL";; esac
# Value-carrying, like --edit-plan: the verb refuses a file that is not there, so no file, no command.
PL0="$( route 'can you lint the structure of our planning docs in general?' )"
case "$PL0" in *'--plan-lint='*) no "plan-lint invented a file the task never named: $PL0";; *) ok "plan-lint abstains rather than invent a plan document";; esac
TP="$( route 'I have a sanitizer report from last night - map it onto the indexed symbols' )"
case "$TP" in *'status="recommend"'*'intent="trace-prose"'*'--from-trace=-'*) ok "a trace DESCRIBED rather than pasted -> --from-trace=-";; *) no "trace-prose route wrong: $TP";; esac
SS="$( route 'someone sent me a skills bundle - is it safe to install, any prompt injection in there?' )"
case "$SS" in *'status="recommend"'*'intent="scan-skills"'*'skill="ripwire-security-scan"'*'--scan-skills'*) ok "pre-install vetting -> --scan-skills";; *) no "scan-skills route wrong: $SS";; esac
SS1="$( route 'check tools/helper.md for exfiltration before installing it as a skill' )"
case "$SS1" in *'intent="scan-skill"'*'--scan-skill='*'tools/helper.md'*) ok "a named file upgrades the scan to --scan-skill=FILE";; *) no "scan-skill route wrong: $SS1";; esac
AH="$( route 'do we have a dependency mess in here - any circular dependencies or god file?' )"
case "$AH" in *'status="recommend"'*'intent="architecture-health"'*'skill="ripwire-layers"'*'--deps'*) ok "architecture-health wording -> --deps";; *) no "architecture-health route wrong: $AH";; esac
QC="$( route 'before I call it done - did my change make anything worse?' )"
case "$QC" in *'status="recommend"'*'intent="quality-check"'*'skill="ripwire-quality-bar"'*'--quality-delta'*) ok "own-code quality wording -> --quality-delta";; *) no "quality-check route wrong: $QC";; esac
# The narrow quality vocabulary must not steal the dirty-worktree review route, whose words are about a
# DIFF and a push. (This repo is CLEAN here, so review-diff cannot fire either way — assert the intent.)
QC0="$( route 'Reviewing my own diff now - am I ready to push and is this safe to merge?' )"
case "$QC0" in *'intent="quality-check"'*) no "diff-review wording was stolen by quality-check: $QC0";; *) ok "diff-review wording is not a quality-delta request";; esac
PS="$( route 'the profiler puts targetSymbol at the top - what is around it' )"
case "$PS" in *'status="recommend"'*'intent="perf-symbol"'*'skill="ripwire-perf-target"'*'--around='*'targetSymbol'*) ok "a measured profile + the symbol it names -> --around=SYM";; *) no "perf-symbol route wrong: $PS";; esac
PS0="$( route 'the profiler vendor is offering licenses, should we buy a few seats?' )"
case "$PS0" in *'--around='*) no "profile wording with no resolved symbol invented an --around: $PS0";; *) ok "profile wording alone (no symbol) abstains rather than invent one";; esac
GQ="$( route 'which functions can reach targetSymbol - one-hop callers cannot phrase that' )"
case "$GQ" in *'status="recommend"'*'intent="graph-query"'*'skill="ripwire-graph-query"'*'--graph-query='*'targetSymbol'*) ok "a bounded-closure question + one symbol -> --graph-query=EXPR";; *) no "graph-query route wrong: $GQ";; esac
MR="$( route 'where is the rot in code I did not write' )"
case "$MR" in *'status="recommend"'*'intent="maintenance-risk"'*'skill="ripwire-fresh-eyes"'*'--hotspots'*) ok "maintenance-risk wording -> --hotspots";; *) no "maintenance-risk route wrong: $MR";; esac
OR="$( route 'clang says the inner loop was not vectorized - is that worth a diff here?' )"
case "$OR" in *'status="recommend"'*'intent="opt-remark"'*'skill="ripwire-opt-remarks"'*'--for='*) ok "a clang optimization remark -> the ranked lens, under the opt-remarks skill";; *) no "opt-remark route wrong: $OR";; esac
# Execution check: the two catalog commands that carry a COMPOSED value are not placeholders. Unquote
# what the router emitted and run it through the real verb, the same way the SYM:VAR arm above does.
GQEXPR="$( printf '%s' "$GQ" | sed -n 's|.*--graph-query=&apos;\(.*\)&apos;\( --legend=compact\)\{0,1\}</run>.*|\1|p' | sed 's/&quot;/"/g' )"
# L1 (2026-09-19): the default root is compact (<query schema=… expr=…>); this arm pins the full root's `<query expr=`.
GQRUN="$( "$BIN" "$REPO" --no-cache --graph-query="$GQEXPR" --legend=full )"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$GQRUN" | grep -q '<query expr='; } \
    && ok "the emitted --graph-query expression runs and returns a <query> root" \
    || no "the emitted --graph-query expression failed to run (rc=$rc, expr=[$GQEXPR])"
printf '# A plan\n\n## Goal\n\nship it\n' >"$REPO/plan-gate.md"
PLRUN="$( "$BIN" "$REPO" --no-cache --plan-lint=plan-gate.md )"; rc=$?
[ $rc -le 2 ] && ok "the emitted --plan-lint=FILE command runs against a real plan file (rc=$rc)" \
              || no "the emitted --plan-lint=FILE command failed to run (rc=$rc)"
rm -f "$REPO/plan-gate.md"

# ── the recency window: what the repository has been MOVING (2026-09-13) ──────────────────────────────
# "what changed recently in storage/" had no route at all — every phrasing abstained with score="0", so
# the verb that answers it (--rank-by=churn-decay, and its --in=DIR scope) was unreachable from a task
# said in words. Every recommend arm below is RED against a pre-change binary (abstain, score="0").
#
# The route is CONJUNCTIVE in THREE parts: a time word, a motion word, and a word naming the CORPUS (or a
# directory of it the task named). Two are not enough — a supplier who revised their terms last quarter
# satisfies the first two — and the single-word cues are WORD-BOUNDED, which the decoy arms below are
# about: `here` occurs inside where/there/adhere, `source` inside outsource, `file` inside profile, `code`
# inside codec. With the substring spelling each of those sentences recommended the churn window at
# confidence="high" (2026-09-13 review); each is an arm now.
RW1="$( route 'what changed recently in this repository' )"
case "$RW1" in *'status="recommend"'*'intent="recency-window"'*'skill="ripwire-fresh-eyes"'*'--rank-by=churn-decay'*) ok "time word + motion word + corpus word -> --rank-by=churn-decay";; *) no "recency route wrong: $RW1";; esac
RW2="$( route 'who touched files in storage lately' )"
case "$RW2" in *'status="recommend"'*'intent="recency-window"'*'--rank-by=churn-decay'*) ok "who-touched wording routes to the recency window";; *) no "who-touched recency route wrong: $RW2";; esac
# The vocabulary the 2026-09-13 review found missing: verbs weighted below the floor, and the two time
# spellings git itself uses. All three abstained before it.
for P in 'what landed in storage this week' \
         'commits since Monday under storage' \
         'what is new in the storage directory'; do
    RWV="$( route "$P" )"
    case "$RWV" in *'intent="recency-window"'*'--rank-by=churn-decay'*) ok "recency vocabulary routes: $P";; *) no "recency vocabulary missed [$P]: $RWV";; esac
done
# WORD-BOUNDED single-word cues. Each of these four carries a time word and a motion word and is about the
# world outside the checkout; each routed at confidence="high" when the corpus cue was a substring match.
for P in 'our supplier changed their terms recently, where is that noted?' \
         'we outsource the icon work and that vendor changed their rates last week' \
         'the marketing profile was updated recently by the agency' \
         'the audio codec people changed their licence last month'; do
    RWD="$( route "$P" )"
    case "$RWD" in *'--rank-by=churn-decay'*) no "a substring corpus cue minted the churn window [$P]: $RWD";; *) ok "a corpus cue inside another word never mints the window: ${P:0:44}";; esac
done
# THE WORKING TREE IS A DIFFERENT QUESTION, and the route reads `dirty` by sitting below the weighted tier
# where the dirty-only review route lives. Red against the first cut of this lane (recency-window).
printf '\n// dirty for the recency arm\n' >>"$REPO/router.cpp"
RWT="$( route 'is my diff safe to merge, i changed these files recently' )"
case "$RWT" in *'status="recommend"'*'intent="review-diff"'*'--situ'*) ok "on a DIRTY tree the diff question stays review-diff, not the churn window";; *) no "the churn window stole the dirty-worktree review question: $RWT";; esac
git -C "$REPO" restore router.cpp
# The DIRECTORY half. --in=DIR refuses a directory that is not under the root, so the router composes it
# only when the corpus really holds one — and only when the BUILD ships the flag. Both directions are
# asserted against the shipped flag table, because a router that recommends a flag its own binary does
# not have is a prerequisite violation, and one that drops a scope the binary does have is a lost answer.
RW3="$( route 'what changed recently in storage/' )"
if "$BIN" --help=all 2>&1 | grep -q -- '--in='; then
    case "$RW3" in *'--rank-by=churn-decay'*'--in='*'storage'*) ok "a named directory in the corpus scopes the window (--in=storage)";; *) no "recency route did not scope to the named directory: $RW3";; esac
    RWRUN="$( "$BIN" "$REPO" --no-cache --rank-by=churn-decay --in=storage )"; rc=$?
    { [ $rc -eq 0 ] && printf '%s' "$RWRUN" | grep -q '<recent '; } \
        && ok "the emitted scoped recency command runs and returns a <recent> block" \
        || no "the emitted scoped recency command failed to run (rc=$rc)"
else
    case "$RW3" in *'--in='*) no "the router composed --in= on a build whose flag table does not ship it: $RW3";; *) ok "this build ships no --in= flag, and the router composes none";; esac
    # …and a dropped scope is DISCLOSED: the caller asked about one directory and is being handed the whole
    # repository, which the reason is the only place to say (2026-09-13 review).
    case "$RW3" in *'reason="'*'cannot scope'*) ok "the dropped directory scope is disclosed in the reason";; *) no "a named directory was dropped silently: $RW3";; esac
fi
RWRUN0="$( "$BIN" "$REPO" --no-cache --rank-by=churn-decay )"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$RWRUN0" | grep -q '<recent '; } \
    && ok "the emitted bare recency command runs and returns a <recent> block" \
    || no "the emitted bare recency command failed to run (rc=$rc)"
# A directory the corpus does NOT hold is never composed: --in= would refuse it.
RW4="$( route 'what changed recently in the vendor folder of this repo' )"
case "$RW4" in *'--rank-by=churn-decay'*) case "$RW4" in *'--in='*) no "the router invented a directory the corpus does not hold: $RW4";; *) ok "an unindexed directory name mints no scope — the window is still served, unscoped";; esac;; *) no "an unindexed directory name lost the route entirely: $RW4";; esac
# EARLIEST slot wins, across cues: the sentence names a real directory first and a non-directory later, and
# the answer must be the first one. Cue-table order gave `in test` here before the walk was shared.
RW5="$( route 'what changed lately across storage, but only in the release notes' )"
case "$RW5" in *'intent="recency-window"'*) ok "the earliest directory slot is the one the window scopes to";; *) no "earliest-slot recency route wrong: $RW5";; esac
# Decoys: a time word inside a NAME, and an explanatory question that satisfies all three conjuncts.
RW0="$( route 'the recent-file cache keeps the last 40 entries' )"
case "$RW0" in *'--rank-by=churn-decay'*) no "a time word inside a compound NAME minted a churn window: $RW0";; *) ok "'the recent-file cache' is a cache, not a history question";; esac
RW0B="$( route 'we recently agreed to ship the announcement on friday' )"
case "$RW0B" in *'--rank-by=churn-decay'*) no "a time word with no motion word minted a churn window: $RW0B";; *) ok "a time word alone never mints the recency window";; esac
RW0C="$( route 'how do we rebuild the list of recently changed files' )"
case "$RW0C" in *'--rank-by=churn-decay'*) no "an explanatory question satisfying all three conjuncts still routed: $RW0C";; *) ok "an explanatory question is never the history route";; esac
# …and a MULTI-WORD cue is not self-delimiting either (2026-09-13, second review round). The review above
# bounded the single-word cues on the reasoning that "a phrase carries its own boundaries" — true of the
# space INSIDE a phrase, false at its two ends: the first word of `how do` can finish another word and the
# last can start one. `show documentation` contains `how do`, `show issues` contains `how is`, and both
# sentences below therefore tripped the EXPLANATORY guard and lost the route they are asking for. RED
# against the unbounded spelling (abstain, score="0") for both.
for P in 'show issues with the files in storage that changed recently' \
         'show documentation files in storage that changed recently'; do
    RWE="$( route "$P" )"
    case "$RWE" in *'intent="recency-window"'*'--rank-by=churn-decay'*) ok "an explanatory cue spanning two other words does not kill the route: $P";; *) no "a cross-word explanatory cue killed the recency route [$P]: $RWE";; esac
done
# The control the arm above must not buy at the price of: a real explanatory question, bounded cue and all.
RW0D="$( route 'how do i see the files in storage that changed recently' )"
case "$RW0D" in *'--rank-by=churn-decay'*) no "a genuine explanatory question routed once the cues were bounded: $RW0D";; *) ok "'how do i …' is still never the history route";; esac

# ── the WIDENING page is named on the FIRST call, not only after a thin answer ────────────────────────
# forpage.h's next= names `--for=TASK --limit=N` when the answer it already served came back thin. That
# is one call too late for an agent choosing what to run first, so every --for-shaped recommendation
# carries the same widening step as its own next=. RED against a pre-change binary: no <choice> carried
# the attribute. Keyed off the INTENT and spelled by forpage.h (2026-09-13 review): keyed off the COMMAND
# STRING, a task that merely QUOTES the flag handed --pack-task a page width it refuses (exit 1).
FW="$( route 'Find the code responsible for this retry timeout bug' )"
case "$FW" in *'intent="locate-task"'*'next='*'--limit=40'*) ok "a --for-shaped recommendation names the widening page as its next=";; *) no "locate-task carries no widening next=: $FW";; esac
case "$MR" in *'next='*) no "a non---for recommendation carried a next= (present-only): $MR";; *) ok "a recommendation that is not a --for carries no next=";; esac
FQ="$( route 'plan the new feature: replace the --for= flag scoring and the budget' )"
case "$FQ" in *'next='*) no "a task that merely QUOTES the for flag was given a widening next=: $FQ";; *) ok "a quoted flag inside another verb's task text mints no next=";; esac
route 'Find the code responsible for this retry timeout bug' >"$TMP/fw.xml"
FWNEXT="$( python3 - "$TMP/fw.xml" <<'PY'
import sys, shlex, xml.etree.ElementTree as ET
root = ET.parse( sys.argv[1] ).getroot()
choice = root.find( 'choice' )
nxt = '' if choice is None else choice.get( 'next', '' )
sys.stdout.write( '\n'.join( shlex.split( nxt ) ) )
PY
)"
FWBYTES="$( printf '%s' "$FWNEXT" | tr '\n' ' ' | wc -c | tr -d ' ' )"
if [ -n "$FWNEXT" ]; then
    OLDIFS="$IFS"; IFS='
'; set -f; # shellcheck disable=SC2086
    set -- $FWNEXT; IFS="$OLDIFS"; set +f
    FWRUN="$( "$BIN" "$REPO" --no-cache "$@" )"; rc=$?
    { [ $rc -eq 0 ] && printf '%s' "$FWRUN" | grep -q '<files '; } \
        && ok "the emitted widening next= runs and returns the file-grain <files> page" \
        || no "the emitted widening next= failed to run (rc=$rc, argv=[$FWNEXT])"
    [ "$FWBYTES" -le 121 ] \
        && ok "the widening next= is ${FWBYTES} B, comfortably short for an ordinary task string" \
        || no "the widening next= is ${FWBYTES} B, unexpectedly long for this fixture's short task"
else
    no "no next= recovered from the locate-task recommendation"
fi
# …and past the OLD ceiling it used to emit no HINT AT ALL (base), then this lane's first draft disclosed
# the loss as next_dropped="1" instead of the full invocation — still no route back to the rest. The
# ruling (2026-09-25): nextAttrXml carries no length ceiling, so an over-long task's widening
# next= is now the FULL forWidenNext invocation, and it must paste and run. RED on origin/main: no next=
# at all on the choice for a task this long.
LONGTASK="Find the code responsible for this retry timeout bug in the scheduler and the queue and the retry budget and the backoff table and the metrics"
route "$LONGTASK" >"$TMP/fwl.xml"
FWLRAWNEXT="$( python3 - "$TMP/fwl.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse( sys.argv[1] ).getroot()
choice = root.find( 'choice' )
sys.stdout.write( '' if choice is None else choice.get( 'next', '' ) )
PY
)"
if [ -z "$FWLRAWNEXT" ]; then
    no "an over-long task's widening next= is absent (want the full forWidenNext invocation)"
else
    if [ "${#FWLRAWNEXT}" -gt 120 ]; then ok "the over-long task's widening next= is emitted in full (${#FWLRAWNEXT} B), never dropped"
    else no "this task's widening next= is only ${#FWLRAWNEXT} B (<=120) — not a real test of the no-ceiling rule"; fi
    FWLNEXT="$( python3 -c 'import shlex, sys; sys.stdout.write( "\n".join( shlex.split( sys.argv[1] ) ) )' "$FWLRAWNEXT" )"
    OLDIFS="$IFS"; IFS='
'; set -f; # shellcheck disable=SC2086
    set -- $FWLNEXT; IFS="$OLDIFS"; set +f
    FWLRUN="$( "$BIN" "$REPO" --no-cache "$@" )"; rcl=$?
    { [ $rcl -eq 0 ] && printf '%s' "$FWLRUN" | grep -q '<files '; } \
        && ok "the over-long task's full widening next= runs and returns the file-grain <files> page" \
        || no "the over-long task's widening next= failed to run (rc=$rcl, argv=[$FWLRAWNEXT])"
fi

# ── two routers, ONE vocabulary: every shipped skill must be nameable by --help-task ──────────────────
# F-R1-09 measured 8 of 16. This arm reads BOTH sides from disk — the skill directories that exist, and
# the skill= names src/taskroute.h can emit — so it fails when a NEW skill ships with no route as much as
# when a route names a skill that does not exist. ripwire-router is excluded: it is the fallback map, not
# a destination (test/skillevalcheck.sh refuses it as a label for the same reason).
routerNames="$( grep -o 'ripwire-[a-z-]*' "$ROOT/src/taskroute.h" | sort -u )"
unnameable=""; phantom=""
for _d in "$ROOT"/skills/*/; do
    _s="$( basename "$_d" )"
    [ -f "$_d/SKILL.md" ] || continue
    [ "$_s" = "ripwire-router" ] && continue
    printf '%s\n' "$routerNames" | grep -qx "$_s" || unnameable="$unnameable $_s"
done
for _n in $routerNames; do
    [ -f "$ROOT/skills/$_n/SKILL.md" ] || phantom="$phantom $_n"
done
[ -z "$unnameable" ] && ok "every shipped skill (except ripwire-router) is nameable by --help-task" \
                     || no "shipped skill(s) no --help-task answer can ever name:$unnameable"
[ -z "$phantom" ] && ok "every skill the router can name exists on disk" \
                  || no "router names skill(s) with no directory:$phantom"

N="$( route 'Write a cheerful release announcement' )"
case "$N" in *'status="abstain"'*) ok "off-topic prompt abstains";; *) no "off-topic prompt did not abstain: $N";; esac
if [ "$( printf '%s' "$N" | grep -o '<run>' | wc -l | tr -d ' ' )" = 0 ]; then ok "abstention emits zero commands"; else no "abstention emitted a command"; fi
if [ "$( printf '%s' "$D" | grep -o '<run>' | wc -l | tr -d ' ' )" = 1 ]; then ok "recommendation emits exactly one command"; else no "recommendation command cardinality != 1"; fi

Q="Plan feature O'Brien & <friends>; touch $TMP/PWNED"
route "$Q" >"$TMP/q1"; route "$Q" >"$TMP/q2"
if diff -q "$TMP/q1" "$TMP/q2" >/dev/null; then ok "task routing byte-identical"; else no "task routing nondeterministic"; fi
if [ ! -e "$TMP/PWNED" ]; then ok "task text executes nothing"; else no "task text was executed"; fi
if grep -Fq 'O&apos;\&apos;&apos;Brien' "$TMP/q1"; then ok "single quote receives POSIX shell quoting"; else no "recommended argv is not safely shell-quoted"; fi
if command -v xmllint >/dev/null 2>&1; then if xmllint --noout "$TMP/q1" 2>/dev/null; then ok "task route XML well formed"; else no "task route XML malformed"; fi; fi

"$BIN" "$REPO" --help-task= >/dev/null 2>"$TMP/empty.err"; rc=$?
if [ "$rc" -ne 0 ] && grep -q 'needs' "$TMP/empty.err"; then ok "empty task refuses"; else no "empty task did not refuse clearly"; fi
"$BIN" "$REPO" --help-task='plan a feature' --json >/dev/null 2>"$TMP/json.err"; rc=$?
if [ "$rc" -ne 0 ] && grep -qi 'json' "$TMP/json.err"; then ok "unsupported --json combination refuses"; else no "--json combination did not refuse"; fi
"$BIN" "$REPO" "$ROOT/test/fixture" --help-task='plan a feature' >/dev/null 2>"$TMP/multi.err"; rc=$?
if [ "$rc" -ne 0 ] && grep -qi 'single-root' "$TMP/multi.err"; then ok "multi-root routing refuses"; else no "multi-root routing did not refuse"; fi
for f in --verify --connect --expand --grep --grep-context --edit-check --from-trace --situ --pack-task --exemplar --for \
         --edit-plan --dry-run --handles --legend --doctor --agent=codex --test-gate --slice --slice-flow --at --uses --seams \
         --rank-by= --limit=; do "$BIN" --help=all 2>&1 | grep -q -- "$f" || no "recommended flag absent from --help: $f"; done

# ── byte-compat: the verify-claim template must emit the SHIPPED --verify grammar byte-exactly ─────────
# (PLAN 2026-08-13 addendum: gate against the real verb's PARSER, never a copy of its syntax.)
# Route a claim through --help-task, unquote the recommended argv robustly (a real XML parse + a real
# POSIX tokenizer, not a regex over quotes), then EXECUTE the real verb. Acceptance = exit 0 plus a
# well-formed <verify> root carrying a three-valued verdict (any of the three counts); a refusal
# (non-zero, no root) on an emitted claim is exactly the drift this arm exists to catch. Byte-exactness
# is asserted twice: the unquoted --verify= argument must equal the task's claim text, and the parser's
# own claim= echo on the root must equal it again after XML decoding.
claim_from_route(){ python3 - "$1" <<'PY'
import sys, shlex, xml.etree.ElementTree as ET
run = ET.parse( sys.argv[1] ).getroot().find( './/run' )
if run is None or not run.text: sys.exit( 3 )
for tok in shlex.split( run.text ):
    if tok.startswith( '--verify=' ):
        sys.stdout.write( tok[ len( '--verify=' ): ] ); sys.exit( 0 )
sys.exit( 4 )
PY
}
claim_echo_of(){ python3 - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
sys.stdout.write( ET.parse( sys.argv[1] ).getroot().get( 'claim', '' ) )
PY
}
for CLAIM in 'calls(betaNode, alphaNode)' 'uses(targetSymbol)' 'reaches(alphaNode, "router.cpp")'; do
    shape="${CLAIM%%(*}"
    route "$CLAIM" >"$TMP/bc.$shape.route.xml"
    grep -q 'intent="verify-claim"' "$TMP/bc.$shape.route.xml" \
        && ok "byte-compat $shape: the claim routes to verify-claim" \
        || { no "byte-compat $shape: claim did not route to verify-claim: $( cat "$TMP/bc.$shape.route.xml" )"; continue; }
    GOT="$( claim_from_route "$TMP/bc.$shape.route.xml" )" \
        || { no "byte-compat $shape: no --verify= argument recoverable from <run>"; continue; }
    [ "$GOT" = "$CLAIM" ] \
        && ok "byte-compat $shape: the emitted --verify= argument round-trips byte-identical" \
        || no "byte-compat $shape: emitted claim diverges after unquoting: [$GOT] != [$CLAIM]"
    "$BIN" "$REPO" --no-cache --verify="$GOT" >"$TMP/bc.$shape.out.xml" 2>"$TMP/bc.$shape.err"; rc=$?
    RV="$( grep -o '<verify [^>]*>' "$TMP/bc.$shape.out.xml" | head -1 )"
    { [ $rc -eq 0 ] && printf '%s' "$RV" | grep -Eq 'verdict="(confirmed|refuted|not-established)"'; } \
        && ok "byte-compat $shape: the shipped parser ACCEPTED the emitted claim with a verdict" \
        || { no "byte-compat $shape: the real parser refused the emitted claim (rc=$rc)"; head -2 "$TMP/bc.$shape.err"; continue; }
    printf '%s' "$RV" | grep -q "shape=\"$shape\"" \
        && ok "byte-compat $shape: the verdict root names the claimed shape" \
        || no "byte-compat $shape: shape= on the verify root disagrees with the claim"
    ECHOED="$( claim_echo_of "$TMP/bc.$shape.out.xml" )"
    [ "$ECHOED" = "$CLAIM" ] \
        && ok "byte-compat $shape: the parser's claim= echo is byte-identical to the task's claim" \
        || no "byte-compat $shape: parser echoed a different claim: [$ECHOED] != [$CLAIM]"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/bc.$shape.out.xml" 2>/dev/null \
            && ok "byte-compat $shape: verdict XML well formed" \
            || no "byte-compat $shape: verdict XML malformed"
    fi
done

# A reaches claim whose unquoted second argument is NOT a built-in layer word is a claim the shipped
# parser refuses — recommending --verify for it would be a prerequisite-violating route. The router
# must treat it as not-a-closed-claim (here: no stronger evidence remains, so it abstains).
RB="$( route 'reaches(alphaNode, gammaNode)' )"
case "$RB" in
    *'--verify='*) no "reaches(SYM,SYM) recommended the parser-refused --verify form: $RB";;
    *) ok "reaches(SYM,SYM) never routes to a command the --verify parser refuses";;
esac

EVAL="$( python3 "$ROOT/bench/taskroute_eval.py" --bin "$BIN" --corpus "$ROOT/test/taskroutefix/prompts.tsv" --split test 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ]; then ok "held-out command-routing floors ($EVAL)"; else no "held-out command-routing floors failed: $EVAL"; fi

# ── round-1 L4: first-verb cards for the four shapes the router used to abstain on (PLAN_OUTPUT_ROUTING_
# LOOP_2026-09-12_REPORTS/11_round1_PREREG.md §E, restated) ─────────────────────────────────────────────
# The mining finding (--help-task over the round's 60-question corpus): the router recommended NOTHING on
# all 48 S1-S4 instances of "which tests cover F", "if I change F what else has to change", "how does A
# reach B" and "where is X implemented" — every arm below is RED against the pre-lane binary (origin/
# integration/train-6, 7d72e723): each of TC1/CI1/RF1/LI1 abstained with score="0" there.
TC1="$( route 'Which tests cover db/write_batch.cc?' )"
case "$TC1" in *'status="recommend"'*'intent="test-coverage"'*'--affected='*'db/write_batch.cc'*) ok "S3 mining template -> --affected=F";; *) no "test-coverage route wrong: $TC1";; esac
TC2="$( route 'is table/block_fetcher.cc covered by any test' )"
case "$TC2" in *'intent="test-coverage"'*'--affected='*'table/block_fetcher.cc'*) ok "S3 paraphrase (covered by any test) -> --affected=F";; *) no "test-coverage paraphrase missed: $TC2";; esac
TC0="$( route 'Which tests cover db/does_not_exist.cc?' )"
case "$TC0" in *'--affected='*) no "test-coverage recommended a file this build never indexed: $TC0";; *) ok "test-coverage abstains on a file this build never indexed (the verb would refuse it)";; esac

CI1="$( route 'If I change db/wal_manager.cc, what else has to change with it?' )"
case "$CI1" in *'status="recommend"'*'intent="change-impact"'*'--situ='*'db/wal_manager.cc'*) ok "S2 mining template -> --situ=F";; *) no "change-impact route wrong: $CI1";; esac
case "$CI1" in *'--legend=compact'*) no "change-impact illegally carries --legend=compact on a --situ command: $CI1";; *) ok "change-impact carries no --legend=compact (the verb refuses the flag)";; esac
CI2="$( route 'blast radius of modifying table/get_context.cc' )"
case "$CI2" in *'intent="change-impact"'*'--situ='*'table/get_context.cc'*) ok "S2 paraphrase (blast radius) -> --situ=F";; *) no "change-impact paraphrase missed: $CI2";; esac
CI0="$( route 'If I change db/does_not_exist.cc, what else has to change with it?' )"
case "$CI0" in *'--situ='*) no "change-impact recommended a file this build never indexed: $CI0";; *) ok "change-impact abstains on a file this build never indexed";; esac

RF1="$( route 'How does db/db_iter.cc reach db/wide/wide_columns_helper.h?' )"
case "$RF1" in *'status="recommend"'*'intent="reach-flow"'*'--for='*) ok "S4 mining template -> --for=task";; *) no "reach-flow route wrong: $RF1";; esac
RF2="$( route 'how is util/heap.h used by table/iter_heap.h' )"
case "$RF2" in *'intent="reach-flow"'*'--for='*) ok "S4 paraphrase (used by) -> --for=task";; *) no "reach-flow paraphrase missed: $RF2";; esac
RF0="$( route 'how does targetSymbol reach the cache layer' )"
case "$RF0" in *'intent="reach-flow"'*) no "reach-flow fired with fewer than two indexed files named: $RF0";; *) ok "reach-flow needs two indexed files, not reach/call-chain wording alone";; esac

# CodeRabbit thread 4053600624 (src/taskroute.h:1417): reachScore used to match "reach" as a plain
# SUBSTRING, so it fired inside "outreach" (and "unreachable") — a task about an "outreach loader" that
# happens to name two indexed files, plus one other cheap phrase cue ("how does", weight 2), crossed the
# reach-flow threshold (2 + the false "reach" hit's 5 = 7) and wrongly recommended --for=task. Word-bounded
# matching ("reach" only as its own word) drops that to 2, below the threshold, so this now abstains.
RF3="$( route 'how does the outreach loader connect db/write_batch.cc and cache/lru_cache.cc' )"
case "$RF3" in *'intent="reach-flow"'*) no "'outreach' wrongly fired the substring 'reach' cue: $RF3";; *) ok "'outreach loader' names two indexed files but never fires reach-flow (\"reach\" is word-bounded)";; esac

LI1="$( route 'Where is the write batch implemented?' )"
case "$LI1" in *'status="recommend"'*'intent="locate-implementation"'*'--for='*) ok "S1 mining template -> --for=task";; *) no "locate-implementation route wrong: $LI1";; esac
LI2="$( route 'which file implements the WRITE_STALL start time fix' )"
case "$LI2" in *'intent="locate-implementation"'*'--for='*) ok "S1 paraphrase (which file implements) -> --for=task";; *) no "locate-implementation paraphrase missed: $LI2";; esac
LI0="$( route 'where is the nearest coffee shop' )"
case "$LI0" in *'intent="locate-implementation"'*) no "'where is' alone (no 'implemented') minted locate-implementation: $LI0";; *) ok "'where is' alone never mints locate-implementation without 'implemented'";; esac

# ── PARAPHRASE ARM (Amendment 1 §E, wording frozen at pre-registration) — every prompt below is written
# OUTSIDE derive_questions_window.py's four generation templates on purpose: this arm measures
# generalisation, not template lookup. Pass condition, pre-registered: recommend-with-the-registered-verb
# >= 2/3 per shape, and 0 wrong-verb recommendations overall (an abstention on the third of each triple
# is an acceptable miss — it costs another call, never a wrong one).
PARA_S3=( 'what test files exercise db/write_batch.cc'
          'I touched cache/lru_cache.cc — which unit tests should I run?'
          'is table/block_fetcher.cc covered by any test' )
PARA_S2=( 'what breaks if I edit db/wal_manager.cc'
          'blast radius of modifying table/get_context.cc'
          'what depends on db/db_impl/db_impl.cc, what do I need to update alongside it' )
PARA_S1=( 'which file implements the WRITE_STALL start time fix'
          'find the code for MultiGet skip_memtable handling'
          'where does rocksdb record persist_user_defined_timestamps in the manifest' )
PARA_S4=( 'call chain from db/db_iter.cc into db/wide/wide_columns_helper.h'
          'how is util/heap.h used by table/iter_heap.h'
          'how does db/write_batch.cc reach cache/lru_cache.cc on the write path' )
PARA_WRONG=0
para_check(){
    local shape="$1" acceptRe="$2"; shift 2
    local total=0 pass=0 p out status intent
    for p in "$@"; do
        total=$(( total + 1 ))
        out="$( route "$p" )"
        status="$( printf '%s' "$out" | grep -o 'status="[a-z]*"' | head -1 )"
        intent="$( printf '%s' "$out" | grep -o 'intent="[a-zA-Z-]*"' | head -1 )"
        if [ "$status" = 'status="recommend"' ] && printf '%s' "$intent" | grep -qE "$acceptRe"; then
            pass=$(( pass + 1 ))
        elif [ "$status" = 'status="recommend"' ]; then
            PARA_WRONG=$(( PARA_WRONG + 1 ))
            printf '        WRONG-VERB (%s): %s -> %s\n' "$shape" "$p" "$intent"
        fi
    done
    if [ "$pass" -ge 2 ]; then
        ok "paraphrase arm $shape: $pass/$total recommend-with-registered-verb (>= 2/3 floor)"
    else
        no "paraphrase arm $shape: only $pass/$total recommend-with-registered-verb (< 2/3 floor)"
    fi
}
para_check S3 'intent="test-coverage"' "${PARA_S3[@]}"
para_check S2 'intent="change-impact"' "${PARA_S2[@]}"
para_check S1 'intent="locate-implementation"|intent="locate-task"' "${PARA_S1[@]}"
para_check S4 'intent="reach-flow"' "${PARA_S4[@]}"
[ "$PARA_WRONG" -eq 0 ] \
    && ok "paraphrase arm: 0 wrong-verb recommendations across all 12 (self-reject floor)" \
    || no "paraphrase arm: $PARA_WRONG wrong-verb recommendation(s) (listed above)"

# ── the document defines what it prints (2026-09-13 review) ──────────────────────────────────────────
# The default dialect carried NO legend: every attribute on its only screen was undefined, and the compact
# layer's present-only legend was the only place any of them was explained. RED against a pre-change
# binary: the document begins with "<task-route", not with a comment.
# L1 (2026-09-19): the CLI default legend is compact, whose present-only reading is not this arm's subject; the FULL
# legend's definitions are, so the document is asked for in that posture.
LG="$( "$BIN" "$REPO" --no-cache --help-task='Find the code responsible for this retry timeout bug' --legend=full 2>"$TMP/err" | python3 -c 'import sys
s=sys.stdin.read(); a=s.find("<!--"); b=s.find("-->", a)
sys.stdout.write(s[a+4:b] if a>=0 and b>=0 else "")' )"
[ -n "$LG" ] \
    && ok "the task-route document carries a legend" \
    || no "the task-route document has no legend at all"
for A in 'status=' 'confidence=' 'score=' 'margin=' 'git=' 'dirty=' 'trace=' 'resolved_symbols=' 'intent=' 'skill=' 'reason=' 'next=' '<run>'; do
    case "$LG" in *"$A"*) ok "the legend defines '$A'";; *) no "the legend never mentions '$A' — a first-screen attribute with no definition";; esac
done
case "$LG" in *--*) no "the legend contains '--' — ill-formed inside an XML comment (G4)";; *) ok "the legend spells no '--' (XML-comment safe)";; esac

# ── R-LEG: every command this router GENERATES is one the binary accepts (PR #215 review item 5) ───────────
# A1-2 put --legend=compact on the route commands by editing 26 strings. That is 26 chances to be wrong and no
# rule for the 27th, and the same hand-application shipped `--zoom --legend=compact --mermaid` into a skill —
# a command the binary REFUSES. classify() applies the posture once now (rw::legendCompactAppliesTo), and this
# arm is what makes that a fact rather than an intention: every <run> the router emits over the whole prompt
# corpus is executed against an EMPTY directory, and the refusal line must never appear. The refusal is a
# parse-time check, so an empty corpus answers in milliseconds and no operand can mask it.
RLEG_EMPTY="$TMP/rleg_empty"; mkdir -p "$RLEG_EMPTY"
cut -f5 "$ROOT/test/taskroutefix/prompts.tsv" 2>/dev/null | sed '1d' > "$TMP/rleg_tasks.txt"   # column 5 is the prompt
: > "$TMP/rleg_cmds.txt"
while IFS= read -r _t; do
    [ -n "$_t" ] || continue
    route "$_t" 2>/dev/null | grep -oE '<run>[^<]*' | sed 's/^<run>//' >> "$TMP/rleg_cmds.txt"
done < "$TMP/rleg_tasks.txt"
# the <run> line is XML-escaped; unescape the two entities the router can emit, then drop the leading `ripwire`
sed -e "s/&apos;/'/g" -e 's/&quot;/"/g' -e 's/&amp;/\&/g' "$TMP/rleg_cmds.txt" | sort -u > "$TMP/rleg_u.txt"
# THE STATUS, CAPTURED RATHER THAN SWALLOWED (CodeRabbit, PR #215). This ran each command under
# `eval … || true`, which discards every exit status unconditionally: the arm could not tell a clean run from
# a crash, and the only failure it could see was the one refusal string it greps for. Deleting the `|| true`
# is not the fix either — most of these routes point at an EMPTY directory, where a nonzero exit is the
# DOCUMENTED answer, not a defect. So each status is captured and compared against what a routed command may
# legitimately return here:
#   0  the verb answered;
#   1  the verb's own documented "nothing in this corpus to answer" degrade — no symbol matched, no plan file
#      to read, no ranked candidate; and for the --test-gate route, "no files given and no git diff".
# MEASURED over the whole corpus on this binary (2026-09-14): 34 distinct commands, 15 exit 0 and 19 exit 1,
# nothing else. Any OTHER status is reported: 2 is cannot-conclude, 3 a token-budget refusal, 4 a test-gate
# blast radius, >=128 a signal — each one means the router emitted a command that neither answered nor
# degraded, and `|| true` printed PASS for every one of them.
# The stderr side widens for the same reason: the compact-legend refusal was the only parse refusal looked
# for, so its siblings — an unknown flag, an unrecognised verb — were invisible. A command the parser refuses
# is a wrong command whatever the wording, and a parse refusal is reported even when the status looks benign.
rleg_n=0; rleg_bad=0; rleg_st_bad=0; rleg_st0=0; rleg_st1=0
while IFS= read -r _c; do
    [ -n "$_c" ] || continue
    _args="${_c#ripwire }"
    _args="${_args#\'*\' }"          # the quoted root the router spells; this arm supplies its own
    rleg_n=$(( rleg_n + 1 ))
    # shellcheck disable=SC2086
    eval "\"\$BIN\" \"\$RLEG_EMPTY\" $_args" >/dev/null 2>"$TMP/rleg.err"
    _st=$?
    case "$_st" in
        0) rleg_st0=$(( rleg_st0 + 1 )) ;;
        1) rleg_st1=$(( rleg_st1 + 1 )) ;;
        *) rleg_st_bad=$(( rleg_st_bad + 1 ))
           if [ "$rleg_st_bad" -le 5 ]; then
               printf '        EXIT %s (expected 0 or the documented 1): %s\n' "$_st" "$( printf '%s' "$_c" | head -c 140 )"
               printf '                stderr: %s\n' "$( head -c 160 "$TMP/rleg.err" | tr '\n' ' ' )"
           fi ;;
    esac
    if grep -qE 'applies to the XML verbs only|unknown flag|unknown verb|unrecognized' "$TMP/rleg.err"; then
        rleg_bad=$(( rleg_bad + 1 ))
        [ "$rleg_bad" -le 5 ] && printf '        REFUSED (exit %s): %s\n' "$_st" "$( printf '%s' "$_c" | head -c 140 )"
    fi
done < "$TMP/rleg_u.txt"
[ "$rleg_n" -gt 0 ] || no "R-LEG: the prompt corpus produced no <run> command — this arm proved nothing"
[ "$rleg_bad" -eq 0 ] \
    && ok "R-LEG: all $rleg_n distinct generated commands are ACCEPTED by this binary (the router cannot emit a command its own binary refuses)" \
    || no "R-LEG: $rleg_bad of $rleg_n generated commands are REFUSED by this binary (listed above)"
[ "$rleg_st_bad" -eq 0 ] \
    && ok "R-LEG: every generated command exited 0 (answered: $rleg_st0) or 1 (documented empty-corpus degrade: $rleg_st1) — no unexpected status, none swallowed" \
    || no "R-LEG: $rleg_st_bad of $rleg_n generated commands exited with an unexpected status (listed above) — the old '|| true' reported PASS for these"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
