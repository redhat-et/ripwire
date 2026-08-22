#!/usr/bin/env bash
# mcpeditkindcheck.sh — gate for the F1 fix (security audit): the MCP edit verbs must REFUSE to write
# through a doc `Section` symbol (markdown heading, or a whole-file section for .html/.csv/.ipynb). Their
# stored span does not delimit a code definition — and for html/csv/ipynb `endByte` is the EXTRACTED-text
# length, unrelated to raw-file bytes — so splicing it silently CORRUPTS the file (e.g. deletes an HTML
# <head>/<script>) while reporting success. The fix guards resolveOneForEdit on SymKind::Section. This gate
# proves: doc sections are refused + the file is byte-unchanged, AND a real code edit still applies (no
# over-block). Verified to FAIL against the pre-fix binary (which reported "applied" + corrupted the file).
# Usage:  test/mcpeditkindcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/mcpeditkindcheck.sh
set -u
BIN="${1:-${RIPWIRE_BIN:-./build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# a repo with three doc-Section sources + one real code file
cat > "$T/guide.md" <<'MD'
# Project Guide

## ZorbleWidgetConfig

Prose that must survive verbatim.
MD
printf '<html><head><script>var secret="do-not-lose-me"</script></head><body>hi</body></html>\n' > "$T/report.html"
printf 'int keeper( int x )\n{\n    return x + 1;\n}\n' > "$T/code.cpp"

# helper: run one replace_symbol_body call through the MCP server, echo the response
mcp_replace(){ # $1=symbol  $2=new_body
    printf '%s\n' \
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"replace_symbol_body","path":"'"$T"'","symbol":"'"$1"'","new_body":"'"$2"'"}}' \
      | "$BIN" --mcp 2>/dev/null
}

# 1) markdown heading → refused + file unchanged
b="$(shasum "$T/guide.md")"; r="$(mcp_replace ZorbleWidgetConfig 'int PWNED(){return 0;}')"; a="$(shasum "$T/guide.md")"
{ echo "$r" | grep -qiE 'document heading/section|not an editable code' && ! echo "$r" | grep -qi 'applied' && [ "$b" = "$a" ]; } \
    && ok "markdown heading: refused + guide.md byte-unchanged" \
    || { no "markdown heading edit not safely refused"; echo "     resp: $(echo "$r" | grep -o '"[a-z_]*":"[^"]*"' | head -3 | tr '\n' ' ')"; }

# 2) html whole-file section (named by file stem 'report') → refused + <script> secret preserved
b="$(shasum "$T/report.html")"; r="$(mcp_replace report 'REPLACED')"; a="$(shasum "$T/report.html")"
{ echo "$r" | grep -qiE 'document heading/section|not an editable code' && [ "$b" = "$a" ] && grep -q 'do-not-lose-me' "$T/report.html"; } \
    && ok "html section: refused + report.html byte-unchanged (embedded secret preserved)" \
    || no "html section edit not safely refused (or content lost)"

# 3) REGRESSION: a real code symbol still edits (the guard must not over-block source)
b="$(cat "$T/code.cpp")"; r="$(mcp_replace keeper 'int keeper( int x )\n{\n    return x + 2;\n}')"; a="$(cat "$T/code.cpp")"
{ echo "$r" | grep -qi 'applied' && [ "$b" != "$a" ]; } \
    && ok "real code symbol (keeper) still edits (guard does not over-block source)" \
    || { no "the guard wrongly blocked a legitimate code edit"; echo "     resp: $(echo "$r" | grep -o '"[a-z_]*":"[^"]*"' | head -3 | tr '\n' ' ')"; }

# 4) determinism: the refusal is stable
r1="$(mcp_replace ZorbleWidgetConfig 'x')"; r2="$(mcp_replace ZorbleWidgetConfig 'x')"
[ "$r1" = "$r2" ] && ok "refusal deterministic run-to-run" || no "refusal non-deterministic"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
