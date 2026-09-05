#!/usr/bin/env bash
# formatgatecheck.sh — F1 (terminality round A, 2026-09-05): put scripts/formatcheck.sh INSIDE the battery.
#
# WHY. `scripts/formatcheck.sh` is a real gate — CI runs it as its own `style` job — but nothing in
# test/regression.sh or test/pargates.py ever called it, so a local battery could be 100% green while the
# style leg of CI was red. That happened on 2026-09-05: `src/graphlegend.h` (a GATED file) lost its
# clang-format byte parity, every local gate passed, and CI run 33976909146 came back red on style alone;
# the fix commit is 8eb669ff. This gate closes that hole: the battery now answers the style question too.
#
# WHY IT CAN SKIP, AND WHY THAT IS NOT A PASS. `.clang-format` was produced and verified with clang-format
# major 22 and formatcheck.sh refuses any other major (different majors format differently, so an unpinned
# run reports false drift on a correctly-formatted tree). clang-format is NOT a build dependency of this
# repo (G3: no host-installed dependencies), so a developer machine legitimately may not have major 22.
# When it does not, this gate prints a `SKIP` line naming BOTH the version it needs and the version it
# found, and exits 0 — pargates.py counts an rc=0 run whose first 400 chars contain "SKIP" as a SKIP, not
# as a pass ("A gate that SKIPS is not a gate that PASSED"), so an absent clang-format can never be read as
# a clean style leg. The pin itself is read out of formatcheck.sh (WANT_MAJOR), never hardcoded here, so
# the two cannot drift apart.
#
# ARMS
#   (A) scripts/formatcheck.sh exists, is executable, and declares a WANT_MAJOR pin.
#   (B) --list names at least one file and every named path exists in the tree (a deleted gated path is
#       the silent way the list rots).
#   (C) THE GATE: scripts/formatcheck.sh (gate mode) exits 0 over this tree. This is the arm that would
#       have been red at 8eb669ff~1.
#   (D) CAN-GO-RED, on the REAL mechanism: a throwaway copy of formatcheck.sh in a temp root whose GATED
#       list is rewritten to one deliberately misformatted file must exit non-zero and name that file —
#       then, with the same file formatted in place, exit 0. Only the file list is patched; the version
#       pin, the dry-run --Werror invocation and the reporting are byte-identical to production. Without
#       this arm a formatcheck.sh that had silently become a no-op (an emptied GATED list, a swallowed rc)
#       would keep arm (C) green forever.
#   (E) --advisory never gates: in the same temp root, with a file it would rewrite, it exits 0.
#
# Usage: bash test/formatgatecheck.sh      (no ripwire binary needed — this gates the formatter, not the
#                                            binary under test). CLANG_FORMAT=/path overrides the binary.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
FC="$ROOT/scripts/formatcheck.sh"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$FC" ] || { echo "formatgatecheck: no scripts/formatcheck.sh at $FC"; exit 2; }

# ── the version pin, read out of the script under test (never hardcoded here) ────────────────────────
WANT_MAJOR="$( sed -n 's/^WANT_MAJOR=\([0-9][0-9]*\).*$/\1/p' "$FC" | head -1 )"

# ── resolve a clang-format (V1 I5, wave-1 verifier 2026-09-05) ───────────────────────────────────────
# The order used to be CLANG_FORMAT -> /opt/homebrew/opt/llvm/bin/clang-format -> PATH, unconditionally,
# so a machine carrying the PINNED major on PATH and a DIFFERENT major at the homebrew path SKIPped a
# gate it could have run. The SKIP was honest either way, which is why this is a note and not a defect —
# but the ordering was an accident, and it is now a decision: an explicitly named CLANG_FORMAT always
# wins (right or wrong — naming one is a choice, and silently overriding it would be worse); otherwise
# the candidate that can ACTUALLY RUN the gate wins; only then the historical macOS fallback.
#
# pick_cf is PURE — it takes the three candidates and their measured majors and never touches the
# filesystem — so arm (F) below can exercise the ordering itself on synthetic triples, which is the only
# way a resolution that depends on what a machine happens to have installed can be gated at all.
pick_cf()
{   # pick_cf ENV_PATH ENV_MAJOR PATH_PATH PATH_MAJOR BREW_PATH BREW_MAJOR WANT -> "<path>|<major>"
    if [ -n "$1" ]; then         printf '%s|%s' "$1" "$2"          # named explicitly: always wins
    elif [ -n "$4" ] && [ "$4" = "$7" ]; then printf '%s|%s' "$3" "$4"   # PATH has the pinned major: run
    elif [ -n "$5" ]; then       printf '%s|%s' "$5" "$6"          # homebrew LLVM (not on PATH on macOS)
    else                         printf '%s|%s' "$3" "$4"          # whatever PATH has, so the SKIP names it
    fi
}

cf_major(){ [ -n "${1:-}" ] && command -v "$1" >/dev/null 2>&1 && "$1" --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9]*\).*/\1/p' | head -1; }

CAND_ENV="${CLANG_FORMAT:-}"
CAND_PATH="$( command -v clang-format 2>/dev/null || true )"
CAND_BREW=""
[ -x /opt/homebrew/opt/llvm/bin/clang-format ] && CAND_BREW=/opt/homebrew/opt/llvm/bin/clang-format
MAJ_ENV="$( cf_major "$CAND_ENV" )"
MAJ_PATH="$( cf_major "$CAND_PATH" )"
MAJ_BREW="$( cf_major "$CAND_BREW" )"
PICKED="$( pick_cf "$CAND_ENV" "$MAJ_ENV" "$CAND_PATH" "$MAJ_PATH" "$CAND_BREW" "$MAJ_BREW" "$WANT_MAJOR" )"
CF="${PICKED%%|*}"
have="${PICKED#*|}"

# every candidate and the major found at it, so a SKIP says what the machine actually has and where
CANDS="CLANG_FORMAT=[${CAND_ENV:-unset}${MAJ_ENV:+ major $MAJ_ENV}] PATH=[${CAND_PATH:-none}${MAJ_PATH:+ major $MAJ_PATH}] homebrew=[${CAND_BREW:-none}${MAJ_BREW:+ major $MAJ_BREW}]"

# ── the SKIP, with the reason spelled out (pargates.py reads "SKIP" in the first 400 chars) ──────────
if [ -z "$WANT_MAJOR" ]; then
    echo "formatgatecheck: could not read WANT_MAJOR out of scripts/formatcheck.sh — the pin this gate reports on is gone"
    exit 1
fi
if [ -z "$have" ]; then
    printf '  SKIP  formatgatecheck: needs clang-format major %s (the version .clang-format was produced and verified with); found NONE — %s. Install LLVM %s or set CLANG_FORMAT=/path/to/clang-format. NOTHING WAS CHECKED.\n' "$WANT_MAJOR" "$CANDS" "$WANT_MAJOR"
    exit 0
fi
if [ "$have" != "$WANT_MAJOR" ]; then
    printf '  SKIP  formatgatecheck: needs clang-format major %s (the version .clang-format was produced and verified with); found major %s at %s — %s. Different majors format differently, so running anyway would report false drift. NOTHING WAS CHECKED.\n' "$WANT_MAJOR" "$have" "$CF" "$CANDS"
    exit 0
fi

echo "formatgatecheck: CF=$CF (major $have, pinned $WANT_MAJOR)  FC=$FC"

# ── (A) ──────────────────────────────────────────────────────────────────────────────────────────────
[ -x "$FC" ] && ok "(A) scripts/formatcheck.sh is executable" \
             || no "(A) scripts/formatcheck.sh is not executable (CI invokes it directly)"

# ── (B) the gated list is non-empty and every path still exists ──────────────────────────────────────
listed="$( CLANG_FORMAT="$CF" bash "$FC" --list 2>/dev/null | grep -c . )"
if [ "${listed:-0}" -lt 1 ]; then
    no "(B) scripts/formatcheck.sh --list named NO files — the gate would be vacuously green"
else
    missing=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$ROOT/$f" ] || missing="$missing $f"
    done < <( CLANG_FORMAT="$CF" bash "$FC" --list 2>/dev/null )
    [ -z "$missing" ] && ok "(B) --list names $listed file(s), all present on disk" \
                      || no "(B) --list names path(s) that no longer exist:$missing"
fi

# ── (C) THE GATE over this tree ──────────────────────────────────────────────────────────────────────
gateOut="$( CLANG_FORMAT="$CF" bash "$FC" 2>&1 )"
gateRc=$?
if [ "$gateRc" -eq 0 ]; then
    ok "(C) scripts/formatcheck.sh gate mode is clean over this tree ($listed gated file(s), clang-format $have)"
else
    no "(C) scripts/formatcheck.sh gate mode FAILED (rc=$gateRc) — a gated file drifted from .clang-format:"
    printf '%s\n' "$gateOut" | grep -E '^  FAIL|^formatcheck:' | sed 's/^/        /'
    printf '        rerun: CLANG_FORMAT=%s bash scripts/formatcheck.sh\n' "$CF"
fi

# ── (D)+(E) the real mechanism at small scale, in a throwaway root ───────────────────────────────────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/src"
cp "$ROOT/.clang-format" "$TMP/.clang-format"
python3 - "$FC" "$TMP/scripts/formatcheck.sh" <<'PYEOF'
import re, sys
src, dst = sys.argv[ 1 ], sys.argv[ 2 ]
text = open( src ).read()
m = re.search( r"(GATED << 'GATED_EOF' \|\| true\n)(.*?)(\nGATED_EOF)", text, re.S )
assert m, "the GATED heredoc is not in the shape this gate patches — update test/formatgatecheck.sh"
text = text[ : m.start( 2 ) ] + "src/probeformatbad.h" + text[ m.end( 2 ) : ]
open( dst, "w" ).write( text )
PYEOF
patchRc=$?
cat > "$TMP/src/probeformatbad.h" <<'EOF'
#pragma once
struct    ProbeFormatBad {int   a;int b;};
inline int probeFormatAdd(int x,int   y){return x+  y;}
EOF

if [ "$patchRc" -ne 0 ]; then
    no "(D) could not build the patched formatcheck copy (the GATED heredoc shape changed)"
else
    redOut="$( CLANG_FORMAT="$CF" bash "$TMP/scripts/formatcheck.sh" 2>&1 )"
    redRc=$?
    if [ "$redRc" -ne 0 ] && printf '%s\n' "$redOut" | grep -q 'src/probeformatbad.h is not formatted'; then
        ok "(D) can-go-red: the REAL gate mechanism fails (rc=$redRc) and names the misformatted file"
    else
        no "(D) can-go-red: a deliberately misformatted gated file did NOT fail the gate (rc=$redRc) — formatcheck.sh is inert:"
        printf '%s\n' "$redOut" | sed 's/^/        /'
    fi

    "$CF" -i --style=file "$TMP/src/probeformatbad.h" >/dev/null 2>&1
    greenOut="$( CLANG_FORMAT="$CF" bash "$TMP/scripts/formatcheck.sh" 2>&1 )"
    greenRc=$?
    [ "$greenRc" -eq 0 ] && ok "(D) and green again once that same file is formatted — the red was the drift, not the harness" \
                         || { no "(D) the formatted file still fails (rc=$greenRc) — the harness, not the file, is the problem:"; printf '%s\n' "$greenOut" | sed 's/^/        /'; }

    # (E) advisory must never gate, even with a file it would rewrite
    cat > "$TMP/src/probeformatbad.h" <<'EOF'
#pragma once
struct    ProbeFormatBad {int   a;int b;};
EOF
    advOut="$( CLANG_FORMAT="$CF" bash "$TMP/scripts/formatcheck.sh" --advisory 2>&1 )"
    advRc=$?
    if [ "$advRc" -eq 0 ] && printf '%s\n' "$advOut" | grep -q 'would reformat: src/probeformatbad.h'; then
        ok "(E) --advisory reports the drifted file and still exits 0 (a report, never a gate)"
    else
        no "(E) --advisory did not behave as a non-gating report (rc=$advRc):"
        printf '%s\n' "$advOut" | sed 's/^/        /'
    fi
fi

# ── (F) the RESOLUTION ORDER itself (V1 I5) ──────────────────────────────────────────────────────────
# pick_cf decides which clang-format this gate runs, and that decision used to be invisible: it depended
# on what the machine happened to have installed, so it could be wrong on every machine but the one the
# author was sitting at. It is pure, so it is gated here on synthetic triples — including the case that
# motivated the change (PATH has the pinned major, homebrew has a different one) and its mirror.
pickis()
{   # pickis LABEL EXPECTED  ENV_P ENV_M PATH_P PATH_M BREW_P BREW_M
    local label="$1" want="$2"; shift 2
    local got; got="$( pick_cf "$1" "$2" "$3" "$4" "$5" "$6" "$WANT_MAJOR" )"
    [ "$got" = "$want" ] && ok "(F) $label -> $got" \
                         || no "(F) $label picked [$got], expected [$want]"
}
OLD=$(( WANT_MAJOR + 3 ))   # some other major, whatever the pin is
pickis "PATH has the pinned major, homebrew has $OLD: PATH wins (the case the old order SKIPped on)" \
       "/usr/bin/clang-format|$WANT_MAJOR"  ""  ""  /usr/bin/clang-format "$WANT_MAJOR" /brew/clang-format "$OLD"
pickis "PATH has $OLD, homebrew has the pinned major: homebrew wins" \
       "/brew/clang-format|$WANT_MAJOR"     ""  ""  /usr/bin/clang-format "$OLD"        /brew/clang-format "$WANT_MAJOR"
pickis "CLANG_FORMAT is named: it wins even against a pinned-major PATH (naming one is a choice)" \
       "/my/cf|$OLD"                        /my/cf "$OLD"  /usr/bin/clang-format "$WANT_MAJOR" /brew/clang-format "$WANT_MAJOR"
pickis "neither has the pin and there is no homebrew: PATH's is reported so the SKIP can name it" \
       "/usr/bin/clang-format|$OLD"         ""  ""  /usr/bin/clang-format "$OLD"        ""     ""
pickis "nothing anywhere: an empty pick, which is the found-NONE skip" \
       "|"                                  ""  ""  ""  ""  ""  ""

[ "$fail" -eq 0 ] && echo "formatgatecheck: ALL PASS" || { echo "formatgatecheck: SOME CHECKS FAILED"; exit 1; }
