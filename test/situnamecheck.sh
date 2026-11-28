#!/usr/bin/env bash
# situnamecheck.sh — --situ NAMES the change itself, before what depends on it (SITU-NAME-CHANGED, 11-27).
#
#   test/situnamecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/situnamecheck.sh
#
# WHY THIS EXISTS. VERB-AUDIT-2 (11-27): default `--situ` ("it worked yesterday / my last edit broke it")
# printed "2 changed file(s), 103 symbols" and a changed_symbols= count, then only the DEPENDENTS — the
# changed files and functions themselves were named on 0 of 4 repos (jq, vscode, zed, cockroach), so the
# next call was `git diff --stat` plus a grep. And an edit already COMMITTED is outside a diff vs HEAD, so
# the report said nothing about the commit that may have broken it.
#
# THE CONTRACT THIS GATE PINS.
#   (a) a `changed:` block leads: one row per edited symbol, `path:first-last name`, with its direct-caller
#       files outside the diff after "←"; it prints BEFORE the change_set: line and the [1] blast radius.
#   (b) a `last commit:` line names the commit's sha7 and its files (the committed change), and the call
#       that covers both (--pr-context=HEAD~1). Both blocks are git-diff only: an explicit --situ=FILES list
#       already names its files, so it prints neither.
#   (c) the cap is DISCLOSED: past the default 8 rows, "+N more: --situ --limit=M"; a direct-caller list
#       past 3 files ends "+K (--callers=NAME)"; --limit=M lifts the row cap with no "+N more" left.
#   (d) a clean tree still names the last commit; (d2) a module-level edit is a whole-file row;
#   (e) a parentless HEAD (root commit, shallow boundary) prints no last commit: line.
# Every arm counts what it saw and FAILS on zero (a gate that saw no rows proves nothing).
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

gitq(){ ( cd "$1" && shift && GIT_AUTHOR_DATE='2026-01-01T00:00:00 +0000' GIT_COMMITTER_DATE='2026-01-01T00:00:00 +0000' git "$@" >/dev/null 2>&1 ); }
seed_repo(){
  gitq "$1" init -q -b main && gitq "$1" config user.email rw@example.invalid && gitq "$1" config user.name ripwire \
    && gitq "$1" add -A && gitq "$1" commit -q -m seed
}
# a loaded host can outlive the 20 s git budget and serve no diff at all; these fixtures are tiny, so lift it
situ(){ ( cd "$1" && shift && RIPWIRE_GIT_WALK_SECONDS=300 "$BIN" . --no-cache "$@" 2>/dev/null ); }
lineno(){ grep -n -m1 -F -- "$2" "$1" | cut -d: -f1; }

# ── fixture 1: a committed change (parse.py) and an uncommitted edit (engine.py) ────────────────────────
FX="$TMP/fx"; mkdir -p "$FX/app" "$FX/tests"
cat > "$FX/app/engine.py" <<'EOF'
def run_engine(job):
    return job


def idle_engine():
    return 0
EOF
cat > "$FX/app/parse.py" <<'EOF'
def parse_job(text):
    return text
EOF
cat > "$FX/app/cli.py" <<'EOF'
from app.engine import run_engine
from app.parse import parse_job


def main(text):
    return run_engine(parse_job(text))
EOF
cat > "$FX/tests/test_cli.py" <<'EOF'
from app.cli import main


def test_main():
    return main("x")
EOF
seed_repo "$FX" || { echo "git fixture setup failed"; exit 2; }
# the committed change ("it worked yesterday")
printf 'def parse_job(text):\n    return text.strip()\n' > "$FX/app/parse.py"
gitq "$FX" commit -q -am "parse: strip the job text" || { echo "git fixture commit failed"; exit 2; }
# the uncommitted edit, inside run_engine only
python3 - "$FX/app/engine.py" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
old = "def run_engine(job):\n    return job\n"
new = "def run_engine(job):\n    if job is None:\n        return 0\n    return job\n"
assert old in s
open(p, "w").write(s.replace(old, new, 1))
EOF
SHA7="$( cd "$FX" && git log -1 --format=%h )"

OUT="$TMP/a.txt"
situ "$FX" --situ > "$OUT" || no "(a) ripwire --situ exited non-zero"
[ -s "$OUT" ] || { no "(a) the fixture produced no --situ report — every arm below would be a false green"; echo "situnamecheck: SOME FAILED"; exit 1; }

# (a) the changed: block names the edited symbol with its span and its direct caller, and leads the report
rows="$( sed -n '/^  changed: /,/^  [a-z\[]/p' "$OUT" | grep -c '^        ' )"
if [ "${rows:-0}" -gt 0 ]; then ok "(a) changed: block printed $rows row(s)"; else no "(a) no changed: rows at all (saw 0)"; fi
if grep -qE '^        app/engine\.py:1-[0-9]+ run_engine ← app/cli\.py$' "$OUT"; then
  ok "(a) the uncommitted edit is named: app/engine.py:1-N run_engine ← app/cli.py"
else
  no "(a) no 'app/engine.py:1-N run_engine ← app/cli.py' row: $( grep -m3 'engine' "$OUT" | tr '\n' '|' )"
fi
if grep -q 'idle_engine' "$OUT"; then no "(a) the unedited idle_engine is listed as changed"; else ok "(a) the unedited idle_engine is not named"; fi
lc="$( lineno "$OUT" '  changed: ' )"; lcs="$( lineno "$OUT" 'change_set:' )"; lb="$( lineno "$OUT" '[1] blast radius' )"
if [ -n "$lc" ] && [ -n "$lcs" ] && [ -n "$lb" ] && [ "$lc" -lt "$lcs" ] && [ "$lc" -lt "$lb" ]; then
  ok "(a) changed: (line $lc) leads change_set: (line $lcs) and the blast radius (line $lb)"
else
  no "(a) changed: does not lead the report (changed=$lc change_set=$lcs blast=$lb)"
fi

# (b) the committed change is named on the last commit: line, with the call that covers both
LC="$( grep -m1 '^  last commit: ' "$OUT" )"
if [ -n "$LC" ]; then
  for tok in "$SHA7" '"parse: strip the job text"' '1 file(s): app/parse.py' '--pr-context=HEAD~1'; do
    case "$LC" in *"$tok"*) ok "(b) last commit: carries $tok" ;; *) no "(b) last commit: lacks $tok: $LC" ;; esac
  done
else
  no "(b) no 'last commit:' line — the committed change is unnamed"
fi
situ "$FX" --situ=app/engine.py > "$TMP/b2.txt" || no "(b) ripwire --situ=app/engine.py exited non-zero"
[ -s "$TMP/b2.txt" ] || no "(b) --situ=app/engine.py produced nothing"
if grep -q 'last commit:' "$TMP/b2.txt"; then no "(b) an explicit --situ=FILES list still prints last commit:"
else ok "(b) an explicit --situ=FILES list prints no last commit: line"; fi
if grep -q '^  changed: ' "$TMP/b2.txt"; then no "(b) an explicit --situ=FILES list restates its files in a changed: block"
else ok "(b) an explicit --situ=FILES list prints no changed: block (the caller named the files)"; fi

# ── fixture 2: the cap — 11 edited functions, one with 5 caller files ───────────────────────────────────
FX2="$TMP/fx2"; mkdir -p "$FX2/lib" "$FX2/use"
python3 - "$FX2" <<'EOF'
import sys, os
d = sys.argv[1]
with open(os.path.join(d, "lib/core.py"), "w") as f:
    for i in range(11):
        f.write(f"def fn{i:02d}(x):\n    return x\n\n\n")
for j in range(5):
    with open(os.path.join(d, f"use/u{j}.py"), "w") as f:
        f.write("from lib.core import fn00\n\n\n" f"def use{j}(x):\n    return fn00(x)\n")
EOF
seed_repo "$FX2" || { echo "git fixture 2 setup failed"; exit 2; }
python3 - "$FX2/lib/core.py" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("    return x\n", "    return x + 1\n")
open(p, "w").write(s)
EOF
OUT2="$TMP/c.txt"
situ "$FX2" --situ > "$OUT2" || no "(c) ripwire --situ exited non-zero"
[ -s "$OUT2" ] || no "(c) fixture 2 produced no report"
n2="$( sed -n '/^  changed: /,/^  [a-z\[]/p' "$OUT2" | grep -c '^        lib/core\.py:' )"
if [ "$n2" -eq 8 ]; then ok "(c) the default cap shows 8 symbol rows (saw $n2)"; else no "(c) expected 8 shown rows, saw $n2"; fi
if grep -qE '^        \+3 more: --situ --limit=11$' "$OUT2"; then ok "(c) the cut is named: +3 more: --situ --limit=11"
else no "(c) no '+3 more: --situ --limit=11' disclosure: $( grep -m2 'more' "$OUT2" | tr '\n' '|' )"; fi
if grep -qE '^        lib/core\.py:1-2 fn00 ← use/u0\.py, use/u1\.py, use/u2\.py \+2 \(--callers=fn00\)$' "$OUT2"; then
  ok "(c) a caller list past 3 files ends +2 (--callers=fn00)"
else
  no "(c) fn00's caller row lacks the +2 disclosure: $( grep -m1 'fn00' "$OUT2" )"
fi
situ "$FX2" --situ --limit=11 > "$TMP/c2.txt" || no "(c) ripwire --situ --limit=11 exited non-zero"
n3="$( sed -n '/^  changed: /,/^  [a-z\[]/p' "$TMP/c2.txt" | grep -c '^        lib/core\.py:' )"
if [ "$n3" -eq 11 ]; then ok "(c) --limit=11 shows all 11 rows"; else no "(c) --limit=11 showed $n3 of 11 rows"; fi
if [ ! -s "$TMP/c2.txt" ]; then no "(c) --limit=11 produced no report (nothing to check for a +N more line)"
elif grep -q 'more: --situ' "$TMP/c2.txt"; then no "(c) --limit=11 still prints a +N more line"; else ok "(c) --limit=11 leaves no +N more line"; fi

# ── (d) a clean tree still names its last change ────────────────────────────────────────────────────────
gitq "$FX" commit -q -am "engine: guard None" || no "(d) could not commit the engine edit"
situ "$FX" --situ > "$TMP/d.txt" || no "(d) ripwire --situ exited non-zero"
grep -q 'working tree is clean' "$TMP/d.txt" || no "(d) the clean tree is not reported as clean: $( head -5 "$TMP/d.txt" | tr '\n' '|' )"
if grep -qE '^  last commit: [0-9a-f]+ "engine: guard None" — 1 file\(s\): app/engine\.py;' "$TMP/d.txt"; then
  ok "(d) a clean tree names the last commit and its file"
else
  no "(d) a clean tree has no last commit: line naming app/engine.py: $( grep -m1 'last commit' "$TMP/d.txt" )"
fi

# ── (d2) a module-level edit returns its file to file-granular: a whole-file row, not symbol rows ─────────
printf 'RETRIES = 3\n' >> "$FX/app/cli.py"
situ "$FX" --situ > "$TMP/d2.txt" || no "(d) ripwire --situ exited non-zero"
if grep -qE '^        app/cli\.py \(whole file: [0-9]+ symbols\)$' "$TMP/d2.txt" && grep -q '^  changed: 1 file(s), 0 symbol(s), 1 kept whole' "$TMP/d2.txt"; then
  ok "(d2) a module-level edit is named as a whole-file row (app/cli.py, 1 kept whole)"
else
  no "(d2) no whole-file row for the module-level edit: $( sed -n '/changed: /,+2p' "$TMP/d2.txt" | tr '\n' '|' )"
fi

# ── (e) a parentless HEAD (a root commit) prints no last commit: line rather than the whole tree ─────────
FX3="$TMP/fx3"; mkdir -p "$FX3"; printf 'def solo():\n    return 1\n' > "$FX3/solo.py"
seed_repo "$FX3" || { echo "git fixture 3 setup failed"; exit 2; }
printf 'def solo():\n    return 2\n' > "$FX3/solo.py"
situ "$FX3" --situ > "$TMP/e.txt" || no "(e) ripwire --situ exited non-zero"
if grep -q 'solo.py:1-2 solo' "$TMP/e.txt"; then ok "(e) the root-commit fixture names its edit"; else no "(e) the root-commit fixture names no edit"; fi
if [ ! -s "$TMP/e.txt" ]; then no "(e) the root-commit fixture produced no report"
elif grep -q 'last commit:' "$TMP/e.txt"; then no "(e) a root commit printed a last commit: line"; else ok "(e) a root commit prints no last commit: line"; fi

if [ "$fail" -eq 0 ]; then echo "situnamecheck: ALL PASS"; else echo "situnamecheck: SOME FAILED"; fi
exit "$fail"
