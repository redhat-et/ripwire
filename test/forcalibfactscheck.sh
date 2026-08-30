#!/usr/bin/env bash
# forcalibfactscheck.sh — gate for the abstention round-2 instrumentation registered in docs/EVALS.md
# ("Agent Retrieval Bench — abstention round 2: the adaptive cut's corpus-support facts",
# PRE-REGISTERED 2026-08-30).
#
# WHAT IT PINS, and why each arm exists rather than being obvious.
#
#   (1) The three facts are PRESENT on `--for --json` and are integers. `kept`/`scored`/`corpus` are the
#       adaptive cut's own counts (AdaptiveCut::kept, ::positiveHits, and the length of the lens rank
#       vector). Before this round they were computed on every --for run and emitted on no surface at all,
#       which is exactly why the first abstention calibration could not test them.
#
#   (2) They are ALWAYS present, including on a query that matches nothing — `scored:0`, not a dropped
#       key. This is the house honesty rule (a zero means "none found", never "the field went missing");
#       a harness cannot tell an absent key from a zero, and the calibration's signal_missing bucket has
#       to mean a failed invocation, not a sharp query.
#
#   (3) The counts AGREE with the cut the tool acts on. Under `--adaptive` the header note states the
#       kept count in prose ("kept N of 40"); the emitted `kept` must be that same N. If these two ever
#       drift, the calibration is measuring a statistic the tool does not use, and nothing downstream
#       would say so.
#
#   (4) The arithmetic invariants the calibration's denominator depends on: 0 < corpus, scored <= corpus,
#       1 <= kept <= 40 (the default --for ceiling). `support = scored/corpus` is the registered PRIMARY
#       statistic, so a corpus of 0 or a scored > corpus would silently produce a garbage AUROC.
#
#   (5) The JSON-ONLY contract. These are harness-facing instrumentation for a round that may well close
#       as a second recorded negative, so the XML bundle must NOT grow them: its header rides a measured
#       byte ceiling (fornotesbudgetcheck.sh fits at est_tokens=800 exactly) and MCP `for` serves that
#       same XML. This arm fails if any of the three names appears as an XML root attribute — i.e. it is
#       the gate that makes "promote them only if the calibration earns it" a mechanical fact rather than
#       an intention in a comment.
#
#   (6) Determinism: two runs of the JSON dialect are byte-identical (the contract, and the harness's own
#       sweep gate compares these facts between two runs before trusting a sweep).
#
# Usage: bash test/forcalibfactscheck.sh [path/to/ripwire]
# Exits non-zero on any failure. Read-only: touches no fixture and no checked-in file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # house convention: the suite passes the binary via RIPWIRE_BIN
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "forcalibfactscheck: BIN=$BIN  ROOT=$ROOT"

# ── (1)(4) present, integral, and arithmetically sane on an ordinary conceptual query ─────────────────
"$BIN" "$ROOT" --for="adaptive cut relevance cliff" --json > "$TMP/hit.json" 2>/dev/null
python3 - "$TMP/hit.json" > "$TMP/hit.txt" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
missing = [k for k in ("kept", "scored", "corpus") if k not in doc]
print("missing", ",".join(missing) if missing else "-")
vals = {k: doc.get(k) for k in ("kept", "scored", "corpus")}
print("integral", all(isinstance(v, int) and not isinstance(v, bool) for v in vals.values()))
# absent/non-integer prints as -1 so the shell arms below stay integer comparisons and report a real
# FAIL rather than dying with "integer expression expected" — a gate whose own arms error out reads as
# infrastructure noise exactly when it is telling the truth.
for k in ("kept", "scored", "corpus"):
    v = vals[k]
    print(k, v if isinstance(v, int) and not isinstance(v, bool) else -1)
PY
grep -q '^missing -$' "$TMP/hit.txt" \
  && ok "kept/scored/corpus all present on --for --json" \
  || no "a calibration fact is missing from --for --json: $( grep '^missing ' "$TMP/hit.txt" )"
grep -q '^integral True$' "$TMP/hit.txt" \
  && ok "all three are JSON integers (a harness can divide with them)" \
  || no "kept/scored/corpus are not all integers"

kept="$(   awk '$1=="kept"   {print $2}' "$TMP/hit.txt" )"
scored="$( awk '$1=="scored" {print $2}' "$TMP/hit.txt" )"
corpus="$( awk '$1=="corpus" {print $2}' "$TMP/hit.txt" )"
[ "${corpus:-0}" -gt 0 ] \
  && ok "corpus > 0 ($corpus) — the registered support denominator is usable" \
  || no "corpus is $corpus: support = scored/corpus would divide by zero"
[ "${scored:-0}" -le "${corpus:-0}" ] \
  && ok "scored ($scored) <= corpus ($corpus) — support stays in [0,1]" \
  || no "scored ($scored) exceeds corpus ($corpus)"
{ [ "${kept:-0}" -ge 1 ] && [ "${kept:-0}" -le 40 ]; } \
  && ok "kept ($kept) inside [1, 40], the default --for ceiling" \
  || no "kept ($kept) outside [1, 40]"

# ── (2) a query that matches nothing still MEASURES: scored is 0, the key is not dropped ──────────────
"$BIN" "$ROOT" --for="zzqqxx nonexistentgibberishtoken" --json > "$TMP/miss.json" 2>/dev/null
python3 - "$TMP/miss.json" > "$TMP/miss.txt" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
print("haskeys", all(k in doc for k in ("kept", "scored", "corpus")))
print("scored", doc.get("scored", "absent"))
print("corpus", doc.get("corpus", "absent"))
PY
grep -q '^haskeys True$' "$TMP/miss.txt" \
  && ok "a zero-hit query still emits all three (a 0 is a measurement, not a dropped key)" \
  || no "the calibration facts vanish on a zero-hit query — absent is indistinguishable from zero"
grep -q '^scored 0$' "$TMP/miss.txt" \
  && ok "zero-hit query reports scored=0" \
  || no "zero-hit query reports $( grep '^scored ' "$TMP/miss.txt" ), expected scored 0"
grep -qv '^corpus 0$' "$TMP/miss.txt" \
  && ok "corpus is still the whole scored index on a zero-hit query" \
  || no "corpus collapsed to 0 on a zero-hit query"

# ── (3) the emitted kept IS the cut --adaptive acts on (prose note vs emitted fact) ───────────────────
"$BIN" "$ROOT" --for="deriveForConfidence" --adaptive --json > "$TMP/adap.json" 2>/dev/null
python3 - "$TMP/adap.json" > "$TMP/adap.txt" <<'PY'
import json, re, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
note = doc.get("adaptive") or ""
m = re.search(r"kept (\d+) of", note)
print("note_kept", m.group(1) if m else "-")
fk = doc.get("kept")
print("fact_kept", fk if isinstance(fk, int) and not isinstance(fk, bool) else "absent")
PY
note_kept="$( awk '$1=="note_kept" {print $2}' "$TMP/adap.txt" )"
fact_kept="$( awk '$1=="fact_kept" {print $2}' "$TMP/adap.txt" )"
if [ "$note_kept" = "-" ]; then
  no "--adaptive emitted no 'kept N of M' note to cross-check the fact against"
elif [ "$note_kept" = "$fact_kept" ]; then
  ok "emitted kept ($fact_kept) equals the cut --adaptive states in its own note"
else
  no "emitted kept ($fact_kept) disagrees with --adaptive's note ($note_kept) — the fact is not the acted-on cut"
fi

# ── (5) JSON-ONLY: the XML root must not have grown any of the three ─────────────────────────────────
"$BIN" "$ROOT" --for="adaptive cut relevance cliff" > "$TMP/hit.xml" 2>/dev/null
root_open="$( head -c 4000 "$TMP/hit.xml" | sed 's/>.*//' )"
xml_leak=0
for attr in kept scored corpus; do
  case "$root_open" in
    *" $attr=\""*) no "the XML <ctx> root grew $attr= — round-2 instrumentation is JSON-only until the calibration earns promotion"; xml_leak=1 ;;
  esac
done
[ "$xml_leak" -eq 0 ] && ok "XML root carries none of kept=/scored=/corpus= (the harness-only contract holds)"

# ── (6) determinism on the instrumented dialect ──────────────────────────────────────────────────────
"$BIN" "$ROOT" --for="adaptive cut relevance cliff" --json > "$TMP/d1.json" 2>/dev/null
"$BIN" "$ROOT" --for="adaptive cut relevance cliff" --json > "$TMP/d2.json" 2>/dev/null
cmp -s "$TMP/d1.json" "$TMP/d2.json" \
  && ok "two --for --json runs are byte-identical" \
  || no "--for --json is not deterministic across runs"

if [ "$fail" -eq 0 ]; then
  echo "forcalibfactscheck: ALL PASS"
else
  echo "forcalibfactscheck: FAILURES above"
fi
exit "$fail"
