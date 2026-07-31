#!/usr/bin/env bash
# ripwirepubliccheck.sh — the public-export scrub gate. This repository is an EXPORT of a private
# development tree; this gate is the machine-checked statement that nothing from that tree leaked.
#
# SCOPE: the COMMITTED tree only — every arm walks `git ls-files`, never the working directory.
# That is deliberate and is what makes the gate mean something: a clone gets exactly the committed
# files, so the committed set is the thing a stranger can read. It also lets the migration keep
# rewrite-pending files (README.md, CHANGELOG.md, CLAUDE.md, AGENTS.md, CONTRIBUTING.md) on disk as
# untracked working material without the gate reporting a leak that no clone could ever see. The
# flip side: a file this gate passes today can still fail tomorrow if it is committed unchanged, so
# run it BEFORE `git add`, not after.
#
# Arms:
#   1. the private working-copy name, case-insensitive, zero tolerance
#   2. absolute /Users/ paths
#   3. audit-round coordinates (§A, §B<d>, §P<d>, V<d>-<d>, W<d>, r<dd>-) in EMITTED strings and
#      in shipped markdown — NOT in ordinary source comments
#   4. credential-shaped literals outside the redaction fixtures that legitimately need them
#   5. personal names / handles / emails outside LICENSE and AUTHORS
#   6. docs/ index coverage + no internal-pattern FILENAME anywhere in the tree
#   7. include closure: no quoted #include escapes the repo; no include path names the private tree
#
# Usage:  bash test/ripwirepubliccheck.sh
# Exit:   0 = clean · 1 = at least one arm failed (offenders listed) · 2 = usage / missing tool.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
cd "$ROOT" || { printf 'ripwirepubliccheck: cannot cd to repo root %s\n' "$ROOT"; exit 2; }
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# A missing tool must never read as a clean tree — that is the green-while-inert failure this suite
# exists to catch. Name the tool and exit 2.
for _tool in git grep python3; do
    command -v "$_tool" >/dev/null 2>&1 || {
        printf 'ripwirepubliccheck: required tool missing: %s (gate cannot run)\n' "$_tool"; exit 2; }
done
git rev-parse --git-dir >/dev/null 2>&1 || {
    printf 'ripwirepubliccheck: not a git repository (gate scopes to git ls-files)\n'; exit 2; }

TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
git ls-files -z > "$TMP/tracked.z" || { printf 'ripwirepubliccheck: git ls-files failed\n'; exit 2; }
tracked=$( tr -dc '\0' < "$TMP/tracked.z" | wc -c | tr -d ' ' )
[ "$tracked" -gt 0 ] || { printf 'ripwirepubliccheck: no tracked files (nothing to check)\n'; exit 2; }

# Text-only sweep over the committed set. `grep -I` skips binaries; -z keeps pathnames with spaces
# intact. Every arm below funnels through this so the scope statement above is true by construction.
#
# SELF-EXCLUSION: this file states the forbidden patterns literally, so it matches its own arms. It
# is excluded from every sweep — the same idiom the gate it replaces used. The cost is real and
# named here: a genuine leak written INTO this script is the one thing the script cannot see, so
# treat edits to it as edits to a trusted file and review them by eye.
SELF="test/$( basename "$0" )"
sweep(){  # sweep <extended-regex> [extra grep flags...]
    local re="$1"; shift
    xargs -0 grep -InE "$@" -- "$re" < "$TMP/tracked.z" 2>/dev/null | grep -vF "$SELF:"
}

# ── arm 1: the private working-copy name, anywhere, any case ──────────────────────────────────────
hits="$( sweep 'canyonraid' -i || true )"
if [ -n "$hits" ]; then
    no "arm 1 — private tree name present in $( printf '%s\n' "$hits" | wc -l | tr -d ' ' ) place(s):"
    printf '%s\n' "$hits" | sed 's/^/          /'
else
    ok "arm 1 — no reference to the private development tree"
fi

# ── arm 2: absolute home-directory paths ──────────────────────────────────────────────────────────
hits="$( sweep '/Users/' || true )"
if [ -n "$hits" ]; then
    no "arm 2 — absolute /Users/ path in $( printf '%s\n' "$hits" | wc -l | tr -d ' ' ) place(s):"
    printf '%s\n' "$hits" | sed 's/^/          /'
else
    ok "arm 2 — no absolute /Users/ paths"
fi

# ── arm 3: audit-round coordinates in EMITTED strings and shipped markdown ────────────────────────
# Source COMMENTS are exempt on purpose: they are internal engineering notes that a user never sees.
# What a user sees is (a) string literals the binary prints and (b) the markdown that ships. Only
# those two are checked, so this arm stays honest instead of drowning in comment noise.
python3 - "$TMP/tracked.z" > "$TMP/arm3" <<'PY'
import re, sys
paths = open(sys.argv[1], 'rb').read().split(b'\0')
coord = re.compile(r'§A|§B[0-9]|§P[0-9]|V[0-9]-[0-9]|W[0-9]|r[0-9][0-9]-')
strlit = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
for raw in paths:
    if not raw:
        continue
    p = raw.decode('utf-8', 'surrogateescape')
    # emitted strings: OUR source only. third_party/ is upstream code we do not author, and the
    # test fixtures deliberately carry adversarial literals (base64 blobs collide with W<d>).
    is_src = p.startswith('src/') and p.endswith(('.h', '.cpp', '.inl', '.hpp'))
    is_md = p.endswith('.md')
    if not (is_src or is_md):
        continue
    try:
        lines = open(p, encoding='utf-8', errors='replace').read().split('\n')
    except OSError:
        continue
    for i, line in enumerate(lines, 1):
        if is_md:
            if coord.search(line):
                print(f'{p}:{i}:{line.strip()[:140]}')
            continue
        if line.lstrip().startswith('//'):
            continue
        for m in strlit.finditer(line):
            if coord.search(m.group(1)):
                print(f'{p}:{i}:{m.group(0)[:140]}')
PY
if [ -s "$TMP/arm3" ]; then
    no "arm 3 — audit-round coordinate in an emitted string or shipped doc:"
    sed 's/^/          /' "$TMP/arm3"
else
    ok "arm 3 — no audit-round coordinates in emitted strings or shipped docs"
fi

# ── arm 4: credential-shaped literals outside the redaction fixtures ──────────────────────────────
# --redact cannot be tested without credential-shaped strings to redact, so a fixed, enumerated set
# of files carries synthetic ones on purpose (see test/README.md). Anywhere ELSE is a leak.
SECRET_RE='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
SECRET_OK='^(src/redact\.h|test/README\.md|test/redactfix/|test/redactcheck\.sh|test/jsonredactcheck\.sh|test/mcpredactcheck\.sh|test/bodydialectcheck\.sh|test/w3fixlegendcheck\.sh)'
hits="$( sweep "$SECRET_RE" | grep -vE "$SECRET_OK" || true )"
if [ -n "$hits" ]; then
    no "arm 4 — credential-shaped literal outside the sanctioned redaction fixtures:"
    printf '%s\n' "$hits" | sed 's/^/          /'
else
    ok "arm 4 — credential-shaped literals confined to the redaction fixtures"
fi

# ── arm 5: personal identifiers outside LICENSE / AUTHORS ─────────────────────────────────────────
# The SPDX copyright notice is the one sanctioned form of the author's name in source: `Copyright
# <year> <name>` on its own comment line. Everything else — machine usernames, account handles,
# email addresses, "Created by … on <date>" residue from the origin tree — is a leak.
PERSON_RE='Brewster|brewster|qgames|davidbrewster|barefoot\.ski|quaterniongames'
hits="$( sweep "$PERSON_RE" \
         | grep -vE '^(LICENSE|AUTHORS|THIRD_PARTY\.md|test/ripwirepubliccheck\.sh):' \
         | grep -vE ':[0-9]+:[[:space:]]*(//|#)?[[:space:]]*Copyright [0-9]{4} David Brewster[[:space:]]*$' \
         || true )"
if [ -n "$hits" ]; then
    no "arm 5 — personal identifier outside LICENSE/AUTHORS and the SPDX copyright line:"
    printf '%s\n' "$hits" | sed 's/^/          /'
else
    ok "arm 5 — personal identifiers confined to LICENSE and SPDX copyright lines"
fi

# ── arm 6: internal-pattern filenames, and docs/ index coverage ───────────────────────────────────
INTERNAL_NAME='(^|/)(PLAN_|AUDIT|NEXT_SESSION|KICKOFF_|HANDOFF_|IDEAS_|REPORT_|DESIGN_|RESEARCH_)'
badnames="$( tr '\0' '\n' < "$TMP/tracked.z" | grep -E "$INTERNAL_NAME" || true )"
if [ -n "$badnames" ]; then
    no "arm 6a — internal-pattern filename committed (pattern $INTERNAL_NAME):"
    printf '%s\n' "$badnames" | sed 's/^/          /'
else
    ok "arm 6a — no internal-pattern filenames in the committed tree"
fi

docfiles="$( tr '\0' '\n' < "$TMP/tracked.z" | grep '^docs/' || true )"
if [ -z "$docfiles" ]; then
    # TODO-ARM (deliberate, and it fails the moment it stops being a TODO): docs/ is written by the
    # documentation lane. While docs/ is empty there is no index to check, so this arm reports and
    # passes. As soon as ANY file is committed under docs/, the else-branch below gates it — there
    # is no configuration in which docs/ ships unindexed.
    ok "arm 6b — docs/ is empty (index arm arms itself as soon as docs/ is populated)"
elif ! printf '%s\n' "$docfiles" | grep -qx 'docs/README.md'; then
    no "arm 6b — docs/ has $( printf '%s\n' "$docfiles" | wc -l | tr -d ' ' ) file(s) but no docs/README.md index"
else
    missing=""
    for d in $docfiles; do
        [ "$d" = "docs/README.md" ] && continue
        base="${d#docs/}"
        grep -Fq "$base" docs/README.md || missing="$missing$d
"
    done
    if [ -n "$missing" ]; then
        no "arm 6b — file(s) under docs/ not listed in docs/README.md:"
        printf '%s' "$missing" | sed 's/^/          /'
    else
        ok "arm 6b — every file under docs/ is listed in docs/README.md"
    fi
fi

# ── arm 7: include closure ────────────────────────────────────────────────────────────────────────
# Every quoted #include must resolve to a file inside the repo. Resolution mirrors the compiler:
# relative to the including file first, then the project's include roots. A build-time include root
# that is NOT in the repo (a system path, an absolute path, the private tree) is exactly the leak
# this arm exists to catch, so unresolved is a FAIL, not a skip.
python3 - "$TMP/tracked.z" > "$TMP/arm7" <<'PY'
import os, re, sys
paths = [p.decode('utf-8', 'surrogateescape')
         for p in open(sys.argv[1], 'rb').read().split(b'\0') if p]
tracked = set(paths)
# The include roots the compiler is actually handed — our own targets' first, then the ones CMake
# passes the vendored dependency targets. A vendored header saying #include "tree_sitter/api.h" is
# self-contained (that header IS in this repo); arm 7 just has to model the same roots the build
# does, or it reports a closure break that no compiler would ever see.
#
# Note what this deliberately does NOT do: exempt third_party/deps/ from the arm. Vendored code is
# where an escape would be easiest to miss, so it stays swept — only the root list grows. And the
# roots are ENUMERATED, not globbed off disk, so pruning a dependency too far still fails the arm
# instead of quietly shrinking the search.
_deps = 'third_party/deps'
_grammars = ('bash', 'c', 'cpp', 'csharp', 'go', 'java', 'javascript', 'json',
             'objc', 'python', 'ruby', 'rust', 'swift')
roots = (['src', 'src/infra', 'third_party', '']                        # our targets
         + [f'{_deps}/tree_sitter/lib/include']                         # PUBLIC, given to every target
         + [f'{_deps}/tree_sitter/lib/src', f'{_deps}/tree_sitter/lib/src/wasm']   # tree-sitter PRIVATE
         + [f'{_deps}/{g}/src' for g in _grammars]                      # add_ts_grammar(): PRIVATE ${_src}
         + [f'{_deps}/ts_typescript/typescript/src', f'{_deps}/ts_typescript/tsx/src']  # add_ts_object()
         + [f'{_deps}/doctest', f'{_deps}/doctest/doctest/parts'])      # doctest INTERFACE + dev root
inc = re.compile(r'^\s*#\s*include\s*"([^"]+)"')
# Generated headers: produced into the build dir by CMake, never committed. Named, not pattern-matched.
generated = {'version.h', 'embedded_queries.h'}
for p in paths:
    if not p.endswith(('.h', '.hpp', '.inl', '.cpp', '.c', '.cc')):
        continue
    try:
        lines = open(p, encoding='utf-8', errors='replace').read().split('\n')
    except OSError:
        continue
    here = os.path.dirname(p)
    for i, line in enumerate(lines, 1):
        m = inc.match(line)
        if not m:
            continue
        target = m.group(1)
        if 'canyonraid' in target.lower():
            print(f'{p}:{i}: include path names the private tree: {target}')
            continue
        if os.path.basename(target) in generated:
            continue
        cands = [os.path.normpath(os.path.join(here, target))]
        cands += [os.path.normpath(os.path.join(r, target)) if r else os.path.normpath(target)
                  for r in roots]
        if not any(c in tracked for c in cands):
            print(f'{p}:{i}: quoted include does not resolve inside the repo: {target}')
PY
if [ -s "$TMP/arm7" ]; then
    no "arm 7 — include closure is not self-contained:"
    sed 's/^/          /' "$TMP/arm7"
else
    ok "arm 7 — every quoted #include resolves inside the repo"
fi

printf 'ripwirepubliccheck: %s tracked file(s) swept\n' "$tracked"
[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
