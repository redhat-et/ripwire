#!/usr/bin/env bash
# jsonredactcheck.sh — gate for §B0: the machine-readable (--json) surfaces must redact the SAME
# credential shapes the XML siblings redact.
#
# Usage:
#   test/jsonredactcheck.sh                          # uses build/ctxpack
#   CTXPACK_BIN=asan/ctxpack test/jsonredactcheck.sh
#   CTXPACK_BIN=build_base/ctxpack test/jsonredactcheck.sh   # red-first: the JSON arms MUST fail here
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.
#
# Contract exercised (the audit's own repro, frozen):
#   • XML CONTROL — `--for --token-budget=1500` redacts an AWS key pasted into a doc comment, and
#     `--pack-task` redacts a GitHub token living in a function body. These already passed before the
#     fix; they pin the control so a regression on the XML side cannot masquerade as a JSON pass.
#   • JSON — the same two verbs under `--json` must emit the SAME redaction markers and NEVER the raw
#     literal. `--help` promises "--json … SAME content, keys mirror the XML attr names 1:1"; before
#     §B0 that was false in the one direction that matters (doc text in collectJsonSigEntries, body
#     text in packBodiesJson had zero redactInPlace call sites).
#   • --no-redact is still the opt-out on BOTH modes (the fix is gated on the RedactCounts pointer,
#     not unconditional) — otherwise a user auditing their own tree loses the escape hatch.
#   • precision survives the new seam: a 40-hex git SHA in prose is NOT redacted in JSON either.
#   • the stderr tally counts the JSON run's redactions (the counts pointer is really threaded, not
#     a local throwaway), and the JSON stays parseable + deterministic.
#
# The corpus is built here, in a temp dir this script creates and removes: a live-looking credential
# must never be committed into the tree, and the gate must be readable as its own repro.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# hard input requirements — a missing input is a FAILURE of the gate, never a silent skip
[ -x "$BIN" ] || { echo "jsonredactcheck: no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "jsonredactcheck: python3 is required (JSON well-formedness arm)"; exit 2; }

echo "jsonredactcheck: BIN=$BIN"

# ── the sandbox corpus ─────────────────────────────────────────────────────────────────────────────
# probe.cpp carries BOTH emission seams the audit measured: an AWS-key-shaped literal inside the doc
# comment that <doc>/"doc" carries, and a ghp_-shaped token inside the body that <b>/"body" carries.
mkdir -p "$CORPUS/src" || { echo "jsonredactcheck: cannot create corpus under $TMP"; exit 2; }
cat > "$CORPUS/src/probe.cpp" <<'PROBE_EOF'
#include <cstdio>

// Probe loader for the deployment credential store.
// Example key from the AWS documentation: AKIAIOSFODNN7EXAMPLE
// Reviewed in commit da39a3ee5e6b4b0d3255bfef95601890afd80709 — rotate quarterly, never commit a live key.
const char* probeSecretLoader()
{
    const char* token = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    std::printf( "loading deployment credential\n" );
    return token;
}

// Deployment entry point that consumes the loaded deployment credential.
int probeDeployMain()
{
    const char* t = probeSecretLoader();
    return t == nullptr ? 1 : 0;
}
PROBE_EOF
[ -s "$CORPUS/src/probe.cpp" ] || { echo "jsonredactcheck: corpus file was not written"; exit 2; }

AWS_RAW="AKIAIOSFODNN7EXAMPLE"
GH_RAW="ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
SHA_DECOY="da39a3ee5e6b4b0d3255bfef95601890afd80709"
TASK="probeSecretLoader deployment credential loader"

run(){ # run <outfile> <errfile> <args...>
  local out="$1" err="$2"; shift 2
  "$BIN" "$CORPUS" "$@" --no-cache >"$out" 2>"$err"
  local rc=$?
  [ $rc -eq 0 ] || no "exit $rc from: $* (see $err)"
  [ -s "$out" ] || no "empty output from: $*"
}

# ── 1) XML control — this already passed pre-fix; it pins the reference behaviour ──────────────────
run "$TMP/for.xml" "$TMP/for.xml.err" --for=probeSecretLoader --token-budget=1500
grep -qF "$AWS_RAW" "$TMP/for.xml" && no "XML CONTROL BROKEN: raw AWS key in --for XML" || ok "XML --for: raw AWS key absent"
grep -qF 'REDACTED:aws-key' "$TMP/for.xml" && ok "XML --for: aws-key redaction marker present" || no "XML CONTROL BROKEN: no aws-key marker in --for XML"

run "$TMP/pt.xml" "$TMP/pt.xml.err" --pack-task="$TASK"
grep -qF "$GH_RAW" "$TMP/pt.xml" && no "XML CONTROL BROKEN: raw GitHub token in --pack-task XML" || ok "XML --pack-task: raw GitHub token absent"
grep -qF 'REDACTED:github-token' "$TMP/pt.xml" && ok "XML --pack-task: github-token marker present" || no "XML CONTROL BROKEN: no github-token marker in --pack-task XML"

# ── 2) the §B0 fix — the same two verbs under --json ───────────────────────────────────────────────
run "$TMP/for.json" "$TMP/for.json.err" --for=probeSecretLoader --token-budget=1500 --json
grep -qF "$AWS_RAW" "$TMP/for.json" && no "LEAK: raw AWS key in --for --json (collectJsonSigEntries doc seam)" || ok "JSON --for: raw AWS key absent"
grep -qF 'REDACTED:aws-key' "$TMP/for.json" && ok "JSON --for: aws-key redaction marker present" || no "JSON --for: no aws-key redaction marker"

run "$TMP/pt.json" "$TMP/pt.json.err" --pack-task="$TASK" --json
grep -qF "$GH_RAW" "$TMP/pt.json" && no "LEAK: raw GitHub token in --pack-task --json (packBodiesJson body seam)" || ok "JSON --pack-task: raw GitHub token absent"
grep -qF "$AWS_RAW" "$TMP/pt.json" && no "LEAK: raw AWS key in --pack-task --json (ranking doc seam)" || ok "JSON --pack-task: raw AWS key absent"
grep -qF 'REDACTED:github-token' "$TMP/pt.json" && ok "JSON --pack-task: github-token marker present" || no "JSON --pack-task: no github-token redaction marker"
grep -qF 'REDACTED:aws-key' "$TMP/pt.json" && ok "JSON --pack-task: aws-key marker present" || no "JSON --pack-task: no aws-key redaction marker"

# ── 3) the tally is really threaded — the JSON runs report on stderr, same as the XML runs ─────────
grep -q 'ctxpack: redacted .* from emitted context (' "$TMP/for.json.err" \
  && ok "JSON --for: stderr redaction summary emitted" || no "JSON --for: no stderr redaction summary (counts pointer not threaded)"
grep -q 'ctxpack: redacted .* from emitted context (' "$TMP/pt.json.err" \
  && ok "JSON --pack-task: stderr redaction summary emitted" || no "JSON --pack-task: no stderr redaction summary"

# ── 4) --no-redact remains the opt-out on the JSON surfaces too ────────────────────────────────────
run "$TMP/for.nr.json" "$TMP/for.nr.json.err" --for=probeSecretLoader --token-budget=1500 --json --no-redact
grep -qF "$AWS_RAW" "$TMP/for.nr.json" && ok "JSON --for --no-redact: raw value passes through (opt-out intact)" || no "JSON --for --no-redact: raw value missing — redaction is unconditional, not gated"
run "$TMP/pt.nr.json" "$TMP/pt.nr.json.err" --pack-task="$TASK" --json --no-redact
grep -qF "$GH_RAW" "$TMP/pt.nr.json" && ok "JSON --pack-task --no-redact: raw value passes through (opt-out intact)" || no "JSON --pack-task --no-redact: raw value missing — redaction is unconditional, not gated"
grep -q 'ctxpack: redacted' "$TMP/for.nr.json.err" && no "JSON --no-redact: stderr summary printed although nothing was redacted" || ok "JSON --no-redact: no stderr summary"

# ── 5) precision — a decoy (40-hex git SHA in prose, no credential keyword) survives in JSON too ───
grep -qF "$SHA_DECOY" "$TMP/for.json" && ok "JSON --for: git-SHA decoy intact (no false redaction)" || no "JSON --for: FALSE REDACTION of the git-SHA decoy"
grep -qF "$SHA_DECOY" "$TMP/pt.json" && ok "JSON --pack-task: git-SHA decoy intact (no false redaction)" || no "JSON --pack-task: FALSE REDACTION of the git-SHA decoy"

# ── 6) the redacted JSON is still well-formed and deterministic ────────────────────────────────────
for f in "$TMP/for.json" "$TMP/pt.json"; do
  python3 -m json.tool <"$f" >/dev/null 2>&1 && ok "valid JSON after redaction: $( basename "$f" )" || no "MALFORMED JSON after redaction: $( basename "$f" )"
done
run "$TMP/pt.json.2" "$TMP/pt.json.2.err" --pack-task="$TASK" --json
cmp -s "$TMP/pt.json" "$TMP/pt.json.2" && ok "redacted --pack-task --json is deterministic (two runs byte-identical)" || no "--pack-task --json not deterministic across runs"

# ── 7) clone-seam guard — the marker must ride the JSON *body* value, not only the doc value ──────
# (a fix that plumbed only collectJsonSigEntries would pass every doc arm above and still leak bodies;
#  assert the marker inside the "body": string itself, which is packBodiesJson's own output)
python3 - "$TMP/pt.json" <<'PY_EOF' && ok "JSON --pack-task: marker is inside a \"body\" value (packBodiesJson seam covered)" || no "JSON --pack-task: no \"body\" value carries a redaction marker"
import json, sys
with open( sys.argv[1] ) as fh: doc = json.load( fh )
sys.exit( 0 if any( "[REDACTED:" in b.get( "body", "" ) for b in doc.get( "bodies", [] ) ) else 1 )
PY_EOF

echo
[ $fail -eq 0 ] && { echo "jsonredactcheck: ALL PASS"; exit 0; } || { echo "jsonredactcheck: FAILURES"; exit 1; }
