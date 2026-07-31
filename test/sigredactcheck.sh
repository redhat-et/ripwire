#!/usr/bin/env bash
# sigredactcheck.sh — gate for W3-N1 (the §B0 family's next member): a SIGNATURE is emitted text too.
#
# Usage:
#   test/sigredactcheck.sh                       # uses build/ripwire
#   test/sigredactcheck.sh asan/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/sigredactcheck.sh    # red-first: every sig arm MUST fail here
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.
#
# What the audit found: `redactInPlace` guarded doc comments and bodies, but nothing guarded the text
# `cleanSig` produces — and a signature carries whatever DEFAULT ARGUMENT the author wrote. So
# `int f( const char* key = "AKIA…" )` shipped the literal verbatim through EVERY sig-emitting seam, in
# both dialects. The fix makes `cleanSig`'s RedactCounts* parameter REQUIRED (no default), so the whole
# family is covered by construction and a future sig-emitting clone cannot silently opt out.
#
# The family, one arm each (this is the enumeration the fix was built against — grep `cleanSig`):
#   • XML  --for              <d> row signature               (serialize.h packSignatures)
#   • JSON --for --json       "sig"                           (serialize.h collectJsonSigEntries)
#   • XML  --expand           <calls><c> callee twin          (serialize.h emitCalleeCallsBlock)
#   • JSON --pack-task --json bodies[].calls[].sig            (serialize.h packBodiesJson)
#   • XML  --format=candidates <sig>                          (serialize.h packCandidates)
#   • XML  --lego=TYPE        <m> contract method             (serialize.h packLego)
#   • XML  --pack-task        <s> d1 caller/callee row        (packtask.h resolveD1Signature)
# plus: --no-redact is still the escape hatch on both dialects, a non-secret default survives verbatim,
# the stderr tally really counts these redactions (the pointer is threaded, not a local throwaway), and
# both dialects stay well-formed.
#
# The corpus is built here, in a temp dir this script creates and removes: a live-looking credential
# must never be committed into the tree, and the gate must read as its own repro.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# hard input requirements — a missing input is a FAILURE of the gate, never a silent skip
[ -x "$BIN" ] || { echo "sigredactcheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "sigredactcheck: python3 is required (JSON arms)"; exit 2; }

echo "sigredactcheck: BIN=$BIN"

# ── the sandbox corpus ─────────────────────────────────────────────────────────────────────────────
# Python carries the defaults ON THE DEFINITION (so the <calls>/calls[] twin sees them too); the C++
# header carries an interface whose method default feeds the <lego> contract.
mkdir -p "$CORPUS/src" || { echo "sigredactcheck: cannot create corpus under $TMP"; exit 2; }
AWSKEY="AKIA""IOSFODNN7EXAMPLE"
GHTOKEN="ghp_""ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

cat > "$CORPUS/app.py" <<PY_EOF
def probeVaultHelper( token = "$GHTOKEN" ):
    return token


def probeVaultLoader( key = "$AWSKEY", label = "rotate-quarterly" ):
    return probeVaultHelper( key )
PY_EOF

cat > "$CORPUS/src/vault.h" <<CPP_EOF
#pragma once

struct ProbeVaultIface
{
    virtual int loadKey( const char* key = "$AWSKEY" ) = 0;
    virtual ~ProbeVaultIface() = default;
};

struct ProbeVaultImpl : ProbeVaultIface
{
    int loadKey( const char* key ) override;
};
CPP_EOF

MARK_AWS="REDACTED:aws-key"
MARK_GH="REDACTED:github-token"

run(){ "$BIN" "$CORPUS" "$@" 2>/dev/null; }

# ── arm 1-2: the <d>/"sig" pair — the direct repro, both dialects ──────────────────────────────────
XMLFOR="$( run --for="probeVaultLoader" )"
JSONFOR="$( run --for="probeVaultLoader" --json )"

case "$XMLFOR" in *"$AWSKEY"*) no "XML --for leaks the default-arg AWS key verbatim in the row signature";; *) ok "XML --for row signature carries no raw key";; esac
case "$XMLFOR" in *"$MARK_AWS"*) ok "XML --for row signature carries the $MARK_AWS marker";; *) no "XML --for row signature has no redaction marker (the key vanished instead of being marked?)";; esac
case "$JSONFOR" in *"$AWSKEY"*) no "JSON --for \"sig\" leaks the default-arg AWS key verbatim";; *) ok "JSON --for \"sig\" carries no raw key";; esac
case "$JSONFOR" in *"$MARK_AWS"*) ok "JSON --for \"sig\" carries the $MARK_AWS marker";; *) no "JSON --for \"sig\" has no redaction marker";; esac

# the two dialects must agree about WHICH secrets they masked — the §B0 parity claim, one level down
xmlMarks="$( printf '%s' "$XMLFOR" | grep -o 'REDACTED:[a-z-]*' | sort -u | tr '\n' ' ' )"
jsonMarks="$( printf '%s' "$JSONFOR" | grep -o 'REDACTED:[a-z-]*' | sort -u | tr '\n' ' ' )"
if [ -n "$xmlMarks" ] && [ "$xmlMarks" = "$jsonMarks" ]; then ok "XML/JSON --for mask the same kind set ($xmlMarks)"
else no "XML/JSON --for disagree on the masked kind set (xml='$xmlMarks' json='$jsonMarks')"; fi

# ── arm 3-4: the callee-signature twin (<calls><c> and bodies[].calls[].sig) ───────────────────────
XMLCALLS="$( run --expand=probeVaultLoader )"
case "$XMLCALLS" in *"$GHTOKEN"*) no "XML <calls><c> leaks the callee's default-arg GitHub token";; *) ok "XML <calls><c> callee signature carries no raw token";; esac
case "$XMLCALLS" in *"$MARK_GH"*) ok "XML <calls><c> callee signature carries the $MARK_GH marker";; *) no "XML <calls><c> callee signature has no redaction marker";; esac

PTJSON="$( run --pack-task="probeVaultLoader" --json )"
callSigs="$( printf '%s' "$PTJSON" | python3 -c '
import sys, json
d = json.load( sys.stdin )
out = []
for b in d.get( "bodies", [] ):
    for c in b.get( "calls", [] ):
        out.append( c.get( "sig", "" ) )
print( "\n".join( out ) )
' 2>/dev/null )"
if [ -z "$callSigs" ]; then no "--pack-task --json emitted no bodies[].calls[].sig — the arm cannot observe its own contract"
else
  case "$callSigs" in *"$GHTOKEN"*) no "JSON bodies[].calls[].sig leaks the callee's default-arg GitHub token";; *) ok "JSON bodies[].calls[].sig carries no raw token";; esac
  case "$callSigs" in *"$MARK_GH"*) ok "JSON bodies[].calls[].sig carries the $MARK_GH marker";; *) no "JSON bodies[].calls[].sig has no redaction marker";; esac
fi

# ── arm 5: --format=candidates (the external-reranker export — flat <sig> rows, no doc, no body) ───
CANDS="$( run --for="probeVaultLoader" --format=candidates )"
case "$CANDS" in *"$AWSKEY"*|*"$GHTOKEN"*) no "--format=candidates <sig> leaks a raw credential";; *) ok "--format=candidates <sig> carries no raw credential";; esac
case "$CANDS" in *"REDACTED:"*) ok "--format=candidates <sig> carries a redaction marker";; *) no "--format=candidates <sig> has no redaction marker";; esac

# ── arm 6: --lego contract methods ────────────────────────────────────────────────────────────────
LEGO="$( run --lego=ProbeVaultIface )"
case "$LEGO" in *"$AWSKEY"*) no "--lego <m> contract method leaks the default-arg AWS key";; *) ok "--lego <m> contract method carries no raw key";; esac
case "$LEGO" in *"$MARK_AWS"*) ok "--lego <m> contract method carries the $MARK_AWS marker";; *) no "--lego <m> contract method has no redaction marker";; esac

# ── arm 7: --pack-task's XML d1 caller/callee rows (the lighter signature ladder) ──────────────────
PTXML="$( run --pack-task="probeVaultLoader" )"
case "$PTXML" in *"$AWSKEY"*|*"$GHTOKEN"*) no "--pack-task XML leaks a raw credential in a signature row";; *) ok "--pack-task XML signature rows carry no raw credential";; esac
case "$PTXML" in *"REDACTED:"*) ok "--pack-task XML carries a redaction marker";; *) no "--pack-task XML has no redaction marker";; esac

# ── arm 8: --no-redact is still the escape hatch, in BOTH dialects ─────────────────────────────────
case "$( run --for="probeVaultLoader" --no-redact )" in *"$AWSKEY"*) ok "--no-redact still passes the signature through verbatim (XML)";; *) no "--no-redact no longer yields the raw signature (XML) — the opt-out is gone";; esac
case "$( run --for="probeVaultLoader" --json --no-redact )" in *"$AWSKEY"*) ok "--no-redact still passes the signature through verbatim (JSON)";; *) no "--no-redact no longer yields the raw signature (JSON) — the opt-out is gone";; esac

# ── arm 9: precision — an ordinary default argument is NOT touched ─────────────────────────────────
case "$XMLFOR" in *"rotate-quarterly"*) ok "a non-credential default argument survives verbatim (no over-redaction)";; *) no "a non-credential default argument was mangled — the sig seam over-redacts";; esac

# ── arm 10: the stderr tally really counts the SIGNATURE redactions ────────────────────────────────
# --format=candidates emits signatures ONLY (no doc, no body), so any tally it prints can only come
# from the new seam. Before the fix this run was silent.
tally="$( "$BIN" "$CORPUS" --for="probeVaultLoader" --format=candidates 2>&1 >/dev/null | grep -c 'redacted [0-9]* secret' )"
if [ "$tally" -ge 1 ]; then ok "the stderr tally reports the signature-only run's redactions (counts pointer is threaded)"
else no "signature-only run redacted but printed no stderr tally — the RedactCounts pointer is not reaching cleanSig"; fi

legoTally="$( "$BIN" "$CORPUS" --lego=ProbeVaultIface 2>&1 >/dev/null | grep -c 'redacted [0-9]* secret' )"
if [ "$legoTally" -ge 1 ]; then ok "--lego (also signature-only) discloses its own tally"
else no "--lego redacted a contract signature but printed no stderr tally"; fi

# ── arm 11: both dialects stay well-formed after the substitution ──────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
  if printf '%s' "$XMLFOR" | xmllint --noout - 2>/dev/null; then ok "redacted XML is still well-formed (G4)"; else no "redacted XML fails xmllint"; fi
else
  no "xmllint is required for the G4 arm (install libxml2) — the gate does not skip"
fi
if printf '%s' "$JSONFOR" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then ok "redacted JSON still parses"; else no "redacted JSON no longer parses"; fi

# ── arm 12: determinism (redaction must not perturb ordering or content run-to-run) ────────────────
if [ "$( run --for="probeVaultLoader" )" = "$XMLFOR" ]; then ok "redacted XML is byte-identical run-to-run"; else no "redacted XML is not deterministic"; fi

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
