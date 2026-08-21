#!/usr/bin/env bash
# mentioncheck.sh — B8: the query-mention anchor on the --for lens.
#
# Default-on: a file, dotted module, or Scope.symbol literally NAMED in the task text is lifted to just
# below the top hit. Pinned promises (each measured in the 4-arm head-to-head as the #1 loss bucket):
#   (i)   SIGNAL — a path mention ("pkg/beta.py"), a URL-embedded mention, a dotted module ("pkg.beta"),
#         and a Scope.symbol mention ("Widget.render") each lift the named target into the top ranks,
#         while the same query WITHOUT the boost leaves it low/absent.
#   (ii)  NEVER DISPLACES #1 — the top-1 candidate is identical boost-on vs boost-off.
#   (iii) INERT WITHOUT MENTIONS — prose that names nothing indexed (incl. "e.g." / version numbers) is
#         BYTE-IDENTICAL boost-on vs boost-off.
#   (iv)  SCOPE — --query and --for --no-route are untouched even with the boost active.
#   (v)   DETERMINISM ×3, xmllint-clean, env (RIPWIRE_NO_MENTION=1) == flag (--no-mention-boost)
#         byte-for-byte, and the flag alone refuses loudly.
#   (vi)  PACKAGE-DIR MENTION — a backticked bare name or dotted chain that names a source DIRECTORY
#         (not a file) lifts that package's index file (__init__.py & friends). Measured: r2 head-to-head
#         loss micropython-lib-947 (gold requests/__init__.py at 35; the `requests` mention anchored
#         nothing). Precision-first: only the dir's index file lifts, never the whole directory.
#
# Usage:  bash test/mentioncheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/mentioncheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "mentioncheck: BIN=$BIN"

# ── fixture: no git needed — the anchor is pure string work over the INDEX ──────────────────────────
# pkg/alpha.py holds the strong lexical matches; pkg/beta.py shares NO word with any query prose (its
# rank without an anchor is low); root-level delta.py holds Widget.render for the Scope.symbol case.
FIX="$TMP/fix"
mkdir -p "$FIX/pkg"
cat > "$FIX/pkg/alpha.py" <<'PY'
def widget_pipeline_process(records):
    """Process widget records through the pipeline."""
    return [r for r in records if r]

def widget_records_pipeline(records):
    """Pipeline stage: validate widget records."""
    return records

def process_widget_records(records):
    """Process the records for each widget in the pipeline."""
    return len(records)
PY
cat > "$FIX/pkg/beta.py" <<'PY'
def flush_stale_cache(entries):
    """Evict stale cache entries."""
    return [e for e in entries if e.fresh]
PY
mkdir -p "$FIX/plugins/requests"
cat > "$FIX/plugins/requests/__init__.py" <<'PY'
def open_http_session(url):
    """Create the session used for outbound calls."""
    return url

def encode_basic_credentials(user, pw):
    """Base64 header assembly for outbound calls."""
    return user + pw
PY
cat > "$FIX/delta.py" <<'PY'
class Widget:
    def render(self):
        """Draw the widget."""
        return "ok"

    def hidden_helper(self):
        return 1
PY

cands(){ "$BIN" "$FIX" --for="$1" --format=candidates --top-k=20 --no-cache "${@:2}" 2>/dev/null; }
rankOf(){ printf '%s' "$1" | grep -o "<cand r=\"[0-9]*\" [^>]*n=\"$2\"" | grep -o 'r="[0-9]*"' | grep -o '[0-9]*' | head -1; }

# ── (i) signal, four mention shapes ──────────────────────────────────────────────────────────────────
sig(){ # $1=label $2=query $3=expected-symbol
    ON="$( cands "$2" )"; OFF="$( cands "$2" --no-mention-boost )"
    rOn="$( rankOf "$ON" "$3" )"; rOff="$( rankOf "$OFF" "$3" )"
    if [ -n "$rOn" ] && [ "$rOn" -le 5 ] && { [ -z "$rOff" ] || [ "$rOn" -lt "$rOff" ]; }; then
        ok "$1: $3 lifted to rank $rOn (default) vs ${rOff:-absent} (--no-mention-boost)"
    else no "$1: expected a lift (on=${rOn:-absent} off=${rOff:-absent})"; fi
}
sig "path mention"      "widget pipeline process records — the fix belongs in pkg/beta.py"                       flush_stale_cache
sig "URL mention"       "widget pipeline process records, see https://github.com/x/y/blob/main/pkg/beta.py#L2"   flush_stale_cache
sig "dotted module"     "widget pipeline process records regression traced to pkg.beta"                          flush_stale_cache
sig "Scope.symbol"      "widget pipeline process records break inside Widget.render"                             render

# ── (vi) package-dir mention: bare backticked name / dotted chain naming a DIRECTORY ─────────────────
sig "pkg-dir backtick"  'widget pipeline process records leak inside the `requests` module'                      open_http_session
sig "pkg-dir dotted"    "widget pipeline process records regression traced to plugins.requests"                   open_http_session
# a backticked word matching NO directory stays inert (precision guard)
ONX="$( cands 'widget pipeline process records inside the `nonexistentpkg` module' )"
OFFX="$( cands 'widget pipeline process records inside the `nonexistentpkg` module' --no-mention-boost )"
[ "$ONX" = "$OFFX" ] && ok "unmatched backtick stays inert" || no "unmatched backtick moved the ranking"

# header note appears when (and only when) something anchored
"$BIN" "$FIX" --for="widget pipeline in pkg/beta.py" --no-cache 2>/dev/null | grep -q 'mention anchor:' \
    && ok "--for header names the anchor" || no "--for header note missing"

# ── (ii) never displaces #1 ──────────────────────────────────────────────────────────────────────────
ON="$( cands "widget pipeline process records — the fix belongs in pkg/beta.py" )"
OFF="$( cands "widget pipeline process records — the fix belongs in pkg/beta.py" --no-mention-boost )"
top1on="$( printf '%s' "$ON" | grep -o '<cand r="1" [^>]*id="[^"]*"' )"
top1off="$( printf '%s' "$OFF" | grep -o '<cand r="1" [^>]*id="[^"]*"' )"
[ -n "$top1on" ] && [ "$top1on" = "$top1off" ] && ok "top-1 identical boost-on vs boost-off" \
    || no "top-1 displaced:  ON<<$top1on>>  OFF<<$top1off>>"

# ── (iii) inert without mentions (incl. dotted-prose false-positive guards: e.g., i.e., 3.10) ────────
Q_PLAIN="widget pipeline process records, e.g. python 3.10 i.e. the usual"
"$BIN" "$FIX" --for="$Q_PLAIN" --no-cache >"$TMP/p1.xml" 2>/dev/null
"$BIN" "$FIX" --for="$Q_PLAIN" --no-mention-boost --no-cache >"$TMP/p2.xml" 2>/dev/null
cmp -s "$TMP/p1.xml" "$TMP/p2.xml" && ok "inert on mention-free prose (byte-identical, e.g./3.10 ignored)" \
    || no "NOT inert on mention-free prose"
grep -q 'mention anchor:' "$TMP/p1.xml" && no "header note must not appear when nothing anchored" \
    || ok "no header note when nothing anchored"

# ── (iv) scope: --query and --no-route untouched even when active ────────────────────────────────────
QM="widget pipeline in pkg/beta.py"
"$BIN" "$FIX" --query="$QM" --no-cache >"$TMP/q1.xml" 2>/dev/null
RIPWIRE_NO_MENTION=1 "$BIN" "$FIX" --query="$QM" --no-cache >"$TMP/q2.xml" 2>/dev/null
cmp -s "$TMP/q1.xml" "$TMP/q2.xml" && ok "--query path untouched" || no "--query path affected"
"$BIN" "$FIX" --for="$QM" --no-route --no-cache >"$TMP/nr1.xml" 2>/dev/null
"$BIN" "$FIX" --for="$QM" --no-route --no-mention-boost --no-cache >"$TMP/nr2.xml" 2>/dev/null
cmp -s "$TMP/nr1.xml" "$TMP/nr2.xml" && ok "--no-route path keeps its pre-routing bytes" \
    || no "--no-route path affected"

# ── (v) determinism ×3, xmllint, env==flag, refuse-loudly ────────────────────────────────────────────
"$BIN" "$FIX" --for="$QM" --no-cache >"$TMP/d1.xml" 2>/dev/null
"$BIN" "$FIX" --for="$QM" --no-cache >"$TMP/d2.xml" 2>/dev/null
"$BIN" "$FIX" --for="$QM" --no-cache >"$TMP/d3.xml" 2>/dev/null
cmp -s "$TMP/d1.xml" "$TMP/d2.xml" && cmp -s "$TMP/d2.xml" "$TMP/d3.xml" && ok "determinism x3 (anchored)" \
    || no "anchored output not deterministic"
if command -v xmllint >/dev/null; then
    xmllint --noout "$TMP/d1.xml" 2>/dev/null && ok "anchored bundle is xmllint-clean (G4)" || no "anchored bundle not well-formed"
else ok "xmllint not present — skipped (G4 covered by xmlwellformed.sh)"; fi
"$BIN" "$FIX" --for="$QM" --no-mention-boost --no-cache >"$TMP/f1.xml" 2>/dev/null
RIPWIRE_NO_MENTION=1 "$BIN" "$FIX" --for="$QM" --no-cache >"$TMP/f2.xml" 2>/dev/null
cmp -s "$TMP/f1.xml" "$TMP/f2.xml" && ok "RIPWIRE_NO_MENTION=1 == --no-mention-boost (byte-identical)" \
    || no "env disable and flag disable diverge"
"$BIN" "$FIX" --no-mention-boost >/dev/null 2>"$TMP/refuse.err"
[ $? -ne 0 ] && grep -q 'no-mention-boost' "$TMP/refuse.err" && ok "flag alone refuses loudly" || no "flag alone did not refuse"

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
