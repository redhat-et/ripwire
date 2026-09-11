#!/usr/bin/env bash
# blindspotcheck.sh — the gate for: a graph verb's answer must never be a CONFIDENT ZERO. Where the
# pipeline KNOWS it could not see part of the corpus, the verb that answers off that graph says so on its
# own root; where the pipeline CAN see the answer, it must actually return it; and where the source proves
# a call site is dead, it must not be counted as live.
#
# THE DEFECT CLASS, and why one gate covers three reports. Issues #62 / #63 / #66 (2026-09-08) are three
# spellings of one reader-facing failure: a number that reads as authoritative and is not. They are NOT one
# CAUSE — see the three arms below, which fail for three unrelated reasons — but they share one CONTRACT,
# the one CLAUDE.md states: "a zero means 'none found', never 'none exists'; every truncation is disclosed
# in the header." A gate per issue would let the contract drift apart at three echo sites, which is the §B4
# family this repo already has scar tissue for. One gate, three arms, one contract.
#
# WHAT IT ASSERTS
#   (A) #66 DISCLOSED ZERO — on a corpus whose only caller lives in a file no grammar reads, --callers and
#       --impact carry graph_unindexed="N" on their own root, and N is VALUE-EQUAL to the map header's
#       unindexed= roll-up on the same corpus. Value-equality is the whole arm: an attribute that is merely
#       PRESENT can be a second derivation that drifts, which is the defect M15 fixed for the gauge pair.
#   (B) #66 OMIT-AT-CONFIDENT — on a corpus with nothing unindexed, the attribute is ABSENT. Without this
#       arm the honest fix degrades into a marker that is always on, which an agent learns to ignore; and
#       absence is itself load-bearing (it is what says "no blind spot of this kind"), so it is gated.
#   (C) #63 HEADER-QUALIFIED REACH — a C++ method selected through the header that DECLARES it answers with
#       the same non-empty caller set as the same method selected through the .cpp that DEFINES it. This
#       arm is not a disclosure arm: the data was always there, so disclosure would have been the wrong fix
#       and a scoped EVALS claim the wrong remedy. Both sides are asserted non-empty first (see VACUITY).
#   (D) #62 PREPROC-DEAD CALL — a call site inside `#if 0` is not served as a live role="call" row, while
#       the live call to the same callee in the same file still is. Both halves, because an arm that only
#       checks the dead one passes just as well on a build that returns nothing at all.
#   (E) MUTATION — every assertion SHAPE above is shown to be able to fail, against hand-built inputs.
#
# VACUITY — the failure mode this gate was written against. Three arms in this tree in the week of
# 2026-09-08 turned out to be unable to fail: the sharpest compared two EMPTY files, because G4 minifies a
# document to a single line and `grep -v '^<!--'` therefore deletes the whole thing, legend and payload
# alike. So: this gate never strips comments line-wise, it extracts the ROOT ELEMENT by name with a
# non-greedy match, and EVERY extraction is asserted non-empty by its own arm before any comparison is made
# against it. `nonempty` below is not a convenience — a silent empty capture is the exact bug class.
#
# Usage:
#   bash test/blindspotcheck.sh                         # build/ripwire
#   bash test/blindspotcheck.sh build/ripwire_base      # the RED run (base binary lacks all three fixes)
#   RIPWIRE_BIN=asan/ripwire bash test/blindspotcheck.sh
#
# Exits non-zero on any failure. Writes only under its own mktemp dir.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "blindspotcheck: python3 required"; exit 2; }
echo "blindspotcheck: BIN=$BIN"

# Extract one root element by NAME from a minified document: `<callers …>` including the closing '>'.
# Non-greedy, first match, and it never touches comments — the leading legend is left exactly where it is
# rather than filtered out, because filtering it out on one line is what emptied the vacuous arms.
rootEl(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
m=re.search(r"<"+sys.argv[2]+r"\b[^>]*>",d)
sys.stdout.write(m.group(0) if m else "")' "$1" "$2"; }

# The one attribute reader, so no arm hand-rolls a second regex for the same job.
attr(){ python3 -c '
import re,sys
m=re.search(sys.argv[2]+r"=\"([^\"]*)\"",sys.argv[1])
sys.stdout.write(m.group(1) if m else "")' "$1" "$2"; }

# Assert a capture is non-empty BEFORE anything is concluded from it. Every arm routes through this.
nonempty(){ [ -n "$2" ] && return 0; no "$1 (empty capture — the arm reading it would have been vacuous)"; return 1; }

# ── corpora ───────────────────────────────────────────────────────────────────────────────────────────
# Built here, not committed: each is the reporter's own minimal repro, and a committed .astro/.h fixture
# would also join every OTHER gate's view of test/.
mkdir -p "$TMP/unind/src" "$TMP/clean/src" "$TMP/hdr" "$TMP/if0"

# (A)/(B): #66 — the caller differs from the contrast arm ONLY in file extension.
cat > "$TMP/unind/src/util.ts" <<'EOF'
export function greet(name: string): string {
  return `hello ${name}`;
}
EOF
cp "$TMP/unind/src/util.ts" "$TMP/clean/src/util.ts"
cat > "$TMP/unind/src/page.astro" <<'EOF'
---
import { greet } from "./util.ts";
function render(): string {
  return greet("world");
}
const message = render();
---
<p>{message}</p>
EOF
cat > "$TMP/clean/src/consumer.ts" <<'EOF'
import { greet } from "./util.ts";
export function render(): string {
  return greet("world");
}
EOF

# (C): #63 — declaring header, defining .cpp, one caller elsewhere.
cat > "$TMP/hdr/Store.h" <<'EOF'
#pragma once
class Store
{
public:
    int putObject(const char* key);
};
EOF
cat > "$TMP/hdr/Store.cpp" <<'EOF'
#include "Store.h"
int Store::putObject(const char* key)
{
    return key ? 1 : 0;
}
EOF
cat > "$TMP/hdr/Caller.cpp" <<'EOF'
#include "Store.h"
int driveTheStore(Store& s)
{
    return s.putObject("k");
}
EOF

# (D): #62 — one live call and one call inside `#if 0`, same callee, same file.
cat > "$TMP/if0/dead.cpp" <<'EOF'
int target(int x)
{
    return x + 1;
}
int liveCaller(int x)
{
    return target(x);
}
int deadCaller(int x)
{
    return 0;
#if 0
    return target(x);
#endif
}
EOF

echo
echo "=== (A) #66 — a zero whose cause the pipeline KNOWS is disclosed on the verb's own root ==="
"$BIN" "$TMP/unind" --no-cache --callers=greet          >"$TMP/a_callers.xml" 2>/dev/null
"$BIN" "$TMP/unind" --no-cache --impact=src/util.ts:greet >"$TMP/a_impact.xml" 2>/dev/null
"$BIN" "$TMP/unind" --no-cache                           >"$TMP/a_map.xml"    2>/dev/null

# the map header's own roll-up, summed to files — the number the verb roots must equal
HDR_UNIND="$( python3 -c '
import re,sys
d=open(sys.argv[1]).read()
m=re.search(r"unindexed=\"([^\"]*)\"",d)
if not m: sys.exit(0)
sys.stdout.write(str(sum(int(p.rsplit(":",1)[1]) for p in m.group(1).split(",") if ":" in p)))' "$TMP/a_map.xml" )"
nonempty "(A) the map header on the unindexed corpus states unindexed=" "$HDR_UNIND" \
    && ok "(A) map header discloses the gap: unindexed sums to $HDR_UNIND file(s)"

for spec in "a_callers.xml:callers:count" "a_impact.xml:impact:reaches"; do
    f="${spec%%:*}"; rest="${spec#*:}"; el="${rest%%:*}"; cnt="${rest#*:}"
    R="$( rootEl "$TMP/$f" "$el" )"
    nonempty "(A) $f: no <$el> root element found" "$R" || continue
    # the premise: this really IS the confident-zero situation, not some other answer
    C="$( attr "$R" "$cnt" )"
    if [ "$C" != "0" ]; then
        no "(A) $f: premise broken — $cnt=\"$C\", expected the reported zero; arm proves nothing"
        continue
    fi
    U="$( attr "$R" "graph_unindexed" )"
    if [ -z "$U" ]; then
        no "(A) $f: $cnt=\"0\" with NO graph_unindexed= — a zero indistinguishable from 'none exists' (#66)"
    elif [ "$U" = "$HDR_UNIND" ]; then
        ok "(A) $f: $cnt=\"0\" discloses graph_unindexed=\"$U\", value-equal to the map header"
    else
        no "(A) $f: graph_unindexed=\"$U\" != the map header's \"$HDR_UNIND\" — two derivations of one number"
    fi
done

echo
echo "=== (B) #66 — absent when there is nothing to disclose (omit-at-confident) ==="
"$BIN" "$TMP/clean" --no-cache --callers=greet >"$TMP/b_callers.xml" 2>/dev/null
RB="$( rootEl "$TMP/b_callers.xml" callers )"
if nonempty "(B) no <callers> root on the clean corpus" "$RB"; then
    CB="$( attr "$RB" count )"
    if [ "$CB" != "1" ]; then
        no "(B) premise broken — the .ts caller should be found (count=\"$CB\", expected 1)"
    elif [ -n "$( attr "$RB" graph_unindexed )" ]; then
        no "(B) graph_unindexed= present on a corpus with nothing unindexed — an always-on marker is one agents learn to ignore"
    else
        ok "(B) clean corpus: count=\"1\", graph_unindexed= absent"
    fi
fi

echo
echo "=== (C) #63 — the declaring header answers what the defining .cpp answers ==="
"$BIN" "$TMP/hdr" --no-cache --callers=Store.cpp:putObject >"$TMP/c_cpp.xml" 2>/dev/null
"$BIN" "$TMP/hdr" --no-cache --callers=Store.h:putObject   >"$TMP/c_hdr.xml" 2>/dev/null
RC_C="$( rootEl "$TMP/c_cpp.xml" callers )"; RC_H="$( rootEl "$TMP/c_hdr.xml" callers )"
if nonempty "(C) no <callers> root for the .cpp-qualified selector" "$RC_C" \
   && nonempty "(C) no <callers> root for the header-qualified selector" "$RC_H"; then
    N_C="$( attr "$RC_C" count )"; N_H="$( attr "$RC_H" count )"
    # The .cpp side is the CONTROL and is asserted non-zero first: if it were 0 the equality below would
    # hold at 0==0 and the arm would pass on a binary that answers nothing at all.
    if [ -z "$N_C" ] || [ "$N_C" = "0" ]; then
        no "(C) control broken — .cpp-qualified count=\"$N_C\"; the equality arm would be vacuous"
    elif [ "$N_H" = "$N_C" ]; then
        ok "(C) header-qualified count=\"$N_H\" == .cpp-qualified count=\"$N_C\" (both non-zero)"
    else
        no "(C) header-qualified count=\"$N_H\" != .cpp-qualified count=\"$N_C\" — a silent empty radius (#63)"
    fi
fi

echo
echo "=== (D) #62 — a call inside \`#if 0\` is not served as a live call ==="
"$BIN" "$TMP/if0" --no-cache --uses=dead.cpp:target >"$TMP/d_uses.xml" 2>/dev/null
RD="$( rootEl "$TMP/d_uses.xml" uses )"
if nonempty "(D) no <uses> root element" "$RD"; then
    LIVE="$( python3 -c '
import re,sys
d=open(sys.argv[1]).read()
rows=re.findall(r"<u\b[^>]*>",d)
sys.stdout.write("\n".join(r for r in rows if "liveCaller" in r))' "$TMP/d_uses.xml" )"
    DEAD="$( python3 -c '
import re,sys
d=open(sys.argv[1]).read()
rows=re.findall(r"<u\b[^>]*>",d)
sys.stdout.write("\n".join(r for r in rows if "deadCaller" in r))' "$TMP/d_uses.xml" )"
    # BOTH halves. The live row is the control: without it, "no dead row" also passes on an empty answer.
    if [ -z "$LIVE" ]; then
        no "(D) control broken — the LIVE call from liveCaller is missing; the dead-row arm would be vacuous"
    elif [ -n "$DEAD" ]; then
        no "(D) a call site inside \`#if 0\` is served as a live row: $DEAD (#62)"
    else
        ok "(D) live call present, \`#if 0\` call absent"
    fi
fi

echo
echo "=== (E) MUTATION — every assertion shape above is shown able to fail ==="
# (A) shape: a root with the zero and no attribute must be seen as a failure.
printf '<callers of="x" defs="1" count="0" graph_ambiguous="0" counts_floor="1">' >"$TMP/m_a.xml"
MA="$( rootEl "$TMP/m_a.xml" callers )"
[ -n "$( attr "$MA" graph_unindexed )" ] \
    && no "(E) the (A) reader claims to see graph_unindexed= on a root that has none" \
    || ok "(E) A-shape: a zero root WITHOUT graph_unindexed= is detected"
# (A) value-equality: present-but-different must not pass.
printf '<callers of="x" count="0" graph_unindexed="7">' >"$TMP/m_a2.xml"
[ "$( attr "$( rootEl "$TMP/m_a2.xml" callers )" graph_unindexed )" = "1" ] \
    && no "(E) the (A) value comparison cannot tell 7 from 1" \
    || ok "(E) A-shape: a graph_unindexed= that DISAGREES with the header is detected"
# (B) shape: an always-on marker must be seen.
printf '<callers of="x" count="1" graph_unindexed="0">' >"$TMP/m_b.xml"
[ -n "$( attr "$( rootEl "$TMP/m_b.xml" callers )" graph_unindexed )" ] \
    && ok "(E) B-shape: an always-on graph_unindexed= IS detected" \
    || no "(E) the (B) absence assertion cannot see a marker that is present"
# (C) shape: unequal counts must be seen, AND a 0==0 pair must be rejected by the control.
printf '<callers of="x" count="0">' >"$TMP/m_c.xml"
[ "$( attr "$( rootEl "$TMP/m_c.xml" callers )" count )" = "0" ] \
    && ok "(E) C-shape: a zero control count IS detected (the 0==0 vacuity guard fires)" \
    || no "(E) the (C) control guard cannot see a zero count"
# (D) shape: the row reader must actually find a dead row when one is present.
printf '<uses of="x" count="2"><u role="call" p="dead.cpp:7" in_id="dead.cpp::liveCaller"/><u role="call" p="dead.cpp:13" in_id="dead.cpp::deadCaller"/></uses>' >"$TMP/m_d.xml"
MD="$( python3 -c '
import re,sys
d=open(sys.argv[1]).read()
sys.stdout.write("\n".join(r for r in re.findall(r"<u\b[^>]*>",d) if "deadCaller" in r))' "$TMP/m_d.xml" )"
[ -n "$MD" ] \
    && ok "(E) D-shape: a served \`#if 0\` row IS detected" \
    || no "(E) the (D) row reader cannot see a dead row that is present"
# VACUITY guard itself: nonempty() must reject an empty capture. Run in a subshell so it cannot set fail.
if ( nonempty "probe" "" >/dev/null 2>&1 ); then
    no "(E) nonempty() accepts an empty capture — every arm's vacuity guard is inert"
else
    ok "(E) vacuity guard: nonempty() rejects an empty capture"
fi
# and the root extractor must return EMPTY on a document that lacks the element (not a stray match)
[ -z "$( rootEl "$TMP/m_d.xml" callers )" ] \
    && ok "(E) rootEl: returns empty for an element the document does not contain" \
    || no "(E) rootEl matched a <callers> element in a document that has none"

echo
[ "$fail" -eq 0 ] && { echo "blindspotcheck: ALL PASS"; exit 0; }
echo "blindspotcheck: FAILURES"; exit 1
