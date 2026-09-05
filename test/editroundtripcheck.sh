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
 # R1 (V3, wave-2 verifier) — source that LEGITIMATELY spells the marker: the TRUE NEGATIVE the true
 # positive above must not be bought with. legend_doc carries the bare "[REDACTED:" substring the way a
 # legend documents it; legend_real quotes the FULL artefact a redacted serve emits, verbatim (U+2026 +
 # one of redact.h's own marker strings); legend_cred carries that artefact AND a real credential, so a
 # served copy of it has exactly one marker MORE than the bytes on disk. Nothing here is itself a
 # credential shape: "AKIA" followed by U+2026 does not match AKIA[0-9A-Z]{16}, and no line carries the
 # 32-char keyword-gated run the generic rule needs.
 "legend.py":   ("legend_doc",  'def legend_doc():\n    # a legend line: a credential shape is rewritten to a [REDACTED:kind] marker\n    return 0\n\n\ndef legend_real():\n    # the emitted artefact, verbatim: AKIA…[REDACTED:aws-key]\n    return 1\n\n\ndef legend_cred():\n    # AKIA…[REDACTED:aws-key] is what the tool writes here\n    k = "AKIAIOSFODNN7EXAMPLEX"\n    return k\n\n\ndef other_legend():\n    return 2\n'),
 # the seam fixtures: C++ (one blank line between definitions) and Python (two)
 "seam.cpp":    ("seam_a",      'int seam_a( int x )\n{\n    return x + 1;\n}\n\nint seam_b( int x )\n{\n    return x + 2;\n}\n\nint seam_c( int x )\n{\n    return x + 3;\n}\n'),
 "seam.py":     ("seam_a",      'def seam_a(x):\n    return x + 1\n\n\ndef seam_b(x):\n    return x + 2\n\n\ndef seam_c(x):\n    return x + 3\n'),
}
for name, (sym, text) in files.items():
    open(os.path.join(c, name), "w", newline="", encoding="utf-8").write(text)
# CRLF: the whole file with \r\n line endings
open(os.path.join(c, "crlf.py"), "w", newline="", encoding="utf-8").write('def probe_crlf(n):\r\n    if n < 3:\r\n        return "<a> & b"\r\n    return ""\r\n\r\n\r\ndef other_crlf():\r\n    return 1\r\n')
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
open(sys.argv[4], "w", newline="", encoding="utf-8").write(raw)
open(sys.argv[3], "w", newline="", encoding="utf-8").write(raw.replace("]]]]><![CDATA[>", "]]>"))
open(sys.argv[5], "w", encoding="utf-8").write(" ".join('%s=%s' % (k, v) for k, v in re.findall(r'([\w-]+)="([^"]*)"', m.group(1))))
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

# ── ARM F2 — the TRUE NEGATIVE: source that legitimately spells the marker still round-trips ───────────
# R1, wave-2 verifier, 2026-09-05. ARM F above only ever exercised the true positive, and the guard it
# passed was a bare "[REDACTED:" substring scan of the payload. That scan cannot tell "this payload came
# from a REDACTED serve" from "this payload's own source spells the marker", so every symbol whose real
# bytes carry the text became permanently unwritable on EVERY write surface — five files under ripwire's
# own src/ among them — while the refusal asserted the body "was served REDACTED" (it was not: the element
# said scrubbed="1" with no redacted="1") and named --no-redact, which returns byte-identical bytes and is
# refused identically. A closed loop built on a false claim, which is the exact anti-terminality this
# round removes. The honest predicate compares against the bytes ALREADY THERE: a redaction only ever ADDS
# markers, so a payload is refused only when it carries MORE than the span it would replace already does.
# This arm asserts all three halves — bare substring, full artefact, and the count.
for s in legend_doc legend_real; do
    fresh
    ( cd "$TMP/w" && "$BIN" . --expand="legend.py:$s" --top-k=0 --no-cache ) >"$TMP/f2.xml" 2>/dev/null
    if ! extract "$TMP/f2.xml" "$s" "$TMP/f2body" "$TMP/raw" "$TMP/attrs" 2>"$TMP/x.err"; then
        no "(F2) could not extract <b n=\"$s\"> from --expand ($( head -c 160 "$TMP/x.err" ))"; continue
    fi
    grep -q 'redacted=1' "$TMP/attrs" && no "(F2) $s: nothing in this body is a credential, yet the element claims redacted=\"1\" (attrs: $( cat "$TMP/attrs" ))"
    # (F2a) the CLI write verb
    ( cd "$TMP/w" && "$BIN" . --replace-symbol-body="$s" --edit-target-file=legend.py --edit-payload="$TMP/f2body" ) >"$TMP/f2.json" 2>"$TMP/f2.err"; rc=$?
    { [ "$rc" = 0 ] && clean; } \
        && ok "(F2) legend.py:$s — source that spells the marker round-trips through --replace-symbol-body (git diff clean)" \
        || no "(F2) legend.py:$s — a body whose REAL source carries the marker text cannot be written back (rc=$rc: $( head -c 200 "$TMP/f2.err" ))"
    # (F2b) the --dry-run preview
    fresh
    ( cd "$TMP/w" && "$BIN" . --edit-check="$s" --edit-target-file=legend.py --edit-payload="$TMP/f2body" --dry-run ) >"$TMP/f2p.xml" 2>"$TMP/f2p.err"; rc=$?
    { [ "$rc" = 0 ] && grep -q '<overwrite ' "$TMP/f2p.xml"; } \
        && ok "(F2) legend.py:$s — the --dry-run preview accepts the same payload and shows the span" \
        || no "(F2) legend.py:$s — the preview refuses a payload the source itself carries (rc=$rc: $( head -c 200 "$TMP/f2p.err" ))"
    # (F2c) --edit-plan --apply
    fresh; mkdir -p "$TMP/w/plans"; cp "$TMP/f2body" "$TMP/w/plans/f2.txt"
    printf '{"version":1,"edits":[{"op":"replace_symbol_body","target":"%s","file":"legend.py","payload":"f2.txt"}]}\n' "$s" > "$TMP/w/plans/f2.json"
    ( cd "$TMP/w" && "$BIN" . --edit-plan=plans/f2.json --apply ) >"$TMP/f2pl.json" 2>"$TMP/f2pl.err"; rc=$?
    { [ "$rc" = 0 ] && ( cd "$TMP/w" && git diff --exit-code --quiet -- legend.py ); } \
        && ok "(F2) legend.py:$s — --edit-plan --apply accepts it too (git diff clean)" \
        || no "(F2) legend.py:$s — --edit-plan refuses a payload the source itself carries (rc=$rc: $( head -c 200 "$TMP/f2pl.err" ))"
    # (F2d) the MCP twins
    fresh
    FB="$( mcp '{"name":"fetch_body","arguments":{"path":".","handle":"legend.py:'"$s"'"}}' )"
    BODY_JSON="$( printf '%s' "$FB" | python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin)["body"]))' 2>/dev/null )"
    if [ -n "$BODY_JSON" ]; then
        RS="$( mcp '{"name":"replace_symbol_body","arguments":{"path":".","symbol":"'"$s"'","file":"legend.py","new_body":'"$BODY_JSON"'}}' )"
        case "$RS" in
            __ERROR__*) no "(F2) legend.py:$s — MCP replace_symbol_body refused the body it just served: $( printf '%s' "$RS" | head -c 200 )";;
            *) clean && ok "(F2) legend.py:$s — MCP fetch_body → replace_symbol_body is byte-exact" || no "(F2) legend.py:$s — the MCP round trip is not byte-identical";;
        esac
    else
        no "(F2) legend.py:$s — fetch_body returned no body ($( printf '%s' "$FB" | head -c 160 ))"
    fi
done
# (F2e) the COUNT, not mere presence: legend_cred's real source already carries ONE artefact, and a
# redacted serve of it carries TWO. The extra one is the credential, and it must still be refused — on
# every surface — with a message that names --no-redact and leaves the file byte-identical.
fresh
( cd "$TMP/w" && "$BIN" . --expand=legend.py:legend_cred --top-k=0 --no-cache ) >"$TMP/f2c.xml" 2>/dev/null
extract "$TMP/f2c.xml" legend_cred "$TMP/f2cbody" "$TMP/raw" "$TMP/attrs" 2>/dev/null
grep -q 'redacted=1' "$TMP/attrs" || no "(F2) fixture degenerate: legend_cred's credential was not redacted (attrs: $( cat "$TMP/attrs" ))"
( cd "$TMP/w" && "$BIN" . --replace-symbol-body=legend_cred --edit-target-file=legend.py --edit-payload="$TMP/f2cbody" ) >"$TMP/f2c.json" 2>"$TMP/f2c.err"; rc=$?
{ [ "$rc" != 0 ] && clean && grep -q -- '--no-redact' "$TMP/f2c.err"; } \
    && ok "(F2) a body that ALREADY carried one marker is still refused when the serve added a second (count, not presence)" \
    || no "(F2) a redacted serve of a body that already carried a marker was written into source (rc=$rc: $( head -c 200 "$TMP/f2c.err" ))"
fresh
( cd "$TMP/w" && "$BIN" . --edit-check=legend_cred --edit-target-file=legend.py --edit-payload="$TMP/f2cbody" --dry-run ) >"$TMP/f2cp.xml" 2>"$TMP/f2cp.err"; rc=$?
{ [ "$rc" != 0 ] && grep -q -- '--no-redact' "$TMP/f2cp.err"; } \
    && ok "(F2) the --dry-run preview refuses the added marker in the same words" \
    || no "(F2) the preview does not refuse a payload carrying an added redaction marker (rc=$rc: $( head -c 200 "$TMP/f2cp.err" ))"
fresh; mkdir -p "$TMP/w/plans"; cp "$TMP/f2cbody" "$TMP/w/plans/f2c.txt"
printf '{"version":1,"edits":[{"op":"replace_symbol_body","target":"legend_cred","file":"legend.py","payload":"f2c.txt"}]}\n' > "$TMP/w/plans/f2c.json"
( cd "$TMP/w" && "$BIN" . --edit-plan=plans/f2c.json --apply ) >/dev/null 2>"$TMP/f2cl.err"; rc=$?
{ [ "$rc" != 0 ] && ( cd "$TMP/w" && git diff --exit-code --quiet -- legend.py ) && grep -q -- '--no-redact' "$TMP/f2cl.err"; } \
    && ok "(F2) --edit-plan refuses the added marker in the same words, nothing written" \
    || no "(F2) --edit-plan wrote an added redaction marker into source (rc=$rc: $( head -c 200 "$TMP/f2cl.err" ))"
# (F2f) the refusal must not ASSERT what the tool did not do: no sentence may claim the body WAS served
# redacted, because the write surface cannot know that and the element it served says otherwise.
grep -qi 'was served REDACTED' "$TMP/f2c.err" \
    && no "(F2) the refusal asserts 'the body ... was served REDACTED' — a claim the write surface cannot make ($( head -c 200 "$TMP/f2c.err" ))" \
    || ok "(F2) the refusal states what it measured and asserts nothing about how the payload was served"
# (F2g) an INSERT of a payload carrying an artefact the target file does not have is refused too
fresh; printf 'def inserted():\n    # AKIA…[REDACTED:aws-key]\n    return 3\n' > "$TMP/f2ins.py"
( cd "$TMP/w" && "$BIN" . --insert-after-symbol=other_py --edit-target-file=probe.py --edit-payload="$TMP/f2ins.py" ) >/dev/null 2>"$TMP/f2i.err"; rc=$?
{ [ "$rc" != 0 ] && clean; } \
    && ok "(F2) --insert-after-symbol refuses a payload carrying an artefact its target file does not have" \
    || no "(F2) an insert wrote a redaction marker into a file that had none (rc=$rc: $( head -c 200 "$TMP/f2i.err" ))"

[ "$fail" = 0 ] && echo "editroundtripcheck: ALL PASS" || echo "editroundtripcheck: FAILURES ABOVE"
exit "$fail"
