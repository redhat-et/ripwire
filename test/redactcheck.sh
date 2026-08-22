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

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/redactfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
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
[ $rc -eq 0 ] && ok "--pack-top-n exits 0" || no "--pack-top-n failed (rc=$rc)"

for s in "${TRUE_POSITIVES[@]}"; do
  if grep -qF "$s" "$TMP/pack.xml"; then no "LEAK in --pack-top-n: '$s' not redacted"; else ok "redacted in --pack-top-n: ${s:0:16}…"; fi
done
for d in "${DECOYS[@]}"; do
  if grep -qF "$d" "$TMP/pack.xml"; then ok "decoy intact in --pack-top-n: ${d:0:16}…"; else no "FALSE REDACTION in --pack-top-n: decoy '$d' was altered"; fi
done
# a redaction marker must be present (proves the transform fired)
grep -q 'REDACTED:' "$TMP/pack.xml" && ok "redaction markers present in --pack-top-n" || no "no redaction markers in --pack-top-n"
grep -q 'REDACTED:jwt' "$TMP/pack.xml" && ok "jwt redaction marker present in --pack-top-n" || no "no jwt redaction marker in --pack-top-n"

# ── 2) exactly one stderr summary line, count-by-type ───────────────────────────────────────────────
lines="$( grep -c 'redacted .* secret' "$TMP/pack.err" )"
[ "$lines" -eq 1 ] && ok "exactly one stderr summary line" || no "expected 1 stderr summary line, got $lines"
grep -q 'ripwire: redacted .* from emitted context (' "$TMP/pack.err" && ok "stderr summary is count-by-type" || { no "stderr summary shape wrong"; cat "$TMP/pack.err"; }

# ── 3) --expand on a single symbol also redacts ─────────────────────────────────────────────────────
"$BIN" "$CORPUS" --expand=loadAwsKey --no-cache >"$TMP/exp.xml" 2>/dev/null
grep -qF "AKIAIOSFODNN7EXAMPLE" "$TMP/exp.xml" && no "LEAK in --expand: AWS key not redacted" || ok "--expand redacts the def body"

# ── 4) --recall doc-body seam: redacts secrets in the recalled markdown, keeps the prose SHA ─────────
"$BIN" "$CORPUS" --recall="deployment credentials aws github anthropic rotation" --no-cache >"$TMP/recall.out" 2>"$TMP/recall.err"
grep -qF "AKIAIOSFODNN7EXAMPLE" "$TMP/recall.out" && no "LEAK in --recall: AWS key not redacted in doc body" || ok "--recall redacts doc-body secrets"
grep -qF "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" "$TMP/recall.out" && no "LEAK in --recall: GitHub token not redacted" || ok "--recall redacts GitHub token"
grep -qF "da39a3ee5e6b4b0d3255bfef95601890afd80709" "$TMP/recall.out" && ok "--recall keeps the prose git SHA intact" || no "FALSE REDACTION in --recall: prose git SHA was altered (or doc not surfaced)"
grep -q 'redacted .* secret' "$TMP/recall.err" && ok "--recall emits the stderr summary" || no "--recall missing stderr summary"

# ── 5) --no-redact restores originals verbatim, NO stderr summary ───────────────────────────────────
"$BIN" "$CORPUS" --pack-top-n=8 --no-redact --no-cache >"$TMP/nr.xml" 2>"$TMP/nr.err"
allback=1
for s in "${TRUE_POSITIVES[@]}"; do
  # the private-key banner check uses the substring; the rest are exact
  grep -qF "$s" "$TMP/nr.xml" || { allback=0; echo "      missing under --no-redact: $s"; }
done
[ "$allback" -eq 1 ] && ok "--no-redact restores every original verbatim" || no "--no-redact did not restore all originals"
grep -q 'REDACTED:' "$TMP/nr.xml" && no "--no-redact still emitted REDACTED markers" || ok "--no-redact emits no redaction markers"
# L5: --pack-top-n now prints its own (unrelated) deprecation line — filter it out before
# asserting redaction-summary silence, so this check stays about redaction, not the deprecation notice.
grep -v -- '--pack-top-n is deprecated' "$TMP/nr.err" >"$TMP/nr.err.noise-filtered"
[ -s "$TMP/nr.err.noise-filtered" ] && { no "--no-redact printed a stderr summary (should be silent)"; cat "$TMP/nr.err.noise-filtered"; } || ok "--no-redact prints no stderr summary"

# ── 6) determinism: two redacted runs are byte-identical ────────────────────────────────────────────
"$BIN" "$CORPUS" --pack-top-n=8 --no-cache >"$TMP/det1" 2>/dev/null
"$BIN" "$CORPUS" --pack-top-n=8 --no-cache >"$TMP/det2" 2>/dev/null
diff -q "$TMP/det1" "$TMP/det2" >/dev/null && ok "redaction deterministic (byte-identical)" || no "redaction nondeterministic"

# ── 7) XML stays well-formed after redaction ────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$TMP/pack.xml" 2>/dev/null && ok "redacted --pack-top-n output is well-formed XML" || no "redacted output is malformed XML"
  "$BIN" "$CORPUS" --expand=loadPrivateKey --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null && ok "redacted --expand output is well-formed XML" || no "redacted --expand output is malformed XML"
else
  printf '  SKIP  xmllint (not installed)\n'
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
