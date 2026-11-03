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
# prose (a single "C") are required in a closed list but not scanned for in "unsupported" claims.
#
# WHAT IS CHECKED, over skills/**/*.md, README.md, AGENTS.md, CLAUDE.md, INSTALL.md, CONTRIBUTING.md, hooks/ and docs/*.md
# (the dated captures and the historical EVALS/LINEAGE/research records are exempt: they quote what was true then):
#   UNSUP   a --help language named as unsupported: "another/other/unsupported language(s) (NAME, ...)",
#           "unsupported language(s) ... NAME", "ripwire does not parse/index/support NAME".
#   CLOSED  a CLOSED list — a paragraph whose closing phrase "nothing else" / "no other language" directly follows four or more
#           --help language names — must name EVERY --help language.
# A closed list is allowed; a stale one is not. Pointing at --help instead of restating it is the cheapest way to pass.
#
# Arms:
#   (A) the Languages line parses to a sane set (>= 20 names, and the tokens the issue named are in it)
#   (B) the DRIFT arm — the real tree has no UNSUP and no CLOSED violation
#   (C) RED FIXTURE — the pre-fix router paragraph, verbatim, trips both UNSUP (PHP, Kotlin) and CLOSED
#   (D) TWIN — a fake doc naming truly unsupported languages (Haskell, OCaml, Scala, Zig) as unsupported, and a closed
#       list that does name every --help language, both PASS: the checker is not just rejecting every language claim
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

# The checker. argv: help.txt, mode (names | scan), then files. Prints one VIOLATION line per problem (scan) or the
# names (names). Exit 0 always; the caller counts lines.
cat >"$T/check.py" <<'PY'
import re, sys
help_path, mode, files = sys.argv[1], sys.argv[2], sys.argv[3:]
txt = open(help_path, encoding="utf-8", errors="replace").read()
m = re.search(r"Languages:(.*?)(?:\n\s*\n|\Z)", txt, re.S)
raw = m.group(1) if m else ""
prev = None
while prev != raw:                      # strip (nested) parenthesised groups
    prev = raw
    raw = re.sub(r"\([^()]*\)", "", raw)
names = []
for tok in re.split(r"[,;/\n]", raw):
    tok = tok.strip().rstrip(".").strip()
    if tok and re.search(r"[A-Za-z]", tok) and tok not in names:
        names.append(tok)
if mode == "names":
    print("\n".join(names)); sys.exit(0)

def pat(n):
    return re.compile(r"(?<![\w+#])" + re.escape(n) + r"(?![\w+#])")
pats = {n: pat(n) for n in names}
scannable = [n for n in names if len(n) > 1]           # a lone "C" is noise in prose
UNSUP = [
    re.compile(r"(?:another|other|unsupported|unlisted|different)\s+languages?\s*\(([^)]*)\)", re.I),
    re.compile(r"unsupported\s+languages?\b([^.\n]{0,60})", re.I),
    re.compile(r"\bripwire\s+(?:does\s+not|doesn't|cannot|can't)\s+(?:parse|index|read|support)\s+([^.\n]{0,40})", re.I),
]
CLOSED = re.compile(r"nothing else|no other languages?|only these languages", re.I)
for path in files:
    body = open(path, encoding="utf-8", errors="replace").read()
    for pm in re.finditer(r"(?:[^\n]+\n?)+", body):          # paragraphs
        para = pm.group(0)
        line = body.count("\n", 0, pm.start()) + 1
        flat = re.sub(r"\s+", " ", para)
        for u in UNSUP:
            for um in u.finditer(flat):
                for n in scannable:
                    if pats[n].search(um.group(1)):
                        print(f"UNSUP {path}:{line}: {n} is a --help language but is called unsupported")
        for cm in CLOSED.finditer(flat):                     # the list must END at the closing phrase
            window = flat[max(0, cm.start() - 160):cm.start()]
            if sum(1 for n in scannable if pats[n].search(window)) >= 4:
                named = [n for n in names if pats[n].search(flat)]
                missing = [n for n in names if n not in named]
                if missing:
                    print(f"CLOSED {path}:{line}: closed language list lacks " + ", ".join(missing))
                break
PY

# ── (A) the Languages line parses ───────────────────────────────────────────────────────────────────────────
python3 -I "$T/check.py" "$T/help.txt" names >"$T/names.txt"
nn="$( wc -l <"$T/names.txt" | tr -d ' ' )"
miss=""; for want in PHP Kotlin Elixir Lua Dart GDScript CUDA TOML YAML Markdown 'C#' Go; do
    grep -qxF "$want" "$T/names.txt" || miss="$miss $want"; done
{ [ "${nn:-0}" -ge 20 ] && [ -z "$miss" ]; } \
    && ok "(A) --help Languages line parses to $nn names, including the ones issue #521 named" \
    || no "(A) --help Languages line parsed to ${nn:-0} names; missing:${miss:- none}"

# ── (B) the DRIFT arm: the real tree ────────────────────────────────────────────────────────────────────────
( cd "$SCAN" || exit 2
  { ls README.md AGENTS.md CLAUDE.md INSTALL.md CONTRIBUTING.md 2>/dev/null
    find skills hooks -type f -name '*.md' 2>/dev/null
    find docs -maxdepth 1 -type f -name '*.md' 2>/dev/null \
        | grep -vE '/(EVALS|LINEAGE|COMMANDS|LIMITS)\.md$|/research/' ; } | sort -u ) >"$T/files.txt"
nf="$( wc -l <"$T/files.txt" | tr -d ' ' )"
grep -q 'ripwire-router/SKILL.md' "$T/files.txt" || no "(B) liveness: the router skill is not in the scanned set (SCAN=$SCAN)"
( cd "$SCAN" && xargs python3 -I "$T/check.py" "$T/help.txt" scan <"$T/files.txt" ) >"$T/real.out"
if [ -s "$T/real.out" ]; then
    no "(B) $( wc -l <"$T/real.out" | tr -d ' ' ) language-claim violation(s) over $nf files:"; sed 's/^/        /' "$T/real.out"
else ok "(B) $nf skill/doc files make no claim that contradicts the --help Languages line"; fi

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

# ── (D) TWIN: truthful claims pass ──────────────────────────────────────────────────────────────────────────
{ printf 'ripwire does not parse Haskell, OCaml, Scala or Zig. A repo in another language (Haskell, OCaml, Scala, Zig)\n'
  printf 'gets an empty map with unindexed= naming the extensions; these are unsupported languages.\n\n'
  printf 'ripwire parses **'; paste -sd, "$T/names.txt" | sed 's/,/, /g'; printf '** and nothing else.\n'; } >"$T/twin.md"
python3 -I "$T/check.py" "$T/help.txt" scan "$T/twin.md" >"$T/twin.out"
if [ ! -s "$T/twin.out" ] && grep -q 'nothing else' "$T/twin.md" && grep -q 'Haskell' "$T/twin.md"; then
    ok "(D) twin: a fake doc calling Haskell/OCaml/Scala/Zig unsupported, and a closed list naming all $nn languages, both pass"
else no "(D) twin doc was flagged (or the fixture lost its claims)"; sed 's/^/        /' "$T/twin.out"; fi

# ── (E) the names the router now uses as 'unsupported' really are absent ────────────────────────────────────
bad=""; for x in Haskell OCaml Scala Zig; do grep -qxF "$x" "$T/names.txt" && bad="$bad $x"; done
[ -z "$bad" ] && ok "(E) Haskell, OCaml, Scala and Zig are absent from the --help Languages line" \
              || no "(E) --help now lists:$bad — the router's 'wrong tool' examples need a new unsupported language"

[ "$fail" = 0 ] && { echo "skilllangdriftcheck: PASS"; exit 0; }
echo "skilllangdriftcheck: FAIL"; exit 1
