#!/usr/bin/env bash
# nulbytecheck.sh — F3 tripwire: no tracked TEXT file may contain an embedded NUL byte.
#
# THE BUG THIS GATE PINS (wave-1 verifier F3). Commit 175d5fe committed a
# literal 0x00 byte into src/mcp.h at byte offset 18573 — inside a COMMENT that was talking about NUL payloads.
# One prose byte, and the largest MCP source in the tree became BINARY to the search tools this project's whole
# working method is built on:
#
#     $ /usr/bin/grep -rn 'hasVisibleContent' src/
#     Binary file src/mcp.h matches                 # rc=0, ZERO locations printed
#     $ /usr/bin/grep -c 'hasVisibleContent' src/mcp.h
#     6                                             # the matches exist; grep just refuses to show the lines
#     $ rg -n 'hasVisibleContent' src/mcp.h
#     binary file matches (found "\0" byte around offset 18573)
#
# Why this needs a GATE and not just the one-character fix. `git grep` and `git diff` sample only the first
# 8000 bytes of a blob for their binary heuristic, and the NUL sat at 18573 — so the breakage was INVISIBLE to
# the review path (every diff rendered normally) and visible only to the search path. It shipped through a
# merge, a suite run and an argvdiff matrix without one signal. Nothing else in this repo asks the question, so
# nothing else would catch the next one.
#
# WHAT IS ASSERTED:
#   (a) every tracked file whose extension is not on the BINARY allowlist below contains ZERO 0x00 bytes.
#       Reported per offending file with the byte offset and the surrounding prose, because "src/mcp.h has a
#       NUL" is not actionable and "src/mcp.h:18573, inside `a client that reached ...`" is.
#   (b) the DETECTOR ITSELF works — the arm that makes this gate worth more than a grep. 175d5fe's mcp.h is
#       materialized out of git into a temp file and the scanner must FLAG it. A tripwire nobody has ever seen
#       trip is a tripwire nobody knows is connected; this one re-proves its own wiring on every run.
#   (c) the allowlist is HONEST: every allowlisted extension is one that actually occurs in `git ls-files`.
#       A speculative row (".png" in a repo with no images) is a hole with a plausible name on it, so the
#       allowlist is ENUMERATED from the tree, and this arm fails when a row stops being backed by a real file.
#
# THE ALLOWLIST is deliberately short and evidence-based: at the time of writing, `git ls-files` turns up
# exactly one extension carrying NUL bytes — .tgz (2 locbench fixtures) — and no
# .png/.jpg/.ico exists in this repo at all, so none is pre-allowlisted. If a future round adds a genuinely
# binary file type, this gate FAILS naming the file, and the fix is one row plus the reason. That failure is
# the feature: an allowlist that grows by guess is how the next `.md` full of control bytes gets waved through.
#
#   bash test/nulbytecheck.sh                                   # scans the working tree
#   bash test/nulbytecheck.sh /path/to/base/ripwire             # BIN is accepted and unused (see below)
#   RIPWIRE_BIN=asan/ripwire bash test/nulbytecheck.sh          # both seams bind the same way
#
# BIN is bound for suite uniformity and then not used: this gate reads SOURCE, so its red-first evidence is a
# pre-fix source TREE (arm (b) supplies exactly that, permanently, out of git) rather than a pre-fix binary.
# Stated here rather than left as a silent omission — a reader who greps this file for "$BIN" deserves to find
# the reason and not a bug.
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "python3 required for the byte scan"; exit 2; }
command -v git    >/dev/null 2>&1 || { echo "git required to enumerate tracked files"; exit 2; }
cd "$ROOT" || exit 2
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository — nothing to enumerate"; exit 2; }
echo "nulbytecheck: ROOT=$ROOT  (BIN=$BIN, bound for uniformity, unused — see header)"

# The scanner, as a reusable script: arm (a) points it at the tree, arm (b) at one extracted historical file.
cat >"$TMP/nulscan.py" <<'PY'
#!/usr/bin/env python3
"""Report embedded NUL bytes in the given files. Exit 1 when any file has one."""
import os
import sys

# Extensions whose files are legitimately binary — ENUMERATED from `git ls-files`, never guessed. See the
# gate header: a new binary type is meant to fail here once and gain a row with a reason.
BINARY_EXTENSIONS = {
    ".tgz",    # bench/locbench/results/*/*.tgz — gzipped gate+fixture bundles
    ".pdf",    # present/ripwire-showcase.pdf — generated binary slide export
    ".pptx",   # present/ripwire-showcase.pptx — generated Office Open XML slide deck
    ".png",    # docs/assets/showcase-preview.png — the README's clickable deck preview, three slides
               # rendered from the committed present/ripwire-showcase.pdf. Added 2026-08-10, the round
               # this gate's header anticipated: it failed once naming the file, and this is the row
               # plus the reason. Regenerate it from the deck PDF; never draw or edit it by hand.
    ".srcpack",  # bench/recalleval/snapshot.srcpack — the ranking lane's FROZEN source corpus, 1422
               # files packed and gzip-compressed (~32 MB of text, 6.7 MB stored). Added 2026-08-19 by
               # the ranking-lane freeze; it failed here once naming the file, and this is the row plus
               # the reason. Binary because it is COMPRESSED, not because its contents are: every byte
               # inside it is a copy of a tracked text file this sweep already scans at its own path, so
               # allowlisting the container hides nothing (the same argument ripwirepubliccheck's
               # SECRET_OK makes for snapshot.mdpack). Regenerate only via
               # `make_snapshot.py --freeze --corpus src`; never hand-edit — recallevalcheck's check #0
               # hashes the contents and would red first.
    ".jpg",    # docs/assets/colorby-hero.jpg — the README front-page hero, a headless-Chrome screenshot
               # of --html --color-by=cx JPEG-compressed (screenshot -> PNG rasterises the ramp's five
               # hex stops faithfully; PNG palette-quantizing it below ~200 KB collapsed the whole point
               # of the image, muddying every colour stop into near-identical brownish tones, so JPEG at
               # quality ~90 is the format that keeps the palette legible AND stays small). Added
               # 2026-09-05 by the showcase-refresh lane (harvest round B, §7); it failed here once
               # naming the file, and this is the row plus the reason. Regenerate only via the
               # documented capture recipe (headless Chromium screenshot of a `--html` export,
               # cropped/resized/re-encoded); never hand-edit.
}

def scan(paths, label):
    offenders = []
    scanned = 0
    links = 0
    for path in paths:
        if os.path.splitext(path)[1].lower() in BINARY_EXTENSIONS:
            continue
        if not os.path.lexists(path):
            continue  # tracked deletion in a dirty review tree; there are no working-tree bytes to scan
        # A tracked SYMLINK's content is its target PATH (git mode 120000), which cannot hold a NUL, and the
        # bytes it points at belong to whatever tree owns them — following it would scan files this repo does
        # not track. Counted rather than silently dropped.
        if os.path.islink(path):
            links += 1
            continue
        try:
            data = open(path, "rb").read()
        except OSError as exc:
            print("  %s could not read tracked file %s: %s" % (label, path, exc))
            offenders.append((path, -1, ""))
            continue
        scanned += 1
        offset = data.find(b"\x00")
        if offset < 0:
            continue
        # the prose around the byte, with the NUL itself spelled — a gate must not print the byte it is
        # complaining about (that is how the report becomes as unsearchable as the file).
        lo, hi = max(0, offset - 42), min(len(data), offset + 42)
        context = data[lo:hi].replace(b"\x00", b"<NUL>").decode("utf-8", "replace").replace("\n", "\\n")
        line = data[:offset].count(b"\n") + 1
        offenders.append((path, offset, context))
        print("  %s embedded NUL in %s at byte %d (line %d), %d total: ...%s..."
              % (label, path, offset, line, data.count(b"\x00"), context))
    return offenders, scanned, links

if __name__ == "__main__":
    mode = sys.argv[1]
    # paths come as NUL-separated bytes on stdin when there are none in argv — ONE invocation for the whole
    # tree, because xargs is free to split a long list and two "N files scanned" lines is a report nobody can
    # read as a single verdict.
    files = sys.argv[2:]
    if not files:
        files = [p.decode("utf-8", "replace") for p in sys.stdin.buffer.read().split(b"\0") if p]
    # arm (b) EXPECTS a hit, so its report line is INFO: a literal "FAIL" in a passing gate's
    # transcript is how a reader (or a grep-driven CI summary) learns to distrust the whole file.
    offenders, scanned, links = scan(files, "FAIL  (a)" if mode == "expect-clean" else "INFO  (b) detector hit:")
    if mode == "expect-clean":
        if offenders:
            print("  INFO  (a) %d text file(s) carry an embedded NUL — see above" % len(offenders))
            sys.exit(1)
        print("  PASS  (a) %d tracked text files scanned (%d symlinks skipped), ZERO embedded NUL bytes"
              % (scanned, links))
        sys.exit(0)
    if mode == "expect-dirty":
        # arm (b): the detector must FLAG the known-bad historical file.
        if offenders:
            print("  PASS  (b) the scanner FLAGS the pre-fix file (the INFO line above is the hit)")
            sys.exit(0)
        print("  FAIL  (b) the scanner did NOT flag the pre-fix file — the detector is broken, not the tree")
        sys.exit(1)
    print("  FAIL  unknown mode %s" % mode)
    sys.exit(2)
PY

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (a) no tracked TEXT file contains an embedded NUL byte ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
git ls-files -z >"$TMP/tracked.z" 2>/dev/null || { echo "  FAIL  (a) git ls-files failed"; fail=1; }
if [ -s "$TMP/tracked.z" ]; then
    # NUL-separated on stdin so a path containing a space or a newline cannot split, and so the whole tree is
    # ONE scan with one verdict line.
    if python3 "$TMP/nulscan.py" expect-clean <"$TMP/tracked.z"; then :; else fail=1; fi
else
    no "(a) no tracked files enumerated"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (b) the DETECTOR fires on the file that shipped the bug (175d5fe:src/mcp.h) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# "would this gate have caught it" is not a claim to make in prose. The bad blob is still in this repo's
# history, so the gate extracts it and re-earns the claim on every run.
BADREF="175d5fe:src/mcp.h"
if git cat-file -e "$BADREF" 2>/dev/null; then
    mkdir -p "$TMP/hist"
    git show "$BADREF" >"$TMP/hist/mcp.h" 2>/dev/null
    if [ -s "$TMP/hist/mcp.h" ]; then
        if python3 "$TMP/nulscan.py" expect-dirty "$TMP/hist/mcp.h"; then :; else fail=1; fi
    else
        no "(b) could not extract $BADREF"
    fi
else
    # A shallow clone / a rewritten history has no such object. SYNTHESIZE the same shape instead of
    # skipping: the arm exists to prove the detector fires, and a fabricated file proves that just as well.
    ok "(b) $BADREF not in this history (shallow clone?) — falling back to a synthesized carrier"
    mkdir -p "$TMP/hist"
    printf '// a comment that reached `\000` for a definition\nint f() { return 0; }\n' >"$TMP/hist/mcp.h"
    if python3 "$TMP/nulscan.py" expect-dirty "$TMP/hist/mcp.h"; then :; else fail=1; fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (c) every allowlisted extension is backed by a real tracked file ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
# The allowlist is the gate's only hole, so it is itself asserted: a row nothing matches is either a stale
# leftover or a speculative exemption, and both are how a real NUL gets waved through later.
RIPWIRE_GATE_ROOT="$ROOT" python3 - <<'PY' || fail=1
import os
import re
import subprocess
import sys

gate = os.path.join(os.environ["RIPWIRE_GATE_ROOT"], "test", "nulbytecheck.sh")
src = open(gate, encoding="utf-8").read()
block = src.split("BINARY_EXTENSIONS = {", 1)[1].split("}", 1)[0]
rows = re.findall(r'"(\.[A-Za-z0-9]+)"', block)

tracked = subprocess.run(["git", "ls-files", "-z"], stdout=subprocess.PIPE).stdout.split(b"\0")
present = {os.path.splitext(p.decode("utf-8", "replace"))[1].lower() for p in tracked if p}

fails = 0
for ext in rows:
    if ext in present:
        print("  PASS  (c) allowlist row %-7s is backed by a tracked file" % ext)
    else:
        print("  FAIL  (c) allowlist row %-7s matches NO tracked file — stale or speculative, remove it" % ext)
        fails += 1
if not rows:
    print("  FAIL  (c) could not parse BINARY_EXTENSIONS out of the gate")
    fails += 1
# and the converse: any tracked extension that carries NULs must BE on the list, or arm (a) is failing for it
print("  INFO  (c) %d allowlist rows, %d distinct tracked extensions" % (len(rows), len(present)))
sys.exit(1 if fails else 0)
PY

echo
[ "$fail" = 0 ] && { echo "nulbytecheck: ALL PASS"; exit 0; }
echo "nulbytecheck: FAILURES above"; exit 1
