#!/usr/bin/env python3
# test/toolcallroutefix/gen_corpus.py — deterministic builder for corpus.jsonl, the labelled command-
# shape corpus test/toolcallroutecheck.sh drives hooks/ripwire-claude-toolroute.sh against. Every axis
# (patterns, dirs, extensions, binaries) below is hand-written from the meter's own classes named in
# docs/EVALS.md's second-router-arm registration — the combinatorics only multiply hand-authored
# values, they do not invent new shapes. Re-run and commit the output when an axis changes; the script
# is deterministic (fixed iteration order, no randomness) so a re-run with no axis change reproduces
# corpus.jsonl byte-for-byte.
#
# Each row: {id, class, tool_name, tool_input, expect_status, expect_recommended, expect_reason}.
#   expect_status      "recommend" | "abstain" | "none" ("none" = the hook must produce NO stdout at
#                       all — not a routable event, e.g. cat/sed/polls/other tools — vs "abstain",
#                       which is a routable event that logged a decision row but injected nothing).
#   expect_recommended a LIST of acceptable bare verbs when expect_status=="recommend" (a Read's
#                       resolved_symbols guess is index-dependent, so "read-source" rows accept either
#                       --expand or --for — both are correct, non-harmful outcomes for that shape).
#   expect_reason      the `reason` field's expected value when expect_status=="abstain", or null when
#                       it does not matter / is not applicable.
#
# Usage: python3 test/toolcallroutefix/gen_corpus.py > test/toolcallroutefix/corpus.jsonl
import json
import sys

rows = []
_id = 0


def add(cls, tool_name, tool_input, status, recommended=None, reason=None):
    global _id
    _id += 1
    rows.append({
        "id": _id,
        "class": cls,
        "session_id": "corpus-%d" % _id,      # unique per row -- the per-session cap is tested separately
        "tool_name": tool_name,
        "tool_input": tool_input,
        "expect_status": status,
        "expect_recommended": recommended,
        "expect_reason": reason,
    })


# ── grep -r on SOURCE dirs -- recommend --grep. Patterns and dirs are the hand-written axes; the
#    binary forms cover grep/egrep/fgrep with an explicit recursive flag, in both -flag orders.
GREP_SRC_PATTERNS = [
    "meterInit", "parseArgs", "TODO_FIXME", "user_email", "computeBudget", "ClassName",
]
GREP_SRC_DIRS = ["src/", "lib/", ".", "app/"]
GREP_BASH_FORMS = [
    lambda pat, d: "grep -rn %s %s" % (pat, d),
    lambda pat, d: "egrep -r %s %s" % (pat, d),
    lambda pat, d: "fgrep -r %s %s" % (pat, d),
]
for pat in GREP_SRC_PATTERNS:
    for d in GREP_SRC_DIRS:
        for form in GREP_BASH_FORMS:
            add("grep-src", "Bash", {"command": form(pat, d)}, "recommend", ["--grep"])

# ── grep -r on NON-SOURCE dirs -- abstain, reason=non-source.
GREP_NONSRC_DIRS = ["docs/", "doc/", "node_modules/", "vendor/", "third_party/", ".git/", "dist/", "build/"]
GREP_NONSRC_PATTERNS = ["needle", "TODO", "\"exact phrase\"", "version"]
for pat in GREP_NONSRC_PATTERNS:
    for d in GREP_NONSRC_DIRS:
        add("grep-nonsource", "Bash", {"command": "grep -rn %s %s" % (pat, d)}, "abstain", None, "non-source")
        add("grep-nonsource", "Bash", {"command": "rg -n %s %s" % (pat, d)}, "abstain", None, "non-source")

# ── rg variants -- source dirs recommend, non-source abstain.
RG_PATTERNS = ["needle", "TODO", "computeBudget", "user_email", "\"quoted phrase\""]
for pat in RG_PATTERNS:
    for d in GREP_SRC_DIRS:
        add("rg-src", "Bash", {"command": "rg -n %s %s" % (pat, d)}, "recommend", ["--grep"])
RG_NONSRC_PATTERNS = ["needle", "TODO", "version"]
for pat in RG_NONSRC_PATTERNS:
    for d in ["docs/", "node_modules/", "vendor/", ".git/"]:
        add("rg-nonsource", "Bash", {"command": "rg --hidden %s %s" % (pat, d)}, "abstain", None, "non-source")

# ── Read of a SOURCE file -- recommend, either --expand (resolved) or --for (fallback), both correct.
READ_SOURCE_EXTS = [
    "cpp", "cc", "h", "hpp", "c", "py", "ts", "tsx", "js", "jsx", "go", "rs", "java", "rb",
    "swift", "cs", "m", "mm", "cu", "cuh", "metal", "sh", "json",
]
for ext in READ_SOURCE_EXTS:
    add("read-source", "Read", {"file_path": "src/thing.%s" % ext}, "recommend", ["--expand", "--for"])
# a few REAL files in this repo, so at least some rows exercise the resolved_symbols guard for real.
for real in ["src/model.h", "src/cli.h", "src/wrap.h", "hooks/ripwire-nudge.sh", "src/lanes.h"]:
    add("read-source-real", "Read", {"file_path": real}, "recommend", ["--expand", "--for"])

# ── Read of a docs/config file -- abstain, reason=non-source.
READ_DOCS_EXTS = ["md", "txt", "yml", "yaml", "toml", "rst", "pdf", "png", "log", "csv"]
for ext in READ_DOCS_EXTS:
    add("read-docs", "Read", {"file_path": "notes/thing.%s" % ext}, "abstain", None, "non-source")

# ── cat/sed/head/tail/less/more reads -- not a routable event at all (expect_status="none").
CAT_SED_CMDS = [
    "cat src/model.h", "sed -n '1,20p' src/model.h", "head -50 src/model.h", "tail -20 src/model.h",
    "less src/model.h", "more src/model.h", "cat -n src/wrap.h", "sed '/pattern/d' src/wrap.h",
]
for cmd in CAT_SED_CMDS:
    add("cat-sed", "Bash", {"command": cmd}, "none")

# ── build/process polls -- not a routable event (expect_status="none").
POLL_CMDS = [
    "ps aux", "ps -ef | grep node", "tail -f /var/log/app.log", "cmake --build build -j 6",
    "npm run build", "git status", "docker ps", "top -l 1", "watch -n1 date",
]
for cmd in POLL_CMDS:
    add("poll", "Bash", {"command": cmd}, "none")

# ── notification-shaped inputs -- routable SHAPE (grep/read), but the marker forces abstain.
add("notification", "Bash", {"command": 'grep -rn "[SYSTEM NOTIFICATION" .claude/sessions/'}, "abstain", None, "notification")
add("notification", "Bash", {"command": 'grep -rn "<task-notification>" logs/'}, "abstain", None, "notification")
add("notification", "Bash", {"command": 'grep -rn "<task-notification> wake" src/'}, "abstain", None, "notification")
add("notification", "Read", {"file_path": "notes/[SYSTEM NOTIFICATION].md"}, "abstain", None, "notification")
add("notification", "Read", {"file_path": "notes/<task-notification>.txt"}, "abstain", None, "notification")

# ── pipes -- the recursive grep itself is still recognized past a trailing pipe segment.
PIPE_CMDS = [
    "grep -rn foo src/ | wc -l", "rg -n bar lib/ | head -10", 'grep -rn "TODO" . | sort | uniq -c',
    "egrep -r pattern app/ | grep -v test", "grep -rn needle src/ | cut -d: -f1", "rg -n alpha . | tail -5",
]
for cmd in PIPE_CMDS:
    add("pipe", "Bash", {"command": cmd}, "recommend", ["--grep"])

# ── quoted patterns (with internal spaces) -- still a single pattern token.
QUOTED_CMDS = [
    'grep -rn "hello world" src/', "grep -rn 'user email' lib/", 'rg "multi word phrase" .',
    'egrep -r "two words" app/', 'grep -rn "a b c" src/', "fgrep -r 'literal string' hooks/",
]
for cmd in QUOTED_CMDS:
    add("quoted", "Bash", {"command": cmd}, "recommend", ["--grep"])

# ── regex metacharacters inside the pattern -- still a single pattern token, still recommend.
REGEX_CMDS = [
    'grep -rn "TODO:.*fix" src/', 'grep -rn "^func " lib/', 'grep -rn "foo\\|bar" src/',
    'grep -rn "a{2,3}" src/', 'grep -rE "colou?r" src/', 'rg -n "\\bword\\b" .',
]
for cmd in REGEX_CMDS:
    add("regex", "Bash", {"command": cmd}, "recommend", ["--grep"])

# ── multi -e (ambiguous which pattern is THE pattern) -- abstain, reason=multi-pattern.
MULTI_E_CMDS = [
    "grep -r -e foo -e bar src/", "grep -rn -e alpha -e beta -e gamma lib/",
    "egrep -r -e one -e two app/", "grep -r -e x -e y -e z -e w .",
]
for cmd in MULTI_E_CMDS:
    add("multi-e", "Bash", {"command": cmd}, "abstain", None, "multi-pattern")

# ── unparseable / no bare pattern at all -- abstain, reason=unparseable or no-pattern.
add("unparseable", "Bash", {"command": 'grep -rn "unterminated src/'}, "abstain", None, "unparseable")
add("unparseable", "Bash", {"command": 'rg "another unterminated lib/'}, "abstain", None, "unparseable")
add("no-pattern", "Bash", {"command": "grep -rn"}, "abstain", None, "no-pattern")
add("no-pattern", "Bash", {"command": "grep --recursive"}, "abstain", None, "no-pattern")

# ── tools this router never touches at all -- expect_status="none" (fast bail, no row).
for tn in ["Edit", "Write", "Task", "Glob", "WebFetch", "NotebookEdit"]:
    add("other-tool", tn, {}, "none")

# ── ripwire's own MCP verbs -- never nudged toward itself; fast bail, no row.
for tn in ["mcp__ripwire__grep", "mcp__ripwire__for", "mcp__ripwire__expand"]:
    add("ripwire-mcp", tn, {}, "none")

sys.stdout.write("\n".join(json.dumps(r, sort_keys=True) for r in rows) + "\n")
print("gen_corpus: %d rows" % len(rows), file=sys.stderr)
