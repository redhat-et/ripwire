#!/usr/bin/env bash
# traceminecheck.sh — the gate for DESIGN_traceEvals.md's session-trace-mined eval (bench/mine_traces.py
# + --eval-mined). Four checks, per the design's §6:
#   1) miner determinism on a checked-in synthetic fixture (test/traceminefix/sample_session.jsonl) —
#      two runs byte-identical; exact pair count / gold set / ctxpack_assisted flag asserted by value.
#      The fixture exercises: a real user turn, a synthetic tool_result-only "user" event (must be
#      filtered), an in-repo Edit, a scratchpad Write (must be excluded), a Read (must never gold), a
#      reverted Edit pair (must drop), a ctxpack-Bash call (must set ctxpack_assisted=true), and a
#      second segment triggered by a later real user turn (boundary-after-edit rule).
#   2) privacy gate — the miner refuses to write inside the target repo without --export-sanitized
#      (non-zero exit AND no file created); with --export-sanitized it succeeds and the verbatim query
#      text is NOT byte-present in the sanitized output.
#   3) metric-parity — --eval-mined on a 1-pair fixture over test/fixture (gold = ALL 6 corpus files)
#      must print recall@10/@20 == Acc@10/@20 == 100.0% for every arm (hand-computable: with F=6 <10<20,
#      ANY top-10/top-20 cut trivially contains every file) — proving --eval-mined calls the same
#      recallAtK/rankFiles every other eval mode uses, not a drifted reimplementation.
#   4) det-gate — --eval-mined stdout is byte-identical run-to-run.
#
# Usage:  CTXPACK_BIN=build/ctxpack test/traceminecheck.sh   (needs python3; git optional)
# Exits non-zero on any failure. Does NOT edit regression.sh or ~/.claude.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
MINER="$ROOT/bench/mine_traces.py"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
[ -f "$MINER" ] || { echo "no miner at $MINER"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "traceminecheck: BIN=$BIN  MINER=$MINER"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── Gate 1: miner determinism + exact structural assertions on the checked-in fixture ──────────────────
REPO="/repo"                                    # a purely-STRING repo root — the fixture's file_paths
SLUG="$( printf '%s' "$REPO" | sed -e 's/[/.]/-/g' )"
SESSDIR="$TMP/home/.claude/projects/$SLUG"
mkdir -p "$SESSDIR"
cp "$ROOT/test/traceminefix/sample_session.jsonl" "$SESSDIR/sample_session.jsonl"

HOME="$TMP/home" python3 "$MINER" --repo "$REPO" --out "$TMP/mined1.jsonl" >/dev/null 2>&1; rc1=$?
HOME="$TMP/home" python3 "$MINER" --repo "$REPO" --out "$TMP/mined2.jsonl" >/dev/null 2>&1; rc2=$?

{ [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; } && ok "miner runs cleanly (exit 0 both runs)" || no "miner exit != 0 (rc1=$rc1 rc2=$rc2)"
diff -q "$TMP/mined1.jsonl" "$TMP/mined2.jsonl" >/dev/null 2>&1 && ok "miner determinism (byte-identical, no wall-clock)" \
    || { no "miner non-deterministic"; diff "$TMP/mined1.jsonl" "$TMP/mined2.jsonl" | head -8; }

NPAIRS="$( wc -l < "$TMP/mined1.jsonl" | tr -d ' ' )"
[ "$NPAIRS" = "2" ] && ok "exactly 2 mined pairs (2-edit segment + follow-up segment; reverted/scratchpad/read excluded)" \
                     || no "expected 2 mined pairs, got $NPAIRS"

PY_ASSERT="$( python3 - "$TMP/mined1.jsonl" <<'PYEOF'
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
if len(recs) != 2:
    print("BAD count"); sys.exit(0)
a, b = recs[0], recs[1]
checks = []
checks.append(("pair1 gold == {src/a.py, src/b.py}", sorted(g["path"] for g in a["gold_files"]) == ["src/a.py", "src/b.py"]))
checks.append(("pair1 excludes src/c.py (Read)", all(g["path"] != "src/c.py" for g in a["gold_files"])))
checks.append(("pair1 excludes src/d.py (reverted Edit)", all(g["path"] != "src/d.py" for g in a["gold_files"])))
checks.append(("pair1 excludes the scratchpad Write", all("scratchpad" not in g["path"] for g in a["gold_files"])))
checks.append(("pair1 ctxpack_assisted == true", a["ctxpack_assisted"] is True))
checks.append(("pair2 gold == {CHANGELOG.md, VERSION}", sorted(g["path"] for g in b["gold_files"]) == ["CHANGELOG.md", "VERSION"]))
checks.append(("pair2 ctxpack_assisted == false", b["ctxpack_assisted"] is False))
checks.append(("no query contains harness task-notification text (origin.kind filter)",
               all("task-notification" not in r["query"] for r in recs)))
checks.append(("miner_version == 1 on both", a["miner_version"] == 1 and b["miner_version"] == 1))
checks.append(("no wall-clock field anywhere", "mined_at" not in a and "mined_at" not in b))
ok = all(v for _, v in checks)
for name, v in checks:
    print(("PASS " if v else "FAIL ") + name)
sys.exit(0 if ok else 1)
PYEOF
)"
echo "$PY_ASSERT" | while IFS= read -r line; do
    case "$line" in
        PASS*) : ;;   # summarized below
        FAIL*) : ;;
    esac
done
if echo "$PY_ASSERT" | grep -q '^FAIL'; then
    no "structural assertions on the mined fixture (see below)"
    echo "$PY_ASSERT" | sed 's/^/     /'
else
    ok "structural assertions on the mined fixture (gold sets, exclusions, assisted flag, miner_version, no wall-clock)"
fi

# ── Gate 2: privacy — refuse in-repo without --export-sanitized; succeed + redact with it ──────────────
REPO2="$TMP/repo2"
mkdir -p "$REPO2"
SLUG2="$( printf '%s' "$REPO2" | sed -e 's/[/.]/-/g' )"
SESSDIR2="$TMP/home/.claude/projects/$SLUG2"
mkdir -p "$SESSDIR2"
QTEXT="a distinctive verbatim probe phrase that must never leak into a sanitized export"
cat > "$SESSDIR2/s1.jsonl" <<EOF
{"type":"user","message":{"role":"user","content":"$QTEXT"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"$REPO2/x.py","old_string":"a","new_string":"b"}},{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"$REPO2/y.py","old_string":"a","new_string":"b"}}]}}
EOF

HOME="$TMP/home" python3 "$MINER" --repo "$REPO2" --out "$REPO2/mined.jsonl" >/dev/null 2>"$TMP/priv1.err"
rc_priv1=$?
{ [ "$rc_priv1" -ne 0 ] && [ ! -e "$REPO2/mined.jsonl" ]; } \
    && ok "privacy gate: --out <in-repo> without --export-sanitized refuses (exit=$rc_priv1, no file created)" \
    || no "privacy gate: expected non-zero exit AND no file (exit=$rc_priv1, exists=$( [ -e "$REPO2/mined.jsonl" ] && echo y || echo n ))"

HOME="$TMP/home" python3 "$MINER" --repo "$REPO2" --export-sanitized "$REPO2/mined.jsonl" >/dev/null 2>"$TMP/priv2.err"
rc_priv2=$?
{ [ "$rc_priv2" -eq 0 ] && [ -e "$REPO2/mined.jsonl" ]; } \
    && ok "privacy gate: --export-sanitized to an in-repo path succeeds" \
    || no "privacy gate: --export-sanitized failed (exit=$rc_priv2)"
if [ -e "$REPO2/mined.jsonl" ]; then
    if grep -qF "$QTEXT" "$REPO2/mined.jsonl"; then
        no "privacy gate: sanitized export byte-CONTAINS the verbatim query text (redaction failed)"
    else
        ok "privacy gate: sanitized export does NOT contain the verbatim query text"
    fi
    grep -q '"session_id"' "$REPO2/mined.jsonl" \
        && no "privacy gate: sanitized export still carries session_id" \
        || ok "privacy gate: sanitized export drops session_id"
fi

# ── Gate 3: metric-parity — recall@10/@20 == Acc@10/@20 == 100.0% for every arm (F=6, hand-computable) ──
run_mined(){ perl -e 'alarm 30; exec @ARGV' "$BIN" test/fixture --eval-mined=test/traceminefix/expected.jsonl --no-cache 2>/dev/null; }
cd "$ROOT"
EM="$( run_mined )"
NON100="$( printf '%s\n' "$EM" | awk '
    $1=="for" || $1=="query" || $1=="anchor" {
        # columns: name recall@5 recall@10 recall@20 acc@5 acc@10 acc@20 mrr
        r10=$3; r20=$4; a10=$6; a20=$7
        gsub(/%/,"",r10); gsub(/%/,"",r20); gsub(/%/,"",a10); gsub(/%/,"",a20)
        if( r10+0 != 100 || r20+0 != 100 || a10+0 != 100 || a20+0 != 100 ) print $1"(r10="r10" r20="r20" a10="a10" a20="a20")"
    }' )"
{ [ -n "$EM" ] && [ -z "$NON100" ]; } \
    && ok "metric-parity: recall@10/@20 == acc@10/@20 == 100.0% for every arm (F=6 gold=6, hand-computable)" \
    || { no "metric-parity: expected 100.0% recall@10/@20 and acc@10/@20 for every arm"; echo "$NON100"; printf '%s\n' "$EM" | sed 's/^/     /'; }

# ── Gate 4: det-gate — --eval-mined stdout byte-identical run-to-run ─────────────────────────────────
[ "$( run_mined )" = "$( run_mined )" ] && ok "--eval-mined deterministic (byte-identical run-to-run)" || no "--eval-mined non-deterministic"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
