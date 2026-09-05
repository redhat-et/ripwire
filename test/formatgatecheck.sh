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

# ── resolve a clang-format: the caller's, then homebrew LLVM (not on PATH on macOS), then PATH ───────
CF=""
if [ -n "${CLANG_FORMAT:-}" ]; then
    CF="$CLANG_FORMAT"
elif [ -x /opt/homebrew/opt/llvm/bin/clang-format ]; then
    CF=/opt/homebrew/opt/llvm/bin/clang-format
elif command -v clang-format >/dev/null 2>&1; then
    CF="$( command -v clang-format )"
fi

have=""
if [ -n "$CF" ] && command -v "$CF" >/dev/null 2>&1; then
    have="$( "$CF" --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9]*\).*/\1/p' | head -1 )"
fi

# ── the SKIP, with the reason spelled out (pargates.py reads "SKIP" in the first 400 chars) ──────────
if [ -z "$WANT_MAJOR" ]; then
    echo "formatgatecheck: could not read WANT_MAJOR out of scripts/formatcheck.sh — the pin this gate reports on is gone"
    exit 1
fi
if [ -z "$have" ]; then
    printf '  SKIP  formatgatecheck: needs clang-format major %s (the version .clang-format was produced and verified with); found NONE — looked at CLANG_FORMAT, /opt/homebrew/opt/llvm/bin/clang-format, then PATH. Install LLVM %s or set CLANG_FORMAT=/path/to/clang-format. NOTHING WAS CHECKED.\n' "$WANT_MAJOR" "$WANT_MAJOR"
    exit 0
fi
if [ "$have" != "$WANT_MAJOR" ]; then
    printf '  SKIP  formatgatecheck: needs clang-format major %s (the version .clang-format was produced and verified with); found major %s at %s. Different majors format differently, so running anyway would report false drift. NOTHING WAS CHECKED.\n' "$WANT_MAJOR" "$have" "$CF"
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

[ "$fail" -eq 0 ] && echo "formatgatecheck: ALL PASS" || { echo "formatgatecheck: SOME CHECKS FAILED"; exit 1; }
