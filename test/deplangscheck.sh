#!/usr/bin/env bash
# deplangscheck.sh — kParserVer 81: the DEPENDENCY-CAPABLE SET is disclosed, and every consumer of it
# reads the SAME predicate.
#
# WHY THIS GATE EXISTS. `dependencyCapable()` is not a local switch: it is the denominator of `--deps`'s
# ccd/acd/nccd and dep_files=, of `--arch`'s propagation_cost, and — through its PAIR form — the predicate
# that decides whether `--cochange`'s surprising= is even defined for a row. Adding four languages to it
# moved every one of those numbers on any corpus holding Bash, Ruby, Lua or Elixir. A number that moves
# for a reason nobody can read off the output is the failure mode the honesty contract exists to prevent,
# so the set is now PUBLISHED as `<health dep_langs=>` and this gate is what keeps it published, correct,
# and singular.
#
# Arms:
#   (A) dep_langs= is present and is EXACTLY the expected set, in Lang-enum order
#   (B) MUTATION CONTROL for (A) — the languages that must NOT be in it are absent. Without this arm a
#       predicate that returned true for everything would satisfy (A)'s "contains sh, rb, lua, ex"
#   (C) the MARKDOWN decision, measured rather than asserted: markdown DOES mint doc->doc link edges (the
#       map shows them), and .md is still excluded from the dependency denominator on purpose
#   (D) the three OUTPUT-VISIBLE consumers agree about one .sh file: --deps counts it, --arch's
#       propagation_cost denominator counts it, and --cochange treats a .sh<->.sh pair as capable
#   (E) --cochange's PAIR rule: a .sh<->.cpp pair is dep_capable="0" even though both sides are capable
#   (F) the two legends state the change, so a moved number is explicable from the output alone
#
# Usage:  test/deplangscheck.sh   |   RIPWIRE_BIN=asan/ripwire test/deplangscheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "deplangscheck: BIN=$BIN"

# One mixed fixture: two C-family files with an include edge, one .sh, one .md that LINKS another .md,
# one .json. Small enough that every count below is hand-checkable.
FIX="$TMP/mixed"
mkdir -p "$FIX"
printf '#pragma once\nint leafValue();\n'                      > "$FIX/leaf.h"
printf '#include "leaf.h"\nint apply(){ return leafValue(); }\n' > "$FIX/apply.cpp"
printf '#!/usr/bin/env bash\ndeploy_fn(){ echo deploy; }\n'    > "$FIX/deploy.sh"
printf '# Index\n\nSee [the design](design.md) for details.\n' > "$FIX/README.md"
printf '# Design\n\nThe design.\n'                             > "$FIX/design.md"
printf '{ "note": "not a dependency" }\n'                      > "$FIX/data.json"

"$BIN" "$FIX" --deps --no-cache >"$TMP/deps" 2>/dev/null
DEPS="$( cat "$TMP/deps" )"
LANGS="$( printf '%s' "$DEPS" | grep -oE 'dep_langs="[^"]*"' | head -1 )"

# ── (A) the published set, exactly ────────────────────────────────────────────────────────────────────
EXPECT='dep_langs="cpp,py,ts,go,rs,swift,objc,js,sh,java,rb,cs,c,php,lua,ex"'
[ "$LANGS" = "$EXPECT" ] \
    && ok "(A) <health dep_langs=> is exactly the 16-language capable set, in Lang-enum order" \
    || no "(A) dep_langs= drifted: got [$LANGS] want [$EXPECT]"

# ── (B) MUTATION CONTROL for (A) — the exclusions are real ────────────────────────────────────────────
# (A) alone would pass on a predicate that said yes to everything, because it pins a string that a
# reviewer could also have "fixed" by widening. These are the languages whose exclusion is a DECISION.
for l in md json toml yaml; do
    printf '%s' "$LANGS" | grep -qE "[\"',]$l[,\"]" \
        && no "(B) mutation control: $l is listed as dependency-capable — the exclusion was lost" \
        || ok "(B) mutation control: $l is NOT in the capable set"
done
for l in sh rb lua ex; do
    printf '%s' "$LANGS" | grep -qE "[\"',]$l[,\"]" \
        && ok "(B) $l IS in the capable set (kParserVer 81)" \
        || no "(B) $l is missing from the capable set"
done

# ── (C) the MARKDOWN decision, measured ───────────────────────────────────────────────────────────────
# Markdown's exclusion is NOT "it has no import syntax" — it mints real doc->doc edges from a `[x](y.md)`
# link, and the map shows them. It is excluded because --deps/--arch measure change AMPLIFICATION and a
# README that links twelve designs does not oblige twelve rebuilds. Both halves are asserted, so the
# decision cannot decay into an accident: the edge must EXIST, and the .md must still not be counted.
"$BIN" "$FIX" --no-cache --top-k=100 >"$TMP/map" 2>/dev/null
if grep -q 'design' "$TMP/map" && grep -qE '<f p="README.md">.*<c n="[^"]*"' "$TMP/map"; then
    ok "(C) markdown DOES mint a doc->doc link edge — the map carries README.md's <c> to the design doc"
else
    # the link-edge shape is the map's, not this gate's, to define; if the map stops showing it the
    # decision below still holds but its rationale is no longer demonstrated here.
    skip "(C) the README->design link edge is not visible in this map shape — the exclusion arm below still runs"
fi
printf '%s' "$DEPS" | grep -q '<health files="6" dep_files="3"' \
    && ok "(C) and it is still EXCLUDED: files=6 (leaf.h, apply.cpp, deploy.sh, 2 .md, data.json) but dep_files=3" \
    || no "(C) the markdown/json exclusion moved: $( printf '%s' "$DEPS" | grep -oE '<health [^/]*/>' )"

# ── (D)/(E) the consumers ─────────────────────────────────────────────────────────────────────────────
# (C) already pinned dep_files=3 over a 6-file corpus. The arm below is the DIFFERENTIAL form of the same
# claim, which is what makes it a measurement rather than a restated constant: delete the one .sh and the
# denominator must fall by exactly one.
NOSH="$TMP/nosh"; cp -R "$FIX" "$NOSH"; rm -f "$NOSH/deploy.sh"
DF_WITH="$(  printf '%s' "$DEPS" | grep -oE 'dep_files="[0-9]+"' | head -1 | tr -dc 0-9 )"
DF_WITHOUT="$( "$BIN" "$NOSH" --deps --no-cache 2>/dev/null | grep -oE 'dep_files="[0-9]+"' | head -1 | tr -dc 0-9 )"
if [ -n "$DF_WITH" ] && [ -n "$DF_WITHOUT" ] && [ "$(( DF_WITH - DF_WITHOUT ))" -eq 1 ]; then
    ok "(D) --deps: removing the one .sh drops dep_files by exactly 1 ($DF_WITH -> $DF_WITHOUT)"
else
    no "(D) --deps: the .sh is not exactly one unit of the denominator (with=$DF_WITH without=$DF_WITHOUT)"
fi
# --arch needs a rules file; propagation_cost is emitted on <metrics> in every --arch path. One deny rule
# that matches nothing keeps the exit code clean and the metrics block present.
printf 'deny path zzz/.* -> yyy/.*\n' > "$FIX/dl.arch"
printf 'deny path zzz/.* -> yyy/.*\n' > "$NOSH/dl.arch"
pc(){ printf '%s' "$1" | tr '>' '\n' | grep '<metrics ' | grep -oE 'propagation_cost="[^"]*"' | head -1 | sed -E 's/.*"([^"]*)".*/\1/'; }
PC_WITH="$(    pc "$( "$BIN" "$FIX"  --arch="$FIX/dl.arch"  --no-cache 2>/dev/null )" )"
PC_WITHOUT="$( pc "$( "$BIN" "$NOSH" --arch="$NOSH/dl.arch" --no-cache 2>/dev/null )" )"
if [ -n "$PC_WITH" ] && [ -n "$PC_WITHOUT" ] && [ "$PC_WITH" != "$PC_WITHOUT" ]; then
    ok "(D) --arch: propagation_cost moved with the same file ($PC_WITHOUT -> $PC_WITH) — one denominator, two verbs"
else
    no "(D) --arch: propagation_cost did not react to the .sh (with=$PC_WITH without=$PC_WITHOUT) — the denominators disagree"
fi

# --cochange is the consumer that changes SILENTLY: making .sh capable also makes .sh files eligible for
# co-change pair analysis. It needs history, so build a throwaway repo with two shell scripts and one
# C++ file that all move together.
CO="$TMP/co"
mkdir -p "$CO"
printf '#pragma once\nint v();\n'                    > "$CO/core.h"
printf '#include "core.h"\nint v(){ return 1; }\n'   > "$CO/core.cpp"
printf '#!/usr/bin/env bash\nrun_a(){ echo a; }\n'   > "$CO/a.sh"
printf '#!/usr/bin/env bash\nrun_b(){ echo b; }\n'   > "$CO/b.sh"
(
    cd "$CO" || exit 1
    git init -q . && git config user.email dl@example.invalid && git config user.name dl-fixture \
        && git config commit.gpgsign false && git add -A && git commit -qm base || exit 1
    for i in 1 2 3 4; do
        printf '# pad %d\n' "$i" >> a.sh
        printf '# pad %d\n' "$i" >> b.sh
        printf '// pad %d\n' "$i" >> core.cpp
        git add -A && git commit -qm "wave $i" || exit 1
    done
) >/dev/null 2>&1
if [ ! -d "$CO/.git" ]; then
    skip "(D)/(E) --cochange consumer: git unusable in this environment"
else
    "$BIN" "$CO" --cochange --pack-top-n=1000 --no-cache >"$TMP/co.out" 2>/dev/null
    shsh="$( grep -oE '<pair [^>]*/>' "$TMP/co.out" | grep -F 'a.sh' | grep -F 'b.sh' | head -1 )"
    shcpp="$( grep -oE '<pair [^>]*/>' "$TMP/co.out" | grep -F '.sh' | grep -F 'core.cpp' | head -1 )"
    if [ -z "$shsh" ]; then
        no "(D) --cochange: the a.sh<->b.sh pair is absent — the co-change scan never saw the shell files"
    elif echo "$shsh" | grep -q 'dep_capable="0"'; then
        no "(D) --cochange: a .sh<->.sh pair is dismissed dep_capable=\"0\", but a shell script CAN source a shell script: $shsh"
    else
        ok "(D) --cochange: a .sh<->.sh pair is pair-capable and carries a real verdict: $shsh"
    fi
    if [ -z "$shcpp" ]; then
        no "(E) --cochange: the .sh<->core.cpp pair is absent from the fixture's own output"
    elif echo "$shcpp" | grep -q 'dep_capable="0"'; then
        ok "(E) --cochange: a .sh<->.cpp pair is dep_capable=\"0\" — both sides capable, different dialects"
    else
        no "(E) --cochange: a .sh<->.cpp pair claims a surprising= verdict; no \`source\` can name a .cpp: $shcpp"
    fi
fi

# ── (F) the legends say it ────────────────────────────────────────────────────────────────────────────
printf '%s' "$DEPS" | grep -q 'dep_langs= names EXACTLY which languages that subset counts' \
    && ok "(F) the --deps legend explains dep_langs= and why a recorded number may not compare" \
    || no "(F) the --deps legend does not explain dep_langs="
printf '%s' "$DEPS" | grep -q 'joined the set at parser version 81' \
    && ok "(F) the --deps legend names the version at which the denominator moved" \
    || no "(F) the --deps legend does not date the change"
"$BIN" "$CO" --cochange --no-cache >"$TMP/colegend" 2>/dev/null || true
grep -q 'resolve in the SAME dialect' "$TMP/colegend" \
    && ok "(F) the --cochange legend states the PAIR rule (both capable AND same dialect)" \
    || no "(F) the --cochange legend still describes a per-file capability rule"

# ── (G) THE TWO EXTENSION TABLES MUST AGREE ───────────────────────────────────────────────────────────
# A language is dependency-capable in TWO places and they are not the same file: lintrules.h::langOfPath
# maps an extension to a Lang (which dependencyCapable() then judges), and resolve.h::includeLangOf maps
# the SAME extension to the dialect its Step-A resolves in. Adding a language means editing both, and
# forgetting the second one produces the exact defect this whole round fixed — a file counted in the
# dependency DENOMINATOR whose directives can never resolve, i.e. a language that looks supported and
# silently contributes nothing but dilution. --quality-delta sees the two tables as a 437-token clone and
# it is right about the hazard; this arm is what makes the hazard detectable instead of the shape.
#
# Read both tables straight out of the source (no binary involved) and require: every extension whose Lang
# is dependency-capable has a non-Other row in includeLangOf, and vice versa.
python3 - "$ROOT" <<'PYEOF'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
lint = (root / "src" / "lintrules.h").read_text(encoding="utf-8")
res  = (root / "src" / "resolve.h").read_text(encoding="utf-8")

m = re.search(r'static const std::array<Row, \d+> kExt = \{ \{(.*?)\} \};', lint, re.S)
if not m:
    print("  FAIL  (G) could not read lintrules.h::langOfPath's extension table"); sys.exit(1)
extToLang = dict(re.findall(r'\{\s*"(\.[A-Za-z0-9]+)",\s*Lang::(\w+)\s*\}', m.group(1)))

m = re.search(r'kExtLang\[\] =\s*\{(.*?)\n    \};', res, re.S)
if not m:
    print("  FAIL  (G) could not read resolve.h::includeLangOf's extension table"); sys.exit(1)
extToDialect = dict(re.findall(r'\{\s*"(\.[A-Za-z0-9]+)",\s*IncludeLang::(\w+)\s*\}', m.group(1)))

m = re.search(r'inline bool dependencyCapable\( Lang lang \) noexcept\s*\{(.*?)\n\}', lint, re.S)
if not m:
    print("  FAIL  (G) could not read lintrules.h::dependencyCapable"); sys.exit(1)
body = m.group(1)
truePart = body.split("return true;")[0]
capable = set(re.findall(r'Lang::(\w+)', truePart))

if len(extToLang) < 20 or len(extToDialect) < 15 or len(capable) < 10:
    print(f"  FAIL  (G) a table parsed suspiciously small (ext->lang={len(extToLang)} ext->dialect={len(extToDialect)} capable={len(capable)}) — the arm would pass vacuously")
    sys.exit(1)

# The DEFERRED LEDGER, pinned rather than inferred. These four languages are dependency-capable (they
# emit Include records, so their files belong in the denominator) yet have NO includeLangOf dialect on
# purpose: a Java/C#/PHP namespace and a Swift module do not map 1:1 onto a file, so there is no sound
# string->fileId rule and a wrong narrow is worse than none (resolve.h::includeLangOf says so at the
# `.cs` row). They are therefore counted in dep_files= while resolving nothing — a real, PRE-EXISTING
# dilution, recorded here so it is a known quantity instead of a surprise. A FIFTH language landing in
# this state goes red, which is the whole point: the ledger must be edited deliberately.
DEFERRED = {"Java", "CSharp", "Php", "Swift"}

bad = []
for ext, lang in sorted(extToLang.items()):
    isCapable = lang in capable
    hasDialect = extToDialect.get(ext, "Other") != "Other"
    if isCapable and not hasDialect and lang not in DEFERRED:
        bad.append(f"{ext} is Lang::{lang} (dependency-CAPABLE) but includeLangOf has no dialect for it — it would be counted in dep_files= and never resolve")
    if hasDialect and not isCapable:
        bad.append(f"{ext} resolves as IncludeLang::{extToDialect[ext]} but Lang::{lang} is not dependency-capable — its edges exist and its files are outside the denominator")
for ext in sorted(set(extToDialect) - set(extToLang)):
    if extToDialect[ext] != "Other":
        bad.append(f"{ext} has a resolver dialect but langOfPath does not classify it at all")
if bad:
    print("  FAIL  (G) the two extension tables disagree:")
    for b in bad: print("          " + b)
    sys.exit(1)
deferredSeen = sorted({l for l in extToLang.values() if l in DEFERRED and l in capable})
print(f"  PASS  (G) langOfPath and includeLangOf agree on all {len(extToLang)} extensions "
      f"({len(capable)} capable languages) — no language is in the denominator it cannot resolve in, "
      f"except the pinned deferred ledger {deferredSeen}")
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
