#!/usr/bin/env bash
# forfileanchorcheck.sh — FOR-FILE-ANCHOR (issue #466, reported by @pguerrerolinares): a --for subject that IS a file resolves to
# that file (src/mention.h RawMention::whole / resolveStemFile; src/forfilepage.h) and serves its page.
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 61ab7aac; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   TRIGGER  CLI --for (XML, default regime) whose subject is a file: a bare basename with a code extension, a hyphenated or
#            snake_case file stem, a path, or a directory — nothing else but stopwords and file nouns ("file", "package", "script").
#   WHAT     <named-file p= lines= defs=> first inside the root: every def (s t= n= l= e= in= by=), and for a script its
#            top-level text (<top l= e=>CDATA</top>, <top_cut … rest=> when cut); the file's top defs rank first.
#   NOT      a name matching several files (listed in <named-files>, none picked), a file mentioned as CONTEXT in a longer
#            question (anchor lift only, no page), a word that is a symbol's name, --json, RIPWIRE_NO_FILE_PAGE=1.
#
# Arms (fixtures created at runtime in a temp dir — never under a .gitignored path):
#   A1 [P] Bash `--for=document-remind` (hyphen stem; diag-466 §repro): the page names the script, serves its top-level text
#          ("set -euo pipefail"), and the r=1/r=2 rows are the script's — not the test sibling or a decoy. The honesty arm: base
#          answered confidence="high" with a decoy head.
#   A2 [P] the same through a bare basename `document-remind.sh` and `the document-remind.sh script`
#   B1 [P] Python `--for=sync_ledger` (snake stem, no symbol of that name): not reason="no_candidates"; page present
#   B2 [P] `--for="what does sync_ledger.py do"`: page present
#   B3 [P] Ruby / Lua / JS / TS stems and basenames: page present with top-level text
#   C1 [P] ambiguous basename `util.py` (two files): <named-files n="util.py" total="2"> listing both; no <named-file> page and
#          no file-subject lift (no "file subject:" note)
#   C2 [G] a dotted Scope.name `Location.go` with NO such file keeps its dotted reading: no page, method `go` of Location in <sigs>
#   D1 [P] directory: `--for="cmd/syncledger package"` serves <named-dir p="cmd/syncledger"> holding main.go's page
#   E1 [G] context, not subject: `where STATE used in sync_ledger.py is defined` carries no page
#   E3 [P] the same context question still ANCHORS the bare basename (mention.h (a0)): mention_anchored= and a tools/sync_ledger.py
#          row in the top 3 (base: the dotted [sync_ledger, py] reading anchored nothing)
#   H1 [P] a bare C basename names its file for the decl/impl partner row too: `--for=widget.c` carries <hdr p="widget.h" of="widget.c"/>
#   E2 [G] a stem that IS a symbol's name (`run_all`, def run_all in run_all.py): no stem anchor, no page
#   F1 [P] in=0 hedge: the clause says in=0 is NOT unused; the uncalled def carries in="0"; by= names the caller's file
#   R1 [P] redaction: a secret in the top-level text is redacted (the AKIA key is absent from the answer)
#   K2 [P] the anchor cap discloses: a subject naming three files pages two and says <named-cut total="3" shown="2"/>
#   K1 [P] the top-level cap discloses: a 120-line script shows at most 40 lines and <top_cut … rest=>
#   N1 [G] no page with RIPWIRE_NO_FILE_PAGE=1, nor under --json
#   D2..D5 [P] (lens F1) a slash token that names a DIRECTORY is read on the FULL path before any shorter suffix: `pkg/foo` beside an
#          unrelated internal/foo.go -> named-dir (D2), the Go convention pkg/foo/foo.go -> named-dir holding encode.go (D3),
#          `src/helper/cookie` beside src/utils/cookie.ts -> named-dir, first <d> row in src/helper/cookie/ (D4), `lib/a.c` with only a
#          root a.c -> a near="1" listing, no page (D5); a file AND a directory both answering (src/utils.ts + src/utils/) -> listed, none picked (D6)
#   M1 [P] (primary C1) next= is built by nextFlag: pasted through `sh -n`, then replayed through shlex, it parses and runs
#   M2 [P] (primary C2) a script's page does not list the defs the script's OWN top level calls as "main does not reach"; the 16-call
#          walk cap is said in both dialects
#   M3 [P] (primary C3) the page has one 16 KB bound: a 7-file directory and two directories stop at a file boundary, bytes_capped=1
#   M4 [P] (primary N2) a minified one-line file with no <file-scope> row says top_cut shown=0, never an empty page
#   K3-K5 [P] (primary N1) the def-row cap (41 defs), the dir-file cap (7 files) and the list cap (9 same-named files) are disclosed
#   H2 [P] (lens N1) a C header's page carries no next=; N3 [P] (lens N3) a path naming a .md file pages nothing
#   T1 [P] (primary N1) tier="test" on a listed file; by_total= beside by=
#   Y1..Y4 [P] (delta review X1..X4) next= lists a METHOD (kind=method) beside the free functions; a dir= row names ONE directory with
#          ITS OWN count, the directory as written first (src/utils/ before pkg/x/src/utils/), and a directory with no same-named file
#          pages that directory first; the module root (mod.rs, index.ts) is a directory's first page; a listing appended after a
#          full directory obeys the 16 KB bound
#   L1 [P] the clause rides in both dialects and defines every attribute the page elements carry (whole-name search in the clause)
#   X1 [G] determinism  X2 [G] xmllint well-formed (when xmllint exists)  X3 [G] no "--" inside the legend comment
#
# Usage:  bash test/forfileanchorcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forfileanchorcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_FILE_PAGE RIPWIRE_NO_MENTION
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forfileanchorcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

T="$( mktemp -d "${TMPDIR:-/tmp}/forfileanchor.XXXXXX" )" || exit 2
trap '[ -n "${FORFILEANCHOR_KEEP:-}" ] || rm -rf "$T"' EXIT   # FORFILEANCHOR_KEEP=1 keeps the answers for a look
H="$T/home"; mkdir -p "$H"

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
python3 - "$T" <<'PY'
import os, sys
T = sys.argv[1]
def w(rel, text):
    p = os.path.join(T, rel); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(text)
# bash: a mostly-top-level hook script, its test sibling (names share the stem's tokens), decoys
top = ["#!/usr/bin/env bash", "# document-remind.sh: Stop hook that reminds the agent to update the journal.", "set -euo pipefail",
       'INPUT="$(cat)"', 'STATE_DIR="${HOME}/.cache/acme"', 'mkdir -p "$STATE_DIR"', 'TOKEN="AKIA' + 'ABCDEFGHIJKLMNOP"']
for i in range(1, 30):
    top += ['if [ -f "$STATE_DIR/flag%d" ]; then' % i, '  echo "journal pending %d" >> "$STATE_DIR/stamp"' % i, "fi"]
top += ["emit() {", '  printf "%s\\n" "$1"', "}", 'emit "remind the document journal"']
w("bash/plugins/acme/scripts/document-remind.sh", "\n".join(top) + "\n")
w("bash/plugins/acme/scripts/test-document-remind.sh",
  "".join("test_document_remind_%d() {\n  echo document remind %d\n}\n" % (i, i) for i in range(6)))
w("bash/plugins/acme/scripts/delegar.py", "def remind(document):\n    return document\n\ndef delegate_document(d):\n    return remind(d)\n")
w("bash/src/escritor.py", "def write_document(x):\n    return x\n\ndef remind_later(x):\n    return x\n")
# python: snake stem with __main__, a test, decoys, an uncalled def and a called one
w("py/tools/sync_ledger.py", "import sys\nSTATE = {}\n\ndef emit(x):\n    print(x)\n\ndef unused_helper():\n    return 1\n\n"
  + "".join("for k%d in range(3):\n    STATE[k%d] = k%d\n" % (i, i, i) for i in range(12))
  + "if __name__ == '__main__':\n    emit(STATE)\n")
w("py/tools/test_sync_ledger.py", "from sync_ledger import emit\n\ndef test_sync_ledger_emit():\n    emit(1)\n")
w("py/src/decoy.py", "LEDGER_SYNC_TAGS = ['sync', 'ledger']\n\ndef sync_tags():\n    return LEDGER_SYNC_TAGS\n")
w("py/pkg_a/util.py", "def a_helper():\n    return 1\n")
w("py/pkg_b/util.py", "def b_helper():\n    return 2\n")
w("py/tools/run_all.py", "def run_all():\n    return 0\n\nrun_all()\n")
w("py/tools/user.py", "from sync_ledger import STATE\n\ndef reader():\n    return STATE\n")
# ruby / lua / js / ts
body = "".join("STATE[%d] = %d\n" % (i, i) for i in range(20))
w("rb/bin/sync_ledger.rb", "STATE = {}\ndef emit(x)\n  puts x\nend\n" + body.replace("STATE[", "STATE[") + "emit(STATE)\n")
w("lua/scripts/sync_ledger.lua", "local STATE = {}\nlocal function emit(x)\n  print(x)\nend\n" + body + "emit(STATE)\n")
js = "const STATE = {};\nfunction emit(x) {\n  console.log(x);\n}\n" + "".join("STATE[%d] = %d;\n" % (i, i) for i in range(20)) + "emit(STATE);\n"
w("js/scripts/sync-ledger.js", js)
w("js/scripts/sync-ledger.test.js", "function syncLedgerTest() {\n  return 'sync ledger';\n}\n")
w("ts/scripts/sync-ledger.ts", js)
# go: a directory anchor
w("go/cmd/syncledger/main.go", "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(helper())\n}\n\nfunc helper() string {\n\treturn \"x\"\n}\n")
w("go/go.mod", "module example.com/x\n\ngo 1.21\n")
w("c/src/widget.c", "#include \"widget.h\"\nint widget_area(int w, int h) {\n    return w * h;\n}\n")
w("c/src/widget.h", "int widget_area(int w, int h);\n")
w("c/src/main.c", "#include \"widget.h\"\nint main(void) {\n    return widget_area(2, 3);\n}\n")
# the dotted Scope.name near miss (no file Location.go anywhere)
w("ts2/src/location.ts", "export class Location {\n  go(path: string): void {\n    history.pushState(null, '', path);\n  }\n}\n")
for n in ("alpha", "beta", "gamma"):
    w("multi/%s_tool.py" % n, "def %s_run():\n    return 1\n" % n)
# lens F1 / primary C1-C3 fixtures
w("d2/pkg/foo/encode.go", "package foo\n\nfunc Encode() int {\n\treturn 1\n}\n")
w("d2/pkg/foo/decode.go", "package foo\n\nfunc Decode() int {\n\treturn 2\n}\n")
w("d2/internal/foo.go", "package internal\n\nfunc LegacyFooShim() int {\n\treturn 3\n}\n")
w("d3/pkg/foo/foo.go", "package foo\n\nvar Version = 1\n")
w("d3/pkg/foo/encode.go", "package foo\n\nfunc Encode() int {\n\treturn 1\n}\n")
w("d3/pkg/foo/decode.go", "package foo\n\nfunc Decode() int {\n\treturn 2\n}\n")
w("d4/src/helper/cookie/index.ts", "export function setCookie(n: string): string {\n  return n\n}\nexport function deleteCookie(n: string): string {\n  return n\n}\n")
w("d4/src/utils/cookie.ts", "export function parse(s: string): string {\n  return s\n}\nexport function serialize(s: string): string {\n  return s\n}\n")
w("d5/a.c", "int a_add(int x) {\n    return x + 1;\n}\n")
w("d6/src/utils.ts", "export function one(): number {\n  return 1\n}\n")
w("d6/src/utils/index.ts", "export function two(): number {\n  return 2\n}\n")
# M2: a script whose top level calls emit, beside a C main
w("m2/scripts/run.sh", "#!/usr/bin/env bash\nset -eu\nemit() {\n  echo \"$1\"\n}\nunused_one() {\n  echo x\n}\nemit \"hi\"\n")
w("m2/src/main.c", "int helper(void) {\n    return 1;\n}\nint main(void) {\n    return helper();\n}\n")
# M3: seven files of sixty long-signature defs in two sibling directories
for d in ("big", "big2"):
    for f in range(1, 8):
        w("m3/pkg/%s/f%d.py" % (d, f), "".join("def %s_f%d_op%02d(first_argument, second_argument, third_argument, fourth_argument, fifth_argument, sixth_argument):\n    return first_argument\n\n" % (d, f, i) for i in range(60)))
# M4: a minified bundle: one long line of assignments, no call, no def
w("m4/src/mini.js", "var a=1;" + "".join("var v%d=%d;" % (i, i) for i in range(1500)) + "\n")
w("m4/src/other.js", "function other() {\n  return 1;\n}\n")
# K3: 41 defs; K4: a 7-file directory; K5: nine files of one name
w("k3/lib/many_defs.py", "".join("def op%02d():\n    return %d\n\n" % (i, i) for i in range(41)))
for f in range(1, 8):
    w("k4/pkg/seven/f%d.py" % f, "def seven_f%d():\n    return %d\n" % (f, f))
for d in range(1, 10):
    w("k5/pkg%d/dup.py" % d, "def dup_%d():\n    return %d\n" % (d, d))
# Y1: a JS class holds methods (kind=method): next= must list an uncalled METHOD, not only free functions; a C main roots the closure
w("y1/web/app.js", "class Server {\n  start() {\n    return helperA();\n  }\n  orphanMethod() {\n    return 2;\n  }\n}\nfunction helperA() {\n  return 1;\n}\nfunction deadFn() {\n  return 3;\n}\n")
w("y1/src/main.c", "int main(void) {\n    return 0;\n}\n")
# Y2: src/utils is a directory at the root AND inside pkg/x, and a file pkg/y/src/utils.ts; y2b has no such file
for root in ("y2", "y2b"):
    w(root + "/src/utils/a.ts", "export function a(): number {\n  return 1\n}\n")
    w(root + "/pkg/x/src/utils/b.ts", "export function b(): number {\n  return 2\n}\n")
    w(root + "/pkg/x/src/utils/c.ts", "export function c(): number {\n  return 3\n}\n")
w("y2/pkg/y/src/utils.ts", "export function y(): number {\n  return 4\n}\n")
# Y3: eight files, the module root sorts last by path; a Python package whose __init__.py sorts after its siblings
for i in range(1, 8):
    w("y3/crate/src/mw/f%d.rs" % i, "pub fn f%d_run() -> u32 {\n    %d\n}\n" % (i, i))
w("y3/crate/src/mw/mod.rs", "pub fn mw_root() -> u32 {\n    0\n}\n")
for i in range(1, 8):
    w("y3p/pkg/ware/f%d.ts" % i, "export function f%d_run(): number {\n  return %d\n}\n" % (i, i))
w("y3p/pkg/ware/index.ts", "export function ware_root(): number {\n  return 0\n}\n")
# Y4: a directory that fills the page, then a name matching several files
for f in range(1, 8):
    w("y4/pkg/big/f%d.py" % f, "".join("def big_f%d_op%02d(first_argument, second_argument, third_argument, fourth_argument, fifth_argument, sixth_argument, seventh_argument, eighth_arg):\n    return first_argument\n\n" % (f, i) for i in range(60)))
for d in range(1, 9):
    w("y4/long_directory_name_number_%d_with_an_even_longer_tail_for_bytes/dup.py" % d, "def dup_%d():\n    return %d\n" % (d, d))
# T1: a test twin (tier=) and a def called from four files (by_total=)
# H2/N3: a C header carries no next= (its prototypes' callers bind to the definitions); a path naming a prose file is no page
w("d7/docs/guide.md", "# Guide\n\n## Install\n\ntext\n")
w("d7/src/guide.py", "def guide():\n    return 1\n")
w("t1/pkg/core.py", "def shared():\n    return 1\n")
w("t1/tests/core.py", "def test_shared():\n    return 1\n")
for i in range(1, 5):
    w("t1/use/a%d.py" % i, "from pkg.core import shared\n\ndef call_%d():\n    return shared()\n" % i)
# K1: a long script
w("long/run-deploy.sh", "#!/bin/sh\n" + "".join('echo "step %d"\n' % i for i in range(120)))
PY

# run FAILS the gate when the binary exits non-zero: an absence arm reads the capture, and a crashed run leaves it empty (CodeRabbit #481)
run(){ local d="$1"; shift; ( cd "$T/$d" || exit 1; HOME="$H" TMPDIR="$T/" "$BIN" "$T/$d" --no-cache "$@" < /dev/null 2>/dev/null ) || no "ripwire exited non-zero: $d $*"; }
has(){ grep -qF -- "$2" "$1"; }
# answered FILE NEEDLE: the capture holds a real answer (non-empty and carrying NEEDLE) — required before every absence-only arm
answered(){ [ -s "$1" ] && has "$1" "$2"; }

# ── A: the #466 Bash rows ───────────────────────────────────────────────────────────────────────────────────────────────────
run bash --for=document-remind > "$T/a1.xml"
if has "$T/a1.xml" '<named-file p="plugins/acme/scripts/document-remind.sh"' && has "$T/a1.xml" 'set -euo pipefail'; then
    ok "A1 hyphen stem: the script's page with its top-level text"
else no "A1 hyphen stem: no page for plugins/acme/scripts/document-remind.sh (or no top-level text)"; fi
head2="$( python3 - "$T/a1.xml" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
rows = {int(r): p for p, r in re.findall(r'<(?:d|h) [^>]*?p="([^"]*)"[^>]*? r="(\d+)"', s)}
print(" ".join(rows.get(k, "-") for k in (1, 2)))
PY
)"
case "$head2" in
    *plugins/acme/scripts/document-remind.sh*) ok "A1 the ranked head (r=1/r=2) is the named script: $head2" ;;
    *) no "A1 the ranked head is not the named script (decoy head, the #466 confident-wrong answer): $head2" ;;
esac
for subj in document-remind.sh "the document-remind.sh script" '`document-remind.sh`'; do
    run bash --for="$subj" > "$T/a2.xml"
    if has "$T/a2.xml" '<named-file p="plugins/acme/scripts/document-remind.sh"'; then ok "A2 '$subj' serves the page"
    else no "A2 '$subj' does not serve the page"; fi
done

# W1 [P] (CR pre-pass 43a) the lift says what it did to the auto-served bodies: the bodies below follow the file's rank, a def
# ranked lower gets none, and the note names the way to read one. No "--" in it (it rides inside an XML comment).
if has "$T/a1.xml" '[file subject: ' && has "$T/a1.xml" 'a def ranked lower gets none' && has "$T/a1.xml" 'expand flag'; then
    ok "W1 the file-subject note discloses the displaced auto-served bodies and names the expand flag"
else no "W1 the file-subject note does not say a lower-ranked def's body is held back"; fi

# ── B: the other languages ──────────────────────────────────────────────────────────────────────────────────────────────────
run py --for=sync_ledger > "$T/b1.xml"
if ! has "$T/b1.xml" 'reason="no_candidates"' && has "$T/b1.xml" '<named-file p="tools/sync_ledger.py"' && has "$T/b1.xml" "if __name__ == '__main__':"; then
    ok "B1 snake stem: not no_candidates; page with the __main__ block"
else no "B1 snake stem sync_ledger: no_candidates or no page"; fi
run py --for="what does sync_ledger.py do" > "$T/b2.xml"
if has "$T/b2.xml" '<named-file p="tools/sync_ledger.py"'; then ok "B2 'what does sync_ledger.py do' serves the page"
else no "B2 'what does sync_ledger.py do' serves no page"; fi
for spec in "rb sync_ledger bin/sync_ledger.rb" "rb sync_ledger.rb bin/sync_ledger.rb" "lua sync_ledger.lua scripts/sync_ledger.lua" \
            "js sync-ledger scripts/sync-ledger.js" "ts sync-ledger.ts scripts/sync-ledger.ts"; do
    set -- $spec
    run "$1" --for="$2" > "$T/b3.xml"
    if has "$T/b3.xml" "<named-file p=\"$3\"" && has "$T/b3.xml" '<top l="'; then ok "B3 $1 '$2' serves $3 with top-level text"
    else no "B3 $1 '$2' serves no page (or no top-level text) for $3"; fi
done

# ── C: ambiguity and the dotted near miss ───────────────────────────────────────────────────────────────────────────────────
run py --for=util.py > "$T/c1.xml"
if has "$T/c1.xml" '<named-files n="util.py" total="2">' && has "$T/c1.xml" '<f p="pkg_a/util.py"' && has "$T/c1.xml" '<f p="pkg_b/util.py"' \
   && ! has "$T/c1.xml" '<named-file ' && ! has "$T/c1.xml" 'file subject:'; then
    ok "C1 ambiguous basename: both listed, none picked, no lift"
else no "C1 ambiguous basename util.py: not listed as two, or one was picked"; fi
run ts2 --for=Location.go > "$T/c2.xml"
if ! has "$T/c2.xml" '<named-file' && ! has "$T/c2.xml" '<named-files' && grep -qE '<d [^>]*n="(Location\.)?go"' "$T/c2.xml"; then
    ok "C2 Location.go (no such file) keeps its dotted reading: method go served, no page"
else no "C2 Location.go: a page appeared or the method go is not served"; fi

# ── D: a directory ──────────────────────────────────────────────────────────────────────────────────────────────────────────
run go --for="cmd/syncledger package" > "$T/d1.xml"
if has "$T/d1.xml" '<named-dir p="cmd/syncledger" files="1">' && has "$T/d1.xml" '<named-file p="cmd/syncledger/main.go"'; then
    ok "D1 directory anchor: named-dir with main.go's page"
else no "D1 directory anchor cmd/syncledger: no named-dir page"; fi

# ── D2..D6: a path token names a directory (lens F1) ───────────────────────────────────────────────────────────────────────────
run d2 --for=pkg/foo > "$T/d2.xml"
if has "$T/d2.xml" '<named-dir p="pkg/foo" files="2"' && ! has "$T/d2.xml" '<named-file p="internal/foo.go"'; then
    ok "D2 pkg/foo is the directory, not the unrelated internal/foo.go"
else no "D2 pkg/foo beside internal/foo.go: no named-dir, or the same-stem file was paged"; fi
run d3 --for=pkg/foo > "$T/d3.xml"
if has "$T/d3.xml" '<named-dir p="pkg/foo" files="3"' && has "$T/d3.xml" '<named-file p="pkg/foo/encode.go"' && ! has "$T/d3.xml" '<named-file p="pkg/foo/foo.go" lines="3" defs="1" next'; then
    ok "D3 the Go convention pkg/foo/foo.go: the directory, with encode.go inside it"
else no "D3 pkg/foo (Go convention): no named-dir holding encode.go"; fi
run d4 --for=src/helper/cookie > "$T/d4.xml"
first4="$( python3 - "$T/d4.xml" <<'PY'
import re, sys
m = re.search(r'<d [^>]*?p="([^"]*)"', open(sys.argv[1]).read())
print(m.group(1) if m else "-")
PY
)"
if has "$T/d4.xml" '<named-dir p="src/helper/cookie"' && ! has "$T/d4.xml" 'src/utils/cookie.ts" lines' && case "$first4" in src/helper/cookie/*) true ;; *) false ;; esac; then
    ok "D4 src/helper/cookie is the directory; the first ranked row is in it ($first4)"
else no "D4 src/helper/cookie: no named-dir, a same-stem file was paged, or the first row is $first4"; fi
run d5 --for=lib/a.c > "$T/d5.xml"
if ! has "$T/d5.xml" '<named-file p="a.c"' && has "$T/d5.xml" '<named-files n="lib/a.c" total="1" near="1">' && ! has "$T/d5.xml" 'file subject:'; then
    ok "D5 lib/a.c with only a root a.c: a near listing, no page, no lift"
else no "D5 lib/a.c: a shorter-suffix file was paged or lifted"; fi
run d6 --for=src/utils > "$T/d6.xml"
if has "$T/d6.xml" '<f p="src/utils.ts"' && has "$T/d6.xml" '<f p="src/utils/" dir="1" files="1"/>' && ! has "$T/d6.xml" '<named-file ' && ! has "$T/d6.xml" 'file subject:'; then
    ok "D6 a file AND a directory answer to src/utils: both listed, none picked, no lift"
else no "D6 src/utils (file + directory): not both listed, or one was picked"; fi

# ── M1/M2: next= is a shell-safe flag, and a script's own top level is a root ───────────────────────────────────────────────────
run c --for=widget.c > "$T/m1.xml"
run m2 --for=run.sh > "$T/m2.xml"
nextof(){ python3 - "$1" "$2" <<'PY'
import html, re, sys
s = open(sys.argv[1]).read()
m = re.search(r'<named-file p="[^"]*' + re.escape(sys.argv[2]) + r'"[^>]*? next="([^"]*)"', s)
print(html.unescape(m.group(1)) if m else "")
PY
}
nx1="$( nextof "$T/m1.xml" widget.c )"
if [ -n "$nx1" ] && printf 'ripwire . %s\n' "$nx1" | sh -n 2>/dev/null; then ok "M1 next= pastes through sh -n"
else no "M1 next= is empty or does not parse as a shell line: $nx1"; fi
nx2="$( nextof "$T/m2.xml" run.sh )"
replay(){ python3 - "$BIN" "$T/$1" "$2" <<'PY'
import shlex, subprocess, sys
bin_, root, nx = sys.argv[1:4]
r = subprocess.run([bin_, root, "--no-cache"] + shlex.split(nx), stdin=subprocess.DEVNULL, capture_output=True, text=True, cwd=root)
sys.stdout.write(r.stdout); sys.exit(r.returncode)
PY
}
replay m2 "$nx2" > "$T/m2q.xml"; rc=$?
if [ -n "$nx2" ] && [ "$rc" -eq 0 ] && has "$T/m2q.xml" 'n="unused_one"' && ! grep -qE '<[a-z]+ [^>]*n="emit"' "$T/m2q.xml"; then
    ok "M1/M2 next= replays through shlex; it lists unused_one and not emit (the script's own top level calls emit)"
else no "M1/M2 next= replay rc=$rc: unused_one missing or emit listed as unreached ($nx2)"; fi
run m2 --for=run.sh --legend=full > "$T/m2f.xml"; run m2 --for=run.sh --legend=compact > "$T/m2c.xml"
if has "$T/m2f.xml" 'within 16 calls' && has "$T/m2f.xml" 'walk cap' && has "$T/m2c.xml" 'within 16 calls'; then ok "M2 the 16-call walk cap is said, full and compact"
else no "M2 the legend states reachability without its 16-call cap"; fi

run c --for=widget.h > "$T/h2.xml"
if has "$T/h2.xml" '<named-file p="src/widget.h"' && ! grep -qE '<named-file p="src/widget.h"[^>]* next=' "$T/h2.xml"; then ok "H2 a header's page carries no next="
else no "H2 widget.h: no page, or a next= that calls its prototypes unreached"; fi
run d7 --for=docs/guide.md > "$T/n3.xml"
if answered "$T/n3.xml" '<sigs' && ! has "$T/n3.xml" '<named-file p="docs/guide.md"' && ! has "$T/n3.xml" '<f p="docs/guide.md"'; then ok "N3 a path naming a prose file pages nothing"
else no "N3 docs/guide.md was paged or listed (or the run printed no answer)"; fi

# ── M3: one byte bound on the page ──────────────────────────────────────────────────────────────────────────────────────────────
pagebytes(){ python3 - "$1" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
a = s.find("<named-"); b = max(s.rfind("</named-"), s.rfind("<named-cut"))
e = s.find(">", b) + 1
print(e - a if a >= 0 and b >= 0 else 0)
PY
}
run m3 --for="pkg/big package" > "$T/m3a.xml"
run m3 --for="pkg/big pkg/big2" > "$T/m3b.xml"
pa="$( pagebytes "$T/m3a.xml" )"; pb="$( pagebytes "$T/m3b.xml" )"
if [ "$pa" -gt 0 ] && [ "$pa" -le 16640 ] && [ "$pb" -gt 0 ] && [ "$pb" -le 16640 ] && grep -qE '<named-dir p="pkg/big" files="7" shown="[0-9]+" capped="1" bytes_capped="1">' "$T/m3a.xml" \
   && has "$T/m3b.xml" '<named-cut total="2" shown="1" bytes_capped="1"/>'; then
    ok "M3 the page stops at its 16 KB bound at a file boundary and says so (one dir $pa B, two dirs $pb B)"
else no "M3 byte bound: one dir $pa B, two dirs $pb B, or no bytes_capped disclosure"; fi

# ── Y1..Y4: the second fix round (delta review X1..X4) ─────────────────────────────────────────────────────────────────────────
run y1 --for=app.js > "$T/y1.xml"
nxy1="$( nextof "$T/y1.xml" web/app.js )"
replay y1 "$nxy1" > "$T/y1q.xml"; rc=$?
if [ -n "$nxy1" ] && [ "$rc" -eq 0 ] && has "$T/y1q.xml" 'n="orphanMethod"' && has "$T/y1q.xml" 'n="deadFn"'; then
    ok "Y1 next= lists an uncalled METHOD (orphanMethod) beside the free functions it already listed"
else no "Y1 next= replay rc=$rc: orphanMethod (kind=method) missing from the file's unreached defs ($nxy1)"; fi
run y2 --for=src/utils > "$T/y2.xml"
run y2b --for=src/utils > "$T/y2b.xml"
if has "$T/y2.xml" '<f p="src/utils/" dir="1" files="1"/>' && has "$T/y2.xml" '<f p="pkg/x/src/utils/" dir="1" files="2"/>' \
   && python3 - "$T/y2.xml" <<'PY'
import sys
s = open(sys.argv[1]).read()
sys.exit(0 if s.find('p="src/utils/" dir="1"') < s.find('p="pkg/x/src/utils/" dir="1"') and 'p="pkg/y/src/utils.ts"' in s and "<named-file " not in s else 1)
PY
then ok "Y2 the dir rows count and name one directory each, the one written exactly first (src/utils/ 1, pkg/x/src/utils/ 2)"
else no "Y2 src/utils: a dir row names one directory with another's count, or the directory as written is not first"; fi
firstf="$( grep -o '<named-file p="[^"]*"' "$T/y2b.xml" | head -1 )"
if has "$T/y2b.xml" '<named-dir p="src/utils" files="3">' && [ "$firstf" = '<named-file p="src/utils/a.ts"' ]; then
    ok "Y2 a directory with no same-named file: the directory as written is paged first ($firstf)"
else no "Y2 src/utils (directories only): first page is $firstf, not src/utils/a.ts"; fi
run y3 --for=crate/src/mw > "$T/y3.xml"; run y3p --for=pkg/ware > "$T/y3p.xml"
f3="$( grep -o '<named-file p="[^"]*"' "$T/y3.xml" | head -1 )"; f3p="$( grep -o '<named-file p="[^"]*"' "$T/y3p.xml" | head -1 )"
if [ "$f3" = '<named-file p="crate/src/mw/mod.rs"' ] && [ "$f3p" = '<named-file p="pkg/ware/index.ts"' ] && has "$T/y3.xml" 'files="8" shown="6" capped="1"'; then
    ok "Y3 the module root (mod.rs, index.ts) is the directory's first page, not the last by path order"
else no "Y3 module root not first: $f3 / $f3p"; fi
run y4 --for="pkg/big dup.py" > "$T/y4.xml"
py4="$( pagebytes "$T/y4.xml" )"
if has "$T/y4.xml" 'bytes_capped="1"' && ! has "$T/y4.xml" '<named-files n="dup.py"' && has "$T/y4.xml" '<named-cut total="2" shown="1" bytes_capped="1"/>' && [ "$py4" -gt 0 ] && [ "$py4" -le 16640 ]; then
    ok "Y4 a listing after a full directory obeys the 16 KB bound and says so ($py4 B)"
else no "Y4 pkg/big dup.py: the listing was appended past the bound ($py4 B) or the cut is not disclosed"; fi

# ── M4: a minified file with no top-level row is not an empty page ──────────────────────────────────────────────────────────────
run m4 --for=mini.js > "$T/m4.xml"
if grep -qE '<named-file p="src/mini.js" lines="1" defs="0"[^>]*><top_cut top_lines="1" shown="0" rest="1-1"/></named-file>' "$T/m4.xml"; then
    ok "M4 mini.js: top_cut says its one line was not served"
else no "M4 mini.js: an empty page with no disclosure"; fi

# ── K3..K5, T1: the remaining caps and attributes ───────────────────────────────────────────────────────────────────────────────
run k3 --for=many_defs.py > "$T/k3.xml"
if has "$T/k3.xml" 'defs="41" shown="40" capped="1"'; then ok "K3 the def-row cap discloses (41 defs, 40 shown)"; else no "K3 def-row cap not disclosed"; fi
run k4 --for="pkg/seven package" > "$T/k4.xml"
if has "$T/k4.xml" '<named-dir p="pkg/seven" files="7" shown="6" capped="1">'; then ok "K4 the dir-file cap discloses (7 files, 6 paged)"; else no "K4 dir-file cap not disclosed"; fi
run k5 --for=dup.py > "$T/k5.xml"
if has "$T/k5.xml" '<named-files n="dup.py" total="9" shown="8" capped="1">'; then ok "K5 the list cap discloses (9 files, 8 listed)"; else no "K5 list cap not disclosed"; fi
run t1 --for=core.py > "$T/t1a.xml"; run t1 --for=pkg/core.py > "$T/t1b.xml"
if has "$T/t1a.xml" '<f p="tests/core.py" defs="1" tier="test"/>' && has "$T/t1b.xml" 'by_total="4"'; then ok "T1 tier=test on a listed file; by_total= beside by="
else no "T1 tier= or by_total= missing"; fi

# ── E: near misses that must NOT serve a page ───────────────────────────────────────────────────────────────────────────────
run py --for="where STATE used in sync_ledger.py is defined" > "$T/e1.xml"
if answered "$T/e1.xml" '<sigs' && ! has "$T/e1.xml" '<named-file'; then ok "E1 a file named as context carries no page"
else no "E1 a file named as context got a page (or the run printed no answer)"; fi
top3="$( python3 - "$T/e1.xml" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
print(" ".join(p for p, r in re.findall(r'<d [^>]*?p="([^"]*)"[^>]*? r="(\d+)"', s) if int(r) <= 3))
PY
)"
if has "$T/e1.xml" 'mention_anchored="' && case " $top3 " in *" tools/sync_ledger.py "*) true ;; *) false ;; esac; then
    ok "E3 the context basename still anchors its file (top 3: $top3)"
else no "E3 the context basename sync_ledger.py anchored nothing (top 3: $top3)"; fi
run c --for=widget.c > "$T/h1.xml"
if has "$T/h1.xml" '<hdr p="src/widget.h" of="src/widget.c"/>'; then ok "H1 a bare C basename gets its header partner row"
else no "H1 no <hdr> partner row for the bare basename widget.c"; fi
run py --for=run_all > "$T/e2.xml"
if answered "$T/e2.xml" '<sigs' && ! has "$T/e2.xml" '<named-file' && ! has "$T/e2.xml" 'file subject:'; then ok "E2 a stem that is a symbol's name stays a name"
else no "E2 run_all (a function's name) was read as a file stem (or the run printed no answer)"; fi

# ── F / R / K: honesty ─────────────────────────────────────────────────────────────────────────────────────────────────────
if grep -qE '<s t="fn" n="unused_helper" l="7" e="8" in="0">' "$T/b1.xml" && grep -qE '<s t="fn" n="emit" [^>]*by="[^"]*tools/test_sync_ledger.py' "$T/b1.xml" \
   && has "$T/b1.xml" 'NOT unused'; then
    ok "F1 in=0 on the uncalled def, by= names the caller's file, the clause hedges in=0"
else no "F1 in=/by= rows or the in=0 hedge missing"; fi
if ! has "$T/a1.xml" 'AKIA''ABCDEFGHIJKLMNOP' && has "$T/a1.xml" 'TOKEN='; then ok "R1 a secret in the top-level text is redacted"
else no "R1 the AKIA key reached the answer (or the line is missing)"; fi
run long --for=run-deploy.sh > "$T/k1.xml"
shown="$( python3 - "$T/k1.xml" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
print(sum(c.count("\n") + 1 for c in re.findall(r'<top l="\d+" e="\d+"><!\[CDATA\[(.*?)\]\]></top>', s, re.S)))
PY
)"
if [ "$shown" -le 40 ] && grep -qE '<top_cut top_lines="121" shown="40" rest="41-121"/>' "$T/k1.xml"; then ok "K1 the 40-line cap discloses top_cut (shown $shown)"
else no "K1 top-level cap: shown=$shown lines or no top_cut disclosure"; fi

run multi --for="alpha_tool.py beta_tool.py gamma_tool.py" > "$T/k2.xml"
if has "$T/k2.xml" '<named-cut total="3" shown="2"/>' && [ "$( grep -o '<named-file ' "$T/k2.xml" | wc -l | tr -d ' ' )" = 2 ]; then
    ok "K2 the anchor cap pages two files and discloses the third"
else no "K2 three named files: no named-cut disclosure or not two pages"; fi

# ── N: postures without the page ────────────────────────────────────────────────────────────────────────────────────────────
( cd "$T/py" && RIPWIRE_NO_FILE_PAGE=1 HOME="$H" TMPDIR="$T/" "$BIN" "$T/py" --no-cache --for=sync_ledger < /dev/null 2>/dev/null ) > "$T/n1.xml" || no "ripwire exited non-zero: RIPWIRE_NO_FILE_PAGE=1 --for=sync_ledger"
run py --for=sync_ledger --json > "$T/n2.json"
if answered "$T/n1.xml" '<sigs' && answered "$T/n2.json" '"' && ! has "$T/n1.xml" '<named-file' && ! has "$T/n2.json" 'named-file'; then ok "N1 no page with RIPWIRE_NO_FILE_PAGE=1 nor under --json"
else no "N1 a page rode under the kill switch or --json (or a run printed no answer)"; fi

# ── L: the clause defines what the page carries ─────────────────────────────────────────────────────────────────────────────
run py --for=sync_ledger --legend=full > "$T/l1.xml"
run long --for=run-deploy.sh --legend=full > "$T/l1k.xml"   # the full dialect on a cut page (top_cut) — each dialect, each element
run py --for=util.py --legend=full > "$T/l1c.xml"
run d5 --for=lib/a.c --legend=full > "$T/l1d5.xml"; run d6 --for=src/utils --legend=compact > "$T/l1d6.xml"
run m3 --for="pkg/big pkg/big2" --legend=full > "$T/l1m3.xml"; run m4 --for=mini.js --legend=full > "$T/l1m4.xml"
run y2 --for=src/utils --legend=full > "$T/l1y2.xml"
for f in "$T/b1.xml" "$T/l1.xml" "$T/c1.xml" "$T/d1.xml" "$T/k1.xml" "$T/k2.xml" "$T/l1k.xml" "$T/l1c.xml" "$T/l1d5.xml" "$T/l1d6.xml" "$T/l1m3.xml" "$T/l1m4.xml" "$T/l1y2.xml" "$T/m3a.xml"; do
    if python3 - "$f" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r"(; named-file p= .*?(?:capped=1 cut|the list was cut))", s, re.S)
if not m: print("    no file-page clause in", sys.argv[1]); sys.exit(1)
clause = m.group(1)
a, b = s.find("<named-"), s.rfind("</named-")
if a < 0 or b < 0: print("    no page in", sys.argv[1]); sys.exit(1)
page = re.sub(r"<!\[CDATA\[.*?\]\]>", "", s[a:b], flags=re.S)
miss = set()
for el in re.findall(r"<(named-file|named-files|named-dir|named-cut|top_cut|top|s|f)\b([^>]*)>", page):
    for a in re.findall(r" ([a-z_]+)=\"", el[1]):
        if not re.search(r"(?<![a-z_])" + a + r"=", clause): miss.add(el[0] + "." + a)
if miss: print("    undefined:", sorted(miss)); sys.exit(1)
PY
    then ok "L1 the clause defines every page attribute ($(basename "$f"))"
    else no "L1 the clause misses a page attribute ($(basename "$f"))"; fi
done

# ── X: determinism, well-formedness, no "--" in the legend ─────────────────────────────────────────────────────────────────
run bash --for=document-remind > "$T/x1.xml"
if cmp -s "$T/a1.xml" "$T/x1.xml"; then ok "X1 deterministic"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    bad=0
    for f in "$T"/a1.xml "$T"/b1.xml "$T"/c1.xml "$T"/d1.xml "$T"/k1.xml "$T"/l1.xml; do xmllint --noout "$f" 2>/dev/null || { bad=1; echo "    not well-formed: $f"; }; done
    if [ "$bad" -eq 0 ]; then ok "X2 xmllint well-formed"; else no "X2 an answer is not well-formed"; fi
else echo "  SKIP  X2 xmllint not installed"; fi
if python3 - "$T/l1.xml" "$T/b1.xml" <<'PY'
import re, sys
for f in sys.argv[1:]:
    for c in re.findall(r"<!--(.*?)-->", open(f).read(), re.S):
        if "--" in c: sys.exit(1)
PY
then ok "X3 no '--' inside a legend comment"; else no "X3 a legend comment holds '--'"; fi

[ "$fail" -eq 0 ] && echo "forfileanchorcheck: PASS" || echo "forfileanchorcheck: FAIL"
exit "$fail"
