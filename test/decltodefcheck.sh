#!/usr/bin/env bash
# decltodefcheck.sh — the gate for: #63's decl→def widening must never ANSWER FOR A DEFINITION IT CANNOT
# TIE TO THE DECLARATION. A count carrying counts_floor="1" is a floor; a floor that OVER-counts is not a
# floor at all, it is a wrong answer wearing an honesty marker.
#
# THE DEFECT (H1, shipped in 0.6.0). graph.h::declToDefFollowThrough widens a header-qualified selector
# (`Store.h:putObject` → declarations only, which carry no call-graph edges) to the definitions those
# declarations stand for. Its target test was
#     s.name == name && s.scope == d.scope && hasBody( s.id )
# and `Symbol::scope` is the IMMEDIATELY ENCLOSING class/namespace name only — namespaces are dropped
# (model.h; graph.h ~1082 already says so for another table). So the test is name+bare-class, which:
#   * matches `b::Store::putObject` for a selector naming `a/Store.h` (both scopes are the bare "Store"),
#     and
#   * degenerates to NAME ALONE for free functions, whose scope is "" — the exact over-count the function's
#     own contract note forbids in writing ("Name alone would turn `Foo.h:size` into every free `size` in
#     the repository — an over-count inside an honesty fix, which is strictly worse than the silence it
#     replaces").
#
# THE FIX IT GATES — positive proof, then disclose the residue. A candidate definition survives only with
# EVIDENCE that it belongs to the declaration's file: it is IN that file, or its file #includes that file,
# resolved PATH-precisely (resolve.h::resolvePreciseInclude — never by basename). Unprovable candidates are
# DROPPED, which leaves the count under rather than over (the floor's safe direction), and the number
# dropped is reported so the answer is not a bare zero.
#
# WHAT IT ASSERTS
#   (A) TWO NAMESPACES, ONE CLASS NAME — `a/Store.h:putObject` has ZERO callers; b/Store.cpp's caller must
#       not be served. Its CONTROL is the same corpus's `b/Store.h:putObject`, which must still find that
#       caller: without the control this arm passes just as well on a build where the widening died
#       entirely, which would be #63 reopened. This is also the path-vs-basename decoy — the two headers
#       share a basename and only the include target's PATH tells them apart.
#   (B) FREE FUNCTIONS — `api.h:helper` has ZERO callers; two unrelated `helper`s in anonymous namespaces
#       in TUs that do not include api.h must not be served. CONTROL: the BARE-name selector still unions
#       both, so the fix narrowed the file: tier and nothing else.
#   (C) #63'S OWN CASE — a header, its definition in a .cpp that #includes it, and a caller. The widening
#       MUST still fire: the header-qualified count equals the .cpp-qualified count and both are non-zero.
#       Trading the over-count for #63's silent zero is not a fix. Two shapes: same directory, and the
#       include/ + src/ split whose target is a RELATIVE path (`../include/api.h`).
#   (D) DECL AND DEF IN ONE FILE — a header that both declares and defines still answers. (The selection
#       already holds a bodied def there, so the widening short-circuits; the arm exists because that
#       short-circuit is what makes the proof's same-file clause a guard rather than the live path.)
#   (E) THE RESIDUE IS COUNTED — when candidates were found and dropped, the count of dropped candidates is
#       reported; when nothing was dropped it is 0. Asserted through a standalone unit driver, at the
#       resolver seam where the number is produced.
#   (E2) THE RESIDUE IS DISCLOSED — the same number reaches the READER, as `unproven_defs="N"` on the
#       --callers/--callees root, on all three dialects (XML, --json, --format=columnar), with the clause
#       that defines it in the legend beside it; and BOTH are absent when nothing was dropped. The arm is
#       there because a dropped candidate that the answer does not mention is a plain zero — which is the
#       silence #63 exists to kill, so shipping (E) without (E2) would trade one honesty defect for another.
#   (E2e..E2h) THE SAME RESIDUE ON THE VERBS THAT READ THE SAME RESOLVER. --safe-delete, --impact (XML, --json,
#       --format=columnar, MCP impact) and --path (MCP path_between) resolve SYM through it too, and met the same
#       drop as callers="0" risk="none-found", reaches="0" and reachable="0" with nothing saying so. Each now carries
#       unproven_defs= with a clause worded for that verb (--path sums both endpoints, E2g), --safe-delete's clause
#       addresses risk= itself so none-found does not stand as a safety reading (E2f), the existing compact row
#       fires on all of them (E2h), and a fully-proven file:name or a bare name carries neither (E2e absent rows).
#   (E2i..E2m) THE SAME RESIDUE ON --uses, --mentions, --verify AND --affected. Each resolves its SYM through the same
#       resolver and met the same drop as count="0" (--uses, and --verify's uses()/unused()), docs="0" (a doc edge is
#       stored on a body, never on a declaration), verdict="not-established" (--verify's calls()/reaches()) and tests="0"
#       reached="0" (--affected). Each now carries unproven_defs= with a clause worded for that verb (E2i); --verify's
#       rides as its own comment beside a closed legend and addresses verdict= itself (E2k); verify's calls() sums both
#       symbols and --affected sums its symbol items (E2l); the existing compact row fires and the full clause is
#       stripped (E2m). The MCP uses/mentions twins resolve through resolveAllByName and refuse a file:name spelling as
#       CLI-only, so there is no zero there to disclose — asserted, not assumed (E2j). There is no MCP verify/affected.
#   (E2n..E2t) THE SAME RESIDUE ON --edit-check, --lego, --connect, --around AND --slice. --edit-check (its --dry-run
#       preview, MCP edit_check with and without new_body) answered incompatible="0" about a declaration whose only
#       definition carries the broken caller — a false "no broken callers" (E2n), so its clause addresses incompatible=
#       itself (E2o). --lego (MCP lego) read implementors="0" off the declaration (E2p), --connect (MCP connect) edges="0"
#       and sums its terminals (E2q), --around served the header row alone (E2r), --slice (MCP slice) uses="0" (E2s).
#       Each carries unproven_defs= with a clause worded for that verb, absent on a proven file:name and a bare name, and
#       the existing compact row fires with the full clause stripped (E2t). The corpora sort the DEFINITION's file first
#       (a_impl.cpp before api.h), so a bare name's lowest id is the body and every control answers.
#   (E2u..E2z) THE SAME RESIDUE WHERE THE ANSWER IS NARROWER RATHER THAN ZERO. --expand and --outline served the
#       declaration's text alone and share one <ctx> root, summed item by item (E2u, E2v); --owners covered the
#       declaration's file under defs="1" (E2w); MCP fetch_body served the declaration's body (E2x); --note-add keyed its
#       note to the declaration (E2y). Each now carries unproven_defs= — on the root, as a key of fetch_body's JSON, on
#       --note-add's stderr — and the compact row fires on --expand and --owners with the full clause stripped (E2z).
#   (E3a..E3f) THE FOCUS PICK. --lego, --connect and --around take ONE node from a match set (resolveFocus), and it was the
#       lowest id — with the header sorting first, the DECLARATION, even where no definition was dropped: a bare name and a
#       fully proven file:name answered the same zero as the dropping selector. A bodyless C/C++ lowest id now yields to the
#       lowest-id bodied C/C++ match of the same scope: --around reaches the caller (E3a), --connect joins it and names the
#       definition's file on its terminal row (E3b), --lego counts the implementor (E3c), and among several definitions the
#       lowest id wins (E3d). Kept as they were: a set of declarations only (the dropping selector still carries its
#       residue), a TypeScript overload signature beside its implementation (E3e), and a C++ pure virtual beside an override
#       of another class (E3f).
#   (E3g) THE READING OF THAT PICK. The compact reading of --around's defs= said "a C/C++ body over its declaration" with no
#       condition, which on (E3f)'s corpus describes a pick the answer did not make: the body there is another class's, and
#       the declaration kept the focus. Every legend that describes the pick — the compact --around reading, the full
#       --around seed clause, the --connect header — must name the same-scope condition, read on the corpus where it keeps
#       the declaration and on the one where the body wins.
#   (F) MUTATION — every assertion SHAPE above is shown able to fail, against hand-built inputs.
#
# WHAT (E) AND (E2) EACH COVER, since between them they close what was once a stated gap. (E) reads the
# number at the seam in graph.h that produces it; (E2) reads the RENDERED answer, which is composed in
# src/verbs_navigate.h and was, until the disclosure landed, incapable of carrying it — graph.h has zero
# emit sites, so for one commit the count existed and no reader could see it. Neither arm subsumes the
# other: (E) would stay green if every emitter dropped the attribute, and (E2) would stay green on a
# rendered constant. Keep both (CONTRIBUTING §2, shape 7).
#
# Usage:
#   bash test/decltodefcheck.sh                     # build/ripwire
#   bash test/decltodefcheck.sh build/ripwire_base  # the RED run (a base binary lacks the fix)
#   RIPWIRE_BIN=asan/ripwire bash test/decltodefcheck.sh
#
# Exits non-zero on any failure. Writes only under its own mktemp dir.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "decltodefcheck: python3 required"; exit 2; }
echo "decltodefcheck: BIN=$BIN"

# ── readers (one each, so no arm hand-rolls a second regex for the same job) ──────────────────────────
# The document is minified onto ONE line and the legend is a comment on that same line, so nothing here is
# ever filtered line-wise: the root element is extracted BY NAME with a non-greedy match instead.
rootEl(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
m=re.search(r"<"+sys.argv[2]+r"\b[^>]*>",d)
sys.stdout.write(m.group(0) if m else "")' "$1" "$2"; }

# LEFT-ANCHORED on purpose: `defs` is a proper suffix of `unproven_defs` and of `bodyless_defs`, so an
# unanchored search would read one attribute's value out of another's name — and arm (E2) below asserts the
# ABSENCE of one of them, which is exactly the assertion a suffix match makes vacuous.
# anchoredMatch <text> <head> <tail-regex> <group> — the ONE left-anchored reader: HEAD literal, then TAIL; prints GROUP of
# the first match, or nothing. attr reads an attribute's value with it, readingOf (below) one legend term's reading.
anchoredMatch(){ python3 -c '
import re,sys
m=re.search(r"(?<![A-Za-z0-9_])"+re.escape(sys.argv[2])+sys.argv[3],sys.argv[1],re.S)
sys.stdout.write(m.group(int(sys.argv[4])) if m else "")' "$1" "$2" "$3" "$4"; }
attr(){ anchoredMatch "$1" "$2=\"" '([^"]*)"' 1; }

# The LEADING comment block — the legend a reader meets before the first element, read as a span because G4
# minifies the whole document onto one line (the same extraction test/graphlegendbudgetcheck.sh uses).
legendOf(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
m=re.match(r"\A(?:\s*<!--.*?-->)+",d,re.S)
sys.stdout.write(m.group(0) if m else "")' "$1"; }

# One JSON key off the top-level object, as text; empty when the key is absent.
jsonKey(){ python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
sys.stdout.write("" if sys.argv[2] not in d else str(d[sys.argv[2]]))' "$1" "$2"; }

# Every `n="…"` row name in a document, one per line — the arms below assert on the NAME SET, never on a
# substring of the whole document (of="…" echoes the selector, so a bare grep matches itself).
rowNames(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
sys.stdout.write("\n".join(re.findall(r"<s\b[^>]*\bn=\"([^\"]*)\"",d)))' "$1"; }

# Assert a capture is non-empty BEFORE anything is concluded from it.
nonempty(){ [ -n "$2" ] && return 0; no "$1 (empty capture — the arm reading it would have been vacuous)"; return 1; }

run(){ # run <corpus> <selector-flag>  → stdout to $2out
    "$BIN" "$1" --no-cache "$2" 2>/dev/null; }

run2(){ # run <corpus> <selector-flag> <dialect-flag> — the --json / --format=columnar spellings of the same answer
    "$BIN" "$1" --no-cache "$2" "$3" 2>/dev/null; }

# The MCP twins: one JSON-RPC tools/call piped into `ripwire --mcp`, the TRANSCRIPT kept in a file so the reader that
# decodes it can be shown able to fail on its own (arm F). <legend> is "full", or "" to leave the server's default.
mcpTranscript(){ # mcpTranscript <out-file> <tool> <legend|""> <key=value>...
    _out="$1" _tool="$2" _legend="$3"; shift 3
    python3 - "$_tool" "$_legend" "$@" <<'PY' | "$BIN" --mcp >"$_out" 2>/dev/null
import json, sys
tool, legend = sys.argv[1], sys.argv[2]
args = dict( kv.split( "=", 1 ) for kv in sys.argv[3:] )
if legend:
    args[ "legend" ] = legend
print( json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } ) )
print( json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": tool, "arguments": args } } ) )
PY
}

# The payload text of a transcript's last response; an error response yields `__ERROR__:message`, never a payload.
mcpPayload(){ python3 -c '
import json,sys
lines=[l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
try:
    r=json.loads(lines[-1])
except Exception:
    sys.stdout.write("__ERROR__:no JSON-RPC response"); sys.exit(0)
if "error" in r:
    sys.stdout.write("__ERROR__:"+str(r["error"].get("message","")))
else:
    sys.stdout.write(r["result"]["content"][0]["text"])' "$1"; }

# The unproven_defs= clause of a legend, as a span: from its `unproven_defs=K` opening to the floor tail every graph
# verb's legend closes on (`counts_floor=`), or the comment's end. Lets (E2f) assert WHAT the clause addresses rather
# than that a word occurs somewhere in a 3 KB legend.
clauseOf(){ python3 -c '
import re,sys
m=re.search(r"unproven_defs=K\b.*?(?=counts_floor=|-->)",sys.argv[1],re.S)
sys.stdout.write(m.group(0) if m else "")' "$1"; }

# The reading a legend gives ONE head term, as a span: from the head, LEFT-ANCHORED (`defs=` is a suffix of unproven_defs=
# and bodyless_defs=), to the end of that reading — the next ". ", a "; qualify" hand-off, or the comment's end. Lets (E3g)
# assert what the defs= reading SAYS, never that a word occurs somewhere in a legend that also holds other terms.
readingOf(){ anchoredMatch "$1" "$2" '.*?(?=\. |\.?\s*-->|; qualify)' 0; }

# 1 when a legend holds the FULL unproven_defs= clause (its `(absent when 0)` opening), else 0 — what (E2m) asserts the
# compact dialect strips, and what (F) shows able to fail.
fullClauseIn(){ case "$1" in *'unproven_defs=K (absent when 0)'*) printf 1 ;; *) printf 0 ;; esac; }

# 1 when an MCP transcript's last response is the refusal of a qualified spelling as CLI-only, else 0 — an answer, or an
# error about something else, is not that refusal (E2j, and its (F) row).
refusesAsCliOnly(){ case "$( mcpPayload "$1" )" in '__ERROR__:'*'CLI-only'*) printf 1 ;; *) printf 0 ;; esac; }

# elNC <file> <EL> [ATTR] — elements read OUTSIDE every comment. rootEl reads the first match anywhere, which is right for a
# document whose root leads it; (E2n..E2z) read roots that do not lead (<lego> inside <ctx>, the map's <r> behind a legend
# that may spell `<r` in prose) and rows below them, so a tag named inside a comment must never be read as the element.
# Without ATTR: the first <EL …> start tag. With it: ATTR's value on EVERY <EL> row, one per line (left-anchored, as attr).
elNC(){ python3 -c '
import re,sys
d=re.sub(r"<!--.*?-->","",open(sys.argv[1]).read(),flags=re.S)
tags=re.findall(r"<"+re.escape(sys.argv[2])+r"(?=[\s/>])[^>]*>",d)
if len(sys.argv)<4:
    sys.stdout.write(tags[0] if tags else "")
else:
    vals=[m.group(1) for t in tags for m in [re.search(r"(?<![A-Za-z0-9_])"+sys.argv[3]+r"=\"([^\"]*)\"",t)] if m]
    sys.stdout.write("\n".join(vals))' "$@"; }

# Every comment met before the first <EL> start tag outside a comment: the legend a reader has read by the time they
# reach that element, wherever it sits (the lego legend rides inside <ctx>). Empty when the document has no such element.
legendBefore(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
seen=[]
for m in re.finditer(r"<!--.*?-->|<"+re.escape(sys.argv[2])+r"(?=[\s/>])",d,re.S):
    if not m.group(0).startswith("<!--"):
        sys.stdout.write("".join(seen)); break
    seen.append(m.group(0))' "$1" "$2"; }

# The n= of every <s> row outside comments — --around's neighbourhood, read as a NAME SET.
rowNamesNC(){ elNC "$1" s n; }

# ── corpora, built here rather than committed: each is a minimal repro and a committed .h/.cpp fixture
#    would also join every OTHER gate's view of test/. ────────────────────────────────────────────────
mkdir -p "$TMP/ns/a" "$TMP/ns/b" "$TMP/free" "$TMP/hdr" "$TMP/split/include" "$TMP/split/src" "$TMP/same" "$TMP/two" "$TMP/combo/test"

# (A) two namespaces, one class name, one shared basename.
cat > "$TMP/ns/a/Store.h" <<'EOF'
#pragma once
namespace a {
class Store {
public:
    int putObject(int x);
};
}
EOF
cat > "$TMP/ns/b/Store.h" <<'EOF'
#pragma once
namespace b {
class Store {
public:
    int putObject(int x);
};
}
EOF
cat > "$TMP/ns/b/Store.cpp" <<'EOF'
#include "Store.h"
namespace b {
int Store::putObject(int x)
{
    return x + 1;
}
}
int callB(int x)
{
    b::Store s;
    return s.putObject(x);
}
EOF

# (B) free functions: a declaring header nobody includes, two unrelated same-named definitions with
#     internal linkage, each called by its own TU.
cat > "$TMP/free/api.h" <<'EOF'
#pragma once
int helper(int a);
EOF
cat > "$TMP/free/other.cpp" <<'EOF'
namespace {
int helper(int a)
{
    return a * 2;
}
}
int unrelatedCaller(int a)
{
    return helper(a);
}
EOF
cat > "$TMP/free/third.cpp" <<'EOF'
namespace {
int helper(int a)
{
    return a + 7;
}
}
int anotherUnrelated(int a)
{
    return helper(a);
}
EOF

# (C1) #63's own shape: header, defining .cpp beside it, caller.
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

# (C2) the same shape across directories, so the include target is a RELATIVE path rather than a bare name.
cat > "$TMP/split/include/api.h" <<'EOF'
#pragma once
class Engine
{
public:
    int spin(int turns);
};
EOF
cat > "$TMP/split/src/engine.cpp" <<'EOF'
#include "../include/api.h"
int Engine::spin(int turns)
{
    return turns * 3;
}
EOF
cat > "$TMP/split/src/driver.cpp" <<'EOF'
#include "../include/api.h"
int driveEngine(Engine& e)
{
    return e.spin(4);
}
EOF

# (D) declaration AND definition in one header, plus a caller elsewhere.
cat > "$TMP/same/Widget.h" <<'EOF'
#pragma once
class Widget
{
public:
    int go(int x);
};
inline int Widget::go(int x)
{
    return x + 1;
}
EOF
cat > "$TMP/same/use.cpp" <<'EOF'
#include "Widget.h"
int driveWidget(Widget& w)
{
    return w.go(2);
}
EOF

# (E2g) TWO file:name endpoints, each dropping exactly one definition — (B)'s shape twice, under different names, so a
#       --path between them tells a sum (2) from either endpoint alone (1).
cat > "$TMP/two/a.h" <<'EOF'
#pragma once
int alpha(int a);
EOF
cat > "$TMP/two/b.h" <<'EOF'
#pragma once
int beta(int b);
EOF
cat > "$TMP/two/x.cpp" <<'EOF'
namespace {
int alpha(int a)
{
    return a + 1;
}
}
int useAlpha(int a)
{
    return alpha(a);
}
EOF
cat > "$TMP/two/y.cpp" <<'EOF'
namespace {
int beta(int b)
{
    return b + 2;
}
}
int useBeta(int b)
{
    return beta(b);
}
EOF

# (E2i) DOCS AND TESTS over (B) and (C1) side by side: a markdown file naming both in backticks (--mentions) and one test
#       per shape reaching it through its caller (--affected), so the dropping selector and its proven and bare-name
#       controls answer over ONE tree. The names are disjoint, so neither half's include proof touches the other, and
#       neither test file is named after a source file, so a control's test row is the caller WALK's, never the partner
#       convention's.
cp "$TMP/free/"* "$TMP/hdr/"* "$TMP/combo/"
cat > "$TMP/combo/NOTES.md" <<'EOF'
# Notes

The `helper` function doubles its argument, and `putObject` stores a key.
EOF
cat > "$TMP/combo/test/test_uses_helper.cpp" <<'EOF'
int unrelatedCaller(int a);
int testUsesHelper()
{
    return unrelatedCaller(3);
}
EOF
cat > "$TMP/combo/test/test_drive_store.cpp" <<'EOF'
class Store;
int driveTheStore(Store& s);
int testDriveStore(Store& s)
{
    return driveTheStore(s);
}
EOF

# (E2n..E2t) ONE DECLARATION, ONE UNTIED DEFINITION, ONE CALLER — with the DEFINITION's file sorting first (a_impl.cpp
#       before api.h), so a bare name's lowest id is the body and a bare-name control answers the way the proven one does.
#       `dord` drops the definition (a_impl.cpp never includes api.h); `dctl` is the same tree with that include.
mkdir -p "$TMP/dord" "$TMP/dctl" "$TMP/ecp" "$TMP/lego" "$TMP/legoctl"
cat > "$TMP/dord/api.h" <<'EOF'
#pragma once
int helper(int a);
EOF
cat > "$TMP/dord/a_impl.cpp" <<'EOF'
int helper(int a)
{
    int b = a * 2;
    return b + 1;
}
EOF
cat > "$TMP/dord/caller.cpp" <<'EOF'
#include "api.h"
int useHelper(int a)
{
    return helper(a);
}
EOF
cp "$TMP/dord/"* "$TMP/dctl/"
{ printf '#include "api.h"\n'; cat "$TMP/dord/a_impl.cpp"; } >"$TMP/dctl/a_impl.cpp"

# (E2n) --edit-check's repro, as a git repo: committed with helper(int a), then helper(int a, int c) in BOTH the
#       declaration and the untied definition while caller.cpp still passes one argument. `ecp` is the committed tree
#       unedited, for the pre-apply preview; `ec` carries the edit in its working tree.
cat > "$TMP/ecp/api.h" <<'EOF'
#pragma once
int helper(int a);
EOF
cat > "$TMP/ecp/impl.cpp" <<'EOF'
int helper(int a)
{
    int b = a * 2;
    return b + 1;
}
EOF
cp "$TMP/dord/caller.cpp" "$TMP/ecp/caller.cpp"
( cd "$TMP/ecp" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1 \
    || no "(E2n) could not commit the edit-check corpus — every --edit-check row below would read no-baseline"
cp -R "$TMP/ecp" "$TMP/ec"
printf '#pragma once\nint helper(int a, int c);\n' >"$TMP/ec/api.h"
printf 'int helper(int a, int c)\n{\n    int b = a * c;\n    return b + 1;\n}\n' >"$TMP/ec/impl.cpp"
printf 'int helper(int a, int c);' >"$TMP/payload_decl.txt"
printf 'int helper(int a, int c)\n{\n    int b = a * c;\n    return b + 1;\n}' >"$TMP/payload_def.txt"

# (E2p) --lego's repro: fwd.h forward-declares Shape, a_shape.h defines it without including fwd.h, circle.h implements it.
#       `legoctl` is the same tree with a_shape.h including fwd.h.
cat > "$TMP/lego/a_shape.h" <<'EOF'
#pragma once
class Shape
{
public:
    virtual int area() = 0;
};
EOF
cat > "$TMP/lego/circle.h" <<'EOF'
#pragma once
#include "a_shape.h"
class Circle : public Shape
{
public:
    int area() override { return 1; }
};
EOF
printf '#pragma once\nclass Shape;\n' >"$TMP/lego/fwd.h"
cp "$TMP/lego/"* "$TMP/legoctl/"
{ printf '#pragma once\n#include "fwd.h"\n'; tail -n +2 "$TMP/lego/a_shape.h"; } >"$TMP/legoctl/a_shape.h"

echo
echo "=== (A) two namespaces, one class name — the header that declares NOTHING's caller answers zero ==="
run "$TMP/ns" --callers=a/Store.h:putObject >"$TMP/a_far.xml"
run "$TMP/ns" --callers=b/Store.h:putObject >"$TMP/a_own.xml"
RA_F="$( rootEl "$TMP/a_far.xml" callers )"; RA_O="$( rootEl "$TMP/a_own.xml" callers )"
if nonempty "(A) no <callers> root for a/Store.h:putObject" "$RA_F" \
   && nonempty "(A) no <callers> root for b/Store.h:putObject" "$RA_O"; then
    N_F="$( attr "$RA_F" count )"; N_O="$( attr "$RA_O" count )"
    # CONTROL FIRST: b/Store.h really does reach callB through its own .cpp's #include. If this is 0 the
    # widening is dead and the a/ assertion below would be green for the wrong reason.
    if [ "$N_O" != "1" ] || ! rowNames "$TMP/a_own.xml" | grep -qx 'callB'; then
        no "(A) control broken — b/Store.h:putObject should still reach callB (count=\"$N_O\"); the a/ arm would be vacuous"
    elif rowNames "$TMP/a_far.xml" | grep -qx 'callB'; then
        no "(A) a/Store.h:putObject serves callB — a definition in ANOTHER namespace, proven by nothing (H1)"
    elif [ "$N_F" != "0" ]; then
        no "(A) a/Store.h:putObject count=\"$N_F\", expected 0 — nothing calls a::Store::putObject"
    else
        ok "(A) a/Store.h:putObject count=\"0\"; control b/Store.h:putObject count=\"1\" names callB"
    fi
fi

echo
echo "=== (B) free functions — scope=\"\" must not let the widening degenerate to name alone ==="
run "$TMP/free" --callers=api.h:helper >"$TMP/b_file.xml"
run "$TMP/free" --callers=helper       >"$TMP/b_bare.xml"
RB_F="$( rootEl "$TMP/b_file.xml" callers )"; RB_B="$( rootEl "$TMP/b_bare.xml" callers )"
if nonempty "(B) no <callers> root for api.h:helper" "$RB_F" \
   && nonempty "(B) no <callers> root for the bare helper" "$RB_B"; then
    N_BF="$( attr "$RB_F" count )"; N_BB="$( attr "$RB_B" count )"
    SERVED="$( rowNames "$TMP/b_file.xml" | grep -xE 'unrelatedCaller|anotherUnrelated' | tr '\n' ' ' )"
    # CONTROL FIRST: the BARE-name tier is untouched by this fix and still unions both definitions.
    if [ "$N_BB" != "2" ]; then
        no "(B) control broken — the bare-name selector should still find both callers (count=\"$N_BB\", expected 2)"
    elif [ -n "$SERVED" ]; then
        no "(B) api.h:helper serves $SERVED — anonymous-namespace helpers in TUs that never include api.h (H1)"
    elif [ "$N_BF" != "0" ]; then
        no "(B) api.h:helper count=\"$N_BF\", expected 0 — nothing calls the declared helper"
    else
        ok "(B) api.h:helper count=\"0\"; control: bare helper still count=\"2\""
    fi
fi

echo
echo "=== (C) #63 — the declaring header still answers what the defining .cpp answers ==="
for shape in "hdr:Store.h:Store.cpp:putObject:driveTheStore" "split:include/api.h:src/engine.cpp:spin:driveEngine"; do
    dir="${shape%%:*}";  rest="${shape#*:}"
    hdr="${rest%%:*}";   rest="${rest#*:}"
    cpp="${rest%%:*}";   rest="${rest#*:}"
    sym="${rest%%:*}";   who="${rest#*:}"
    run "$TMP/$dir" "--callers=$cpp:$sym" >"$TMP/c_${dir}_cpp.xml"
    run "$TMP/$dir" "--callers=$hdr:$sym" >"$TMP/c_${dir}_hdr.xml"
    RC_C="$( rootEl "$TMP/c_${dir}_cpp.xml" callers )"; RC_H="$( rootEl "$TMP/c_${dir}_hdr.xml" callers )"
    nonempty "(C/$dir) no <callers> root for the .cpp-qualified selector" "$RC_C" || continue
    nonempty "(C/$dir) no <callers> root for the header-qualified selector" "$RC_H" || continue
    N_C="$( attr "$RC_C" count )"; N_H="$( attr "$RC_H" count )"
    if [ -z "$N_C" ] || [ "$N_C" = "0" ]; then
        no "(C/$dir) control broken — .cpp-qualified count=\"$N_C\"; the equality arm would be vacuous at 0==0"
    elif [ "$N_H" != "$N_C" ]; then
        no "(C/$dir) header-qualified count=\"$N_H\" != .cpp-qualified count=\"$N_C\" — #63's silent zero is back"
    elif ! rowNames "$TMP/c_${dir}_hdr.xml" | grep -qx "$who"; then
        no "(C/$dir) header-qualified answer does not name $who — equal counts over the wrong rows"
    else
        ok "(C/$dir) $hdr:$sym count=\"$N_H\" == $cpp:$sym count=\"$N_C\", both name $who"
    fi
done

echo
echo "=== (D) declaration and definition in ONE file — the selection already holds the body ==="
run "$TMP/same" --callers=Widget.h:go >"$TMP/d.xml"
RD="$( rootEl "$TMP/d.xml" callers )"
if nonempty "(D) no <callers> root for Widget.h:go" "$RD"; then
    N_D="$( attr "$RD" count )"
    if [ "$N_D" = "1" ] && rowNames "$TMP/d.xml" | grep -qx 'driveWidget'; then
        ok "(D) Widget.h:go count=\"1\" names driveWidget (decl+def in one file)"
    else
        no "(D) Widget.h:go count=\"$N_D\" — a file holding BOTH the declaration and the body must answer"
    fi
fi

echo
echo "=== (E) the residue is COUNTED — candidates found and dropped are reported, not silently gone ==="
# graph.h has no emit site, so the number is asserted at the resolver seam through a standalone driver
# compiled against the already-built ripwire objects (the test/includeprecisecheck.sh recipe). See THE
# DISCLOSURE GAP in this file's header for what this arm does NOT cover.
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ ! -f "$FLAGS_MK" ] || [ ! -f "$LINK_TXT" ]; then
    echo "cannot find CMake flags/link under $BUILD_DIR — build with CMake first"; exit 2
fi
CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
eval "CXX_FLAGS=(    $( grep -m1 '^CXX_FLAGS ='    "$FLAGS_MK" | sed 's/^CXX_FLAGS =//' ) )"
eval "CXX_DEFINES=(  $( grep -m1 '^CXX_DEFINES ='  "$FLAGS_MK" | sed 's/^CXX_DEFINES =//' ) )"
eval "CXX_INCLUDES=( $( grep -m1 '^CXX_INCLUDES =' "$FLAGS_MK" | sed 's/^CXX_INCLUDES =//' ) )"
LINK_BODY="$( sed -E 's#^[^ ]+ ##' "$LINK_TXT" )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#-o +ripwire##' )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | sed -E 's#[^ "]*ripwire.dir/src/main.cpp.o##' )"
LINK_BODY="$( printf '%s' "$LINK_BODY" | tr -d '"' )"

cat > "$TMP/decltodef_unit.cpp" <<EOF
// generated by test/decltodefcheck.sh — the residue count at the seam that produces it.
#include "$ROOT/src/model.h"
#include "$ROOT/src/ingest.h"
#include "$ROOT/src/graph.h"
#include <cstdio>
#include <string>
#include <vector>
using namespace rw;
static int g_fail = 0;
static void check( bool cond, const char* what )
{
    std::printf( cond ? "  PASS  %s\n" : "  FAIL  %s\n", what );
    if( !cond ) { g_fail = 1; }
}
// how many symbols in \`sel\` own a body — the widening's own predicate, so the driver never re-rolls it.
static std::size_t bodiedIn( const IngestResult& ing, const std::vector<NodeId>& sel )
{
    std::size_t n = 0;
    for( NodeId id : sel ) { if( isDefinitionNotDeclaration( ing.symbols[ id ] ) ) { ++n; } }
    return n;
}
int main( int argc, char** argv )
{
    if( argc < 3 ) { std::printf( "UNIT FAIL: usage: %s <nsCorpus> <hdrCorpus>\n", argv[0] ); return 2; }
    const IngestResult nsIng  = ingest( argv[1] );
    const IngestResult hdrIng = ingest( argv[2] );

    // DROPPED: b::Store::putObject is a bodied same-named, same-bare-scope candidate whose file includes
    // b/Store.h, never a/Store.h — one candidate found, one dropped, nothing widened.
    std::size_t dropped = 12345;
    const std::vector<NodeId> far = resolveAllByNameQualified( nsIng, "a/Store.h:putObject", &dropped );
    check( !far.empty(), "(E) premise: a/Store.h:putObject resolves to the declaration" );
    check( bodiedIn( nsIng, far ) == 0, "(E) a/Store.h:putObject widened to NO definition" );
    check( dropped == 1, "(E) unproven candidate count is 1 for a/Store.h:putObject" );

    // NOT DROPPED: Store.cpp includes Store.h, so its definition is proven and the selection widens.
    std::size_t none = 12345;
    const std::vector<NodeId> own = resolveAllByNameQualified( hdrIng, "Store.h:putObject", &none );
    check( bodiedIn( hdrIng, own ) == 1, "(E) Store.h:putObject widened to its proven definition" );
    check( none == 0, "(E) unproven candidate count is 0 when every candidate was proven" );

    // A selector that never reaches the widening at all reports 0, not a stale value.
    std::size_t bare = 12345;
    (void) resolveAllByNameQualified( hdrIng, "putObject", &bare );
    check( bare == 0, "(E) a bare-name selector reports 0 unproven (the widening never runs)" );

    if( g_fail ) { std::printf( "UNIT FAIL\n" ); return 1; }
    std::printf( "UNIT ALL PASS\n" );
    return 0;
}
EOF

UNIT_OK=1
# compiled+linked FROM the build dir: link.txt's object and library paths are relative to it.
if ( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -c "$TMP/decltodef_unit.cpp" -o "$TMP/unit.o" ) 2>"$TMP/cc.err"; then
    ok "(E) residue driver compiles against the ripwire flags"
else
    no "(E) residue driver failed to compile — the residue count is not reported at the resolver seam"
    sed -n '1,25p' "$TMP/cc.err"
    UNIT_OK=0
fi
# shellcheck disable=SC2086
if [ "$UNIT_OK" = 1 ]; then
    if ( cd "$BUILD_DIR" && "$CXX" "${CXX_FLAGS[@]}" "$TMP/unit.o" $LINK_BODY -o "$TMP/unit" ) 2>"$TMP/ld.err"; then
        ok "(E) residue driver links against the ripwire objects"
    else
        no "(E) residue driver failed to link"; sed -n '1,25p' "$TMP/ld.err"; UNIT_OK=0
    fi
fi
if [ "$UNIT_OK" = 1 ]; then
    "$TMP/unit" "$TMP/ns" "$TMP/hdr" >"$TMP/unit.out" 2>&1
    urc=$?
    grep -E '^  (PASS|FAIL) ' "$TMP/unit.out" || true
    if [ "$urc" -eq 0 ] && grep -q '^UNIT ALL PASS$' "$TMP/unit.out"; then
        ok "(E) residue driver: UNIT ALL PASS"
    else
        no "(E) residue driver reported failures (rc=$urc)"; sed -n '1,40p' "$TMP/unit.out"
    fi
fi

echo
echo "=== (E2) the residue is DISCLOSED — unproven_defs= on the rendered answer, absent when nothing dropped ==="
# The numbers pinned here are the ones arm (E)'s driver reads at the seam (1 for a/Store.h:putObject, 2 for
# api.h:helper): the point of this arm is that the SAME number survives to the reader, so a disagreement
# between the two arms is the defect, not a tolerance.
run  "$TMP/ns"   --callers=a/Store.h:putObject                   >"$TMP/e2_x_callers.xml"
run  "$TMP/ns"   --callees=a/Store.h:putObject                   >"$TMP/e2_x_callees.xml"
run  "$TMP/free" --callers=api.h:helper                          >"$TMP/e2_free.xml"
run  "$TMP/free" --callers=helper                                >"$TMP/e2_bare.xml"
run  "$TMP/hdr"  --callers=Store.h:putObject                     >"$TMP/e2_clean.xml"
run2 "$TMP/ns"   --callers=a/Store.h:putObject --json            >"$TMP/e2_json.json"
run2 "$TMP/ns"   --callers=a/Store.h:putObject --format=columnar >"$TMP/e2_col.xml"

# (E2a) PRESENT, with the seam's own number, on both directions of the 1-hop question. The callees half is
# the one that would have been lost to a copy of bodyless_defs=: that attribute is gated behind !wantCallers
# because a declaration has no callees, and the residue has no such asymmetry — a selector that could not
# tie its definitions to the file it named is equally unanswered whichever edge direction was asked.
for pair in "e2_x_callers.xml:callers:1" "e2_x_callees.xml:callees:1" "e2_free.xml:callers:2"; do
    f="${pair%%:*}"; rest="${pair#*:}"; el="${rest%%:*}"; want="${rest#*:}"
    R="$( rootEl "$TMP/$f" "$el" )"
    nonempty "(E2a) no <$el> root in $f" "$R" || continue
    GOT="$( attr "$R" unproven_defs )"
    CNT="$( attr "$R" count )"
    if [ "$GOT" = "$want" ]; then
        ok "(E2a) $f <$el> carries unproven_defs=\"$GOT\" beside count=\"$CNT\""
    else
        no "(E2a) $f <$el> unproven_defs=\"${GOT:-<absent>}\", expected \"$want\" — the dropped candidates reach the reader as a bare count=\"$CNT\""
    fi
done

# (E2b) ABSENT when nothing was dropped — the other half of "absent at zero", and the arm that stops the
# attribute from becoming noise on every answer. CONTROL FIRST in both cases: a document with no answer in
# it has no attribute either, and would pass this vacuously.
R_CLEAN="$( rootEl "$TMP/e2_clean.xml" callers )"
R_BARE="$( rootEl "$TMP/e2_bare.xml" callers )"
if nonempty "(E2b) no <callers> root for Store.h:putObject" "$R_CLEAN" \
   && nonempty "(E2b) no <callers> root for the bare helper" "$R_BARE"; then
    C_CLEAN="$( attr "$R_CLEAN" count )"; C_BARE="$( attr "$R_BARE" count )"
    if [ "$C_CLEAN" != "1" ] || [ "$C_BARE" != "2" ]; then
        no "(E2b) control broken — every candidate proven: count=\"$C_CLEAN\" (expected 1); bare name: count=\"$C_BARE\" (expected 2). Both absence arms would be vacuous"
    elif [ -n "$( attr "$R_CLEAN" unproven_defs )" ]; then
        no "(E2b) Store.h:putObject carries unproven_defs=\"$( attr "$R_CLEAN" unproven_defs )\" — every candidate was PROVEN, so there is no residue to disclose"
    elif [ -n "$( attr "$R_BARE" unproven_defs )" ]; then
        no "(E2b) the bare-name selector carries unproven_defs= — the widening never runs on that tier, so the attribute is a claim about nothing"
    else
        ok "(E2b) absent at zero: neither the fully-proven file:name answer nor the bare-name answer carries unproven_defs="
    fi
fi

# (E2c) THE OTHER TWO DIALECTS. --help promises the same content in each; an honesty attribute that only the
# default XML carries is a disclosure a --json caller never receives.
J="$( jsonKey "$TMP/e2_json.json" unproven_defs )"
if [ "$J" = "1" ]; then ok "(E2c) --json carries \"unproven_defs\":1"; else no "(E2c) --json unproven_defs is \"${J:-<absent>}\", expected 1"; fi
R_COL="$( rootEl "$TMP/e2_col.xml" callers )"
if nonempty "(E2c) no <callers> root in the columnar answer" "$R_COL"; then
    G_COL="$( attr "$R_COL" unproven_defs )"
    if [ "$G_COL" = "1" ]; then ok "(E2c) --format=columnar carries unproven_defs=\"1\""; else no "(E2c) columnar unproven_defs=\"${G_COL:-<absent>}\", expected 1"; fi
fi

# (E2d) THE LEGEND, emitted exactly when the attribute is — graphlegend.h's own rule (rootRelPathsLegend: a
# legend that defines an attribute the document did not emit is the mirror-image false claim), which is also
# what keeps this clause off every bare-name answer and out of the shared essay's byte budget.
L_HAS="$( legendOf "$TMP/e2_x_callers.xml" )"
L_NOT="$( legendOf "$TMP/e2_clean.xml" )"
if nonempty "(E2d) the disclosing answer has no leading legend comment" "$L_HAS" \
   && nonempty "(E2d) the clean answer has no leading legend comment" "$L_NOT"; then
    case "$L_HAS" in
        *'unproven_defs='*) HAS_DEF=1 ;;
        *)                  HAS_DEF=0 ;;
    esac
    case "$L_NOT" in
        *'unproven_defs='*) NOT_DEF=1 ;;
        *)                  NOT_DEF=0 ;;
    esac
    if [ "$HAS_DEF" != 1 ]; then
        no "(E2d) the answer carrying unproven_defs= does not DEFINE it in the legend the reader meets first"
    elif [ "$NOT_DEF" != 0 ]; then
        no "(E2d) an answer with no residue still defines unproven_defs= — a legend defining an attribute the document did not emit"
    else
        ok "(E2d) the unproven_defs= clause is present exactly when the attribute is"
    fi
fi

# ── (E2e..E2h) THE SAME RESIDUE ON THE VERBS THAT READ THE SAME RESOLVER ────────────────────────────────────────────
# --safe-delete, --impact (and MCP impact) and --path (and MCP path_between) resolve SYM through the resolver the callers
# form reads, so the repros here met the identical drop — and answered it with the zeros a reader acts on most:
# --safe-delete=api.h:helper read callers="0" impact_reaches="0" uses="0" risk="none-found", --impact reaches="0" and
# --path reachable="0", with nothing on the root or in the legend saying two definitions were never walked. Per verb:
# the PREMISE (that zero really is on the root, or the arm is about nothing), PRESENT (the seam's number beside it, in
# every dialect the verb has), DEFINED (a clause in the legend the reader meets first), and ABSENT (a fully-proven
# file:name and a bare name carry neither, so an answer that dropped nothing is left as it was). --safe-delete has no
# --json, --format=columnar or MCP twin; --path has no dialect but its MCP twin.

# e2Present <label> <file> <root> <want> <premise-attr> <premise-value>
e2Present(){
    _lbl="$1" _f="$2" _el="$3" _want="$4" _pa="$5" _pv="$6"
    _R="$( rootEl "$_f" "$_el" )"
    nonempty "$_lbl: no <$_el> root" "$_R" || return 0
    _P="$( attr "$_R" "$_pa" )"
    if [ "$_P" != "$_pv" ]; then
        no "$_lbl: premise broken — $_pa=\"$_P\", expected \"$_pv\"; the disclosure arm would be about a zero that is not there"
        return 0
    fi
    _G="$( attr "$_R" unproven_defs )"
    if [ "$_G" = "$_want" ]; then
        ok "$_lbl: <$_el $_pa=\"$_P\"> carries unproven_defs=\"$_G\""
    else
        no "$_lbl: <$_el> unproven_defs=\"${_G:-<absent>}\", expected \"$_want\" — the dropped definitions reach the reader as a bare $_pa=\"$_P\""
    fi
    case "$( legendOf "$_f" )" in
        *'unproven_defs='*) ok "$_lbl: the leading legend defines unproven_defs=" ;;
        *)                  no "$_lbl: no clause defining unproven_defs= in the legend the reader meets first" ;;
    esac
}

# e2Absent <label> <file> <root> <control-attr> <control-value>
e2Absent(){
    _lbl="$1" _f="$2" _el="$3" _ca="$4" _cv="$5"
    _R="$( rootEl "$_f" "$_el" )"
    nonempty "$_lbl: no <$_el> root" "$_R" || return 0
    _C="$( attr "$_R" "$_ca" )"
    if [ "$_C" != "$_cv" ]; then
        no "$_lbl: control broken — $_ca=\"$_C\", expected \"$_cv\"; an answer that found nothing carries no attribute either, vacuously"
    elif [ -n "$( attr "$_R" unproven_defs )" ]; then
        no "$_lbl: carries unproven_defs=\"$( attr "$_R" unproven_defs )\" — nothing was dropped, so there is no residue to disclose"
    else
        case "$( legendOf "$_f" )" in
            *'unproven_defs='*) no "$_lbl: nothing dropped, yet the legend defines unproven_defs= — a clause for an attribute the document did not emit" ;;
            *)                  ok "$_lbl: $_ca=\"$_C\", and neither unproven_defs= nor its clause is present" ;;
        esac
    fi
}

echo
echo "=== (E2e) --safe-delete, --impact and --path, and the MCP twins, carry the residue beside their zero ==="
run  "$TMP/free" --safe-delete=api.h:helper                 >"$TMP/e2_sd.xml"
run  "$TMP/free" --impact=api.h:helper                      >"$TMP/e2_imp.xml"
run2 "$TMP/free" --impact=api.h:helper --json               >"$TMP/e2_imp.json"
run2 "$TMP/free" --impact=api.h:helper --format=columnar    >"$TMP/e2_imp_col.xml"
run  "$TMP/free" --path=unrelatedCaller,api.h:helper        >"$TMP/e2_pth.xml"
run  "$TMP/hdr"  --safe-delete=Store.h:putObject            >"$TMP/e2_sd_clean.xml"
run  "$TMP/free" --safe-delete=helper                       >"$TMP/e2_sd_bare.xml"
run  "$TMP/hdr"  --impact=Store.h:putObject                 >"$TMP/e2_imp_clean.xml"
run  "$TMP/free" --impact=helper                            >"$TMP/e2_imp_bare.xml"
run  "$TMP/hdr"  --path=driveTheStore,Store.h:putObject     >"$TMP/e2_pth_clean.xml"
run  "$TMP/free" --path=unrelatedCaller,helper              >"$TMP/e2_pth_bare.xml"
# The MCP twins read COPIES: the server keeps an index of its own, and nothing it writes may land in a corpus the CLI
# arms read.
cp -R "$TMP/free" "$TMP/mcp_free" && cp -R "$TMP/hdr" "$TMP/mcp_hdr" || no "(E2e) could not copy the corpora for the MCP twins"
mcpTranscript "$TMP/e2_mcp_imp.rpc"       impact       full "path=$TMP/mcp_free" "symbol=api.h:helper"
mcpTranscript "$TMP/e2_mcp_pth.rpc"       path_between full "path=$TMP/mcp_free" "from=unrelatedCaller" "to=api.h:helper"
mcpTranscript "$TMP/e2_mcp_imp_clean.rpc" impact       full "path=$TMP/mcp_hdr"  "symbol=Store.h:putObject"
mcpTranscript "$TMP/e2_mcp_pth_clean.rpc" path_between full "path=$TMP/mcp_hdr"  "from=driveTheStore" "to=Store.h:putObject"
for n in e2_mcp_imp e2_mcp_pth e2_mcp_imp_clean e2_mcp_pth_clean; do
    mcpPayload "$TMP/$n.rpc" >"$TMP/$n.xml"
done

e2Present "(E2e) --safe-delete=api.h:helper"               "$TMP/e2_sd.xml"      safe-delete 2 risk      none-found
e2Present "(E2e) --impact=api.h:helper"                    "$TMP/e2_imp.xml"     impact      2 reaches   0
e2Present "(E2e) --impact=api.h:helper --format=columnar"  "$TMP/e2_imp_col.xml" impact      2 reaches   0
e2Present "(E2e) --path=unrelatedCaller,api.h:helper"      "$TMP/e2_pth.xml"     path        2 reachable 0
e2Present "(E2e) MCP impact symbol=api.h:helper"           "$TMP/e2_mcp_imp.xml" impact      2 reaches   0
e2Present "(E2e) MCP path_between to=api.h:helper"         "$TMP/e2_mcp_pth.xml" path        2 reachable 0
# --json has no legend (the L2 rule): the key travels self-named, so PREMISE and PRESENT only.
J_R="$( jsonKey "$TMP/e2_imp.json" reaches )"; J_U="$( jsonKey "$TMP/e2_imp.json" unproven_defs )"
if [ "$J_R" != "0" ]; then
    no "(E2e) --impact=api.h:helper --json premise broken — \"reaches\" is \"$J_R\", expected 0"
elif [ "$J_U" = "2" ]; then
    ok "(E2e) --impact=api.h:helper --json carries \"unproven_defs\":2 beside \"reaches\":0"
else
    no "(E2e) --impact=api.h:helper --json \"unproven_defs\" is \"${J_U:-<absent>}\", expected 2 — the drop reaches a JSON reader as a bare \"reaches\":0"
fi

e2Absent "(E2e) --safe-delete=Store.h:putObject, every candidate proven" "$TMP/e2_sd_clean.xml"      safe-delete callers   1
e2Absent "(E2e) --safe-delete=helper, bare name"                         "$TMP/e2_sd_bare.xml"       safe-delete callers   2
e2Absent "(E2e) --impact=Store.h:putObject, every candidate proven"      "$TMP/e2_imp_clean.xml"     impact      reaches   1
e2Absent "(E2e) --impact=helper, bare name"                              "$TMP/e2_imp_bare.xml"      impact      reaches   2
e2Absent "(E2e) --path to Store.h:putObject, every candidate proven"     "$TMP/e2_pth_clean.xml"     path        reachable 1
e2Absent "(E2e) --path to the bare helper"                               "$TMP/e2_pth_bare.xml"      path        reachable 1
e2Absent "(E2e) MCP impact symbol=Store.h:putObject, proven"             "$TMP/e2_mcp_imp_clean.xml" impact      reaches   1
e2Absent "(E2e) MCP path_between to=Store.h:putObject, proven"           "$TMP/e2_mcp_pth_clean.xml" path        reachable 1

echo
echo "=== (E2f) --safe-delete's verdict: risk=none-found beside a residue is not left standing as a safety reading ==="
# risk= keeps its three documented values (--help lists them); what it must not do is stand ALONE on a read that walked
# none of the dropped definitions. So: the attribute rides the same root as the verdict, and the clause that defines it
# addresses risk= itself — asserted on the clause's own span, never on a word somewhere in the legend.
R_SD="$( rootEl "$TMP/e2_sd.xml" safe-delete )"
if nonempty "(E2f) no <safe-delete> root for api.h:helper" "$R_SD"; then
    CL_SD="$( clauseOf "$( legendOf "$TMP/e2_sd.xml" )" )"
    if [ "$( attr "$R_SD" risk )" != "none-found" ]; then
        no "(E2f) premise broken — risk=\"$( attr "$R_SD" risk )\", expected none-found; the verdict arm would be about another value"
    elif [ -z "$( attr "$R_SD" unproven_defs )" ]; then
        no "(E2f) risk=\"none-found\" stands with no unproven_defs= beside it — a safe-to-delete reading about two definitions nobody walked"
    else
        case "$CL_SD" in
            *'risk='*) ok "(E2f) the unproven_defs= clause addresses risk= itself: none-found is qualified where it is defined" ;;
            *)         no "(E2f) the unproven_defs= clause never names risk=, so none-found still reads as a finding: ${CL_SD:-<no clause>}" ;;
        esac
    fi
fi

echo
echo "=== (E2g) --path sums both endpoints' residue — neither endpoint's drop is lost, neither is counted twice ==="
# With (E2e)'s to=api.h:helper (the TO endpoint alone, 2), these tell a sum from src-only, dst-only and double counting.
run "$TMP/two" --path=a.h:alpha,b.h:beta >"$TMP/e2_two_both.xml"
run "$TMP/two" --path=a.h:alpha,useBeta  >"$TMP/e2_two_from.xml"
e2Present "(E2g) --path=a.h:alpha,b.h:beta (one dropped per endpoint)" "$TMP/e2_two_both.xml" path 2 reachable 0
e2Present "(E2g) --path=a.h:alpha,useBeta (the FROM endpoint alone)"   "$TMP/e2_two_from.xml" path 1 reachable 0

echo
echo "=== (E2h) under the compact legend, the existing unproven_defs row fires on all three roots ==="
# compactlegend.h already carries an unproven_defs reading and reads it off any root's head, so these roots needed no new
# term — asserted rather than assumed, on the CLI's --legend=compact and on the MCP server's default (compact).
run2 "$TMP/free" --safe-delete=api.h:helper          --legend=compact >"$TMP/e2_sd_cmp.xml"
run2 "$TMP/free" --impact=api.h:helper               --legend=compact >"$TMP/e2_imp_cmp.xml"
run2 "$TMP/free" --path=unrelatedCaller,api.h:helper --legend=compact >"$TMP/e2_pth_cmp.xml"
mcpTranscript "$TMP/e2_mcp_imp_cmp.rpc" impact "" "path=$TMP/mcp_free" "symbol=api.h:helper"
mcpPayload "$TMP/e2_mcp_imp_cmp.rpc" >"$TMP/e2_mcp_imp_cmp.xml"
for pair in "e2_sd_cmp.xml:safe-delete" "e2_imp_cmp.xml:impact" "e2_pth_cmp.xml:path" "e2_mcp_imp_cmp.xml:impact"; do
    f="${pair%%:*}"; el="${pair#*:}"
    R="$( rootEl "$TMP/$f" "$el" )"
    nonempty "(E2h) no <$el> root in $f" "$R" || continue
    L="$( legendOf "$TMP/$f" )"
    if [ -z "$( attr "$R" unproven_defs )" ]; then
        no "(E2h) $f: the compact <$el> root carries no unproven_defs= — nothing for the compact reading to define"
    else
        case "$L" in
            *'unproven_defs=K:'*) ok "(E2h) $f: <$el unproven_defs=\"$( attr "$R" unproven_defs )\"> and the compact legend reads it" ;;
            *)                    no "(E2h) $f: <$el> carries unproven_defs= under the compact legend with no unproven_defs=K: reading" ;;
        esac
    fi
done

# ── (E2i..E2m) THE SAME RESIDUE ON --uses, --mentions, --verify AND --affected ─────────────────────────────────────────
# Four more verbs resolve SYM through the same resolver, and on the same repros answered the drop as silence:
# --uses=api.h:helper read count="0" (a call site is kept only where it resolves to a def in defs=, and the one def
# kept is the bodyless declaration), --mentions read docs="0" (graph.h stores a doc edge on a body, never on a
# declaration), --verify's uses()/unused() read count="0" and calls()/reaches() verdict="not-established" with limit=
# naming the model floor rather than the drop, and --affected read tests="0" reached="0" — the zero on the verb whose
# answer is the list of tests to run. Same four questions per verb as (E2e): PREMISE, PRESENT, DEFINED, ABSENT.
# Dialects: --uses has XML and --format=columnar (its --json refuses); the other three have XML alone.

echo
echo "=== (E2i) --uses, --mentions, --verify and --affected carry the residue beside their zero ==="
run  "$TMP/free"  --uses=api.h:helper                                >"$TMP/e2_us.xml"
run2 "$TMP/free"  --uses=api.h:helper --format=columnar              >"$TMP/e2_us_col.xml"
run  "$TMP/combo" --mentions=api.h:helper                            >"$TMP/e2_mn.xml"
run  "$TMP/free"  '--verify=uses(api.h:helper)'                      >"$TMP/e2_vf_uses.xml"
run  "$TMP/free"  '--verify=unused(api.h:helper)'                    >"$TMP/e2_vf_unused.xml"
run  "$TMP/free"  '--verify=calls(unrelatedCaller,api.h:helper)'     >"$TMP/e2_vf_calls.xml"
run  "$TMP/free"  '--verify=reaches(api.h:helper,"other.cpp")'       >"$TMP/e2_vf_reaches.xml"
run  "$TMP/combo" --affected=api.h:helper                            >"$TMP/e2_af.xml"
run  "$TMP/hdr"   --uses=Store.h:putObject                           >"$TMP/e2_us_clean.xml"
run  "$TMP/free"  --uses=helper                                      >"$TMP/e2_us_bare.xml"
run  "$TMP/combo" --mentions=Store.h:putObject                       >"$TMP/e2_mn_clean.xml"
run  "$TMP/combo" --mentions=helper                                  >"$TMP/e2_mn_bare.xml"
run  "$TMP/hdr"   '--verify=uses(Store.h:putObject)'                 >"$TMP/e2_vf_uses_clean.xml"
run  "$TMP/free"  '--verify=uses(helper)'                            >"$TMP/e2_vf_uses_bare.xml"
run  "$TMP/hdr"   '--verify=calls(driveTheStore,Store.h:putObject)'  >"$TMP/e2_vf_calls_clean.xml"
run  "$TMP/free"  '--verify=calls(unrelatedCaller,helper)'           >"$TMP/e2_vf_calls_bare.xml"
run  "$TMP/hdr"   '--verify=reaches(Store.h:putObject,"Caller.cpp")' >"$TMP/e2_vf_reaches_clean.xml"
run  "$TMP/free"  '--verify=reaches(helper,"other.cpp")'             >"$TMP/e2_vf_reaches_bare.xml"
run  "$TMP/combo" --affected=Store.h:putObject                       >"$TMP/e2_af_clean.xml"
run  "$TMP/combo" --affected=helper                                  >"$TMP/e2_af_bare.xml"

e2Present "(E2i) --uses=api.h:helper"                          "$TMP/e2_us.xml"         uses     2 count     0
e2Present "(E2i) --uses=api.h:helper --format=columnar"        "$TMP/e2_us_col.xml"     uses     2 count     0
e2Present "(E2i) --mentions=api.h:helper"                      "$TMP/e2_mn.xml"         mentions 2 docs      0
e2Present "(E2i) --verify=uses(api.h:helper)"                  "$TMP/e2_vf_uses.xml"    verify   2 count     0
e2Present "(E2i) --verify=unused(api.h:helper)"                "$TMP/e2_vf_unused.xml"  verify   2 count     0
e2Present "(E2i) --verify=calls(unrelatedCaller,api.h:helper)" "$TMP/e2_vf_calls.xml"   verify   2 verdict   not-established
e2Present "(E2i) --verify=reaches(api.h:helper,\"other.cpp\")" "$TMP/e2_vf_reaches.xml" verify   2 witnesses 0
e2Present "(E2i) --affected=api.h:helper"                      "$TMP/e2_af.xml"         affected 2 tests     0

e2Absent "(E2i) --uses=Store.h:putObject, every candidate proven"           "$TMP/e2_us_clean.xml"         uses     count     1
e2Absent "(E2i) --uses=helper, bare name"                                   "$TMP/e2_us_bare.xml"          uses     count     2
e2Absent "(E2i) --mentions=Store.h:putObject, every candidate proven"       "$TMP/e2_mn_clean.xml"         mentions docs      1
e2Absent "(E2i) --mentions=helper, bare name"                               "$TMP/e2_mn_bare.xml"          mentions docs      1
e2Absent "(E2i) --verify=uses(Store.h:putObject), every candidate proven"   "$TMP/e2_vf_uses_clean.xml"    verify   count     1
e2Absent "(E2i) --verify=uses(helper), bare name"                           "$TMP/e2_vf_uses_bare.xml"     verify   count     2
e2Absent "(E2i) --verify=calls(driveTheStore,Store.h:putObject), proven"    "$TMP/e2_vf_calls_clean.xml"   verify   verdict   confirmed
e2Absent "(E2i) --verify=calls(unrelatedCaller,helper), bare name"          "$TMP/e2_vf_calls_bare.xml"    verify   verdict   confirmed
e2Absent "(E2i) --verify=reaches(Store.h:putObject,\"Caller.cpp\"), proven" "$TMP/e2_vf_reaches_clean.xml" verify   witnesses 1
e2Absent "(E2i) --verify=reaches(helper,\"other.cpp\"), bare name"          "$TMP/e2_vf_reaches_bare.xml"  verify   witnesses 1
e2Absent "(E2i) --affected=Store.h:putObject, every candidate proven"       "$TMP/e2_af_clean.xml"         affected tests     1
e2Absent "(E2i) --affected=helper, bare name"                               "$TMP/e2_af_bare.xml"          affected tests     1

echo
echo "=== (E2j) the MCP uses and mentions twins refuse a file:name spelling — there is no zero there to disclose ==="
# Both twins resolve through resolveAllByName, which never runs the widening, and both refuse a qualified spelling as
# CLI-only instead of answering it. A twin that began to ANSWER api.h:helper would answer from the same declaration and
# would owe the attribute the CLI now carries, so the refusal is asserted rather than left as a sentence in a header.
cp -R "$TMP/combo" "$TMP/mcp_combo" || no "(E2j) could not copy the corpus for the MCP twins"
mcpTranscript "$TMP/e2_mcp_us.rpc"      uses     "" "path=$TMP/mcp_combo" "symbol=api.h:helper"
mcpTranscript "$TMP/e2_mcp_mn.rpc"      mentions "" "path=$TMP/mcp_combo" "symbol=api.h:helper"
mcpTranscript "$TMP/e2_mcp_mn_bare.rpc" mentions "" "path=$TMP/mcp_combo" "symbol=helper"
# CONTROL FIRST: the same server answers the bare name, so a refusal below is about the spelling, not a dead transcript.
P_MN_BARE="$( mcpPayload "$TMP/e2_mcp_mn_bare.rpc" )"
case "$P_MN_BARE" in
    '__ERROR__:'*|'') no "(E2j) control broken — MCP mentions symbol=helper did not answer ($( printf '%s' "$P_MN_BARE" | head -c 160 )); the refusal rows would be about a server that answers nothing" ;;
    *'"docs":1'*)
        ok "(E2j) control: MCP mentions symbol=helper answers \"docs\":1"
        for n in e2_mcp_us e2_mcp_mn; do
            if [ "$( refusesAsCliOnly "$TMP/$n.rpc" )" = 1 ]; then
                ok "(E2j) $n: the twin refuses api.h:helper as a CLI-only spelling"
            else
                no "(E2j) $n: the twin no longer refuses api.h:helper ($( mcpPayload "$TMP/$n.rpc" | head -c 160 )) — an answer comes from the declaration and owes unproven_defs="
            fi
        done ;;
    *) no "(E2j) control broken — MCP mentions symbol=helper answered without \"docs\":1: $( printf '%s' "$P_MN_BARE" | head -c 160 )" ;;
esac

echo
echo "=== (E2k) --verify's verdict: not-established beside a residue is qualified where it is defined ==="
# verdict= keeps its three values (the claim grammar and --help close the set). limit= names the MODEL's floor, which is
# a different reason from a selector that dropped definitions, and a reader acts on the two differently — so the clause
# that defines unproven_defs= addresses verdict= and not-established itself, asserted on the clause's own span. --verify's
# legend is one closed literal, so the clause rides as its own comment; legendOf reads the whole leading run.
R_VF="$( rootEl "$TMP/e2_vf_uses.xml" verify )"
if nonempty "(E2k) no <verify> root for uses(api.h:helper)" "$R_VF"; then
    CL_VF="$( clauseOf "$( legendOf "$TMP/e2_vf_uses.xml" )" )"
    if [ "$( attr "$R_VF" verdict )" != "not-established" ]; then
        no "(E2k) premise broken — verdict=\"$( attr "$R_VF" verdict )\", expected not-established; the verdict arm would be about another value"
    elif [ -z "$( attr "$R_VF" unproven_defs )" ]; then
        no "(E2k) verdict=\"not-established\" stands with no unproven_defs= beside it — limit= names the model floor, never the two definitions nobody read"
    else
        case "$CL_VF" in
            *'verdict='*'not-established'*) ok "(E2k) the unproven_defs= clause addresses verdict= and not-established within its own span" ;;
            *)                              no "(E2k) the unproven_defs= clause never names verdict= and not-established: ${CL_VF:-<no clause>}" ;;
        esac
    fi
fi

echo
echo "=== (E2l) --verify=calls sums both symbols' residue; --affected sums its symbol items and a path item adds nothing ==="
# With (E2i)'s calls(unrelatedCaller,api.h:helper) (the TO symbol alone, 2), these tell a sum from src-only, dst-only and
# double counting; the --affected pair tells a per-item sum from first-item-only and from a path item that counts.
run "$TMP/two" '--verify=calls(a.h:alpha,b.h:beta)' >"$TMP/e2_vf_two_both.xml"
run "$TMP/two" '--verify=calls(a.h:alpha,useBeta)'  >"$TMP/e2_vf_two_from.xml"
run "$TMP/two" --affected=a.h:alpha,b.h:beta         >"$TMP/e2_af_two_both.xml"
run "$TMP/two" --affected=x.cpp,a.h:alpha            >"$TMP/e2_af_two_mixed.xml"
e2Present "(E2l) --verify=calls(a.h:alpha,b.h:beta) (one dropped per symbol)" "$TMP/e2_vf_two_both.xml"  verify   2 verdict not-established
e2Present "(E2l) --verify=calls(a.h:alpha,useBeta) (the FROM symbol alone)"   "$TMP/e2_vf_two_from.xml"  verify   1 verdict not-established
e2Present "(E2l) --affected=a.h:alpha,b.h:beta (one dropped per item)"        "$TMP/e2_af_two_both.xml"  affected 2 tests   0
e2Present "(E2l) --affected=x.cpp,a.h:alpha (the path item adds nothing)"     "$TMP/e2_af_two_mixed.xml" affected 1 tests   0

echo
echo "=== (E2m) under the compact legend, the existing unproven_defs row fires on the four roots and the full clause goes ==="
# No compact term was added: the row compactlegend.h already carries reads unproven_defs= off any root's head. --verify's
# clause is the one that could survive, being its own comment rather than a sentence inside a stripped legend, so every
# document here is also asserted to have lost the full clause.
run2 "$TMP/free"  --uses=api.h:helper           --legend=compact >"$TMP/e2_us_cmp.xml"
run2 "$TMP/combo" --mentions=api.h:helper       --legend=compact >"$TMP/e2_mn_cmp.xml"
run2 "$TMP/free"  '--verify=uses(api.h:helper)' --legend=compact >"$TMP/e2_vf_cmp.xml"
run2 "$TMP/combo" --affected=api.h:helper       --legend=compact >"$TMP/e2_af_cmp.xml"
for pair in "e2_us_cmp.xml:uses" "e2_mn_cmp.xml:mentions" "e2_vf_cmp.xml:verify" "e2_af_cmp.xml:affected"; do
    f="${pair%%:*}"; el="${pair#*:}"
    R="$( rootEl "$TMP/$f" "$el" )"
    nonempty "(E2m) no <$el> root in $f" "$R" || continue
    L="$( legendOf "$TMP/$f" )"
    if [ -z "$( attr "$R" unproven_defs )" ]; then
        no "(E2m) $f: the compact <$el> root carries no unproven_defs= — nothing for the compact reading to define"
    elif [ "$( fullClauseIn "$L" )" = 1 ]; then
        no "(E2m) $f: the FULL unproven_defs= clause survived into the compact dialect beside its compact reading"
    else
        case "$L" in
            *'unproven_defs=K:'*) ok "(E2m) $f: <$el unproven_defs=\"$( attr "$R" unproven_defs )\">, the compact legend reads it, and the full clause is gone" ;;
            *)                    no "(E2m) $f: <$el> carries unproven_defs= under the compact legend with no unproven_defs=K: reading" ;;
        esac
    fi
done

# ── (E2n..E2t) THE SAME RESIDUE ON --edit-check, --lego, --connect, --around AND --slice ───────────────────────────────
# Five more readers of the same resolver (--lego, --connect and --around through resolveFocus, its lowest-id projection)
# answered the drop with a zero and nothing beside it. The one a reader acts on first is --edit-check's: incompatible="0"
# about the declaration, while the definition the selector dropped carries the caller that no longer binds.
# Same four questions as (E2e), through two readers that find a root wherever it sits and read its zero off whichever
# element carries it: --lego's <lego> rides inside <ctx> with implementors= on <iface>, and --around's <r> follows a map
# legend. --around's zero is a missing ROW, so its arm reads the neighbourhood's name set.

# e3Present <label> <file> <root> <want> <premise-el> <premise-attr> <premise-value>
e3Present(){
    _lbl="$1" _f="$2" _el="$3" _want="$4" _pe="$5" _pa="$6" _pv="$7"
    _R="$( elNC "$_f" "$_el" )"
    nonempty "$_lbl: no <$_el> element" "$_R" || return 0
    _P="$( attr "$( elNC "$_f" "$_pe" )" "$_pa" )"
    if [ "$_P" != "$_pv" ]; then
        no "$_lbl: premise broken — <$_pe $_pa=\"$_P\">, expected \"$_pv\"; the disclosure arm would be about a zero that is not there"
        return 0
    fi
    _G="$( attr "$_R" unproven_defs )"
    if [ "$_G" = "$_want" ]; then
        ok "$_lbl: beside <$_pe $_pa=\"$_P\">, <$_el> carries unproven_defs=\"$_G\""
    else
        no "$_lbl: <$_el> unproven_defs=\"${_G:-<absent>}\", expected \"$_want\" — the dropped definitions reach the reader as a bare $_pa=\"$_P\""
    fi
    if [ "$( fullClauseIn "$( legendBefore "$_f" "$_el" )" )" = 1 ]; then
        ok "$_lbl: the legend met before <$_el> defines unproven_defs="
    else
        no "$_lbl: no clause defining unproven_defs= in the legend met before <$_el>"
    fi
}

# e3Absent <label> <file> <root> <control-el> <control-attr> <control-value>
e3Absent(){
    _lbl="$1" _f="$2" _el="$3" _ce="$4" _ca="$5" _cv="$6"
    _R="$( elNC "$_f" "$_el" )"
    nonempty "$_lbl: no <$_el> element" "$_R" || return 0
    _C="$( attr "$( elNC "$_f" "$_ce" )" "$_ca" )"
    if [ "$_C" != "$_cv" ]; then
        no "$_lbl: control broken — <$_ce $_ca=\"$_C\">, expected \"$_cv\"; an answer that found nothing carries no attribute either, vacuously"
    elif [ -n "$( attr "$_R" unproven_defs )" ]; then
        no "$_lbl: carries unproven_defs=\"$( attr "$_R" unproven_defs )\" — nothing was dropped, so there is no residue to disclose"
    else
        case "$( legendBefore "$_f" "$_el" )" in
            *'unproven_defs='*) no "$_lbl: nothing dropped, yet the legend defines unproven_defs= — a clause for an attribute the document did not emit" ;;
            *)                  ok "$_lbl: <$_ce $_ca=\"$_C\">, and neither unproven_defs= nor its clause is present" ;;
        esac
    fi
}

# The MCP twins read COPIES, as in (E2e).
cp -R "$TMP/ec" "$TMP/mcp_ec" && cp -R "$TMP/ecp" "$TMP/mcp_ecp" && cp -R "$TMP/lego" "$TMP/mcp_lego" && cp -R "$TMP/dord" "$TMP/mcp_dord" \
    || no "(E2n) could not copy the corpora for the MCP twins"
mcpText(){ # mcpText <name> <tool> <legend|""> <key=value>... → $TMP/<name>.xml, the payload of one transcript
    _n="$1"; shift
    mcpTranscript "$TMP/$_n.rpc" "$@"
    mcpPayload "$TMP/$_n.rpc" >"$TMP/$_n.xml"
}

echo
echo "=== (E2n) --edit-check, its preview and MCP edit_check carry the residue beside incompatible=\"0\" ==="
# CONTROL FIRST, and it is what makes the zero FALSE: impl.cpp:helper names the definition api.h:helper dropped, and on the
# same tree it flags the caller that passes one argument to a two-parameter helper.
run "$TMP/ec" --edit-check=api.h:helper    >"$TMP/e2_ec.xml"
run "$TMP/ec" --edit-check=impl.cpp:helper >"$TMP/e2_ec_def.xml"
"$BIN" "$TMP/ecp" --no-cache --edit-check=api.h:helper    --edit-payload="$TMP/payload_decl.txt" --dry-run >"$TMP/e2_ecd.xml"     2>/dev/null
"$BIN" "$TMP/ecp" --no-cache --edit-check=impl.cpp:helper --edit-payload="$TMP/payload_def.txt"  --dry-run >"$TMP/e2_ecd_def.xml" 2>/dev/null
mcpText e2_mcp_ec      edit_check full "path=$TMP/mcp_ec"  "symbol=api.h:helper"
mcpText e2_mcp_ec_def  edit_check full "path=$TMP/mcp_ec"  "symbol=impl.cpp:helper"
mcpText e2_mcp_ecd     edit_check full "path=$TMP/mcp_ecp" "symbol=api.h:helper"    "new_body=$( cat "$TMP/payload_decl.txt" )"
mcpText e2_mcp_ecd_def edit_check full "path=$TMP/mcp_ecp" "symbol=impl.cpp:helper" "new_body=$( cat "$TMP/payload_def.txt" )"

e3Absent  "(E2n) control: --edit-check=impl.cpp:helper flags the caller"               "$TMP/e2_ec_def.xml"         edit-check edit-check incompatible 1
e3Absent  "(E2n) control: --edit-check=impl.cpp:helper --dry-run flags the caller"     "$TMP/e2_ecd_def.xml"        edit-check edit-check incompatible 1
e3Absent  "(E2n) control: MCP edit_check symbol=impl.cpp:helper flags the caller"      "$TMP/e2_mcp_ec_def.xml"     edit-check edit-check incompatible 1
e3Absent  "(E2n) control: MCP edit_check impl.cpp:helper new_body flags the caller"    "$TMP/e2_mcp_ecd_def.xml"    edit-check edit-check incompatible 1
e3Present "(E2n) --edit-check=api.h:helper"                                            "$TMP/e2_ec.xml"             edit-check 1 edit-check incompatible 0
e3Present "(E2n) --edit-check=api.h:helper --dry-run"                                  "$TMP/e2_ecd.xml"            edit-check 1 edit-check incompatible 0
e3Present "(E2n) MCP edit_check symbol=api.h:helper"                                   "$TMP/e2_mcp_ec.xml"         edit-check 1 edit-check incompatible 0
e3Present "(E2n) MCP edit_check symbol=api.h:helper new_body"                          "$TMP/e2_mcp_ecd.xml"        edit-check 1 edit-check incompatible 0

echo
echo "=== (E2o) --edit-check's verdict: incompatible=\"0\" beside a residue is qualified where it is defined ==="
R_EC="$( elNC "$TMP/e2_ec.xml" edit-check )"
if nonempty "(E2o) no <edit-check> root for api.h:helper" "$R_EC"; then
    CL_EC="$( clauseOf "$( legendBefore "$TMP/e2_ec.xml" edit-check )" )"
    if [ "$( attr "$R_EC" incompatible )" != "0" ]; then
        no "(E2o) premise broken — incompatible=\"$( attr "$R_EC" incompatible )\", expected 0; the verdict arm would be about another value"
    elif [ -z "$( attr "$R_EC" unproven_defs )" ]; then
        no "(E2o) incompatible=\"0\" stands with no unproven_defs= beside it — a no-broken-callers reading about a definition nobody read"
    else
        case "$CL_EC" in
            *'incompatible='*'INCOMPLETE'*) ok "(E2o) the unproven_defs= clause addresses incompatible= and calls the read INCOMPLETE within its own span" ;;
            *)                              no "(E2o) the unproven_defs= clause does not address incompatible= as an INCOMPLETE read: ${CL_EC:-<no clause>}" ;;
        esac
    fi
fi

echo
echo "=== (E2p) --lego and MCP lego carry the residue beside implementors=\"0\" ==="
run "$TMP/lego"    --lego=fwd.h:Shape     >"$TMP/e2_lg.xml"
run "$TMP/lego"    --lego=a_shape.h:Shape >"$TMP/e2_lg_def.xml"
run "$TMP/lego"    --lego=Shape           >"$TMP/e2_lg_bare.xml"
run "$TMP/legoctl" --lego=fwd.h:Shape     >"$TMP/e2_lg_ctl.xml"
mcpText e2_mcp_lg     lego full "path=$TMP/mcp_lego" "type=fwd.h:Shape"
mcpText e2_mcp_lg_def lego full "path=$TMP/mcp_lego" "type=a_shape.h:Shape"
e3Present "(E2p) --lego=fwd.h:Shape"                               "$TMP/e2_lg.xml"         lego 1 iface implementors 0
e3Present "(E2p) MCP lego type=fwd.h:Shape"                         "$TMP/e2_mcp_lg.xml"     lego 1 iface implementors 0
e3Absent  "(E2p) --lego=a_shape.h:Shape, the definition itself"     "$TMP/e2_lg_def.xml"     lego   iface implementors 1
e3Absent  "(E2p) --lego=Shape, bare name"                           "$TMP/e2_lg_bare.xml"    lego   iface implementors 1
e3Absent  "(E2p) --lego=fwd.h:Shape, every candidate proven"        "$TMP/e2_lg_ctl.xml"     lego   iface implementors 1
e3Absent  "(E2p) MCP lego type=a_shape.h:Shape, the definition"     "$TMP/e2_mcp_lg_def.xml" lego   iface implementors 1

echo
echo "=== (E2q) --connect and MCP connect carry the residue beside edges=\"0\", summed over the terminals ==="
run "$TMP/dord" --connect=api.h:helper,useHelper >"$TMP/e2_cn.xml"
run "$TMP/dord" --connect=helper,useHelper       >"$TMP/e2_cn_bare.xml"
run "$TMP/dctl" --connect=api.h:helper,useHelper >"$TMP/e2_cn_ctl.xml"
run "$TMP/two"  --connect=a.h:alpha,b.h:beta     >"$TMP/e2_cn_two_both.xml"
run "$TMP/two"  --connect=a.h:alpha,useBeta      >"$TMP/e2_cn_two_from.xml"
mcpText e2_mcp_cn      connect full "path=$TMP/mcp_dord" "symbols=api.h:helper,useHelper"
mcpText e2_mcp_cn_bare connect full "path=$TMP/mcp_dord" "symbols=helper,useHelper"
e3Present "(E2q) --connect=api.h:helper,useHelper"                    "$TMP/e2_cn.xml"          connect 1 connect edges 0
e3Present "(E2q) MCP connect symbols=api.h:helper,useHelper"          "$TMP/e2_mcp_cn.xml"      connect 1 connect edges 0
e3Present "(E2q) --connect=a.h:alpha,b.h:beta (one dropped per terminal)" "$TMP/e2_cn_two_both.xml" connect 2 connect edges 0
e3Present "(E2q) --connect=a.h:alpha,useBeta (one terminal drops)"    "$TMP/e2_cn_two_from.xml" connect 1 connect edges 0
e3Absent  "(E2q) --connect=helper,useHelper, bare name"               "$TMP/e2_cn_bare.xml"     connect   connect edges 1
e3Absent  "(E2q) --connect=api.h:helper,useHelper, every candidate proven" "$TMP/e2_cn_ctl.xml" connect   connect edges 1
e3Absent  "(E2q) MCP connect symbols=helper,useHelper, bare name"     "$TMP/e2_mcp_cn_bare.xml" connect   connect edges 1

echo
echo "=== (E2r) --around carries the residue beside a neighbourhood of one row ==="
# The zero here is a missing ROW: the declaration has no call edges, so its neighbourhood is itself. PREMISE on the name set.
run "$TMP/dord" --around=api.h:helper >"$TMP/e2_ar.xml"
run "$TMP/dord" --around=helper       >"$TMP/e2_ar_bare.xml"
run "$TMP/dctl" --around=api.h:helper >"$TMP/e2_ar_ctl.xml"
R_AR="$( elNC "$TMP/e2_ar.xml" r )"
if nonempty "(E2r) no <r> root for --around=api.h:helper" "$R_AR"; then
    if ! rowNamesNC "$TMP/e2_ar.xml" | grep -qx helper || rowNamesNC "$TMP/e2_ar.xml" | grep -qx useHelper; then
        no "(E2r) premise broken — the neighbourhood is not the declaration alone ($( rowNamesNC "$TMP/e2_ar.xml" | tr '\n' ' ')); the arm would be about a zero that is not there"
    else
        G_AR="$( attr "$R_AR" unproven_defs )"
        if [ "$G_AR" = "1" ]; then
            ok "(E2r) --around=api.h:helper: a one-row neighbourhood, and <r> carries unproven_defs=\"1\""
        else
            no "(E2r) --around=api.h:helper: <r> unproven_defs=\"${G_AR:-<absent>}\", expected \"1\" — the header row reaches the reader as the whole neighbourhood"
        fi
        if [ "$( fullClauseIn "$( legendBefore "$TMP/e2_ar.xml" r )" )" = 1 ]; then
            ok "(E2r) --around=api.h:helper: the legend met before <r> defines unproven_defs="
        else
            no "(E2r) --around=api.h:helper: no clause defining unproven_defs= in the legend met before <r>"
        fi
    fi
fi
for pair in "e2_ar_bare.xml:bare name" "e2_ar_ctl.xml:every candidate proven"; do
    f="${pair%%:*}"; what="${pair#*:}"
    R="$( elNC "$TMP/$f" r )"
    nonempty "(E2r) no <r> root in $f" "$R" || continue
    if ! rowNamesNC "$TMP/$f" | grep -qx useHelper; then
        no "(E2r) $f ($what): control broken — useHelper is not in the neighbourhood; an answer that walked nothing carries no attribute either"
    elif [ -n "$( attr "$R" unproven_defs )" ]; then
        no "(E2r) $f ($what): carries unproven_defs=\"$( attr "$R" unproven_defs )\" — nothing was dropped"
    else
        case "$( legendBefore "$TMP/$f" r )" in
            *'unproven_defs='*) no "(E2r) $f ($what): nothing dropped, yet the legend defines unproven_defs=" ;;
            *)                  ok "(E2r) $f ($what): useHelper in the neighbourhood, and neither unproven_defs= nor its clause is present" ;;
        esac
    fi
done

echo
echo "=== (E2s) --slice and MCP slice carry the residue beside uses=\"0\" ==="
run "$TMP/dord" --slice=api.h:helper:a      >"$TMP/e2_sl.xml"
run "$TMP/dord" --slice=a_impl.cpp:helper:a >"$TMP/e2_sl_def.xml"
mcpText e2_mcp_sl     slice full "path=$TMP/mcp_dord" "symbol=api.h:helper"      "var=a"
mcpText e2_mcp_sl_def slice full "path=$TMP/mcp_dord" "symbol=a_impl.cpp:helper" "var=a"
e3Present "(E2s) --slice=api.h:helper:a"                          "$TMP/e2_sl.xml"         slice 1 slice uses 0
e3Present "(E2s) MCP slice symbol=api.h:helper var=a"             "$TMP/e2_mcp_sl.xml"     slice 1 slice uses 0
e3Absent  "(E2s) --slice=a_impl.cpp:helper:a, the definition"     "$TMP/e2_sl_def.xml"     slice   slice uses 1
e3Absent  "(E2s) MCP slice symbol=a_impl.cpp:helper, the definition" "$TMP/e2_mcp_sl_def.xml" slice slice uses 1

echo
echo "=== (E2t) under the compact legend, the existing unproven_defs row fires on the five roots and the full clause goes ==="
"$BIN" "$TMP/ec" --no-cache --edit-check=api.h:helper --legend=compact >"$TMP/e2_ec_cmp.xml" 2>/dev/null
run2 "$TMP/lego" --lego=fwd.h:Shape                 --legend=compact >"$TMP/e2_lg_cmp.xml"
run2 "$TMP/dord" --connect=api.h:helper,useHelper   --legend=compact >"$TMP/e2_cn_cmp.xml"
run2 "$TMP/dord" --around=api.h:helper              --legend=compact >"$TMP/e2_ar_cmp.xml"
run2 "$TMP/dord" --slice=api.h:helper:a             --legend=compact >"$TMP/e2_sl_cmp.xml"
mcpText e2_mcp_ec_cmp edit_check "" "path=$TMP/mcp_ec"   "symbol=api.h:helper"
mcpText e2_mcp_lg_cmp lego       "" "path=$TMP/mcp_lego" "type=fwd.h:Shape"
mcpText e2_mcp_cn_cmp connect    "" "path=$TMP/mcp_dord" "symbols=api.h:helper,useHelper"
mcpText e2_mcp_sl_cmp slice      "" "path=$TMP/mcp_dord" "symbol=api.h:helper" "var=a"
for pair in "e2_ec_cmp.xml:edit-check" "e2_lg_cmp.xml:lego" "e2_cn_cmp.xml:connect" "e2_ar_cmp.xml:r" "e2_sl_cmp.xml:slice" \
            "e2_mcp_ec_cmp.xml:edit-check" "e2_mcp_lg_cmp.xml:lego" "e2_mcp_cn_cmp.xml:connect" "e2_mcp_sl_cmp.xml:slice"; do
    f="${pair%%:*}"; el="${pair#*:}"
    R="$( elNC "$TMP/$f" "$el" )"
    nonempty "(E2t) no <$el> root in $f" "$R" || continue
    L="$( legendBefore "$TMP/$f" "$el" )"
    if [ -z "$( attr "$R" unproven_defs )" ]; then
        no "(E2t) $f: the compact <$el> root carries no unproven_defs= — nothing for the compact reading to define"
    elif [ "$( fullClauseIn "$L" )" = 1 ]; then
        no "(E2t) $f: the FULL unproven_defs= clause survived into the compact dialect beside its compact reading"
    else
        case "$L" in
            *'unproven_defs=K:'*) ok "(E2t) $f: <$el unproven_defs=\"$( attr "$R" unproven_defs )\">, the compact legend reads it, and the full clause is gone" ;;
            *)                    no "(E2t) $f: <$el> carries unproven_defs= under the compact legend with no unproven_defs=K: reading" ;;
        esac
    fi
done

# ── (E2u..E2z) THE SAME RESIDUE WHERE THE ANSWER IS NARROWER RATHER THAN ZERO ─────────────────────────────────────────────
# --expand, --outline, --owners, MCP fetch_body and --note-add resolve through the same resolver and answer the drop with
# less, not with nothing: the declaration's text, the declaration's file, a note keyed to the declaration. The PREMISE is
# therefore which FILES the answer served (the declaration's alone), and the control is an answer that served the
# definition's file too. --expand and --outline share one <ctx> root, so the attribute rides that root and its clause
# rides as a comment inside it, ahead of the payload element whichever mode served it (whole-file <src>, <bodies>,
# <outline>).

# The distinct p= values of every <EL> row outside comments, sorted and space-joined: which FILES an answer served.
pathsOf(){ elNC "$1" "$2" p | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//'; }

# exPresent <label> <file> <want> <payload-el> <row-el> <served-paths>
exPresent(){
    _lbl="$1" _f="$2" _want="$3" _pe="$4" _re="$5" _paths="$6"
    _R="$( elNC "$_f" ctx )"
    nonempty "$_lbl: no <ctx> root" "$_R" || return 0
    _P="$( pathsOf "$_f" "$_re" )"
    if [ "$_P" != "$_paths" ]; then
        no "$_lbl: premise broken — the <$_re> rows serve \"$_P\", expected \"$_paths\"; the arm would be about an answer that is not narrower"
        return 0
    fi
    _G="$( attr "$_R" unproven_defs )"
    if [ "$_G" = "$_want" ]; then
        ok "$_lbl: <$_re> rows from \"$_P\", and <ctx> carries unproven_defs=\"$_G\""
    else
        no "$_lbl: <ctx> unproven_defs=\"${_G:-<absent>}\", expected \"$_want\" — the answer serves \"$_P\" with nothing saying which definitions it left out"
    fi
    if [ "$( fullClauseIn "$( legendBefore "$_f" "$_pe" )" )" = 1 ]; then
        ok "$_lbl: the legend met before <$_pe> defines unproven_defs="
    else
        no "$_lbl: no clause defining unproven_defs= in the legend met before <$_pe>"
    fi
}

# exAbsent <label> <file> <payload-el> <row-el> <path-the-control-serves>
exAbsent(){
    _lbl="$1" _f="$2" _pe="$3" _re="$4" _must="$5"
    _R="$( elNC "$_f" ctx )"
    nonempty "$_lbl: no <ctx> root" "$_R" || return 0
    case " $( pathsOf "$_f" "$_re" ) " in
        *" $_must "*) ;;
        *) no "$_lbl: control broken — the <$_re> rows do not serve $_must ($( pathsOf "$_f" "$_re" ))"; return 0 ;;
    esac
    if [ -n "$( attr "$_R" unproven_defs )" ]; then
        no "$_lbl: carries unproven_defs=\"$( attr "$_R" unproven_defs )\" — nothing was dropped, so there is no residue to disclose"
    else
        case "$( legendBefore "$_f" "$_pe" )" in
            *'unproven_defs='*) no "$_lbl: nothing dropped, yet the legend defines unproven_defs=" ;;
            *)                  ok "$_lbl: <$_re> rows serve $_must, and neither unproven_defs= nor its clause is present" ;;
        esac
    fi
}

echo
echo "=== (E2u) --expand serves the declaration alone, and now says what it left out ==="
run  "$TMP/dord" --expand=api.h:helper                            >"$TMP/e2_ex.xml"
run2 "$TMP/dord" --expand=api.h:helper --top-k=0                  >"$TMP/e2_ex0.xml"
run2 "$TMP/dord" --expand=api.h:helper,useHelper --top-k=0        >"$TMP/e2_ex_mixed.xml"
run2 "$TMP/two"  --expand=a.h:alpha,b.h:beta --top-k=0            >"$TMP/e2_ex_two.xml"
run  "$TMP/dctl" --expand=api.h:helper                            >"$TMP/e2_ex_ctl.xml"
run2 "$TMP/dctl" --expand=api.h:helper --top-k=0                  >"$TMP/e2_ex0_ctl.xml"
run2 "$TMP/dord" --expand=helper --top-k=0                        >"$TMP/e2_ex0_bare.xml"
exPresent "(E2u) --expand=api.h:helper (whole-file)"                          "$TMP/e2_ex.xml"       1 src    src "api.h"
exPresent "(E2u) --expand=api.h:helper --top-k=0 (bodies)"                    "$TMP/e2_ex0.xml"      1 bodies b   "api.h"
exPresent "(E2u) --expand=api.h:helper,useHelper --top-k=0 (a NAME item adds 0)" "$TMP/e2_ex_mixed.xml" 1 bodies b "api.h caller.cpp"
exPresent "(E2u) --expand=a.h:alpha,b.h:beta --top-k=0 (summed item by item)" "$TMP/e2_ex_two.xml"   2 bodies b   "a.h b.h"
exAbsent  "(E2u) --expand=api.h:helper, every candidate proven"               "$TMP/e2_ex_ctl.xml"     src    src a_impl.cpp
exAbsent  "(E2u) --expand=api.h:helper --top-k=0, every candidate proven"     "$TMP/e2_ex0_ctl.xml"    bodies b   a_impl.cpp
exAbsent  "(E2u) --expand=helper --top-k=0, bare name"                        "$TMP/e2_ex0_bare.xml"   bodies b   a_impl.cpp

echo
echo "=== (E2v) --outline, alone and beside --expand on the root they share ==="
run2 "$TMP/dord" --outline=api.h:helper --top-k=0 >"$TMP/e2_ol.xml"
run2 "$TMP/dctl" --outline=api.h:helper --top-k=0 >"$TMP/e2_ol_ctl.xml"
"$BIN" "$TMP/dord" --no-cache --expand=api.h:helper --outline=api.h:helper --top-k=0 >"$TMP/e2_exol.xml" 2>/dev/null
exPresent "(E2v) --outline=api.h:helper --top-k=0"                            "$TMP/e2_ol.xml"     1 outline o "api.h"
exPresent "(E2v) --expand=api.h:helper --outline=api.h:helper (one root, summed)" "$TMP/e2_exol.xml" 2 bodies b "api.h"
exAbsent  "(E2v) --outline=api.h:helper --top-k=0, every candidate proven"    "$TMP/e2_ol_ctl.xml"   outline o a_impl.cpp

echo
echo "=== (E2w) --owners covers the declaration's file under defs=\"1\", and now says what it did not analyse ==="
run "$TMP/ecp" --owners=api.h:helper    >"$TMP/e2_ow.xml"
run "$TMP/ecp" --owners=impl.cpp:helper >"$TMP/e2_ow_def.xml"
run "$TMP/ecp" --owners=helper          >"$TMP/e2_ow_bare.xml"
e3Present "(E2w) --owners=api.h:helper"                     "$TMP/e2_ow.xml"      owners 1 owners defs 1
e3Absent  "(E2w) --owners=impl.cpp:helper, the definition"  "$TMP/e2_ow_def.xml"  owners   owners defs 1
e3Absent  "(E2w) --owners=helper, bare name"                "$TMP/e2_ow_bare.xml" owners   owners defs 2

echo
echo "=== (E2x) MCP fetch_body serves the declaration's body, and now carries \"unproven_defs\" ==="
mcpTranscript "$TMP/e2_mcp_fb.rpc"      fetch_body "" "path=$TMP/mcp_dord" "handle=api.h:helper"
mcpTranscript "$TMP/e2_mcp_fb_def.rpc"  fetch_body "" "path=$TMP/mcp_dord" "handle=a_impl.cpp:helper"
mcpTranscript "$TMP/e2_mcp_fb_bare.rpc" fetch_body "" "path=$TMP/mcp_dord" "handle=helper"
for n in e2_mcp_fb e2_mcp_fb_def e2_mcp_fb_bare; do
    mcpPayload "$TMP/$n.rpc" >"$TMP/$n.json"
done
fbRow(){ # fbRow <label> <json-file> <served-file> <unproven_defs, or "" for absent>
    _lbl="$1" _j="$2" _file="$3" _want="$4"
    case "$( head -c 1 "$_j" )" in
        '{') ;;
        *) no "$_lbl: fetch_body did not answer ($( head -c 160 "$_j" ))"; return 0 ;;
    esac
    _F="$( jsonKey "$_j" file )"
    if [ "$_F" != "$_file" ]; then
        no "$_lbl: premise broken — the body served is from \"$_F\", expected \"$_file\""
        return 0
    fi
    _U="$( jsonKey "$_j" unproven_defs )"
    if [ "$_U" = "$_want" ]; then
        ok "$_lbl: serves $_F's body, and \"unproven_defs\" is ${_U:-absent}"
    else
        no "$_lbl: serves $_F's body with \"unproven_defs\" ${_U:-absent}, expected ${_want:-absent}"
    fi
}
fbRow "(E2x) MCP fetch_body handle=api.h:helper"                     "$TMP/e2_mcp_fb.json"      api.h      1
fbRow "(E2x) MCP fetch_body handle=a_impl.cpp:helper, the definition" "$TMP/e2_mcp_fb_def.json"  a_impl.cpp ""
fbRow "(E2x) MCP fetch_body handle=helper, bare name"                "$TMP/e2_mcp_fb_bare.json" a_impl.cpp ""

echo
echo "=== (E2y) --note-add keys its note to the declaration, and now says so about the definition on stderr ==="
cp -R "$TMP/dord" "$TMP/na_drop" && cp -R "$TMP/dord" "$TMP/na_def" || no "(E2y) could not copy the corpora --note-add writes into"
"$BIN" "$TMP/na_drop" --no-cache --note-add="api.h:helper: a gotcha"      >/dev/null 2>"$TMP/e2_na.err";     NA_RC=$?
"$BIN" "$TMP/na_def"  --no-cache --note-add="a_impl.cpp:helper: a gotcha" >/dev/null 2>"$TMP/e2_na_def.err"; NA_DEF_RC=$?
if [ "$NA_RC" != 0 ] || ! grep -q 'canonicalised' "$TMP/e2_na.err"; then
    no "(E2y) premise broken — --note-add=api.h:helper did not store a canonicalised note (rc=$NA_RC): $( head -c 200 "$TMP/e2_na.err" )"
elif grep -q 'unproven_defs=1' "$TMP/e2_na.err"; then
    ok "(E2y) --note-add=api.h:helper stores its note and says unproven_defs=1 on stderr"
else
    no "(E2y) --note-add=api.h:helper stored its note on the declaration with nothing on stderr about the definition it could not tie to api.h"
fi
if [ "$NA_DEF_RC" != 0 ]; then
    no "(E2y) control broken — --note-add=a_impl.cpp:helper failed (rc=$NA_DEF_RC): $( head -c 200 "$TMP/e2_na_def.err" )"
elif grep -q 'unproven_defs' "$TMP/e2_na_def.err"; then
    no "(E2y) --note-add=a_impl.cpp:helper mentions unproven_defs — nothing was dropped"
else
    ok "(E2y) --note-add=a_impl.cpp:helper, the definition: stored, and nothing on stderr about unproven_defs"
fi

echo
echo "=== (E2z) under the compact legend, the existing unproven_defs row fires on --expand's <ctx> and on <owners> ==="
run2 "$TMP/dord" --expand=api.h:helper --legend=compact >"$TMP/e2_ex_cmp.xml"
run2 "$TMP/ecp"  --owners=api.h:helper --legend=compact >"$TMP/e2_ow_cmp.xml"
for triple in "e2_ex_cmp.xml:ctx:src" "e2_ow_cmp.xml:owners:owners"; do
    f="${triple%%:*}"; rest="${triple#*:}"; el="${rest%%:*}"; before="${rest#*:}"
    R="$( elNC "$TMP/$f" "$el" )"
    nonempty "(E2z) no <$el> root in $f" "$R" || continue
    L="$( legendBefore "$TMP/$f" "$before" )"
    if [ -z "$( attr "$R" unproven_defs )" ]; then
        no "(E2z) $f: the compact <$el> root carries no unproven_defs= — nothing for the compact reading to define"
    elif [ "$( fullClauseIn "$L" )" = 1 ]; then
        no "(E2z) $f: the FULL unproven_defs= clause survived into the compact dialect beside its compact reading"
    else
        case "$L" in
            *'unproven_defs=K:'*) ok "(E2z) $f: <$el unproven_defs=\"$( attr "$R" unproven_defs )\">, the compact legend reads it, and the full clause is gone" ;;
            *)                    no "(E2z) $f: <$el> carries unproven_defs= under the compact legend with no unproven_defs=K: reading" ;;
        esac
    fi
done

# ── (E3a..E3f) THE FOCUS PICK: a definition with a body over a bodyless declaration ─────────────────────────────────────
# The (E2n..E2t) corpora sort the definition's file FIRST so their controls answer. These sort the HEADER first — api.h
# before impl.cpp, a_fwd.h before shape.h — which is the order that exposed the pick: the lowest id is then the declaration,
# so a bare name and a fully proven file:name answered the same zero the dropping selector did.
mkdir -p "$TMP/hord" "$TMP/hctl" "$TMP/legoh" "$TMP/legohctl" "$TMP/tsovl" "$TMP/pvirt"
cp "$TMP/dord/api.h" "$TMP/dord/caller.cpp" "$TMP/hord/"
cp "$TMP/dord/a_impl.cpp" "$TMP/hord/impl.cpp"
cp "$TMP/hord/"* "$TMP/hctl/"
{ printf '#include "api.h"\n'; cat "$TMP/hord/impl.cpp"; } >"$TMP/hctl/impl.cpp"
printf '#pragma once\nclass Shape;\n' >"$TMP/legoh/a_fwd.h"
cp "$TMP/lego/a_shape.h" "$TMP/legoh/shape.h"
sed 's/a_shape\.h/shape.h/' "$TMP/lego/circle.h" >"$TMP/legoh/circle.h"
cp "$TMP/legoh/"* "$TMP/legohctl/"
{ printf '#pragma once\n#include "a_fwd.h"\n'; tail -n +2 "$TMP/legoh/shape.h"; } >"$TMP/legohctl/shape.h"
# (E3e) a TypeScript overload SIGNATURE (bodyless) ahead of its implementation, in one file.
cat > "$TMP/tsovl/ovl.ts" <<'EOF'
export function describe(x: number): string;
export function describe(x: any): string {
    return String(x);
}
export function useDescribe(): string {
    return describe(1);
}
EOF
# (E3f) a C++ pure virtual (bodyless, scope Base) sorting ahead of an override in ANOTHER class.
cat > "$TMP/pvirt/a_base.h" <<'EOF'
#pragma once
class Base
{
public:
    virtual int area() = 0;
};
EOF
cat > "$TMP/pvirt/derived.h" <<'EOF'
#pragma once
#include "a_base.h"
class Derived : public Base
{
public:
    int area() override { return 1; }
};
EOF
cat > "$TMP/pvirt/use.cpp" <<'EOF'
#include "derived.h"
int total(Derived& d)
{
    return d.area();
}
EOF
cp -R "$TMP/hord" "$TMP/mcp_hord" && cp -R "$TMP/legoh" "$TMP/mcp_legoh" || no "(E3) could not copy the corpora for the MCP twins"

# The p= of the connect terminal row named NAME (<t n="NAME" … p="FILE:LINE">), outside comments: which definition a pick chose.
termP(){ paste -d '|' <( elNC "$1" t n ) <( elNC "$1" t p ) | awk -F'|' -v n="$2" '$1 == n { print $2; exit }'; }

# e3Pick <label> <file> <terminal-name> <want-p> <want-edges>
e3Pick(){
    _lbl="$1" _f="$2" _n="$3" _wp="$4" _we="$5"
    _R="$( elNC "$_f" connect )"
    nonempty "$_lbl: no <connect> root" "$_R" || return 0
    _P="$( termP "$_f" "$_n" )"; _E="$( attr "$_R" edges )"
    if [ "$_P" = "$_wp" ] && [ "$_E" = "$_we" ]; then
        ok "$_lbl: the $_n terminal is $_P, and edges=\"$_E\""
    else
        no "$_lbl: the $_n terminal is ${_P:-<none>} with edges=\"$_E\", expected $_wp with edges=\"$_we\""
    fi
}

echo
echo "=== (E3a) --around on a bare name and a fully proven file:name reaches the caller through the definition ==="
run "$TMP/hord" --around=helper       >"$TMP/e3_ar_bare.xml"
run "$TMP/hctl" --around=api.h:helper >"$TMP/e3_ar_ctl.xml"
run "$TMP/hord" --around=api.h:helper >"$TMP/e3_ar_drop.xml"
for pair in "e3_ar_bare.xml:bare name, header first" "e3_ar_ctl.xml:every candidate proven, header first"; do
    f="${pair%%:*}"; what="${pair#*:}"
    R="$( elNC "$TMP/$f" r )"
    nonempty "(E3a) no <r> root in $f" "$R" || continue
    if rowNamesNC "$TMP/$f" | grep -qx useHelper && [ -z "$( attr "$R" unproven_defs )" ]; then
        ok "(E3a) $f ($what): useHelper is in the neighbourhood, and nothing was dropped"
    else
        no "(E3a) $f ($what): the neighbourhood is { $( rowNamesNC "$TMP/$f" | paste -sd ' ' - ) } with unproven_defs=\"$( attr "$R" unproven_defs )\" — the focus is the declaration"
    fi
done
R_E3D="$( elNC "$TMP/e3_ar_drop.xml" r )"
if nonempty "(E3a) no <r> root for the dropping selector" "$R_E3D"; then
    # The row set JOINED, never compared through tr: elNC prints no trailing newline, so a trailing-space spelling of the
    # expected set could not match the right answer (measured: this row read red on a correct document).
    if [ "$( rowNamesNC "$TMP/e3_ar_drop.xml" | paste -sd ' ' - )" = "helper" ] && [ "$( attr "$R_E3D" unproven_defs )" = "1" ]; then
        ok "(E3a) kept: --around=api.h:helper matches declarations only, so its focus is still the declaration, with unproven_defs=\"1\""
    else
        no "(E3a) --around=api.h:helper no longer answers from the declaration with its residue: rows={ $( rowNamesNC "$TMP/e3_ar_drop.xml" | paste -sd ' ' - ) } unproven_defs=\"$( attr "$R_E3D" unproven_defs )\""
    fi
fi

echo
echo "=== (E3b) --connect and MCP connect join through the definition, and the terminal row names its file ==="
run "$TMP/hord" --connect=helper,useHelper       >"$TMP/e3_cn_bare.xml"
run "$TMP/hctl" --connect=api.h:helper,useHelper >"$TMP/e3_cn_ctl.xml"
run "$TMP/hord" --connect=api.h:helper,useHelper >"$TMP/e3_cn_drop.xml"
mcpText e3_mcp_cn_bare connect full "path=$TMP/mcp_hord" "symbols=helper,useHelper"
e3Pick    "(E3b) --connect=helper,useHelper, header first"                  "$TMP/e3_cn_bare.xml"     helper impl.cpp:1 1
e3Pick    "(E3b) --connect=api.h:helper,useHelper, every candidate proven"  "$TMP/e3_cn_ctl.xml"      helper impl.cpp:2 1
e3Pick    "(E3b) MCP connect symbols=helper,useHelper, header first"        "$TMP/e3_mcp_cn_bare.xml" helper impl.cpp:1 1
e3Present "(E3b) kept: --connect=api.h:helper,useHelper drops the definition" "$TMP/e3_cn_drop.xml" connect 1 connect edges 0

echo
echo "=== (E3c) --lego and MCP lego count the implementor through the definition, not the forward declaration ==="
run "$TMP/legoh"    --lego=Shape         >"$TMP/e3_lg_bare.xml"
run "$TMP/legohctl" --lego=a_fwd.h:Shape >"$TMP/e3_lg_ctl.xml"
run "$TMP/legoh"    --lego=a_fwd.h:Shape >"$TMP/e3_lg_drop.xml"
mcpText e3_mcp_lg_bare lego full "path=$TMP/mcp_legoh" "type=Shape"
for triple in "e3_lg_bare.xml:--lego=Shape, forward declaration first" "e3_lg_ctl.xml:--lego=a_fwd.h:Shape, every candidate proven" \
              "e3_mcp_lg_bare.xml:MCP lego type=Shape, forward declaration first"; do
    f="${triple%%:*}"; what="${triple#*:}"
    I="$( elNC "$TMP/$f" iface )"
    nonempty "(E3c) no <iface> row in $f" "$I" || continue
    if [ "$( attr "$I" implementors )" = "1" ] && [ "$( attr "$I" p )" = "shape.h" ] && [ -z "$( attr "$( elNC "$TMP/$f" lego )" unproven_defs )" ]; then
        ok "(E3c) $what: <iface p=\"shape.h\" implementors=\"1\">, and nothing was dropped"
    else
        no "(E3c) $what: <iface p=\"$( attr "$I" p )\" implementors=\"$( attr "$I" implementors )\"> — the focus is the forward declaration"
    fi
done
e3Present "(E3c) kept: --lego=a_fwd.h:Shape drops the definition" "$TMP/e3_lg_drop.xml" lego 1 iface implementors 0

echo
echo "=== (E3d) among several definitions, the lowest id is chosen ==="
run "$TMP/free" --connect=helper,unrelatedCaller >"$TMP/e3_cn_free.xml"
e3Pick "(E3d) --connect=helper,unrelatedCaller over api.h, other.cpp, third.cpp" "$TMP/e3_cn_free.xml" helper other.cpp:2 1

echo
echo "=== (E3e, E3f) kept as they were: a TypeScript overload signature, and a C++ pure virtual beside another class's override ==="
run "$TMP/tsovl" --connect=describe,useDescribe >"$TMP/e3_cn_ts.xml"
run "$TMP/pvirt" --connect=area,total           >"$TMP/e3_cn_pv.xml"
for triple in "e3_cn_ts.xml:describe:ovl.ts:1:(E3e) TypeScript overload signature" "e3_cn_pv.xml:area:a_base.h:5:(E3f) C++ pure virtual, override in Derived"; do
    f="${triple%%:*}"; rest="${triple#*:}"; n="${rest%%:*}"; rest="${rest#*:}"; wp="${rest%%:*}"; rest="${rest#*:}"; wp="$wp:${rest%%:*}"; what="${rest#*:}"
    D="$( paste -d '|' <( elNC "$TMP/$f" t n ) <( elNC "$TMP/$f" t defs ) | awk -F'|' -v n="$n" '$1 == n { print $2; exit }' )"
    P="$( termP "$TMP/$f" "$n" )"
    if [ "$D" != "2" ]; then
        no "$what: premise broken — the $n terminal carries defs=\"$D\", expected 2; with one definition there is no pick to keep"
    elif [ "$P" = "$wp" ]; then
        ok "$what: the $n terminal is still $P, the lowest id"
    else
        no "$what: the $n terminal moved to ${P:-<none>} (expected $wp) — the pick changed outside the C/C++ same-scope case"
    fi
done

echo
echo "=== (E3g) every legend that describes the pick names its same-scope condition ==="
# Two corpora, so the reading is checked where the condition DECIDES the answer: pvirt, where the only body is Derived's and
# the focus stays on Base's pure virtual (the neighbourhood is its own row), and hord, where the body is in the declaration's
# scope and wins (useHelper is reached). A reading with no condition is true of hord and false of pvirt.
run2 "$TMP/pvirt" --around=area   --legend=compact >"$TMP/e3_ar_pv_cmp.xml"
run2 "$TMP/hord"  --around=helper --legend=compact >"$TMP/e3_ar_bare_cmp.xml"
run  "$TMP/pvirt" --around=area                    >"$TMP/e3_ar_pv.xml"
# e3Reading <label> <file> <el-the-legend-precedes> <reading-head> <needle> — the reading must hold the needle
e3Reading(){
    _lbl="$1" _f="$2" _el="$3" _head="$4" _needle="$5"
    _C="$( readingOf "$( legendBefore "$_f" "$_el" )" "$_head" )"
    nonempty "$_lbl: no '$_head' reading in the legend before <$_el>" "$_C" || return 0
    case "$_C" in
        *"$_needle"*) ok "$_lbl: the '$_head' reading names the condition ('$_needle')" ;;
        *)            no "$_lbl: the '$_head' reading states no same-scope condition, so it describes a pick the answer does not always make: $_C" ;;
    esac
}
for pair in "e3_ar_pv_cmp.xml:area" "e3_ar_bare_cmp.xml:helper useHelper"; do
    f="${pair%%:*}"; rows="${pair#*:}"
    R="$( elNC "$TMP/$f" r )"
    nonempty "(E3g) no <r> root in $f" "$R" || continue
    GOT="$( rowNamesNC "$TMP/$f" | paste -sd ' ' - )"
    if [ "$( attr "$R" defs )" != "2" ] || [ "$GOT" != "$rows" ]; then
        no "(E3g) $f: premise broken — defs=\"$( attr "$R" defs )\" rows={ $GOT }, expected defs=\"2\" rows={ $rows }"
        continue
    fi
    e3Reading "(E3g) compact --around, rows { $rows }" "$TMP/$f" r "defs=N:" "same scope"
done
e3Reading "(E3g) full --around seed clause (pvirt)" "$TMP/e3_ar_pv.xml"   r       "defs= (only when >1)"   "of its scope"
e3Reading "(E3g) full --around seed clause (hord)"  "$TMP/e3_ar_bare.xml" r       "defs= (only when >1)"   "of its scope"
e3Reading "(E3g) --connect header (pvirt)"          "$TMP/e3_cn_pv.xml"   connect "defs= on a terminal row" "of its scope"

echo
echo "=== (F) MUTATION — every assertion shape above is shown able to fail ==="
# (A)/(B) shape: the row-name reader must SEE a wrong caller when one is present…
printf '<callers of="a/Store.h:putObject" defs="2" count="1"><s t="fn" n="callB" p="b/Store.cpp:8"/></callers>' >"$TMP/m_a.xml"
rowNames "$TMP/m_a.xml" | grep -qx 'callB' \
    && ok "(F) A/B-shape: a wrongly-served row IS detected" \
    || no "(F) the row-name reader cannot see a served row that is present"
# …and must NOT be fooled by of=", which echoes the selector into the same document.
printf '<callers of="b/Store.cpp:callB" defs="1" count="0"></callers>' >"$TMP/m_a2.xml"
[ -z "$( rowNames "$TMP/m_a2.xml" )" ] \
    && ok "(F) A/B-shape: of=\"…callB\" with no rows is NOT read as a served row" \
    || no "(F) the row-name reader matched the of= echo — every 'must not serve' arm would be inert"
# (A)/(B) controls: a zero control count must be rejected rather than passing as agreement.
printf '<callers of="x" count="0"></callers>' >"$TMP/m_c0.xml"
[ "$( attr "$( rootEl "$TMP/m_c0.xml" callers )" count )" = "0" ] \
    && ok "(F) control guard: a zero control count IS detected (0==0 vacuity would be caught)" \
    || no "(F) the control guard cannot see a zero count"
# (C) shape: unequal counts must be seen.
printf '<callers of="Store.h:putObject" count="0"></callers>' >"$TMP/m_c.xml"
[ "$( attr "$( rootEl "$TMP/m_c.xml" callers )" count )" != "1" ] \
    && ok "(F) C-shape: a header count that DISAGREES with the .cpp count is detected" \
    || no "(F) the (C) equality comparison cannot tell 0 from 1"
# (E2) shape: the attribute reader must SEE the attribute when it is there…
printf '<callers of="a/Store.h:putObject" defs="1" count="0" unproven_defs="7"></callers>' >"$TMP/m_e2.xml"
[ "$( attr "$( rootEl "$TMP/m_e2.xml" callers )" unproven_defs )" = "7" ] \
    && ok "(F) E2-shape: unproven_defs=\"7\" IS read off a root that carries it" \
    || no "(F) the unproven_defs reader cannot see the attribute — every (E2a) arm would be inert"
# …must report ABSENCE as empty, so (E2b) is an assertion and not a tautology…
printf '<callers of="Store.h:putObject" defs="2" count="1"></callers>' >"$TMP/m_e2b.xml"
[ -z "$( attr "$( rootEl "$TMP/m_e2b.xml" callers )" unproven_defs )" ] \
    && ok "(F) E2-shape: a root WITHOUT the attribute reads as empty" \
    || no "(F) the reader invents a value for an absent attribute — (E2b) would pass on anything"
# …and must not confuse the two attributes whose names end in the same six bytes (`defs`). Both directions:
# the suffix must not be read as the whole name, and the whole name must not be read as the suffix.
printf '<callers of="x" bodyless_defs="3" unproven_defs="5" defs="9" count="0"></callers>' >"$TMP/m_e2c.xml"
RM="$( rootEl "$TMP/m_e2c.xml" callers )"
[ "$( attr "$RM" defs )" = "9" ] && [ "$( attr "$RM" unproven_defs )" = "5" ] && [ "$( attr "$RM" bodyless_defs )" = "3" ] \
    && ok "(F) E2-shape: defs=/bodyless_defs=/unproven_defs= are read as three distinct attributes" \
    || no "(F) the attribute reader matches a NAME SUFFIX — defs=$( attr "$RM" defs ) unproven=$( attr "$RM" unproven_defs ) bodyless=$( attr "$RM" bodyless_defs )"
# (E2c) shape: the JSON reader must tell a present key from an absent one.
printf '{"of":"x","defs":1,"count":0,"unproven_defs":4}' >"$TMP/m_e2j.json"
printf '{"of":"x","defs":1,"count":0}'                   >"$TMP/m_e2j0.json"
[ "$( jsonKey "$TMP/m_e2j.json" unproven_defs )" = "4" ] && [ -z "$( jsonKey "$TMP/m_e2j0.json" unproven_defs )" ] \
    && ok "(F) E2-shape: the JSON key reader distinguishes present from absent" \
    || no "(F) the JSON key reader cannot tell a present key from an absent one"
# (E2d) shape: the legend reader must return nothing for a document with no leading comment, or its
# present/absent comparison is two empty strings agreeing with each other (CONTRIBUTING §2, shape 3).
[ -z "$( legendOf "$TMP/m_e2.xml" )" ] \
    && ok "(F) E2-shape: legendOf returns empty for a document with no leading comment" \
    || no "(F) legendOf invents a legend — the (E2d) comparison could be empty==empty"
# (E) shape: the driver's own reporter must be able to say FAIL — a run that prints no verdict is not a pass.
printf 'UNIT FAIL\n' >"$TMP/m_e.out"
grep -q '^UNIT ALL PASS$' "$TMP/m_e.out" \
    && no "(F) the (E) verdict reader accepts a driver run that failed" \
    || ok "(F) E-shape: a driver run without UNIT ALL PASS is NOT read as a pass"
# (E2e) shape: the MCP transcript reader must hand back the payload, and must never hand back an error as one.
printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}' \
    '{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<impact of=\"x\" unproven_defs=\"3\"></impact>"}]}}' >"$TMP/m_rpc_ok.rpc"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}' \
    '{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"symbol not found"}}' >"$TMP/m_rpc_err.rpc"
mcpPayload "$TMP/m_rpc_ok.rpc"  >"$TMP/m_rpc_ok.xml"
mcpPayload "$TMP/m_rpc_err.rpc" >"$TMP/m_rpc_err.xml"
[ "$( attr "$( rootEl "$TMP/m_rpc_ok.xml" impact )" unproven_defs )" = "3" ] && [ -z "$( rootEl "$TMP/m_rpc_err.xml" impact )" ] \
    && ok "(F) E2e-shape: the MCP reader returns the payload, and an error response yields no root to assert on" \
    || no "(F) the MCP transcript reader cannot tell a payload from an error — every MCP arm would be inert or vacuous"
# (E2f) shape: clauseOf must see risk= INSIDE the clause, and must not credit a risk= that sits before or after it.
L_IN='<!-- risk= NAMES what was found. unproven_defs=K (absent when 0) so risk= describes defs= alone. counts_floor="1" means -->'
L_OUT='<!-- risk= NAMES what was found. unproven_defs=K (absent when 0) counts definitions. counts_floor="1" risk= -->'
case "$( clauseOf "$L_IN" )"  in *'risk='*) M_IN=1 ;;  *) M_IN=0 ;;  esac
case "$( clauseOf "$L_OUT" )" in *'risk='*) M_OUT=1 ;; *) M_OUT=0 ;; esac
[ "$M_IN" = 1 ] && [ "$M_OUT" = 0 ] \
    && ok "(F) E2f-shape: clauseOf reads risk= inside the clause and does not credit one outside it" \
    || no "(F) clauseOf cannot tell a clause that addresses risk= from a legend that merely contains it (in=$M_IN out=$M_OUT)"
# (E2j) shape: only a refusal of the spelling as CLI-only counts — an ANSWER (the silent zero itself) and an error about
# something else must both read as "not refused", or the arm would pass on a twin that answers.
printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}' \
    '{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"qualified file:name selectors are CLI-only on this verb"}}' >"$TMP/m_e2j_ref.rpc"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}' \
    '{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<uses of=\"api.h:helper\" defs=\"1\" count=\"0\"></uses>"}]}}' >"$TMP/m_e2j_ans.rpc"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}' \
    '{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"unknown field: legend"}}' >"$TMP/m_e2j_err.rpc"
[ "$( refusesAsCliOnly "$TMP/m_e2j_ref.rpc" )" = 1 ] && [ "$( refusesAsCliOnly "$TMP/m_e2j_ans.rpc" )" = 0 ] && [ "$( refusesAsCliOnly "$TMP/m_e2j_err.rpc" )" = 0 ] \
    && ok "(F) E2j-shape: refusesAsCliOnly reads the CLI-only refusal, and neither an answer nor another error" \
    || no "(F) refusesAsCliOnly cannot tell the refusal from an answer or another error — (E2j) would pass on a twin that answers"
# (E2m) shape: a compact leading run that KEPT the full clause beside its compact reading must be told from one that did not.
printf '<!-- ripwire verify ripwire.verify/v1: x. unproven_defs=K: K defs. --><!-- ripwire verify: unproven_defs=K (absent when 0) counts --><verify unproven_defs="2"></verify>' >"$TMP/m_e2m_kept.xml"
printf '<!-- ripwire verify ripwire.verify/v1: x. unproven_defs=K: K defs. --><verify unproven_defs="2"></verify>' >"$TMP/m_e2m_gone.xml"
[ "$( fullClauseIn "$( legendOf "$TMP/m_e2m_kept.xml" )" )" = 1 ] && [ "$( fullClauseIn "$( legendOf "$TMP/m_e2m_gone.xml" )" )" = 0 ] \
    && ok "(F) E2m-shape: a full clause kept in a compact leading run IS detected, and a compact reading alone is not" \
    || no "(F) fullClauseIn cannot tell a compact legend that kept the full clause from one that dropped it"
# (E2n..E2t) shape: elNC must skip a tag spelled inside a comment and a longer tag sharing its prefix, legendBefore must
# return the comments met before the element (nested or not) and none after it, and nothing at all when the element is
# absent, and rowNamesNC must not read a row spelled in a comment.
printf '<!-- a legend naming <lego unproven_defs="9"> --><ctx><rr unproven_defs="8"/><!-- A --><lego unproven_defs="2"><!-- B --><iface implementors="0"/></lego></ctx>' >"$TMP/m_e3.xml"
[ "$( attr "$( elNC "$TMP/m_e3.xml" lego )" unproven_defs )" = "2" ] && [ -z "$( elNC "$TMP/m_e3.xml" r )" ] \
    && ok "(F) E2n-shape: elNC reads the element itself, never a tag named in a comment or a longer tag sharing its prefix" \
    || no "(F) elNC read a commented tag or a prefix-sharing tag (lego=$( elNC "$TMP/m_e3.xml" lego ) r=$( elNC "$TMP/m_e3.xml" r ))"
L_E3="$( legendBefore "$TMP/m_e3.xml" lego )"
case "$L_E3" in *'A -->'*) E3_A=1 ;; *) E3_A=0 ;; esac
case "$L_E3" in *'B -->'*) E3_B=1 ;; *) E3_B=0 ;; esac
[ "$E3_A" = 1 ] && [ "$E3_B" = 0 ] && [ -z "$( legendBefore "$TMP/m_e3.xml" slice )" ] \
    && ok "(F) E2n-shape: legendBefore returns the comments met before the element, none after, and nothing when it is absent" \
    || no "(F) legendBefore cannot tell the legend before an element from a comment after it (A=$E3_A B=$E3_B absent=$( legendBefore "$TMP/m_e3.xml" slice | head -c 40 ))"
printf '<!-- <s n="useHelper"> --><r><f p="api.h"><s t="fn" n="helper"/></f></r>' >"$TMP/m_e3r.xml"
[ "$( rowNamesNC "$TMP/m_e3r.xml" )" = "helper" ] \
    && ok "(F) E2r-shape: rowNamesNC reads the rows, never a row spelled in a comment" \
    || no "(F) rowNamesNC read a commented row — the (E2r) premise could pass on a legend: $( rowNamesNC "$TMP/m_e3r.xml" | tr '\n' ' ' )"
# (E2u) shape: pathsOf must read each served file once, and never a row spelled in a comment or a longer tag sharing the
# row's prefix (<b> is a prefix of <bodies>), or the narrower-answer premise could pass on a legend.
printf '<!-- <b p="impl.cpp"> --><ctx><bodies shown="3"><b p="api.h"/><b p="api.h"/><bx p="x.h"/><b p="caller.cpp"/></bodies></ctx>' >"$TMP/m_e2u.xml"
[ "$( pathsOf "$TMP/m_e2u.xml" b )" = "api.h caller.cpp" ] \
    && ok "(F) E2u-shape: pathsOf reads each served file once, never a commented row or a prefix-sharing tag" \
    || no "(F) pathsOf misread the served files: $( pathsOf "$TMP/m_e2u.xml" b )"
# (E3b) shape: termP must return the p= of the terminal NAMED, never another terminal's or one spelled in a comment.
printf '<!-- <t n="helper" p="api.h:2"/> --><connect edges="1"><g><t n="useHelper" p="caller.cpp:2"/><t n="helper" p="impl.cpp:1" defs="2"/></g></connect>' >"$TMP/m_e3b.xml"
[ "$( termP "$TMP/m_e3b.xml" helper )" = "impl.cpp:1" ] && [ "$( termP "$TMP/m_e3b.xml" useHelper )" = "caller.cpp:2" ] && [ -z "$( termP "$TMP/m_e3b.xml" absent )" ] \
    && ok "(F) E3b-shape: termP reads the named terminal's p=, never a commented row or another terminal's, and nothing for an absent name" \
    || no "(F) termP misread a terminal: helper=$( termP "$TMP/m_e3b.xml" helper ) useHelper=$( termP "$TMP/m_e3b.xml" useHelper ) absent=$( termP "$TMP/m_e3b.xml" absent )"
# (E3g) shape: readingOf must read the NAMED head's reading alone — never another term whose name ends in the same bytes
# (unproven_defs=K: holds the needle below), never a later term (rank_by= holds it too), and it must stop at "; qualify".
L_E3G_BAD='<!-- unproven_defs=K: K defs of the same scope. defs=N: of= names N defs; the lowest-id one was walked, a C/C++ body over its declaration. rank_by=: the same scope -->'
L_E3G_OK='<!-- defs=N: of= names N defs; the lowest-id one was walked, a C/C++ body in the same scope over its declaration. -->'
L_E3G_FULL='<!-- defs= (only when >1) = N definitions (a declaration yields); qualify with file:name of its scope. -->'
case "$( readingOf "$L_E3G_BAD" "defs=N:" )"  in *'same scope'*)   G_BAD=1 ;;  *) G_BAD=0 ;;  esac
case "$( readingOf "$L_E3G_OK" "defs=N:" )"   in *'same scope'*)   G_OK=1 ;;   *) G_OK=0 ;;   esac
case "$( readingOf "$L_E3G_FULL" "defs= (only when >1)" )" in *'of its scope'*) G_FULL=1 ;; *) G_FULL=0 ;; esac
[ "$G_BAD" = 0 ] && [ "$G_OK" = 1 ] && [ "$G_FULL" = 0 ] && [ -z "$( readingOf "$L_E3G_OK" "rank_by=" )" ] \
    && ok "(F) E3g-shape: readingOf reads the named head's reading alone, stops at '; qualify', and is empty for an absent head" \
    || no "(F) readingOf credited a needle outside the named reading or missed one inside it (bad=$G_BAD ok=$G_OK past-qualify=$G_FULL)"
# VACUITY guard itself. Run in a subshell so it cannot set fail.
if ( nonempty "probe" "" >/dev/null 2>&1 ); then
    no "(F) nonempty() accepts an empty capture — every arm's vacuity guard is inert"
else
    ok "(F) vacuity guard: nonempty() rejects an empty capture"
fi
[ -z "$( rootEl "$TMP/m_e.out" callers )" ] \
    && ok "(F) rootEl: returns empty for an element the document does not contain" \
    || no "(F) rootEl matched a <callers> element in a document that has none"

echo
echo "=== determinism + well-formedness on the answers this gate reads ==="
run "$TMP/ns" --callers=a/Store.h:putObject >"$TMP/det1.xml"
run "$TMP/ns" --callers=a/Store.h:putObject >"$TMP/det2.xml"
if cmp -s "$TMP/det1.xml" "$TMP/det2.xml"; then ok "determinism: a/Store.h:putObject byte-identical run-to-run"; else no "non-deterministic --callers output"; fi
if command -v xmllint >/dev/null 2>&1; then
    # The e2_* documents are the ones whose legends grew a clause — an XML comment may not hold a double hyphen (G4).
    if xmllint --noout "$TMP/a_far.xml" 2>/dev/null && xmllint --noout "$TMP/c_hdr_hdr.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_sd.xml" 2>/dev/null && xmllint --noout "$TMP/e2_imp.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_pth.xml" 2>/dev/null && xmllint --noout "$TMP/e2_mcp_imp.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_us.xml" 2>/dev/null && xmllint --noout "$TMP/e2_us_col.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_mn.xml" 2>/dev/null && xmllint --noout "$TMP/e2_vf_calls.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_af.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_ec.xml" 2>/dev/null && xmllint --noout "$TMP/e2_ecd.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_lg.xml" 2>/dev/null && xmllint --noout "$TMP/e2_cn.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_ar.xml" 2>/dev/null && xmllint --noout "$TMP/e2_sl.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_mcp_lg.xml" 2>/dev/null && xmllint --noout "$TMP/e2_mcp_cn.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_ex.xml" 2>/dev/null && xmllint --noout "$TMP/e2_ex0.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e2_exol.xml" 2>/dev/null && xmllint --noout "$TMP/e2_ow.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e3_ar_bare.xml" 2>/dev/null && xmllint --noout "$TMP/e3_cn_bare.xml" 2>/dev/null \
       && xmllint --noout "$TMP/e3_lg_bare.xml" 2>/dev/null && xmllint --noout "$TMP/e3_cn_ts.xml" 2>/dev/null; then
        ok "xml well-formed"
    else
        no "xml malformed"
    fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

echo
[ "$fail" -eq 0 ] && { echo "decltodefcheck: ALL PASS"; exit 0; }
echo "decltodefcheck: FAILURES"; exit 1
