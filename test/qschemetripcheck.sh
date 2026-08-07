#!/usr/bin/env bash
# qschemetripcheck.sh — the F2/X4 SCHEME-BUMP TRIPWIRE. B10.1a (ffcc618) changed the SEMANTICS of a
# cached quality Snapshot's dead set (added `isTestScriptPath` to `isDeadCandidate`) WITHOUT bumping
# `kQSnapCacheScheme` — the exact determinism hole that constant's own comment exists to prevent (a pre-fix
# blob served to a post-fix binary answers with the OLD, narrower dead-set semantics). This gate is a
# deliberately noisy CHANGE-DETECTOR, not a correctness check: it hashes the concatenated source text of the
# small manifest of "what a cached Snapshot means" functions listed in the comment block right above
# `kQSnapCacheScheme` in src/quality.h, and compares against a pinned hash committed beside it
# (test/qschemetrip.hash). The manifest is read straight out of that comment (one place, no drift between the
# doc and this gate) — see quality.h's "TRIPWIRE (test/qschemetripcheck.sh)" paragraph to grow/shrink it.
#
# A mismatch means the concatenated text of isDeadCandidate / isFixturePath / isTestScriptPath /
# serializeSnapshot / deserializeSnapshot / computeSnapshot changed since the hash was last pinned. Answer,
# in the SAME diff that touched one of those functions:
#   - did the SEMANTICS of what a cached Snapshot represents change (what counts as dead, what a clone
#     group's identity is, the on-disk blob shape)? → bump kQSnapCacheScheme in src/quality.h, THEN re-pin.
#   - refactor-only (rename/reflow/comment edit, no behavior change)? → just re-pin.
# Re-pin:  UPDATE_GOLDEN=1 test/qschemetripcheck.sh
#
#
# r27 P0.2 — THE EXTRACTION SIDE. Until now this gate hashed six quality.h functions and NEVER looked at
# ingest.cpp, and that blind spot is exactly why the qsnap cache shipped un-keyed on the parser version:
# 28c7d32 bumped `kParserVer` 28 -> 30 (correcting 80 wrong canonical ids) and nothing here noticed, because
# nothing here was watching the file where a cached Snapshot's MEANING actually comes from. A Snapshot's whole
# contents are a function of tree-sitter extraction, so ingest.cpp's `kCacheVersion`/`kParserVer` declarations
# are now part of the hashed manifest: bumping either trips this gate, whose answer is "update quality.h's
# kIngest*Mirror constants in the SAME diff, then re-pin". `test/qextractionkeycheck.sh` asserts the resulting
# equality; this gate is what makes you look.
#
# This is a pure source-text check — it does not build or run the ripwire binary.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SRC="$ROOT/src/quality.h"
ING="$ROOT/src/ingest.cpp"
PIN="$ROOT/test/qschemetrip.hash"
# RE-PIN LOG (the pin is a bare hash, so its justification has to live here).
# 2026-08-07, essential complexity: kParserVer 43 -> 45 (44 was taken by the sibling nesting-quirk round;
#   see ingest.cpp's own note) and the quality.h mirror with it — RawDef/Symbol gained ev/evWhy (a def-record
#   FORMAT change) and Swift guard_statement joined isDecisionType (a Swift cx VALUE change). An EXTRACTION
#   change, not a Snapshot-SEMANTICS change, so kQSnapCacheScheme deliberately did NOT move.
# 2026-07-31, H4 W2b FIXUP: kParserVer 33 -> 34 and the
#   quality.h mirror with it, because a qualified call to a `>`-family OPERATOR now re-splits on the operator
#   tail — the per-ref qualifier changes, so a v33 blob's edges are provably wrong and must not be re-served.
#   This is an EXTRACTION change, not a Snapshot-SEMANTICS change: what a cached Snapshot MEANS (dead set,
#   clone-group identity, blob shape) is untouched, so kQSnapCacheScheme deliberately did NOT move.
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$SRC" ] || { echo "no $SRC — run from the repo"; exit 2; }
[ -f "$ING" ] || { echo "no $ING — run from the repo"; exit 2; }

sha256(){
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
    elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
    else echo "no sha256sum/shasum available" >&2; exit 2
    fi
}

# ── manifest: read straight out of the comment block above kQSnapCacheScheme (one place, no drift) ─────────
# lines shaped "//   <fnName>            (quality.h) — ..." between the "TRIPWIRE (...)" marker and the
# constant's own declaration.
MANIFEST="$( awk '
    /TRIPWIRE \(test\/qschemetripcheck\.sh\)/ { intrip=1; next }
    intrip && /^constexpr[ \t]+std::uint32_t[ \t]+kQSnapCacheScheme/ { exit }
    intrip && /^\/\/[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+\(quality\.h\)/ {
        line=$0
        sub( /^\/\/[ \t]+/, "", line )
        n=split( line, a, /[ \t]/ )
        print a[1]
    }
' "$SRC" )"

[ -n "$MANIFEST" ] && ok "manifest read from src/quality.h's tripwire comment ($( printf '%s\n' "$MANIFEST" | grep -c . ) functions)" \
    || { no "manifest extraction found ZERO functions — the comment shape near kQSnapCacheScheme moved; fix the awk pattern or the comment"; }

# ── extract one function's full Allman-style source ( signature line(s) .. matching closing brace ) ────────
# Depth-counting starts only once a line whose TRIMMED content is exactly "{" is seen (the true Allman body
# open) — this deliberately ignores any brace pairs on the signature line itself (e.g. a `= {}` default
# argument), which would otherwise terminate the extraction after one line. A candidate match whose line ends
# in ";" (a forward declaration/prototype, e.g. computeSnapshot's own fwd decl a few hundred lines above its
# definition) is skipped — scanning continues for the real, brace-bodied definition.
extract_fn(){
    local file="$1" fn="$2"
    awk -v fn="$fn" '
        BEGIN { capturing=0; bodyStarted=0; depth=0 }
        !capturing && $0 ~ ( "^inline[ \t].*[^A-Za-z0-9_]" fn "\\(" ) {
            probe=$0; sub( /\/\/.*/, "", probe ); gsub( /[ \t]+$/, "", probe )
            if( probe ~ /;$/ ) next                 # forward declaration/prototype — keep scanning
            capturing=1
        }
        capturing {
            print
            if( !bodyStarted )
            {
                t=$0; gsub( /^[ \t]+|[ \t]+$/, "", t )
                if( t == "{" ) { bodyStarted=1; depth=1 }
            }
            else
            {
                line=$0; o=gsub( /\{/, "{", line )
                line=$0; c=gsub( /\}/, "}", line )
                depth+=o-c
                if( depth<=0 ) { capturing=0; exit }
            }
        }
    ' "$file"
}

CONCAT=""
missing=0
for fn in $MANIFEST; do
    body="$( extract_fn "$SRC" "$fn" )"
    if [ -z "$body" ]; then
        no "manifest function '$fn' not found in src/quality.h (renamed/removed? update the manifest comment)"
        missing=1
        continue
    fi
    CONCAT="$CONCAT### $fn
$body
"
done
[ "$missing" -eq 0 ] && ok "every manifest function's source text extracted"

# ── r27 P0.2: the EXTRACTION-side manifest — ingest.cpp's two cache-identity DECLARATION LINES ─────────────
# Only the `constexpr ... = N;` line itself (comments and the long rationale blocks around them are excluded),
# so the hash moves when a VALUE moves and stays put when someone edits the prose. A trip here means: a cached
# Snapshot's meaning may have changed under you — mirror the new value into src/quality.h's
# kIngestCacheVersionMirror / kIngestParserVerMirror, then re-pin.
# (BSD sed has no BRE alternation — one pass per constant, in a fixed order so the hash is stable.)
extract_decl(){ sed -n "s/^\(constexpr[ \t][^=]*[ \t]$1[ \t]*=[ \t]*[0-9][0-9]*;\).*/\1/p" "$ING" | head -1; }
EXTRACT_DECLS="$( extract_decl kCacheVersion; extract_decl kParserVer )"
EXTRACT_N="$( printf '%s\n' "$EXTRACT_DECLS" | grep -c . )"
if [ "$EXTRACT_N" -eq 2 ]; then
    ok "ingest.cpp extraction-identity declarations extracted (kCacheVersion + kParserVer)"
else
    no "expected 2 extraction-identity declarations in src/ingest.cpp, found $EXTRACT_N — the constant shape moved; fix the sed pattern"
fi
CONCAT="$CONCAT### ingest.cpp extraction identity
$EXTRACT_DECLS
"

# ── H4 V1-L6: the CHURN-side identity — gitmine.h's merge-diff mode line ───────────────────────────────────
# The qchurn memo caches the OUTPUT of the git-log walks, and kMergeDiffArgs changes that stream's content
# for every merge commit — exactly the hole this gate exists to close, one file over (the H4 round shipped
# the -c change WITH a kQChurnCacheScheme bump; this arm makes forgetting that bump impossible next time).
# Declaration line only (value-sensitive, prose-insensitive), same policy as the ingest.cpp arm above.
GITM="$ROOT/src/gitmine.h"
MERGE_DECL="$( sed -n 's/^\(inline[ \t]constexpr[ \t][^=]*kMergeDiffArgs[ \t]*=[ \t]*"[^"]*";\).*/\1/p' "$GITM" | head -1 )"
if [ -n "$MERGE_DECL" ]; then
    ok "gitmine.h churn-identity declaration extracted (kMergeDiffArgs)"
else
    no "kMergeDiffArgs declaration not found in src/gitmine.h — the constant shape moved; fix the sed pattern"
fi
CONCAT="$CONCAT### gitmine.h churn identity
$MERGE_DECL
"

CURHASH="$( printf '%s' "$CONCAT" | sha256 )"

if [ ! -f "$PIN" ]; then
    if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
        printf '%s\n' "$CURHASH" > "$PIN"
        ok "pinned initial hash to test/qschemetrip.hash ($CURHASH)"
    else
        no "no pinned hash at test/qschemetrip.hash — create with UPDATE_GOLDEN=1 test/qschemetripcheck.sh"
    fi
else
    PINNED="$( tr -d ' \t\r\n' < "$PIN" )"
    if [ "$CURHASH" = "$PINNED" ]; then
        ok "manifest source hash matches the pinned hash (scheme=kQSnapCacheScheme unchanged meaning)"
    elif [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
        printf '%s\n' "$CURHASH" > "$PIN"
        ok "re-pinned test/qschemetrip.hash to $CURHASH (UPDATE_GOLDEN=1)"
    else
        no "manifest source text changed — pinned=$PINNED current=$CURHASH"
        cat <<'EOF'
        Did the SEMANTICS of what a cached Snapshot represents change (what counts as dead, a clone group's
        identity, the on-disk blob shape)?
          -> bump kQSnapCacheScheme in src/quality.h, THEN re-pin: UPDATE_GOLDEN=1 test/qschemetripcheck.sh
        Did ingest.cpp's kCacheVersion / kParserVer move (an EXTRACTION change — every cached canonId, metric,
        body hash, clone group and dead-set entry is a function of it)?
          -> mirror the new value into src/quality.h's kIngestCacheVersionMirror / kIngestParserVerMirror in
             the SAME diff (test/qextractionkeycheck.sh asserts the equality), THEN re-pin.
        Refactor-only (rename/reflow/comment edit, no behavior change)?
          -> just re-pin:            UPDATE_GOLDEN=1 test/qschemetripcheck.sh
EOF
    fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
