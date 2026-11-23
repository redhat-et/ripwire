#!/usr/bin/env bash
# sentencesubjectcheck.sh — SENTENCE-SUBJECT: a --for SENTENCE gets the subject blocks the bare names get (src/subjectanchor.h,
# src/lexical.h parseGraphSubject, src/verbs_for.h appendSentenceReask).
#   C   a sentence that `backticks` ONE function and asks what calls or depends on it gets <callers by="subject">, however long it is
#       and whatever other identifier it mentions in passing; a call's argument list and a Go receiver are read as the name; the rest
#       of the answer is byte-identical (the block is additive)
#   CN  NEGATIVE: no cue, two backticked functions, the callee sense, a negated cue, a cue whose object is not the name ("how does the
#       app invoke the task and run the `f` step"): no callers block (each arm counts what it saw)
#   G   `[call] chain from A to B`, `A reach(es) B` and `calls both A and B` run the path / connect verb the key form runs, only
#       when no key form (`common callers of`, `path from`, `callers of`) is in the sentence: that block is never replaced
#   GN  NEGATIVE: the words without code ("a chain from start to finish", "which tests reach the cache"): no graph block; the key
#       form is unchanged
#   R   RE-ASK: a code-spelling sentence that asks for callers or a path and got no block ends with ONE <reask next="..."/>, the bare
#       call, which runs; an answer that has the block, a stored key and a sentence with no cue carry none
# #646 CodeRabbit round (each arm RED on train head 6621e14e7):
#   CQ  in a long sentence (the sentence reading, not the short-subject one), a spelling whose OUTER qualifier places nothing
#       (`Missing.setup.prepare_setup_platform`) is no name: no callers block, no re-ask; its twin `setup.prepare_setup_platform` (the
#       file stem) still gets the block
#   CQs the SHORT subject reading ("Which functions call `Missing.setup.prepare_setup_platform` directly?") validates every
#       qualifier too: no callers block; its `setup.` twin keeps it (SUBJECT-EXACT-OUTER-QUAL, found fixing CodeRabbit on #646)
#   CG  a Go receiver spelling with no pronoun after the cue ("Which functions call `(*kv.Replica).NewEvalContext`?") gets the block
#   RD  the re-ask keeps the stated direction: "the path to `end_there` from `start_here`" is --path=start_here,end_there
# Usage: bash test/sentencesubjectcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN - build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" TMPDIR="$TMP/home/"; mkdir -p "$HOME"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "sentencesubjectcheck: BIN=$BIN"
# --no-verb-route --page-bytes=12000: this gate reads the --for answer's subject blocks; a backticked symbol with a who-calls /
# change cue is otherwise ROUTED to the verb (verbs_forroute.h, RT1/RT2), and a default page 1 may END EARLY after a proven
# callers block (RT2 ES). Both are forverbroutecheck's; here the full ranked page is the subject.
ask(){ ( cd "$1" && "$BIN" "$1" --no-cache "--for=$2" --no-verb-route --page-bytes=12000 2>/dev/null ) </dev/null; }
has(){ case "$1" in *"$2"*) ok "$3";; *) no "$3 (missing: $2)";; esac; }
hasnt(){ case "$1" in *"$2"*) no "$3 (present: $2)";; *) ok "$3";; esac; }
blk(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.search(r"<callers by=\"subject\".*?</callers>",sys.stdin.read(),re.S); print(m.group(0) if m else "")'; }
verb(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.search(r"<graph_verb endpoints=\"subject\" verb=\"([^\"]*)\"",sys.stdin.read()); print(m.group(1) if m else "@@NONE")'; }
reask(){ printf '%s' "$1" | python3 -c 'import re,sys; t=sys.stdin.read(); m=re.findall(r"<reask next=\"([^\"]*)\"/>",t); print(m[0] if len(m)==1 else ("@@NONE" if not m else "@@MANY"))'; }

R="$TMP/py"; mkdir -p "$R/app"
cat > "$R/app/setup.py" <<'X'
def prepare_setup_platform(hass, name):
    return name

def first_caller(hass):
    return prepare_setup_platform(hass, "a")

class EvalContext:
    def __init__(self, hass):
        self.hass = hass
X
cat > "$R/app/flow.py" <<'X'
def start_here(x):
    return middle_hop(x)

def middle_hop(x):
    return end_there(x)

def end_there(x):
    return x

def other_end(x):
    return x

def left_user(x):
    return end_there(x) + other_end(x)
X
G="$TMP/go"; mkdir -p "$G/kv"
cat > "$G/go.mod" <<'X'
module example.com/demo

go 1.21
X
cat > "$G/kv/replica.go" <<'X'
package kv

type Replica struct{ n int }

func (r *Replica) NewEvalContext(a int) int { return r.n + a }

func evaluateBatch(r *Replica) int { return r.NewEvalContext(1) }
X

# ── C: a code-marked sentence naming ONE function and asking who calls it ──
#
# OWNER RULING 109 (2026-11-20). additive() used to compare the hop answer MINUS the <callers by="subject"> block against
# the no-hop answer byte for byte. That cannot hold once KB1's key group is non-empty, because KB1 places the group right
# after the FIRST top-level row block — which is <callers by="subject"> in the hop answer and <sigs> in the no-hop one — so
# stripping the subject block leaves the group where that block had been. Before owner ruling 87 the arm passed because KB1
# delivered NOTHING on these questions in both answers (measured: 0 key groups either side; see
# results/K87_CONTRACT_1120/READOUT.md §6.1), so there was no group to misplace. Ruling 109 re-registers it to set the key
# group aside on BOTH sides, as forkeybodycheck's (K1n)/(K3n)/(K4) already do, and pairs it with the CK arm below, which
# pins the two groups byte-identical. Every row is still compared byte for byte; only the group's POSITION is set aside.
additive(){ # $1 root $2 task $3 answer $4 label $5 key group expected on this question (1|0)
    local A="$3"
    local B; B="$( cd "$1" && RIPWIRE_NO_CALLER_HOP=1 "$BIN" "$1" --no-cache "--for=$2" --no-verb-route --page-bytes=12000 2>/dev/null </dev/null )" || no "C $4: the no-hop answer exited $?"
    if python3 - "$A" "$B" <<'X'
import re,sys
a,b=sys.argv[1:3]
K=re.compile(r'<bodies of="key"[^>]*>.*?</bodies>',re.S)   # RULING 109: set aside on BOTH sides (the legend is a comment, stripped below)
m=lambda s:re.sub(r' est_tokens="\d+"| at="[^"]*"','',s)
a=re.sub(r'<callers by="subject".*?</callers>','',a,flags=re.S)
a=K.sub('',a,count=1); b=K.sub('',b,count=1)
ca=re.sub(r'<!--.*?-->','',m(a),flags=re.S); cb=re.sub(r'<!--.*?-->','',m(b),flags=re.S)
sys.exit(0 if ca==cb and cb.strip() else 1)
X
    then ok "C $4: the rest of the answer is byte-identical (key group set aside on both sides)"; else no "C $4: the block displaced something (or no answer)"; fi
    # A RELAXED comparison cannot be proved red on the unfixed binary -- that binary satisfied the stricter bar it
    # replaces -- so its non-vacuity proof is a mutation. The CK arm below carries the red-on-the-unfixed-binary proof.
    if python3 - "$A" "$B" <<'X'
import re,sys
a,b=sys.argv[1:3]
K=re.compile(r'<bodies of="key"[^>]*>.*?</bodies>',re.S)
m=lambda s:re.sub(r' est_tokens="\d+"| at="[^"]*"','',s)
a=re.sub(r'<callers by="subject".*?</callers>','',a,flags=re.S)
a=K.sub('',a,count=1); b=K.sub('',b,count=1)
ca=re.sub(r'<!--.*?-->','',m(a),flags=re.S); cb=re.sub(r'<!--.*?-->','',m(b),flags=re.S)
sys.exit(0 if ca!=cb[:-1] else 1)
X
    then ok "C $4: negative control: the same comparison fails when one byte is dropped"; else no "C $4: the comparison accepts a mutated answer -- it is vacuous"; fi
    # (CK) RULING 109's new arm. Where the question's backtick span PLACES a definition, KB1's contract says a key group
    # rides, and ruling 87 says it rides whatever else the page serves -- so the hop and no-hop answers must carry the SAME
    # group, byte for byte, even though they place it after different first blocks. Where the span places nothing (a call
    # argument list, a Go receiver spelling: forkeybodycheck (K7)'s "a span naming nothing"), neither answer carries one,
    # and this arm pins THAT instead -- so it is an assertion in both directions and never a silent pass.
    if python3 - "$A" "$B" "$5" <<'X'
import re,sys
a,b,want=sys.argv[1],sys.argv[2],sys.argv[3]=="1"
K=re.compile(r'<bodies of="key"[^>]*>.*?</bodies>',re.S)
ka,kb=K.findall(a),K.findall(b)
if not want:
    sys.exit(0 if not ka and not kb else 1)
sys.exit(0 if len(ka)==1 and len(kb)==1 and ka[0]==kb[0] else 1)
X
    then
        if [ "$5" = 1 ]; then ok "C $4: (CK) the hop and no-hop answers carry the SAME key group, byte for byte"
        else ok "C $4: (CK) the span places nothing, so neither answer carries a key group"; fi
    else
        if [ "$5" = 1 ]; then no "C $4: (CK) the key group is missing from one side, duplicated, or differs between the hop and no-hop answers"
        else no "C $4: (CK) a key group rode a span that places nothing"; fi
    fi
}
csub(){ # $1 root $2 task $3 caller row $4 label $5 key group expected (1|0)
    local A; A="$( ask "$1" "$2" )" || no "C $4: ripwire exited $?"
    has "$A" '<callers by="subject"' "C $4: callers ride by subject"
    has "$( blk "$A" )" "$3" "C $4: the caller row"
    additive "$1" "$2" "$A" "$4" "$5"
}
csub "$R" 'If `prepare_setup_platform` (app/setup.py) gained a new required parameter, exactly which non-test functions call it directly and would have to change? Give each function with its file; functions that merely receive the resulting EvalContext as a parameter do not count.' first_caller "long sentence, a second identifier in passing" 1
csub "$R" 'Which functions call `prepare_setup_platform(hass, name)` and must change when it gains a third argument, in production code and in tests? Group them by file.' first_caller "a call's argument list" 0
csub "$G" 'If `(*kv.Replica).NewEvalContext` gained a new required parameter, which functions call it directly and would have to change?' evaluateBatch "go receiver spelling" 0
csub "$G" 'Which functions call `(*kv.Replica).NewEvalContext`?' evaluateBatch "CG go receiver spelling, no pronoun after the cue" 0
csub "$R" 'If `setup.prepare_setup_platform` gained a new required parameter, exactly which non-test functions call it directly and would have to change?' first_caller "CQ twin: the file-stem qualifier places it" 1
A="$( ask "$R" 'If `Missing.setup.prepare_setup_platform` gained a new required parameter, exactly which non-test functions call it directly and would have to change?' )" || no "CQ: ripwire exited $?"
case "$A" in *'<ctx '*) ok "CQ: an answer printed";; *) no "CQ: no answer printed";; esac
hasnt "$A" '<callers by="subject"' "CQ: an outer qualifier that places nothing is no name (no callers block)"
hasnt "$A" '<reask' "CQ: and no re-ask names it"
# CQs: the SHORT subject (subjectReading's exact reading, not the sentence one) validates every qualifier too
A="$( ask "$R" 'Which functions call `Missing.setup.prepare_setup_platform` directly?' )" || no "CQs: ripwire exited $?"
case "$A" in *'<ctx '*) ok "CQs: an answer printed";; *) no "CQs: no answer printed";; esac
hasnt "$A" '<callers by="subject"' "CQs: a short subject whose outer qualifier places nothing is no name (no callers block)"
A="$( ask "$R" 'Which functions call `setup.prepare_setup_platform` directly?' )" || no "CQs twin: ripwire exited $?"
has "$( blk "$A" )" first_caller "CQs twin: the file-stem qualifier still places the short subject"

# ── CN: no block (each arm also proves an answer printed; the arm FAILs when it saw nothing) ──
seen=0
for q in 'How does `prepare_setup_platform` choose the name it returns, and where is that documented in the repository?' \
         'If `prepare_setup_platform` changes its signature, which functions call `end_there` today?' \
         'What does `prepare_setup_platform` call internally, and which values does it update along the way?' \
         'I changed nothing in `prepare_setup_platform`; where is the 404 fallback decided for the platform setup?' \
         'When I run the setup, how does the app invoke the task and run the `prepare_setup_platform` step in parallel?'; do
    A="$( ask "$R" "$q" )" || no "CN ($q): ripwire exited $?"
    case "$A" in *'<ctx '*) seen=$(( seen + 1 ));; *) no "CN no answer printed ($q)";; esac
    hasnt "$A" '<callers by="subject"' "CN ($q): no callers block"
done
if [ "$seen" = 5 ]; then ok "CN saw 5 answers"; else no "CN saw $seen of 5 answers"; fi

# ── G: sentence graph forms run the verb the key runs ──
gv(){ local A; A="$( ask "$R" "$1" )" || no "G $3: ripwire exited $?"; local V; V="$( verb "$A" )"; if [ "$V" = "$2" ]; then ok "G $3: verb=$V"; else no "G $3: verb=$V (want $2)"; fi; }
gv 'Trace the exact call chain from `start_here` (app/flow.py) to `end_there`. Name every function with its file.' '--path=start_here,end_there' "call chain from A to B"
gv 'How does `start_here()` reach `end_there` when the flow runs?' '--path=start_here,end_there' "A reach B"
gv 'Which non-test function calls both `end_there` and `other_end`? Give the function and its file.' '--connect=end_there,other_end' "calls both A and B"
gv 'path from start_here to end_there' '--path=start_here,end_there' "the key form, unchanged (control)"
gv 'Which function calls both `end_there` and `other_end`, and which other callers of end_there do not?' '--callers=end_there' "a key form in the same sentence keeps its block (nothing replaced)"
seen=0
for q in 'Is there a chain from start to finish documented in the flow notes?' 'Which tests reach the cache when the flow runs?' 'Does the setup call both handlers and the logger?'; do
    A="$( ask "$R" "$q" )" || no "GN ($q): ripwire exited $?"
    case "$A" in *'<ctx '*) seen=$(( seen + 1 ));; *) no "GN no answer printed ($q)";; esac
    hasnt "$A" '<graph_verb' "GN ($q): no graph block"
done
if [ "$seen" = 3 ]; then ok "GN saw 3 answers"; else no "GN saw $seen of 3 answers"; fi

# ── R: the re-ask hint ──
runs(){ # $1 root $2 invocation $3 row it must print $4 label
    local out rc; out="$( cd "$1" && "$BIN" "$1" --no-cache "$2" 2>/dev/null </dev/null )"; rc=$?
    if { [ "$rc" = 0 ] || [ "$rc" = 4 ]; }; then ok "R $4: next= runs (rc=$rc)"; else no "R $4: next= rc=$rc"; fi
    has "$out" "$3" "R $4: the bare call answers it"
}
q='I need to change prepare_setup_platform to log retry timing metrics somewhere; what depends on it?'
A="$( ask "$R" "$q" )" || no "R callers: ripwire exited $?"
hasnt "$A" '<callers by="subject"' "R callers: the sentence got no block (premise)"
# REASK-GRAIN: a CHANGE question ("I need to change X ...; what depends on it?") asks for the transitive radius, so its bare form is
# the impact verb (it was --callers= until the grain rule, a cheaper answer to a different question); a who-calls question keeps --callers=
N="$( reask "$A" )"; if [ "$N" = '--impact=prepare_setup_platform' ]; then ok "R change question: next=$N (the radius, not the one-hop callers)"; else no "R change question: next=$N (want --impact=prepare_setup_platform)"; fi
[ "${N#--}" != "$N" ] && runs "$R" "$N" first_caller "impact"
A="$( ask "$R" 'I need to log retry timing metrics somewhere beside prepare_setup_platform; which functions call it?' )" || no "R callers: ripwire exited $?"
hasnt "$A" '<callers by="subject"' "R callers: the sentence got no block (premise)"
N="$( reask "$A" )"; if [ "$N" = '--callers=prepare_setup_platform' ]; then ok "R callers: next=$N (a who-calls question stays one hop)"; else no "R callers: next=$N"; fi
[ "${N#--}" != "$N" ] && runs "$R" "$N" first_caller "callers"
A="$( ask "$R" 'What is the path, if any, between `start_here` and `other_end`?' )" || no "R path: ripwire exited $?"
hasnt "$A" '<graph_verb' "R path: the sentence got no block (premise)"
N="$( reask "$A" )"; if [ "$N" = '--path=start_here,other_end' ]; then ok "R path: next=$N"; else no "R path: next=$N"; fi
[ "${N#--}" != "$N" ] && runs "$R" "$N" start_here "path"
A="$( ask "$R" 'What is the path to `end_there` from `start_here`?' )" || no "RD: ripwire exited $?"
hasnt "$A" '<graph_verb' "RD: the sentence got no block (premise)"
N="$( reask "$A" )"; if [ "$N" = '--path=start_here,end_there' ]; then ok "RD: next=$N (the stated direction)"; else no "RD: next=$N (want --path=start_here,end_there)"; fi
seen=0
for q in 'If `prepare_setup_platform` (app/setup.py) gained a new required parameter, which functions call it directly?' \
         'Trace the exact call chain from `start_here` (app/flow.py) to `end_there`.' \
         'prepare_setup_platform gains a required parameter' 'How does `prepare_setup_platform` choose the name it returns?'; do
    A="$( ask "$R" "$q" )" || no "RN ($q): ripwire exited $?"
    case "$A" in *'<ctx '*) seen=$(( seen + 1 ));; *) no "RN no answer printed ($q)";; esac
    hasnt "$A" '<reask' "RN ($q): no re-ask"
done
if [ "$seen" = 4 ]; then ok "RN saw 4 answers"; else no "RN saw $seen of 4 answers"; fi

[ "$fail" = 0 ] && echo "sentencesubjectcheck: PASS" || echo "sentencesubjectcheck: FAIL"
exit "$fail"
