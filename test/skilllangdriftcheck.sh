#!/usr/bin/env bash
# skilllangdriftcheck.sh — SKILL-LANG-DRIFT (issue #521): the skills and docs must not contradict the binary's own
# language list.
#
# WHY. skills/ripwire-router/SKILL.md once said "ripwire parses C++, C, ... Swift; JSON (config keys) — nothing else" (15
# languages) and named PHP and Kotlin as examples of unsupported languages, while `ripwire --help` listed 26. An agent
# that reads the router on an Elixir, PHP or Kotlin repo is told to fall back to `rg`, and skips the tool exactly where
# it works. Nothing in the suite compared a skill's language claim with the shipped binary, so the copy aged silently.
# This gate is the readmedriftcheck.sh discipline applied to that claim: the binary's --help is the AUTHORITY and the
# prose is checked against it.
#
# DERIVATION. The Languages line(s) of `$BIN --help`: the text from "Languages:" to the first blank line, with every
# parenthesised group removed (extensions, grammar notes), split on , ; and /. Names with no letters in common with
# prose (a single "C") are required in a closed list but not scanned for in "unsupported" claims. Names that are also
# English words (Go, Rust, Swift, Dart, Ruby, Bash, Metal) match only capitalised; the rest match in any case.
# The authority is checked too (arm F): --help's names must equal the Lang set of src/ingest_crawl.h's extension table,
# so a language the crawler indexes cannot be missing from --help (Clojure was, until #523).
#
# WHAT IS CHECKED, over skills/**/*.md, README.md, AGENTS.md, CLAUDE.md, INSTALL.md, CONTRIBUTING.md, hooks/*.sh and
# docs/*.md (exempt: docs/COMMANDS.md is generated from --help; the dated EVALS/LINEAGE/research records quote what was
# true then):
#   UNSUP   a --help language named as unsupported: "another/other/unsupported language(s) (NAME, ...)",
#           "unsupported language(s): NAME" / "Unsupported: NAME" / "... such as NAME", "ripwire does not (yet)
#           parse/index/read/support/handle NAME", "ripwire won't index NAME", "NAME is not supported", "no NAME support".
#   CLOSED  a CLOSED list — a run of four or more --help names ending at "nothing else" / "nothing more" / "no other language",
#           or following "supports/parses/indexes/reads only" / "only these languages" — must name EVERY --help
#           language. It is judged on that run of names itself, not on the sentence or paragraph around it.
# A closed list is allowed; a stale one is not. Pointing at --help instead of restating it is the cheapest way to pass.
# A per-feature sentence that trips a pattern ("Per-language rules cover C++, Python, Go, Rust; no other language has
# the large-function gate.") is exempted by the marker <!-- skilllangdrift: ok --> on its line(s).
#
# Arms:
#   (A) the Languages line parses to a sane set (>= 20 names, and the tokens the issue named are in it)
#   (F) the authority: --help names == the crawler table's Lang set, both ways
#   (B) the DRIFT arm — the real tree has no UNSUP and no CLOSED violation (and the scanner exited 0)
#   (C) RED FIXTURE — the pre-fix router paragraph, verbatim, trips both UNSUP (PHP, Kotlin) and CLOSED
#   (G) RECALL — eleven further wordings are each RED (none was caught by the first version of this gate)
#   (D) TWIN — a fake doc naming truly unsupported languages (Haskell, OCaml, Scala, Zig) as unsupported, and closed
#       lists that do name every --help language, all PASS: the checker is not just rejecting every language claim
#   (H) FALSE-POSITIVE TWINS — ordinary prose passes; per-feature sentences pass with the marker and are RED without it
#   (E) the unsupported names the router uses today really are absent from --help
#
# Usage:  bash test/skilllangdriftcheck.sh [BIN]      (BIN falls back to RIPWIRE_BIN, then build/ripwire)
#         SKILLLANGDRIFT_ROOT=DIR  scans another tree (the way to see the gate red on an older checkout)
# Exit:   0 clean · 1 an arm failed · 2 usage / missing prerequisite
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
SCAN="${SKILLLANGDRIFT_ROOT:-$ROOT}"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "skilllangdriftcheck: no executable ripwire binary: $BIN"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "skilllangdriftcheck: python3 required"; exit 2; }
T="$( mktemp -d "${TMPDIR:-/tmp}/skilllangdrift.XXXXXX" )" || exit 2
trap 'rm -rf "$T"' EXIT

"$BIN" --help >"$T/help.txt" 2>&1

# The checker. argv: help.txt, mode (names | crawl | scan), then files. Prints one VIOLATION line per problem (crawl,
# scan) or the names (names). Exit 0 unless a file cannot be read; the caller counts lines AND checks the status.
cat >"$T/check.py" <<'PY'
import re, sys
help_path, mode, files = sys.argv[1], sys.argv[2], sys.argv[3:]
txt = open(help_path, encoding="utf-8", errors="replace").read()
m = re.search(r"Languages:(.*?)(?:\n\s*\n|\Z)", txt, re.S)
raw = m.group(1) if m else ""
def strip_parens(s):
    prev = None
    while prev != s:                    # strip (nested) parenthesised groups
        prev = s
        s = re.sub(r"\([^()]*\)", "", s)
    return s
raw = strip_parens(raw)
names = []
for tok in re.split(r"[,;/\n]", raw):
    tok = tok.strip().rstrip(".").strip()
    if tok and re.search(r"[A-Za-z]", tok) and tok not in names:
        names.append(tok)
if mode == "names":
    print("\n".join(names)); sys.exit(0)

# crawl: the crawler's extension table (kLangTable rows `{ ".ext", Lang::X, ...`) is what really gets indexed. Every
# Lang it maps must surface as a --help name, and every --help name must come from a Lang it maps. One Lang can carry
# several --help names (Cpp = C++ + the Metal and CUDA rows; ObjC = ObjC + ObjC++). A Lang missing from HELP_NAMES is
# itself a violation: a new language needs its --help spelling written down here, which is the moment to add it there.
if mode == "crawl":
    HELP_NAMES = {"Cpp": ["C++", "Metal", "CUDA"], "C": ["C"], "ObjC": ["ObjC", "ObjC++"], "Python": ["Python"],
                  "TypeScript": ["TypeScript"], "JavaScript": ["JavaScript"], "Java": ["Java"], "Ruby": ["Ruby"],
                  "Php": ["PHP"], "Lua": ["Lua"], "Elixir": ["Elixir"], "Dart": ["Dart"], "Kotlin": ["Kotlin"],
                  "Clojure": ["Clojure"], "Bash": ["Bash"], "Go": ["Go"], "Rust": ["Rust"], "Swift": ["Swift"],
                  "CSharp": ["C#"], "GDScript": ["GDScript"], "Json": ["JSON"], "Toml": ["TOML"], "Yaml": ["YAML"],
                  "Markdown": ["Markdown"]}
    src = open(files[0], encoding="utf-8", errors="replace").read()
    langs = sorted(set(re.findall(r"\{\s*(?:\"[^\"]*\"|k\w+)\s*,\s*Lang::(\w+)\s*,", src)))
    if len(langs) < 20:
        print(f"CRAWL only {len(langs)} Lang rows parsed from {files[0]} — the table's shape changed"); sys.exit(0)
    want = []
    for L in langs:
        if L not in HELP_NAMES:
            print(f"CRAWL Lang::{L} has an extension row but no --help spelling in this gate's HELP_NAMES"); continue
        for n in HELP_NAMES[L]:
            want.append(n)
            if n not in names:
                print(f"CRAWL Lang::{L} is indexed but the --help Languages line lacks {n}")
    for n in names:
        if n not in want:
            print(f"CRAWL --help lists {n} but no extension row in the crawler table indexes it")
    sys.exit(0)

# Names that are ordinary English words ("go", "rust", "swift") match only as capitalised; the rest match in any case
# ("ripwire does not support php").
WORDS = {"c", "go", "rust", "swift", "dart", "ruby", "bash", "metal"}
def pat(n):
    return re.compile(r"(?<![\w+#])" + re.escape(n) + r"(?![\w+#])", 0 if n.lower() in WORDS else re.I)
pats = {n: pat(n) for n in names}
scannable = [n for n in names if len(n) > 1]           # a lone "C" is noise in prose
UNSUP = [
    # "another language (PHP, Kotlin, ...)"
    re.compile(r"(?:another|other|unsupported|unlisted|different)\s+languages?\s*\(([^)]*)\)", re.I),
    # "unsupported language(s): PHP" / "unsupported languages such as PHP" / "Unsupported: PHP, Kotlin" — a LIST
    # introducer is required, so "files in an unsupported language are counted ..., unlike Python" is not a claim
    re.compile(r"\bunsupported(?:\s+languages?)?\s*(?::|,?\s+(?:such\s+as|like|e\.g\.,?|including))\s*([^.\n]{0,80})", re.I),
    # "ripwire does not (yet) parse/index/read/support/handle NAME", "ripwire won't index NAME"
    re.compile(r"\bripwire\s+(?:does\s+not|doesn't|cannot|can't|won't|will\s+not)\s+(?:yet\s+|currently\s+)?"
               r"(?:parse|index|read|support|handle)\s+([^.\n]{0,40})", re.I),
    # "NAME is not supported", "NAME and NAME are unsupported" — the clause before it, back to , ; : or a sentence end
    re.compile(r"([^.;:,\n]{1,40}?)\s+(?:is|are)(?:\s+not|n't|\s+un)\s*supported\b", re.I),
    # "no NAME support"
    re.compile(r"\bno\s+([^.;:,\n]{1,30}?)\s+support\b", re.I),
]
CLOSE_AFTER = re.compile(r"nothing else|nothing more|no other languages?", re.I)        # the list ENDS here
CLOSE_BEFORE = re.compile(r"\b(?:(?:supports?|parses?|indexes|reads)\s+)?only\s+these\s+languages\s*:?"
                          r"|\b(?:supports?|parses?|indexes|reads)\s+only\b", re.I)               # the list STARTS here
SENT = re.compile(r"[.!?:](?=\s)")
MARK = "skilllangdrift: ok"            # an HTML comment on the line exempts that line: <!-- skilllangdrift: ok -->
# A LIST is a run of --help names joined by separators (, ; / ** — and/or), with at most one trailing noun ("Rust files,
# nothing else"). Only the run that touches the closing phrase is judged, so names elsewhere in the sentence or
# paragraph neither complete nor trigger it.
NAME = "|".join(re.escape(n) if n.lower() in WORDS else "(?i:" + re.escape(n) + ")"
                for n in sorted(names, key=len, reverse=True))
NAME = r"(?<![\w+#])(?:" + NAME + r")(?![\w+#])"
GAP = r"(?:[\s,;/*`'\"\u2014\u2013-]|\band\b|\bor\b)*"
RUN_TO_END = re.compile(r"(?:" + NAME + GAP + r")+(?:\w+" + GAP + r")?$")
RUN_FROM_START = re.compile(r"^" + GAP + r"(?:" + NAME + GAP + r")+")

def closed(path, line, lst):
    if sum(1 for n in scannable if pats[n].search(lst)) >= 4:     # judged on the LIST, not the paragraph around it
        missing = [n for n in names if not pats[n].search(lst)]
        if missing:
            print(f"CLOSED {path}:{line}: closed language list lacks " + ", ".join(missing))
        return True
    return False

for path in files:
    body = open(path, encoding="utf-8", errors="replace").read()
    body = "\n".join("" if MARK in ln else ln for ln in body.split("\n"))
    for pm in re.finditer(r"(?:[^\n]+\n?)+", body):          # paragraphs
        para = pm.group(0)
        line = body.count("\n", 0, pm.start()) + 1
        flat = re.sub(r"\s+", " ", para)
        for u in UNSUP:
            for um in u.finditer(flat):
                for n in scannable:
                    if pats[n].search(um.group(1)):
                        print(f"UNSUP {path}:{line}: {n} is a --help language but is called unsupported")
        for cm in CLOSE_AFTER.finditer(flat):                # the list: the run of names that ends at the phrase
            before = strip_parens(flat[:cm.start()])
            cut = [b.end() for b in SENT.finditer(before)]
            r = RUN_TO_END.search(before[cut[-1] if cut else 0:])
            if r and closed(path, line, r.group(0)):
                break
        for cm in CLOSE_BEFORE.finditer(flat):               # the list: the run of names that follows the phrase
            r = RUN_FROM_START.search(strip_parens(flat[cm.end():]))
            if r and closed(path, line, r.group(0)):
                break
PY

# ── (A) the Languages line parses ───────────────────────────────────────────────────────────────────────────
python3 -I "$T/check.py" "$T/help.txt" names >"$T/names.txt"
nn="$( wc -l <"$T/names.txt" | tr -d ' ' )"
miss=""; for want in PHP Kotlin Elixir Lua Dart GDScript Clojure CUDA TOML YAML Markdown 'C#' Go; do
    grep -qxF "$want" "$T/names.txt" || miss="$miss $want"; done
{ [ "${nn:-0}" -ge 20 ] && [ -z "$miss" ]; } \
    && ok "(A) --help Languages line parses to $nn names, including the ones issue #521 named" \
    || no "(A) --help Languages line parsed to ${nn:-0} names; missing:${miss:- none}"

# ── (F) the AUTHORITY is itself checked: --help names == the crawler table's Lang set ───────────────────────
CRAWL="$ROOT/src/ingest_crawl.h"
if [ -f "$CRAWL" ]; then
    python3 -I "$T/check.py" "$T/help.txt" crawl "$CRAWL" >"$T/crawl.out" 2>&1; crc=$?
    if [ "$crc" -eq 0 ] && [ ! -s "$T/crawl.out" ]; then
        ok "(F) every Lang in src/ingest_crawl.h's extension table has its name on the --help Languages line, and back"
    else no "(F) --help Languages line and the crawler table disagree (exit $crc):"; sed 's/^/        /' "$T/crawl.out"; fi
else no "(F) src/ingest_crawl.h not found under $ROOT"; fi

# ── (B) the DRIFT arm: the real tree ────────────────────────────────────────────────────────────────────────
# Exempt: docs/COMMANDS.md is generated from --help itself (docscommandscheck.sh pins it); EVALS, LINEAGE and research/
# are dated records that quote what was true then. hooks/ holds shell scripts, so its *.sh files are what is scanned.
( cd "$SCAN" || exit 2
  { ls README.md AGENTS.md CLAUDE.md INSTALL.md CONTRIBUTING.md 2>/dev/null
    find skills -type f -name '*.md' 2>/dev/null
    find hooks -type f -name '*.sh' 2>/dev/null
    find docs -maxdepth 1 -type f -name '*.md' 2>/dev/null \
        | grep -vE '/(EVALS|LINEAGE|COMMANDS)\.md$|/research/' ; } | sort -u ) >"$T/files.txt"
nf="$( wc -l <"$T/files.txt" | tr -d ' ' )"
grep -q 'ripwire-router/SKILL.md' "$T/files.txt" || no "(B) liveness: the router skill is not in the scanned set (SCAN=$SCAN)"
grep -q '^hooks/.*\.sh$' "$T/files.txt" || no "(B) liveness: no hooks/*.sh in the scanned set (SCAN=$SCAN)"
( cd "$SCAN" && tr '\n' '\0' <"$T/files.txt" | xargs -0 python3 -I "$T/check.py" "$T/help.txt" scan ) \
    >"$T/real.out" 2>"$T/real.err"
src=$?
if [ "$src" -ne 0 ]; then
    no "(B) the scanner exited $src over $nf files:"; sed 's/^/        /' "$T/real.err"
elif [ -s "$T/real.out" ]; then
    no "(B) $( wc -l <"$T/real.out" | tr -d ' ' ) language-claim violation(s) over $nf files:"; sed 's/^/        /' "$T/real.out"
else ok "(B) $nf skill/doc/hook files make no claim that contradicts the --help Languages line"; fi

# scan TEXT -> the checker's output for a one-paragraph fixture
scan(){ printf '%s\n' "$1" >"$T/fx.md"; python3 -I "$T/check.py" "$T/help.txt" scan "$T/fx.md"; }

# ── (C) RED FIXTURE: the pre-fix router paragraph, verbatim ─────────────────────────────────────────────────
cat >"$T/stale.md" <<'EOF'
## Wrong tool for the job

ripwire parses **C++, C, ObjC/ObjC++, Metal (MSL), C#, Python, TypeScript, JavaScript, Java, Ruby, Bash, Go,
Rust, Swift; JSON (config keys)** — nothing else. A repo in another language (PHP, Kotlin, ...) gets a silently thin or
empty map, not an error — don't mistake that for
"nothing here." Reach for plain `rg` + reads instead.
EOF
python3 -I "$T/check.py" "$T/help.txt" scan "$T/stale.md" >"$T/stale.out"
u="$( grep -c '^UNSUP' "$T/stale.out" )"; c="$( grep -c '^CLOSED' "$T/stale.out" )"
{ [ "$u" -ge 2 ] && [ "$c" -ge 1 ] && grep -q 'PHP is a' "$T/stale.out" && grep -q 'Kotlin is a' "$T/stale.out" \
    && grep -q 'CLOSED.*Elixir' "$T/stale.out"; } \
    && ok "(C) the pre-fix router paragraph is RED: $u UNSUP (PHP, Kotlin) + $c CLOSED (lacks Elixir ...)" \
    || { no "(C) the pre-fix paragraph was not caught (UNSUP=$u CLOSED=$c)"; sed 's/^/        /' "$T/stale.out"; }

# ── (G) RECALL: each further wording is RED (each one passed the first version of this gate) ────────────────
all="$( paste -sd, "$T/names.txt" | sed 's/,/, /g' )"
noPhp="$( grep -vxF PHP "$T/names.txt" | paste -sd, - | sed 's/,/, /g' )"
g=0; gn=0
red(){ # label kind name text
    gn=$(( gn + 1 ))
    if scan "$4" | grep -q "^$2 .*$3"; then g=$(( g + 1 )); else no "(G) not caught [$1]: $4"; fi; }
red is-not-supported  UNSUP  PHP      'PHP is not supported by ripwire.'
red no-x-support      UNSUP  PHP      'ripwire has no PHP support.'
red not-yet-parse     UNSUP  PHP      'ripwire does not yet parse PHP.'
red wont-index        UNSUP  Lua      "ripwire won't index Lua files."
red unsupported-colon UNSUP  Kotlin   'Unsupported: PHP, Kotlin.'
red lowercase         UNSUP  PHP      'ripwire does not support php.'
red supports-only     CLOSED Kotlin   'ripwire supports only C++, C, Python, Go and Rust.'
red only-these        CLOSED Kotlin   'Ripwire supports only these languages: Python, Java, Rust, Go.'
red nothing-more      CLOSED Elixir   'It reads C++, Python, Go, Rust and Java — and nothing more.'
red list-not-para     CLOSED 'lacks PHP' "ripwire parses $noPhp — nothing else. A PHP repo: use rg."
red stale-after-full  CLOSED Kotlin   "ripwire parses $all. Of those, it parses Python, Java, Rust and Go, and nothing else."
[ "$g" = "$gn" ] && ok "(G) $g further wordings are RED: is-not-supported, no-X-support, does-not-yet, won't-index, Unsupported:, lowercase, supports-only, only-these, and-nothing-more, and a closed list judged on itself"

# ── (D) TWIN: truthful claims pass ──────────────────────────────────────────────────────────────────────────
{ printf 'ripwire does not parse Haskell, OCaml, Scala or Zig. A repo in another language (Haskell, OCaml, Scala, Zig)\n'
  printf 'gets an empty map with unindexed= naming the extensions; these are unsupported languages.\n\n'
  printf 'ripwire parses **%s** and nothing else.\n\n' "$all"
  printf 'ripwire supports only these languages: %s.\n' "$all"; } >"$T/twin.md"
python3 -I "$T/check.py" "$T/help.txt" scan "$T/twin.md" >"$T/twin.out"
if [ ! -s "$T/twin.out" ] && grep -q 'nothing else' "$T/twin.md" && grep -q 'Haskell' "$T/twin.md"; then
    ok "(D) twin: a fake doc calling Haskell/OCaml/Scala/Zig unsupported, and closed lists naming all $nn languages, pass"
else no "(D) twin doc was flagged (or the fixture lost its claims)"; sed 's/^/        /' "$T/twin.out"; fi

# ── (H) FALSE-POSITIVE TWINS: ordinary prose passes ─────────────────────────────────────────────────────────
# Two pass on the patterns alone; per-feature coverage sentences need the line marker, and are RED without it, so the
# marker is what excuses them.
h=0; hn=0
green(){ hn=$(( hn + 1 )); out="$( scan "$1" )"; [ -z "$out" ] && h=$(( h + 1 )) || no "(H) flagged: $1 -> $out"; }
green 'An unsupported language never errors; Go and Rust repos get the full map.'
green 'Files in an unsupported language are counted in unindexed=, unlike Python files.'
green 'ripwire does not support go-to-definition; an LSP does.'
M=' <!-- skilllangdrift: ok -->'
for f in 'Add a new grammar for another language (see the Python and Go queries as templates).' \
         'The fixture has C++, Python, Go and Rust files, nothing else.' \
         'ripwire does not parse Markdown fences as code.' \
         "ripwire doesn't read JSON comments." \
         'Per-language rules cover C++, Python, Go, Rust; no other language has the large-function gate.' \
         'In other languages (Java, Go) the receiver is implicit.'; do
    green "$f$M"
    hn=$(( hn + 1 )); [ -n "$( scan "$f" )" ] && h=$(( h + 1 )) || no "(H) without the marker this should be RED: $f"
done
[ "$h" = "$hn" ] && ok "(H) $h false-positive twins: 3 prose sentences pass as written; 6 per-feature sentences pass with the marker and are RED without it"

# ── (E) the names the router now uses as 'unsupported' really are absent ────────────────────────────────────
bad=""; for x in Haskell OCaml Scala Zig; do grep -qxF "$x" "$T/names.txt" && bad="$bad $x"; done
[ -z "$bad" ] && ok "(E) Haskell, OCaml, Scala and Zig are absent from the --help Languages line" \
              || no "(E) --help now lists:$bad — the router's 'wrong tool' examples need a new unsupported language"

[ "$fail" = 0 ] && { echo "skilllangdriftcheck: PASS"; exit 0; }
echo "skilllangdriftcheck: FAIL"; exit 1
