#!/usr/bin/env bash
# taskroutecheck.sh — deterministic task -> one safe Ripwire command contract.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
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
git -C "$REPO" add router.cpp package.json
git -C "$REPO" commit -qm base
route(){ "$BIN" "$REPO" --no-cache --help-task="$1" 2>"$TMP/err"; }

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
GQEXPR="$( printf '%s' "$GQ" | sed -n 's|.*--graph-query=&apos;\(.*\)&apos;</run>.*|\1|p' | sed 's/&quot;/"/g' )"
GQRUN="$( "$BIN" "$REPO" --no-cache --graph-query="$GQEXPR" )"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$GQRUN" | grep -q '<query expr='; } \
    && ok "the emitted --graph-query expression runs and returns a <query> root" \
    || no "the emitted --graph-query expression failed to run (rc=$rc, expr=[$GQEXPR])"
printf '# A plan\n\n## Goal\n\nship it\n' >"$REPO/plan-gate.md"
PLRUN="$( "$BIN" "$REPO" --no-cache --plan-lint=plan-gate.md )"; rc=$?
[ $rc -le 2 ] && ok "the emitted --plan-lint=FILE command runs against a real plan file (rc=$rc)" \
              || no "the emitted --plan-lint=FILE command failed to run (rc=$rc)"
rm -f "$REPO/plan-gate.md"
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
         --edit-plan --dry-run --handles --legend --doctor --agent=codex --test-gate --slice --slice-flow --at --uses --seams; do "$BIN" --help=all 2>&1 | grep -q -- "$f" || no "recommended flag absent from --help: $f"; done

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

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
