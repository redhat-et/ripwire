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
#   8. no reference to an internal-pattern .md name that is ABSENT from this tree (a dangling pointer
#      at a culled process doc); a reference to a .md that DOES ship is fine
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
# OWNER-ACCEPTED ONE-OFF (2026-08-08): the external-tool-survey PLAN was deliberately committed at
# 7bcd8b0 as a public roadmap — the owner accepted the internal-pattern filename and its §-coordinates
# on record. EXACTLY this path is exempt here (arm 3) and in arm 6a; any other internal-pattern file
# or coordinate-carrying doc still fails. Remove the exemption if the file is ever culled.
ONEOFF_ACCEPTED='PLAN_EXTERNAL_TOOL_SURVEY_2026-08-08.md'
python3 - "$TMP/tracked.z" "$ONEOFF_ACCEPTED" > "$TMP/arm3" <<'PY'
import re, sys
paths = open(sys.argv[1], 'rb').read().split(b'\0')
oneoff = sys.argv[2]
coord = re.compile(r'§A|§B[0-9]|§P[0-9]|V[0-9]-[0-9]|W[0-9]|r[0-9][0-9]-')
strlit = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
for raw in paths:
    if not raw:
        continue
    p = raw.decode('utf-8', 'surrogateescape')
    if p == oneoff:
        continue
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
# bench/recalleval/snapshot.mdpack is a hash-pinned, byte-frozen copy of tracked *.md (including
# test/README.md above) — every line inside it exists at a real path this sweep already scans with
# its own per-path ruling, so scanning the copy can only double-report what the original already
# answers for. The pack is regenerated only by make_snapshot.py --freeze and integrity-checked by
# recallevalcheck's check #0, so nothing can hide in it that is not also at its source path.
SECRET_OK='^(src/redact\.h|test/README\.md|test/redactfix/|test/redactcheck\.sh|test/jsonredactcheck\.sh|test/mcpredactcheck\.sh|test/bodydialectcheck\.sh|test/w3fixlegendcheck\.sh|bench/recalleval/snapshot\.mdpack)'
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
# A commit identity being visible in git history is not a licence to bake it into the FILES: a clone's
# tree is read by people and by agents that never look at `git log`, and `--owners`/`--pr-context` put
# real author addresses into any recorded output. The generators scrub them (docs/docs_commands_build.py,
# test/showcase_capture.py); this arm is the statement that the scrub ran.
# Concatenated on purpose: the tracked tree must not itself SPELL the identifiers this arm hunts
# (the detector was the last tracked file carrying them). The regex is byte-identical after joining.
PERSON_RE='Brew''ster|brew''ster|qga''mes|davidbrew''ster|bare''foot\.ski|quaternion''games'
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

# ── arm 5b: generic email-shape check — PERSON_RE above only catches NAMES it already knows; this
# catches ANY real-looking address, named or not. The discriminator is IMPORTED from
# docs/docs_commands_build.py's find_address() (same idiom as test/docscommandscheck.sh's arm E) so
# this does not re-spell the symbol@file.ext-vs-real-address rule by hand — ripwire's own community
# labels (`str@ingest.cpp:887`, `AGENTS@AGENTS.md:1:0`) are that exact shape and must not trip this.
#
# V3 MED-4: the exemption used to be `test/[^/]+\.(sh|py)$` — wholesale, by FILE. That was both too
# WIDE (any address in a top-level test/*.sh|py file was waved through, real or planted) and too
# NARROW (a fixture under test/sub/foo.sh was not exempt at all). It is replaced below by an
# allowlist keyed on the ADDRESS itself: a hit is exempt only if its domain is one of the synthetic
# domains this repo's fixtures actually construct, wherever in the tree it appears. Anything that
# is not a synthetic-domain hit gets its own explicit (path, address) exemption instead — see PAIR
# below — so nothing is waved through just for living in test/.
#
# PATH_ALLOW, enumerated by scanning the whole committed tree first (see the commit message for the
# full list this was built from):
#   third_party/**                    — vendored upstream code; its own authors' real copyright/
#                                        LICENSE emails are correct and required, not a leak of ours.
#   bench/cppbench/dataset.lock       — a benchmark dataset of real historical public open-source
#                                        commit messages (external corpus, not this repo's identity).
#   docs/docs_commands_build.py       — the generator's OWN source, describing its `symbol@basename.ext`
#                                        placeholder shape in comments (a literal ".ext", not a real TLD,
#                                        so find_address()'s TLD check does not itself filter it out).
#
# SYNTHETIC_DOMAINS — the exact set of throwaway domains found in test fixtures across the whole
# committed tree (`git config user.email …@x.com`/`@t.com`/`@test.com`/`example.com`/
# `example.invalid`) to exercise --owners/--pr-context/churn/merge-scout etc. test/README.md
# documents the same synthetic-fixture carve-out for arm 4's credential literals.
#
# PAIR_ALLOW — the `symbol@file.ext` / `sym@file.ext` community-label placeholder shape (a literal
# ".ext", not a synthetic domain) that two test fixtures use in prose to document ripwire's own
# `symbol@basename.ext:line:col` label format; each is exempted by its exact (path, address) pair,
# not by file, so nothing else in those files is waved through.
#
# V4 MED-1 / LOW-1: two more gaps closed. (a) the scan used to take only the FIRST address per
# LINE via find_address(line) then `continue` the whole line on a synthetic-domain match — a
# planted line with a synthetic address FOLLOWED by a real one on the same line
# (`git config user.email a@x.com  # contact: real.person@corp.io`) passed clean. It now walks
# every address on the line. (b) the synthetic-domain exemption used to apply tree-wide, but every
# legitimate synthetic-domain hit in this repo lives under test/ or bench/ (measured: 39 files,
# zero elsewhere) — it is now conjoined with a path check, so the same synthetic address in
# README/src/docs is treated as a leak, not a fixture.
PATH_ALLOW='^(third_party/|bench/cppbench/dataset\.lock$|docs/docs_commands_build\.py$)'
python3 - "$TMP/tracked.z" "$ROOT" "$PATH_ALLOW" > "$TMP/arm5b" 2> "$TMP/arm5b.err" <<'PY'
import os, re, sys
paths = [p.decode('utf-8', 'surrogateescape')
         for p in open(sys.argv[1], 'rb').read().split(b'\0') if p]
ROOT = sys.argv[2]
path_allow = re.compile(sys.argv[3])
SYNTHETIC_DOMAINS = frozenset( ( 'x.com', 'example.com', 'example.invalid', 't.com', 'test.com' ) )
PAIR_ALLOW = frozenset( (
    ( 'test/docscommandscheck.sh', 'sym@file.ext' ),
    ( 'test/docscommandscheck.sh', 'symbol@file.ext' ),
    ( 'test/showcase_capture.py', 'symbol@file.ext' ),
) )

sys.path.insert(0, os.path.join(ROOT, 'docs'))
try:
    import docs_commands_build as gen
except ImportError as exc:
    print(f'REFUSE import error: {exc}')
    sys.exit(1)
if not hasattr(gen, 'find_address'):
    print('REFUSE docs_commands_build has no find_address attribute')
    sys.exit(1)
find_address = gen.find_address

# Live positive control — not merely a callable-presence check: PROVES the returned function still
# recognises an email-shaped address, so an empty scan result below can only mean "genuinely clean",
# never "the scanner silently stopped matching anything" (a crash — or a renamed/no-op function —
# previously made this arm pass while a planted address in the committed tree went undetected).
CONTROL = 'definitely-not-a-real-person@example-control-domain.test'
if not find_address(f'contact: {CONTROL}'):
    print(f'REFUSE positive control failed: find_address() did not match a known-good address ({CONTROL})')
    sys.exit(1)

SELF = 'test/ripwirepubliccheck.sh'
for p in paths:
    if p == SELF or path_allow.match(p):
        continue
    try:
        data = open(p, 'rb').read()
    except OSError:
        continue
    if b'\0' in data:
        continue   # binary, skip
    text = data.decode('utf-8', 'replace')
    for i, line in enumerate(text.split('\n'), 1):
        # Walk every address on the line — not just the first — so a synthetic-domain hit early
        # on the line cannot shield a real address later on the SAME line (e.g. a planted
        # `git config user.email a@x.com  # contact: real.person@corp.io`).
        pos = 0
        while True:
            m = find_address(line[pos:])
            if not m:
                break
            addr = m.group(0)
            pos += m.end()
            domain = addr.split('@', 1)[1].lower() if '@' in addr else ''
            # The synthetic-domain exemption is scoped to test/ and bench/ — every legitimate
            # synthetic-domain hit in this tree lives under one of those two dirs; the same
            # address in README/src/docs is not a fixture, it is a leak.
            if domain in SYNTHETIC_DOMAINS and p.startswith(('test/', 'bench/')):
                continue
            if (p, addr) in PAIR_ALLOW:
                continue
            print(f'{p}:{i}: {addr}')
PY
py_status=$?
if grep -q '^REFUSE' "$TMP/arm5b"; then
    no "arm 5b — $( grep '^REFUSE' "$TMP/arm5b" )"
elif [ "$py_status" -ne 0 ]; then
    no "arm 5b — scanner crashed (python exit $py_status): $( tail -5 "$TMP/arm5b.err" | tr '\n' ' ' )"
elif [ -s "$TMP/arm5b" ]; then
    no "arm 5b — email-shaped address outside the allowlisted vendored/benchmark paths and synthetic test domains:"
    sed 's/^/          /' "$TMP/arm5b"
else
    ok "arm 5b — no email-shaped addresses outside vendored code, benchmark data and synthetic test domains"
fi

# ── arm 6: internal-pattern filenames, and docs/ index coverage ───────────────────────────────────
INTERNAL_NAME='(^|/)(PLAN_|AUDIT|NEXT_SESSION|KICKOFF_|HANDOFF_|IDEAS_|REPORT_|DESIGN_|RESEARCH_)'
# ONEOFF_ACCEPTED (arm 3, same rationale): the one owner-accepted PLAN file is exempt by exact path.
badnames="$( tr '\0' '\n' < "$TMP/tracked.z" | grep -E "$INTERNAL_NAME" | grep -Fxv "$ONEOFF_ACCEPTED" || true )"
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
        # a file counts as indexed if named directly OR if an ancestor directory is indexed with a
        # trailing slash (e.g. `captures/` covers dated capture files without per-regeneration churn)
        covered=0
        grep -Fq "$base" docs/README.md && covered=1
        dir="${base%/*}"
        while [ "$covered" = 0 ] && [ "$dir" != "$base" ] && [ -n "$dir" ]; do
            grep -Fq "${dir}/" docs/README.md && covered=1
            case "$dir" in */*) dir="${dir%/*}" ;; *) break ;; esac
        done
        [ "$covered" = 1 ] || missing="$missing$d
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
_grammars = ('bash', 'c', 'cpp', 'csharp', 'cuda', 'go', 'java', 'javascript', 'json',
             'objc', 'python', 'ruby', 'rust', 'swift', 'toml', 'yaml')
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

# ── arm 8: no dangling reference to a culled internal-pattern .md name ────────────────────────────
# Arm 6a catches the internal doc ITSELF being committed; this arm catches every OTHER tracked file
# still POINTING at one after it was culled — a comment, a README line, a data file's prose field
# citing "PLAN_x.md" or "SPEC.md" when no such file ships in this tree. A name that resolves to a
# real shipped file (basename match, anywhere in the tree — docs move) is not a violation.
#
# EXEMPT (path, NAME) PAIRS — not whole files. A whole-file exemption hides a NEW dangling reference
# planted anywhere else in an exempted file forever (an unrelated PLAN_/SPEC-shaped name landing in
# test/docmentioncheck.sh, say, would sail through undetected); pinning the exact name each file is
# known to legitimately carry keeps that file's OTHER lines covered.
#   test/docmentioncheck.sh    : DESIGN_widgetTotals.md — a SYNTHETIC fixture name the gate creates
#                                 and scores at runtime (doc-mention surfacing test), never a citation.
#   test/historyoraclecheck.sh : PLAN_relief.md — a SYNTHETIC fixture doc the gate writes into its own
#                                 scratch git repo (chosen to look like an internal doc on purpose, to
#                                 prove doc-drift/whereis behave the same on a PLAN_-shaped filename),
#                                 never a citation of a real file.
#   bench/locbench/results/{r1_anchorhop,r1cpp_anchorhop}/*_candidate_implementation.patch : SPEC.md —
#                                 archived historical git diffs of a past experiment. Their hunks were
#                                 checked and carry exactly one internal-pattern name each (SPEC.md);
#                                 rewriting patch text would falsify the historical record, and the
#                                 patch is already unappliable in this tree regardless (it patches a
#                                 file — SPEC.md — that was never exported here). The SAME patch also
#                                 carries the BARE "SPEC §" shape (no ".md") that the second pattern
#                                 below catches, for the same never-rewrite-history reason.
ARM8_EXEMPT_PAIRS='test/docmentioncheck.sh|DESIGN_widgetTotals.md
test/historyoraclecheck.sh|PLAN_relief.md
bench/locbench/results/r1_anchorhop/r1_candidate_implementation.patch|SPEC.md
bench/locbench/results/r1cpp_anchorhop/r1cpp_candidate_implementation.patch|SPEC.md
bench/locbench/results/r1cpp_anchorhop/r1cpp_candidate_implementation.patch|SPEC §'
# A QUOTED heredoc delimiter ('PY') is deliberate: an unquoted one lets the shell expand `$vars` AND
# run backtick/`$()` command substitution over the ENTIRE body, including python source comments —
# this file's own "mirrors the main sweep's `grep -I`" comment below would otherwise get executed as
# a shell command mid-heredoc (it was, until this was caught: a bare `grep -I` with no pattern/file
# prints its usage banner to stderr). The exempt pairs are passed as an argv string instead, so no
# shell expansion touches the python source at all.
python3 - "$TMP/tracked.z" "$ARM8_EXEMPT_PAIRS" > "$TMP/arm8" <<'PY'
import os, re, sys
paths = [p.decode('utf-8', 'surrogateescape')
         for p in open(sys.argv[1], 'rb').read().split(b'\0') if p]
tracked_basenames = {os.path.basename(p) for p in paths}
SELF = 'test/ripwirepubliccheck.sh'   # this file's own arm 8 source names the pattern literally
exempt_pairs = set()
for line in sys.argv[2].splitlines():
    line = line.strip()
    if not line:
        continue
    path, name = line.split('|', 1)
    exempt_pairs.add((path, name))
# (1) NAMED-FILE shape: a citation of a specific culled .md filename (PLAN_x.md, SPEC.md, ...).
pat_named = re.compile(r'\b(?:PLAN_|AUDIT|DESIGN_|RESEARCH_|NEXT_SESSION|KICKOFF_|HANDOFF_|IDEAS_|REPORT_|SPEC)[A-Za-z0-9_.-]*\.md\b')
# (2) BARE-NAME shape: no ".md" at all, e.g. "RESEARCH §2d", "PLAN §Execution", "SPEC §6/§8" — the 19
# residual dangling citations V3 found (pattern_named requires the ".md" suffix, so it silently missed
# these). Requiring the DOC WORD immediately before "§" is what keeps this narrow: a bare round label
# like "§P8"/"§A6a"/"§B12" with NO doc name in front is NOT internal-pattern-shaped and stays exempt by
# construction (nothing in this pattern can match it), and "field-notes" is included because it is the
# other never-shipped internal doc name this tree used to cite the same way (see git history: the sibling
# fix that cleared the first wave of these named it explicitly).
pat_bare = re.compile(r'\b(?:PLAN|SPEC|RESEARCH|DESIGN|AUDIT|IDEAS|HANDOFF|KICKOFF|NEXT_SESSION|field-notes)\s*§')
# V4 LOW-2: pat_bare is matched per LINE, so a citation split across a comment-continuation —
# "// see RESEARCH" then "// §4 for the rationale" — never appears in either single line and is
# invisible. pat_named cannot have the same gap: its charclass ([A-Za-z0-9_.-]*) contains no
# whitespace, so a real ".md" filename can never itself span a line break.
#
# Fix: for each line, ALSO build a 2-line joined copy with the next line's comment leader (//, #,
# *) stripped and a single space substituted for the join, then scan that copy too — but only
# report a match whose span actually CROSSES the join point (starts before the boundary, ends at
# or after it). Matches entirely inside line i are already caught by the single-line pass above;
# without this filter they would be reported twice. Reported at the FIRST line of the pair, since
# that is where a reader would look to find the citation.
comment_cont_re = re.compile(r'^[ \t]*(?://|#|\*)[ \t]*')
for p in paths:
    if p == SELF:
        continue
    try:
        data = open(p, 'rb').read()
    except OSError:
        continue
    if b'\0' in data:
        continue   # binary, skip (mirrors the main sweep's grep -I)
    text = data.decode('utf-8', 'replace')
    lines = text.split('\n')
    lineCount = len(lines)
    for lineIndex, line in enumerate(lines):
        i = lineIndex + 1
        for m in pat_named.finditer(line):
            name = m.group(0)
            if os.path.basename(name) in tracked_basenames:
                continue   # a real shipped file — not a violation
            if (p, name) in exempt_pairs:
                continue   # this EXACT (file, name) pair is a known-synthetic/archived reference
            print(f'{p}:{i}: references absent doc {name}')
        for m in pat_bare.finditer(line):
            name = m.group(0)
            if (p, name) in exempt_pairs:
                continue   # this EXACT (file, name) pair is a known-archived reference
            print(f'{p}:{i}: bare doc-name citation with no shipped doc: {name}')
        if lineIndex + 1 < lineCount:
            boundary = len(line)
            joined = line + ' ' + comment_cont_re.sub('', lines[lineIndex + 1])
            for m in pat_bare.finditer(joined):
                if not (m.start() < boundary and m.end() > boundary):
                    continue   # not a genuine cross-line span — either fully in line i (already
                               # reported above) or fully in the next line (that line's own pass
                               # will find it when lineIndex advances)
                name = m.group(0)
                if (p, name) in exempt_pairs:
                    continue   # this EXACT (file, name) pair is a known-archived reference
                print(f'{p}:{i}: bare doc-name citation split across two comment lines: {name}')
PY
if [ -s "$TMP/arm8" ]; then
    no "arm 8 — dangling reference to a culled internal-pattern .md name:"
    sed 's/^/          /' "$TMP/arm8"
else
    ok "arm 8 — no dangling references to culled internal-pattern .md names"
fi

printf 'ripwirepubliccheck: %s tracked file(s) swept\n' "$tracked"
[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
