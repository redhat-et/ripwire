#!/usr/bin/env bash
# editroundtripcheck.sh — E1 (terminality round A, 2026-09-05, lane E): the edit path is BYTE-EXACT end to
# end, or it can never be terminal.
#
# THE CLAIM. An agent that fetches a body with --expand (or the MCP fetch_body twin), pastes it back
# through --replace-symbol-body / replace_symbol_body, and stops — must leave `git diff --exit-code` clean,
# in EVERY language the index serves, for bodies carrying XML-hostile bytes (< & " ' and a tab), a CDATA
# terminator (]]>), CRLF line endings, and a credential-shaped literal. Where the served text is NOT the
# bytes on disk, the document must SAY so on the element (scrubbed="1", redacted="1"), and the write verb
# must refuse to write a redaction marker into source.
#
# THE SEAM RULES (measured on the edit suite's baseline, bench/agentloop/run_editsuite.py: 12/12 ripwire
# windows terminal, 1/12 tasks byte-exact). Every shell channel an agent reaches for to hand the verb a
# payload — a heredoc, echo, an editor — appends a newline the definition span never contained, so the
# most natural replace lands one blank line too many, and an insert of a bare definition lands GLUED to its
# neighbour because the verb guaranteed separate LINES, not the file's definition separator. The receipt
# said applied; the agent believed it; the bytes were wrong. So:
#   * ReplaceBody / InsertAfter: ONE trailing newline on the payload is folded into the newline already at
#     the right seam, disclosed as "trailing_newline_folded":true (never removed otherwise; an agent's
#     deliberate extra blank line survives).
#   * InsertBefore / InsertAfter: the inserted block is separated from the anchor by the SAME blank-line
#     run the file uses at that seam (the run before the anchor's first byte / after its last), disclosed
#     as "separator_padded":N (newlines added; 0 when the payload already carried them). Padding only ever
#     ADDS newlines.
# Same engine (mcpedit::applyEdit) on all three surfaces: CLI verbs, MCP twins, --edit-plan.
#
# The corpus is GENERATED here (a CRLF file and a NUL-free credential literal are not things to commit),
# in a throwaway git repo; the verbs WRITE and are never pointed at the checkout that runs the gate.
#
# Usage: bash test/editroundtripcheck.sh        (RIPWIRE_BIN=… for another binary)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "editroundtripcheck: BIN=$BIN"

# ── the corpus: one file per served language, each target body carrying < & " ' and a TAB ────────────
C="$TMP/corpus"; mkdir -p "$C"
python3 - "$C" <<'PY'
import os, sys
c = sys.argv[1]
T = "\t"
files = {
 "probe.c":     ("probe_c",     'const char* probe_c( int n )\n{\n%sif( n < 3 && n > 1 ) { return "<a> & \'b\'"; }\n    return "";\n}\n\nint other_c( void ) { return 1; }\n' % T),
 "probe.cpp":   ("probe_cpp",   'const char* probe_cpp( int n )\n{\n%sif( n < 3 && n > 1 ) { return "<a> & \'b\'"; }\n    return "";\n}\n\nint other_cpp() { return 1; }\n' % T),
 # ObjC: an int-returning function — a `const char*`-returning free function in a .m file is NOT indexed by
 # the objc grammar path (found by this gate 2026-09-05, recorded in lane E's report, a language-lane defect)
 "probe.m":     ("probe_m",     '#import <Foundation/Foundation.h>\n\nint probe_m( int n )\n{\n%sconst char* s = "<a> & \'b\'";\n    return ( n < 3 && n > 1 && s[0] ) ? 1 : 0;\n}\n\nint other_m( void ) { return 1; }\n' % T),
 "probe.py":    ("probe_py",    'def probe_py(n):\n    if n < 3 and n > 1:\n%sreturn "<a> & \'b\'"\n    return ""\n\n\ndef other_py():\n    return 1\n' % (T + T)),
 "probe.js":    ("probe_js",    'function probe_js(n) {\n%sif (n < 3 && n > 1) { return "<a> & \'b\'"; }\n    return "";\n}\n\nfunction other_js() { return 1; }\n' % T),
 "probe.ts":    ("probe_ts",    'export function probe_ts(n: number): string {\n%sif (n < 3 && n > 1) { return "<a> & \'b\'"; }\n    return "";\n}\n\nexport function other_ts(): number { return 1; }\n' % T),
 "probe.go":    ("probe_go",    'package probe\n\nfunc probe_go(n int) string {\n%sif n < 3 && n > 1 {\n\t\treturn "<a> & \'b\'"\n\t}\n\treturn ""\n}\n\nfunc other_go() int { return 1 }\n' % T),
 "probe.rs":    ("probe_rs",    'pub fn probe_rs(n: i32) -> &\'static str {\n%sif n < 3 && n > 1 { return "<a> & \'b\'"; }\n    ""\n}\n\npub fn other_rs() -> i32 { 1 }\n' % T),
 "Probe.java":  ("probe_java",  'public class Probe {\n    static String probe_java(int n) {\n%sif (n < 3 && n > 1) { return "<a> & \'b\'"; }\n        return "";\n    }\n\n    static int other_java() { return 1; }\n}\n' % (T + T)),
 "probe.rb":    ("probe_rb",    'def probe_rb(n)\n%sreturn "<a> & \'b\'" if n < 3 && n > 1\n  ""\nend\n\ndef other_rb\n  1\nend\n' % T),
 "probe.swift": ("probe_swift", 'func probe_swift(_ n: Int) -> String {\n%sif n < 3 && n > 1 { return "<a> & \'b\'" }\n    return ""\n}\n\nfunc other_swift() -> Int { return 1 }\n' % T),
 "Probe.cs":    ("probe_cs",    'public static class Probe {\n    public static string probe_cs(int n) {\n%sif (n < 3 && n > 1) { return "<a> & \'b\'"; }\n        return "";\n    }\n\n    public static int other_cs() { return 1; }\n}\n' % (T + T)),
 "probe.sh":    ("probe_sh",    'probe_sh() {\n%sif [ "$1" -lt 3 ] && [ "$1" -gt 1 ]; then printf "%%s" "<a> & \'b\'"; fi\n}\n\nother_sh() { return 1; }\n' % T),
 # a body containing the CDATA terminator — served split (]]]]><![CDATA[>), and that split is disclosed
 "cdata.cpp":   ("pick",        '#include <vector>\n\nint pick( const std::vector<std::vector<int>>& a, int i )\n{\n    return a[0][a[1][i]]>0 ? 1 : 0;\n}\n\nint other_pick() { return 2; }\n'),
 # a credential-shaped literal — redacted by default, and the redaction must be visible on the element
 "cred.py":     ("connect",     'import os\n\n\ndef connect():\n    key = "AKIAIOSFODNN7EXAMPLEX"\n    return os.environ.get("X", key)\n\n\ndef other_cred():\n    return 1\n'),
 # the seam fixtures: C++ (one blank line between definitions) and Python (two)
 "seam.cpp":    ("seam_a",      'int seam_a( int x )\n{\n    return x + 1;\n}\n\nint seam_b( int x )\n{\n    return x + 2;\n}\n\nint seam_c( int x )\n{\n    return x + 3;\n}\n'),
 "seam.py":     ("seam_a",      'def seam_a(x):\n    return x + 1\n\n\ndef seam_b(x):\n    return x + 2\n\n\ndef seam_c(x):\n    return x + 3\n'),
}
for name, (sym, text) in files.items():
    open(os.path.join(c, name), "w", newline="").write(text)
# CRLF: the whole file with \r\n line endings
open(os.path.join(c, "crlf.py"), "w", newline="").write('def probe_crlf(n):\r\n    if n < 3:\r\n        return "<a> & b"\r\n    return ""\r\n\r\n\r\ndef other_crlf():\r\n    return 1\r\n')
PY
( cd "$C" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1
fresh(){ rm -rf "$TMP/w"; git clone --local -q "$C" "$TMP/w" 2>/dev/null; }
clean(){ ( cd "$TMP/w" && git diff --exit-code --quiet -- . ) ; }   # 0 = byte-identical to the commit

# the body two ways: RAW = the text between <![CDATA[ and ]]></b> exactly as a copy-paste agent takes it;
# DECODED = the faithful CDATA decoding (the ]]]]><![CDATA[> split rejoined to ]]>). Not an XML parser on
# purpose: XML line-end normalisation would turn every CRLF into LF and hide the document's own bytes.
extract(){ # $1 doc-file $2 sym → decoded body to $3, raw body to $4, attrs of <b> to $5
python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import re, sys
doc = open(sys.argv[1], encoding="utf-8", newline="").read()
sym = sys.argv[2]
m = re.search(r'<b ([^>]*\bn="%s"[^>]*)><!\[CDATA\[(.*?)\]\]></b>' % re.escape(sym), doc, re.S)
assert m, "no <b n=%r> in the document" % sym
raw = m.group(2)
open(sys.argv[4], "w", newline="").write(raw)
open(sys.argv[3], "w", newline="").write(raw.replace("]]]]><![CDATA[>", "]]>"))
open(sys.argv[5], "w").write(" ".join('%s=%s' % (k, v) for k, v in re.findall(r'([\w-]+)="([^"]*)"', m.group(1))))
PY
}

# ── ARM A — every language: --expand body (CDATA-decoded) → --replace-symbol-body → git diff clean ──────
langs="probe.c:probe_c probe.cpp:probe_cpp probe.m:probe_m probe.py:probe_py probe.js:probe_js probe.ts:probe_ts probe.go:probe_go probe.rs:probe_rs Probe.java:probe_java probe.rb:probe_rb probe.swift:probe_swift Probe.cs:probe_cs probe.sh:probe_sh crlf.py:probe_crlf cdata.cpp:pick"
nlang=0; nclean=0
for pair in $langs; do
    f="${pair%%:*}"; s="${pair##*:}"; nlang=$(( nlang + 1 ))
    fresh
    ( cd "$TMP/w" && "$BIN" . --expand="$f:$s" --top-k=0 --no-cache ) >"$TMP/doc.xml" 2>"$TMP/doc.err"
    if ! extract "$TMP/doc.xml" "$s" "$TMP/body" "$TMP/raw" "$TMP/attrs" 2>"$TMP/x.err"; then
        no "(A) $f: could not extract <b n=\"$s\"> from --expand ($( head -c 200 "$TMP/x.err" ))"; continue
    fi
    ( cd "$TMP/w" && "$BIN" . --replace-symbol-body="$s" --edit-target-file="$f" --edit-payload="$TMP/body" ) >"$TMP/r.json" 2>"$TMP/r.err"
    if clean; then
        nclean=$(( nclean + 1 ))
    else
        no "(A) $f:$s — --expand body pasted back through --replace-symbol-body is NOT byte-identical:"; ( cd "$TMP/w" && git diff | sed -n '5,14p' | sed 's/^/        /' )
    fi
    # (D) the raw-text paste equals the decoded body EXCEPT where the element says the CDATA is not the bytes
    if cmp -s "$TMP/body" "$TMP/raw"; then
        grep -q 'scrubbed=1' "$TMP/attrs" && no "(D) $f: raw == decoded but the element claims scrubbed=\"1\""
    else
        grep -q 'scrubbed=1' "$TMP/attrs" \
            && ok "(D) $f: the raw CDATA text differs from the bytes (]]> split) and the element says scrubbed=\"1\"" \
            || no "(D) $f: the raw CDATA text differs from the bytes and NOTHING on the element says so"
    fi
    grep -q 'probe_crlf' "$TMP/raw" && { grep -q $'\r' "$TMP/raw" && ok "(A) crlf.py: the served CDATA keeps its CRLF endings" || no "(A) crlf.py: the served CDATA lost its CRLF endings"; }
done
[ "$nclean" = "$nlang" ] && ok "(A) $nclean/$nlang languages round-trip byte-exact through --expand → --replace-symbol-body (C, C++, ObjC, Python, JS, TS, Go, Rust, Java, Ruby, Swift, C#, Bash, CRLF, ]]>)" \
                        || no "(A) only $nclean/$nlang languages round-trip byte-exact"
command -v xmllint >/dev/null 2>&1 && { fresh; ( cd "$TMP/w" && "$BIN" . --expand=cdata.cpp:pick --top-k=0 --no-cache 2>/dev/null ) | xmllint --noout - 2>/dev/null && ok "(A) the ]]>-split document is well-formed XML" || no "(A) the ]]>-split document is not well-formed"; }

# ── ARM B — the MCP twins: fetch_body → replace_symbol_body, byte-exact ─────────────────────────────────
mcp(){ # $1 = the tools/call JSON (params) ; prints the result text or __ERROR__:msg
python3 - "$BIN" "$TMP/w" "$1" <<'PY'
import json, subprocess, sys
binp, cwd, params = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
req = "\n".join([json.dumps({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}),
                 json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":params})]) + "\n"
out = subprocess.run([binp, "--mcp"], input=req, capture_output=True, text=True, cwd=cwd).stdout
last = [l for l in out.splitlines() if l.strip()][-1]
r = json.loads(last)
if "error" in r: print("__ERROR__:" + r["error"].get("message","")); sys.exit(0)
print(r["result"]["content"][0]["text"])
PY
}
for pair in probe.py:probe_py probe.cpp:probe_cpp cdata.cpp:pick crlf.py:probe_crlf; do
    f="${pair%%:*}"; s="${pair##*:}"; fresh
    FB="$( mcp '{"name":"fetch_body","arguments":{"path":".","handle":"'"$f:$s"'"}}' )"
    BODY_JSON="$( printf '%s' "$FB" | python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin)["body"]))' 2>/dev/null )"
    [ -n "$BODY_JSON" ] || { no "(B) $f: fetch_body returned no body ($( printf '%s' "$FB" | head -c 160 ))"; continue; }
    RS="$( mcp '{"name":"replace_symbol_body","arguments":{"path":".","symbol":"'"$s"'","file":"'"$f"'","new_body":'"$BODY_JSON"'}}' )"
    case "$RS" in __ERROR__*) no "(B) $f: replace_symbol_body refused the fetched body: $RS";; esac
    clean && ok "(B) $f:$s — MCP fetch_body → replace_symbol_body is byte-exact" || { no "(B) $f:$s — the MCP round trip is not byte-identical"; ( cd "$TMP/w" && git diff | sed -n '5,12p' ); }
done

# ── ARM C — the heredoc payload (one trailing newline) folds into the seam, disclosed ───────────────────
fresh; extract <( cd "$TMP/w" && "$BIN" . --expand=probe.py:probe_py --top-k=0 --no-cache 2>/dev/null ) probe_py "$TMP/body" "$TMP/raw" "$TMP/attrs" 2>/dev/null
{ cat "$TMP/body"; printf '\n'; } > "$TMP/heredoc"     # exactly what `cat > f <<'EOF' … EOF` produces
( cd "$TMP/w" && "$BIN" . --replace-symbol-body=probe_py --edit-target-file=probe.py --edit-payload="$TMP/heredoc" ) >"$TMP/c.json" 2>"$TMP/c.err"
clean && ok "(C) a heredoc payload (body + one trailing newline) replaces byte-exact: the newline folds into the seam" \
      || { no "(C) a heredoc payload leaves one extra blank line after the definition (git diff not clean)"; ( cd "$TMP/w" && git diff | sed -n '5,12p' | sed 's/^/        /' ); }
grep -q '"trailing_newline_folded":true' "$TMP/c.json" && ok "(C) the receipt discloses trailing_newline_folded:true" || no "(C) the receipt does not disclose the fold ($( head -c 200 "$TMP/c.json" ))"
fresh
( cd "$TMP/w" && "$BIN" . --replace-symbol-body=probe_py --edit-target-file=probe.py --edit-payload="$TMP/body" ) >"$TMP/c2.json" 2>/dev/null
grep -q '"trailing_newline_folded":false' "$TMP/c2.json" && ok "(C) an exact payload reports trailing_newline_folded:false" || no "(C) an exact payload does not report trailing_newline_folded:false"
# a DELIBERATE blank line (two trailing newlines) survives: one folds, one stays
fresh; { cat "$TMP/body"; printf '\n\n'; } > "$TMP/two"
( cd "$TMP/w" && "$BIN" . --replace-symbol-body=probe_py --edit-target-file=probe.py --edit-payload="$TMP/two" ) >/dev/null 2>&1
python3 - "$TMP/w/probe.py" <<'PY' && ok "(C) two trailing newlines: one folds, the deliberate blank line survives" || no "(C) two trailing newlines did not leave exactly one extra blank line"
import sys; t = open(sys.argv[1]).read(); sys.exit(0 if '    return ""\n\n\n\ndef other_py' in t and '    return ""\n\n\n\n\ndef other_py' not in t else 1)
PY
# MCP twin: new_body ending in "\n"
fresh; BODY_NL="$( python3 -c 'import sys,json; print(json.dumps(open(sys.argv[1]).read() + "\n"))' "$TMP/body" )"
RS="$( mcp '{"name":"replace_symbol_body","arguments":{"path":".","symbol":"probe_py","file":"probe.py","new_body":'"$BODY_NL"'}}' )"
clean && printf '%s' "$RS" | grep -q '"trailing_newline_folded":true' && ok "(C) MCP replace_symbol_body folds a trailing newline the same way and says so" || no "(C) the MCP twin does not fold/disclose ($( printf '%s' "$RS" | head -c 160 ))"

# ── ARM G — insert seams: the block is separated by the file's OWN definition separator ────────────────
printf 'int seam_new( int x )\n{\n    return x + 9;\n}\n' > "$TMP/new.cpp"          # heredoc-shaped: trailing newline, no blank lines
printf 'def seam_new(x):\n    return x + 9\n' > "$TMP/new.py"
expect_cpp_after='int seam_a( int x )
{
    return x + 1;
}

int seam_new( int x )
{
    return x + 9;
}

int seam_b( int x )'
expect_py_before='def seam_a(x):
    return x + 1


def seam_new(x):
    return x + 9


def seam_b(x):'
fresh
( cd "$TMP/w" && "$BIN" . --insert-after-symbol=seam_a --edit-target-file=seam.cpp --edit-payload="$TMP/new.cpp" ) >"$TMP/g1.json" 2>/dev/null
[ "$( head -11 "$TMP/w/seam.cpp" )" = "$expect_cpp_after" ] && ok "(G) --insert-after-symbol keeps ONE blank line each side in a one-blank-line C++ file" \
    || { no "(G) --insert-after-symbol: the inserted definition is not separated like its neighbours:"; head -12 "$TMP/w/seam.cpp" | sed 's/^/        /'; }
grep -q '"separator_padded":' "$TMP/g1.json" && ok "(G) the receipt discloses separator_padded" || no "(G) the receipt does not disclose separator_padded"
fresh
( cd "$TMP/w" && "$BIN" . --insert-before-symbol=seam_b --edit-target-file=seam.py --edit-payload="$TMP/new.py" ) >"$TMP/g2.json" 2>/dev/null
[ "$( head -9 "$TMP/w/seam.py" )" = "$expect_py_before" ] && ok "(G) --insert-before-symbol keeps TWO blank lines each side in a two-blank-line Python file" \
    || { no "(G) --insert-before-symbol: the inserted definition is not separated like its neighbours:"; head -10 "$TMP/w/seam.py" | sed 's/^/        /'; }
# a payload that ALREADY carries the separator is not padded twice
fresh; printf 'def seam_new(x):\n    return x + 9\n\n\n' > "$TMP/new2.py"
( cd "$TMP/w" && "$BIN" . --insert-before-symbol=seam_b --edit-target-file=seam.py --edit-payload="$TMP/new2.py" ) >"$TMP/g3.json" 2>/dev/null
[ "$( head -9 "$TMP/w/seam.py" )" = "$expect_py_before" ] && grep -q '"separator_padded":0' "$TMP/g3.json" \
    && ok "(G) a payload that already carries the separator is not padded (separator_padded:0)" \
    || no "(G) a payload carrying its own separator was padded again or not disclosed as 0"
# MCP twin
fresh; RS="$( mcp '{"name":"insert_after_symbol","arguments":{"path":".","symbol":"seam_a","file":"seam.cpp","text":"int seam_new( int x )\n{\n    return x + 9;\n}\n"}}' )"
[ "$( head -11 "$TMP/w/seam.cpp" )" = "$expect_cpp_after" ] && ok "(G) MCP insert_after_symbol lands the same bytes" || no "(G) MCP insert_after_symbol lands different bytes ($( printf '%s' "$RS" | head -c 120 ))"

# ── ARM H — --edit-plan goes through the same seam rules ───────────────────────────────────────────────
fresh; mkdir -p "$TMP/w/plans"; cp "$TMP/new.cpp" "$TMP/w/plans/1.txt"; cp "$TMP/new.py" "$TMP/w/plans/2.txt"; { cat "$TMP/body"; printf '\n'; } > "$TMP/w/plans/3.txt"
cat > "$TMP/w/plans/p.json" <<'EOF'
{"version":1,"edits":[{"op":"insert_after_symbol","target":"seam_a","file":"seam.cpp","payload":"1.txt"},
                      {"op":"insert_before_symbol","target":"seam_b","file":"seam.py","payload":"2.txt"},
                      {"op":"replace_symbol_body","target":"probe_py","file":"probe.py","payload":"3.txt"}]}
EOF
( cd "$TMP/w" && "$BIN" . --edit-plan=plans/p.json --apply ) >"$TMP/h.json" 2>"$TMP/h.err"
[ "$( head -11 "$TMP/w/seam.cpp" )" = "$expect_cpp_after" ] && [ "$( head -9 "$TMP/w/seam.py" )" = "$expect_py_before" ] \
    && ( cd "$TMP/w" && git diff --exit-code --quiet -- probe.py ) \
    && ok "(H) --edit-plan --apply: the same three seam rules on both inserts and the heredoc replace" \
    || { no "(H) --edit-plan --apply lands different seam bytes than the single verbs ($( head -c 200 "$TMP/h.err" ))"; }

# ── ARM F — redaction is DISCLOSED on the element, and a redaction marker is never written into source ─
fresh
( cd "$TMP/w" && "$BIN" . --expand=cred.py:connect --top-k=0 --no-cache ) >"$TMP/red.xml" 2>/dev/null
extract "$TMP/red.xml" connect "$TMP/redbody" "$TMP/raw" "$TMP/attrs" 2>/dev/null
grep -q 'REDACTED' "$TMP/redbody" || no "(F) fixture degenerate: the credential literal was not redacted by default"
grep -q 'redacted=1' "$TMP/attrs" && ok "(F) a body rewritten by redaction carries redacted=\"1\" on its <b>" \
    || no "(F) the served body was rewritten by redaction and the element does not say so (attrs: $( cat "$TMP/attrs" ))"
( cd "$TMP/w" && "$BIN" . --replace-symbol-body=connect --edit-target-file=cred.py --edit-payload="$TMP/redbody" ) >"$TMP/f.json" 2>"$TMP/f.err"; rc=$?
{ [ "$rc" != 0 ] && clean && grep -q -- '--no-redact' "$TMP/f.err"; } \
    && ok "(F) pasting a redacted body back REFUSES (file byte-identical) and names --no-redact" \
    || no "(F) a redaction marker was written into source, or the refusal does not name --no-redact (rc=$rc: $( head -c 160 "$TMP/f.err" ))"
fresh
( cd "$TMP/w" && "$BIN" . --expand=cred.py:connect --top-k=0 --no-cache --no-redact ) >"$TMP/nored.xml" 2>/dev/null
extract "$TMP/nored.xml" connect "$TMP/body" "$TMP/raw" "$TMP/attrs" 2>/dev/null
( cd "$TMP/w" && "$BIN" . --replace-symbol-body=connect --edit-target-file=cred.py --edit-payload="$TMP/body" ) >/dev/null 2>&1
clean && ! grep -q 'redacted=1' "$TMP/attrs" && ok "(F) --no-redact serves the bytes (no redacted= on the element) and they round-trip byte-exact" || no "(F) the --no-redact body does not round-trip"

[ "$fail" = 0 ] && echo "editroundtripcheck: ALL PASS" || echo "editroundtripcheck: FAILURES ABOVE"
exit "$fail"
