#!/usr/bin/env bash
# redactcheck.sh — gate for W4-#7: deterministic secret redaction of emitted body content.
#
# Usage:
#   test/redactcheck.sh                          # uses build/ripwire on test/redactfix
#   RIPWIRE_BIN=asan/ripwire test/redactcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.
#
# Contract exercised:
#   • each TRUE-POSITIVE credential (one of every supported shape) is redacted in the emitted body of
#     --pack-top-n / --expand / --recall (its raw value never leaves the tool)
#   • each DECOY non-secret (40-char git SHA in prose, base64 test vector without keyword context, an
#     sk- identifier below the length threshold) survives VERBATIM — precision over recall
#   • --no-redact restores the originals verbatim and prints NO stderr summary
#   • exactly one stderr summary line is emitted (count-by-type) when anything was redacted
#   • the redaction transform is deterministic (two runs byte-identical) and keeps the XML well-formed
#   • REDACT-TOUCH (section 8): the source, manifest and plan LINES an answer quotes are redacted too — --for <touch> and
#     <listed>, --path hop bodies, --whereis t=, --plan-lint <owed>, and the MCP twins (rt1..rt5, the arms list there)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/redactfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/redactfix directory"; exit 2; }

echo "redactcheck: BIN=$BIN  CORPUS=$CORPUS"

# The fake-but-live-looking credentials that MUST be redacted (raw value must NOT appear in output).
TRUE_POSITIVES=(
  "AKIAIOSFODNN7EXAMPLE"                                    # AWS access-key id
  "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"               # AWS 40-char secret (keyword-gated)
  "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"                # GitHub fine-grained PAT
  "github_pat_11ABCDEFG0abcdefghijklmnop"                   # GitHub classic PAT prefix
  "xoxb-2401234567-1234567890123-fakeFAKEfakeFAKEfake0"     # Slack bot token
  "AIzaSyA1234567890abcdefghijklmnopqrstuvw"                # Google API key
  "sk-abcdef1234567890ABCDEFGHIJKLMNOPQRSTUV"               # OpenAI key
  "sk-ant-api03-abcdefGHIJKL1234567890mnopQRST"             # Anthropic key
  "BEGIN RSA PRIVATE KEY"                                    # PEM private-key header
  "0123456789abcdef0123456789abcdef0123"                    # generic hex on api_key= line
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"   # bare JWT + same JWT inside an Authorization: Bearer header (A4-F11)
)

# The decoys that must SURVIVE verbatim.
DECOYS=(
  "da39a3ee5e6b4b0d3255bfef95601890afd80709"               # 40-hex git SHA in prose (no keyword)
  "TWFueSBoYW5kcyBtYWtlIGxpZ2h0IHdvcmsuICBhYmNkZWY"        # base64 test vector (no keyword)
  "sk-test-123"                                             # sk- identifier below the length threshold
  "the bearer of good news arrived early this morning with the quarterly report"   # "bearer" as prose, no credential shape (A4-F11 negative)
)

# ── 1) --pack-top-n body seam: true positives redacted, decoys intact ───────────────────────────────
"$BIN" "$CORPUS" --pack-top-n=8 --no-cache >"$TMP/pack.xml" 2>"$TMP/pack.err"
rc=$?
if [ $rc -eq 0 ]; then ok "--pack-top-n exits 0"; else no "--pack-top-n failed (rc=$rc)"; fi

for s in "${TRUE_POSITIVES[@]}"; do
  if grep -qF "$s" "$TMP/pack.xml"; then no "LEAK in --pack-top-n: '$s' not redacted"; else ok "redacted in --pack-top-n: ${s:0:16}…"; fi
done
for d in "${DECOYS[@]}"; do
  if grep -qF "$d" "$TMP/pack.xml"; then ok "decoy intact in --pack-top-n: ${d:0:16}…"; else no "FALSE REDACTION in --pack-top-n: decoy '$d' was altered"; fi
done
# a redaction marker must be present (proves the transform fired)
if grep -q 'REDACTED:' "$TMP/pack.xml"; then ok "redaction markers present in --pack-top-n"; else no "no redaction markers in --pack-top-n"; fi
if grep -q 'REDACTED:jwt' "$TMP/pack.xml"; then ok "jwt redaction marker present in --pack-top-n"; else no "no jwt redaction marker in --pack-top-n"; fi

# ── 2) exactly one stderr summary line, count-by-type ───────────────────────────────────────────────
lines="$( grep -c 'redacted .* secret' "$TMP/pack.err" )"
if [ "$lines" -eq 1 ]; then ok "exactly one stderr summary line"; else no "expected 1 stderr summary line, got $lines"; fi
if grep -q 'ripwire: redacted .* from emitted context (' "$TMP/pack.err"; then ok "stderr summary is count-by-type"; else { no "stderr summary shape wrong"; cat "$TMP/pack.err"; }; fi

# ── 3) --expand on a single symbol also redacts ─────────────────────────────────────────────────────
"$BIN" "$CORPUS" --expand=loadAwsKey --no-cache >"$TMP/exp.xml" 2>/dev/null
grep -qF "AKIAIOSFODNN7EXAMPLE" "$TMP/exp.xml" && no "LEAK in --expand: AWS key not redacted" || ok "--expand redacts the def body"

# ── 4) --recall doc-body seam: redacts secrets in the recalled markdown, keeps the prose SHA ─────────
#
# THE QUERY IS LOAD-BEARING, and this comment is why it may not be trimmed. --recall serves a heading
# document SECTION BY SECTION, most specific first, so a section the query does not match is never
# emitted — and an absence arm over a section that was never served passes while proving nothing
# (CONTRIBUTING §2, shape 1: a population that cannot contain the defect). Every term below is here to
# surface one section of test/redactfix/deploy_notes.md: rotation/credentials the preamble, aws/github/
# anthropic their namesake sections, release+summarizer the token and key lines, rollback the
# not-a-secret SHA section. The PRESENCE GUARD immediately after asserts each section actually arrived,
# so if a future ranking change stops surfacing one, this gate fails LOUDLY instead of going quiet.
"$BIN" "$CORPUS" --recall="deployment credentials aws github anthropic rotation rollback release summarizer" --no-cache >"$TMP/recall.out" 2>"$TMP/recall.err"
while IFS='|' read -r probe label; do
  grep -qF "$probe" "$TMP/recall.out" \
    && ok "--recall surfaced the $label section (absence arms below are live)" \
    || no "--recall did NOT surface the $label section — the redaction arm over it would prove nothing"
done <<'PROBES'
Set the deploy access key id|AWS
Personal access token for the release bot|GitHub
API key for the summarizer|Anthropic
The rollback target is git commit|not-a-secret
PROBES
grep -qF "AKIAIOSFODNN7EXAMPLE" "$TMP/recall.out" && no "LEAK in --recall: AWS key not redacted in doc body" || ok "--recall redacts doc-body secrets"
grep -qF "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" "$TMP/recall.out" && no "LEAK in --recall: GitHub token not redacted" || ok "--recall redacts GitHub token"
if grep -qF "da39a3ee5e6b4b0d3255bfef95601890afd80709" "$TMP/recall.out"; then ok "--recall keeps the prose git SHA intact"; else no "FALSE REDACTION in --recall: prose git SHA was altered"; fi
if grep -q 'redacted .* secret' "$TMP/recall.err"; then ok "--recall emits the stderr summary"; else no "--recall missing stderr summary"; fi

# ── 5) --no-redact restores originals verbatim, NO stderr summary ───────────────────────────────────
"$BIN" "$CORPUS" --pack-top-n=8 --no-redact --no-cache >"$TMP/nr.xml" 2>"$TMP/nr.err"
allback=1
for s in "${TRUE_POSITIVES[@]}"; do
  # the private-key banner check uses the substring; the rest are exact
  grep -qF "$s" "$TMP/nr.xml" || { allback=0; echo "      missing under --no-redact: $s"; }
done
if [ "$allback" -eq 1 ]; then ok "--no-redact restores every original verbatim"; else no "--no-redact did not restore all originals"; fi
grep -q 'REDACTED:' "$TMP/nr.xml" && no "--no-redact still emitted REDACTED markers" || ok "--no-redact emits no redaction markers"
# L5: --pack-top-n now prints its own (unrelated) deprecation line — filter it out before
# asserting redaction-summary silence, so this check stays about redaction, not the deprecation notice.
grep -v -- '--pack-top-n is deprecated' "$TMP/nr.err" >"$TMP/nr.err.noise-filtered"
[ -s "$TMP/nr.err.noise-filtered" ] && { no "--no-redact printed a stderr summary (should be silent)"; cat "$TMP/nr.err.noise-filtered"; } || ok "--no-redact prints no stderr summary"

# ── 6) determinism: two redacted runs are byte-identical ────────────────────────────────────────────
"$BIN" "$CORPUS" --pack-top-n=8 --no-cache >"$TMP/det1" 2>/dev/null
"$BIN" "$CORPUS" --pack-top-n=8 --no-cache >"$TMP/det2" 2>/dev/null
if diff -q "$TMP/det1" "$TMP/det2" >/dev/null; then ok "redaction deterministic (byte-identical)"; else no "redaction nondeterministic"; fi

# ── 7) XML stays well-formed after redaction ────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
  if xmllint --noout "$TMP/pack.xml" 2>/dev/null; then ok "redacted --pack-top-n output is well-formed XML"; else no "redacted output is malformed XML"; fi
  if "$BIN" "$CORPUS" --expand=loadPrivateKey --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null; then ok "redacted --expand output is well-formed XML"; else no "redacted --expand output is malformed XML"; fi
else
  printf '  SKIP  xmllint (not installed)\n'
fi

# ── 8) REDACT-TOUCH: every source, manifest or plan LINE an answer quotes passes the redactor ───────
# Each arm's fixture is built here, at run time, with a token of a shape the redactor already knows (a GitHub ghp_ token, an AWS
# key id). Per arm: the answer prints the marker where the line is quoted and the raw token nowhere, stderr's tally counts every
# marker the answer prints, and --no-redact prints the token raw (no marker, no tally). Red on the pre-change main 9087eb59c:
#   (rt1) --for <touch> (exemplarfamily.h touchListXml): a registry line naming every handler, its token straddling the 120-byte
#         cut — cut first, `ghp_` and 15 bytes print, too short for the GitHub rule, and leak; redacted first, the marker prints
#         (itself cut at 120 bytes, cut="1": nothing of the token is left to leak)
#   (rt1m) MCP `for`: the same <touch> row, the tally on the server's stderr
#   (rt2) --for <listed><ln> (listedin.h appendListed): a Makefile.am SOURCES line carrying a token
#   (rt3) --path <bodies of="hops"> (hopbody.h routeBodiesXml, which passed nullptr): the middle hop's body holds an AWS key id;
#         (rt3m) MCP path_between, the same body
#   (rt4) --whereis t= (crossref.h writeWhereisPage): a definition line holding a token, on HEAD; (rt4m) MCP whereis
#   (rt5) --plan-lint <owed> (planlint.h writePlanLint): an owed line holding a token
RT="$TMP/rt"; mkdir -p "$RT"
. "$ROOT/test/lib/clean-env.sh"
rtok(){ printf '%s%s' "$1" "$( printf "$2%.0s" $( seq 1 "$3" ) )"; }   # prefix, fill byte, fill count
markers(){ grep -o '\[REDACTED:[a-z/]*' "$1" | grep -vx '\[REDACTED:kind' | wc -l | tr -d ' '; }   # the legend's [REDACTED:kind] is no marker
tally(){ sed -n 's/^ripwire: redacted \([0-9]*\) secret.*/\1/p' "$1" | head -1; }
mcpcall(){   # dir tool json-args out err [--no-redact]: one tools/call; out = the text content, err = the server's stderr
    python3 - "$BIN" "$1" "$2" "$3" "$4" "$5" "${6:-}" <<'PY'
import json, subprocess, sys
binp, d, tool, args, out, err, extra = sys.argv[1:8]
reqs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "g", "version": "1"}}},
        {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": tool, "arguments": json.loads(args)}}]
cmd = [binp, "--mcp"] + ([extra] if extra else [])
p = subprocess.run(cmd, input="".join(json.dumps(r) + "\n" for r in reqs), capture_output=True, text=True, timeout=300, cwd=d)
text = ""
for line in p.stdout.splitlines():
    try: o = json.loads(line)
    except ValueError: continue
    if o.get("id") == 1:
        text = "".join(c.get("text", "") for c in o.get("result", {}).get("content", []))
open(out, "w").write(text)
open(err, "w").write(p.stderr)
PY
}
# check ARM OUT ERR RAWFILL ELEMENT-REGEX: the element holds a marker, the raw fill appears nowhere, stderr counts every marker
rtcheck(){
    local arm="$1" out="$2" err="$3" fill="$4" el="$5" n
    n="$( markers "$out" )"
    if tr '\n' ' ' <"$out" | grep -Eq "$el" && ! grep -q "$fill" "$out" && [ "$n" -gt 0 ] && [ "$( tally "$err" )" = "$n" ]; then
        ok "($arm) the quoted line prints the marker, the raw token nowhere; stderr counts all $n markers"
    else no "($arm) $( tr '\n' ' ' <"$out" | grep -Eo "$el" | head -c 300 ) | raw: $( grep -c "$fill" "$out" ) | markers $n, stderr: $( grep -o 'redacted[^(]*' "$err" )"; fi
}
# raw ARM OUT ERR TOKEN-PREFIX: --no-redact prints the token raw, no marker, no tally
rtraw(){
    if grep -q "$4" "$2" && ! grep -q 'REDACTED' "$2" && ! grep -q 'ripwire: redacted' "$3"; then ok "($1) --no-redact prints the line raw, no tally"
    else no "($1) --no-redact: raw $( grep -c "$4" "$2" ), markers $( markers "$2" ), stderr: $( grep -o 'redacted[^(]*' "$3" )"; fi
}
rtrun(){ local d="$1" out="$2" err="$3"; shift 3; ( cd "$d" || exit 1; "$BIN" "$d" --no-cache "$@" </dev/null >"$out" 2>"$err" ) || no "run $d $*: rc=$?"; }

# (rt1) <touch>
P="$RT/py"; mkdir -p "$P/app/handlers"
printf 'class Handler:\n    def handle(self, req):\n        raise NotImplementedError\n' >"$P/app/handlers/base.py"
for h in json xml csv yaml; do
    H="$( printf '%s' "$h" | awk '{ print toupper( substr( $0, 1, 1 ) ) substr( $0, 2 ) }' )"
    printf 'from .base import Handler\n\n\nclass %sHandler(Handler):\n    def handle(self, req):\n        return "%s"\n' "$H" "$h" >"$P/app/handlers/${h}_handler.py"
done
TT="$( rtok ghp_ A 36 )"
printf 'HANDLERS = {"json": JsonHandler, "xml": XmlHandler, "csv": CsvHandler, "yaml": YamlHandler, "auth": "%s"}\n' "$TT" >"$P/app/registry.py"
rtrun "$P" "$RT/t1.xml" "$RT/t1.err" "--for=add a new handler"
rtcheck rt1 "$RT/t1.xml" "$RT/t1.err" AAAAAAAAAA '<touch p="app/registry.py:1"[^>]* cut="1">[^<]*ghp_…\[REDACTED:'
rtrun "$P" "$RT/t1n.xml" "$RT/t1n.err" "--for=add a new handler" --no-redact
rtraw rt1 "$RT/t1n.xml" "$RT/t1n.err" 'ghp_AAAAAAAAAAAA'
mcpcall "$P" for "{\"path\":\"$P\",\"task\":\"add a new handler\"}" "$RT/t1m.xml" "$RT/t1m.err"
rtcheck rt1m "$RT/t1m.xml" "$RT/t1m.err" AAAAAAAAAA '<touch p="app/registry.py:1"[^>]* cut="1">[^<]*ghp_…\[REDACTED:'
mcpcall "$P" for "{\"path\":\"$P\",\"task\":\"add a new handler\"}" "$RT/t1mn.xml" "$RT/t1mn.err" --no-redact
rtraw rt1m "$RT/t1mn.xml" "$RT/t1mn.err" 'ghp_AAAAAAAAAAAA'

# (rt2) <listed><ln>
A="$RT/am"; mkdir -p "$A"
TL="$( rtok ghp_ L 36 )"
printf 'bin_PROGRAMS = demo\n\ndist_demo_SOURCES = \\\n\twidget-alpha.c %s \\\n\twidget-beta.c \\\n\tmain.c\n' "$TL" >"$A/Makefile.am"
printf 'int main(void) { return 0; }\n' >"$A/main.c"
printf 'int widget_new_alpha(void) { return 1; }\nint widget_alpha_run(void) { return widget_new_alpha(); }\n' >"$A/widget-alpha.c"
printf 'int widget_new_beta(void) { return 2; }\n' >"$A/widget-beta.c"
rtrun "$A" "$RT/t2.xml" "$RT/t2.err" "--for=new widget"
rtcheck rt2 "$RT/t2.xml" "$RT/t2.err" LLLLLLLLLL '<ln l="4">[^<]*\[REDACTED:github-token\]'
rtrun "$A" "$RT/t2n.xml" "$RT/t2n.err" "--for=new widget" --no-redact
rtraw rt2 "$RT/t2n.xml" "$RT/t2n.err" 'ghp_LLLLLLLLLLLL'

# (rt3) <bodies of="hops">
W="$RT/web"; mkdir -p "$W/src"
printf 'export function fetch(req: string): string {\n  return dispatch(req)\n}\nexport function dispatch(req: string): string {\n  const signer = "AKIAIOSFODNN7EXAMPLE"\n  return compose(req + signer)\n}\nexport function compose(body: string): string {\n  return body\n}\n' >"$W/src/server.ts"
rtrun "$W" "$RT/t3.xml" "$RT/t3.err" --path=fetch,compose
rtcheck rt3 "$RT/t3.xml" "$RT/t3.err" IOSFODNN7EXAMPLE '<bodies of="hops"[^>]*><b [^>]*n="dispatch"[^>]*><!\[CDATA\[[^]]*AKIA…\[REDACTED:aws-key\]'
rtrun "$W" "$RT/t3n.xml" "$RT/t3n.err" --path=fetch,compose --no-redact
rtraw rt3 "$RT/t3n.xml" "$RT/t3n.err" 'AKIAIOSFODNN7EXAMPLE'
mcpcall "$W" path_between "{\"path\":\"$W\",\"from\":\"fetch\",\"to\":\"compose\"}" "$RT/t3m.xml" "$RT/t3m.err"
rtcheck rt3m "$RT/t3m.xml" "$RT/t3m.err" IOSFODNN7EXAMPLE '<bodies of="hops"[^>]*><b [^>]*n="dispatch"[^>]*><!\[CDATA\[[^]]*AKIA…\[REDACTED:aws-key\]'

# (rt4) --whereis t=
G="$RT/git"; mkdir -p "$G"
TW="$( rtok ghp_ W 36 )"
printf 'def deploy(token="%s"):\n    return token\n' "$TW" >"$G/deploy.py"
( cd "$G" && git init -q -b main . && git add -A && git -c user.name=ripwire -c user.email=ripwire@example.invalid commit -qm init ) || no "(rt4) git fixture"
rtrun "$G" "$RT/t4.xml" "$RT/t4.err" --whereis=deploy
rtcheck rt4 "$RT/t4.xml" "$RT/t4.err" WWWWWWWWWW '<hit [^>]*t="def deploy\(token=&quot;ghp_[^"]*\[REDACTED:github-token\]'
rtrun "$G" "$RT/t4n.xml" "$RT/t4n.err" --whereis=deploy --no-redact
rtraw rt4 "$RT/t4n.xml" "$RT/t4n.err" 'ghp_WWWWWWWWWWWW'
mcpcall "$G" whereis "{\"path\":\"$G\",\"symbol\":\"deploy\"}" "$RT/t4m.xml" "$RT/t4m.err"
rtcheck rt4m "$RT/t4m.xml" "$RT/t4m.err" WWWWWWWWWW '<hit [^>]*t="def deploy\(token=&quot;ghp_[^"]*\[REDACTED:github-token\]'

# (rt5) --plan-lint <owed>
TP="$( rtok ghp_ P 36 )"
printf '# PLAN\n\n### T1\nRotate the deploy token.\n- owed: rotate the deploy token %s before release\n' "$TP" >"$RT/plan.md"
( cd "$RT" && "$BIN" "$RT" --no-cache --plan-lint="$RT/plan.md" </dev/null >"$RT/t5.xml" 2>"$RT/t5.err" ); rc5=$?
[ "$rc5" -le 2 ] || no "(rt5) --plan-lint exited $rc5"
rtcheck rt5 "$RT/t5.xml" "$RT/t5.err" PPPPPPPPPP '<owed line="5"[^>]*><!\[CDATA\[[^]]*\[REDACTED:github-token\]'
( cd "$RT" && "$BIN" "$RT" --no-cache --plan-lint="$RT/plan.md" --no-redact </dev/null >"$RT/t5n.xml" 2>"$RT/t5n.err" )
rtraw rt5 "$RT/t5n.xml" "$RT/t5n.err" 'ghp_PPPPPPPPPPPP'

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
