#!/usr/bin/env bash
# deckcheck.sh — every `--flag` NAMED IN PROSE must actually exist, the generalization of the
# ripwirepubliccheck.sh lesson (match its idiom below) to a different lie: a deck-build agent last
# round fabricated `--doc-drift --dated` — plausible, wrong, and it shipped into a 20-slide deck,
# caught only because an orchestrator happened to grep the built binary's --help text by hand.
# This gate makes that grep automatic and runs it on every prose source that quotes ctxpack flags.
#
# Scope (what counts as "prose that quotes flags"):
#   present/*.py, present/*.js — the deck-build SCRIPTS (deck1-3 are Python, deck4 is JS); their string
#                    literals are what actually ships onto slides. present/*.pptx/.pdf/.html are BUILT
#                    ARTIFACTS, not sources: the .html export especially is full of `--ink`/`--panel`-
#                    style CSS custom properties that collide with the flag-token shape and are not
#                    ctxpack flags at all, and the orchestrator's working tree regenerates these —
#                    scanning generated output would make this gate flap on files this agent doesn't
#                    own. Scan the scripts that GENERATE the deck, not the deck.
#   README.md      — the public-facing usage doc; same fabrication risk as a slide.
#   skills/*/SKILL.md — INCLUDED, deliberately: these are agent-facing prose exactly like README,
#                    written by the same kind of generation pass, and in THIS tree they already
#                    carry real examples (`--anchor`, `--cochange-boost`) that would have been
#                    false positives without the allowlist below — proof the same fabrication risk
#                    lives here, not just in slide decks.
#   .claude/skills/*/SKILL.md, .agents/skills/*/SKILL.md — the repo's OWN agent skills. Added after
#                    these two trees were found silently DIVERGED (.claude/ still claimed 14 MCP verbs
#                    and 7 quality kinds against the real 30 and 10) while every gate validated only
#                    the .agents/ copy. They are one tree now (.agents/skills is a symlink to
#                    .claude/skills), and both globs are scanned so the gate keeps working whether or
#                    not that stays true; SOURCES is deduplicated by resolved directory so the shared
#                    files are not scanned — or reported — twice.
#
# Beyond existence, a flag's VALUE is checked where --help states the permitted set (see "enum values"
# below): `--rank-by=bogus` is as false a claim as `--bogus`, and --help prints those enums verbatim.
#
# A token is allowed if EITHER:
#   (a) it appears in `$BIN --help` (the ground truth: what the shipped binary actually parses), or
#   (b) it is listed in test/deckcheck_allowlist.txt with a reason — genuine prose false positives:
#       a REAL ctxpack flag --help deliberately omits (CTXPACK_DEV-gated experiment, deprecated
#       --order alias, a `wrap`-subcommand-only flag), or a flag that belongs to a DIFFERENT tool
#       quoted in a worked example (xmllint --noout, git --raw, cmake --build, aider --read,
#       this repo's own install.sh --hook/--codex/--claude).
# Anything else is a FABRICATION: printed as `file:line: --token` so a human can fix it in one hop.
#
# The allowlist is also checked for ROT: an entry no longer referenced anywhere in the scanned
# sources fails the gate too — an allowlist is not a place old exemptions go to hide forever.
#
# Usage:  bash test/deckcheck.sh   |   CTXPACK_BIN=asan/ctxpack bash test/deckcheck.sh
# Exit codes: 0 = clean. 1 = at least one fabricated/unlisted flag, or a stale allowlist entry.
#             2 = usage error (no binary, no --help output).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
cd "$ROOT" || { echo "deckcheck: cannot cd to repo root $ROOT"; exit 2; }
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
ALLOWLIST="$ROOT/test/deckcheck_allowlist.txt"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "deckcheck: no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$ALLOWLIST" ] || { echo "deckcheck: missing allowlist $ALLOWLIST"; exit 2; }

echo "deckcheck: BIN=$BIN"

# ── the token shape, used identically on --help and on prose ────────────────────────────────────────
# Case-INSENSITIVE first char and `_` allowed, deliberately wider than any real ctxpack flag: a
# fabrication must be EXTRACTED before it can be judged. The old shape was anchored to a lowercase
# [a-z] and excluded `_`, so `--Doc-Drift` or `--doc_drift` yielded NO TOKEN AT ALL and a capitalized
# or underscored fabrication sailed through silently — the gate's worst failure mode, since it looks
# like a pass. Every real flag is lowercase-hyphenated, so widening this costs nothing and any
# capitalized/underscored token now lands in front of a human as a FAIL.
TOKEN_RE='--[A-Za-z][A-Za-z0-9_-]*'
# The same shape with a LEFT-CONTEXT GUARD for prose: the char before `--` may not be `-`, `/`, `_` or
# alphanumeric. This kills two false-positive classes that would otherwise pressure someone into
# adding an allowlist row for a flag that was never claimed: a URL path segment (`.../--madeupflag`)
# and a `---foo` typo/em-dash-ish run. `(^|…)` keeps a flag at start-of-line matching.
PROSE_RE='(^|[^-/_A-Za-z0-9])'"$TOKEN_RE"

# ── ground truth: every --flag token the shipped binary's own --help prints ─────────────────────────
"$BIN" --help >"$TMP/help.txt" 2>&1
grep -oE -- "$TOKEN_RE" "$TMP/help.txt" | sort -u >"$TMP/valid.txt"
validCount=$( wc -l <"$TMP/valid.txt" | tr -d ' ' )
[ "$validCount" -gt 0 ] || { echo "deckcheck: --help printed zero --flag tokens — broken build or empty help; refusing to run"; exit 2; }

# ── ground truth #2: enum VALUES, harvested from --help itself (no second source of truth) ──────────
# Two harvests, unioned per flag:
#   (A) inline alternations printed next to the flag — `--rank-by=pagerank|authority|hub|rrf|churn`,
#       `--format=xml|columnar`, and `/`-joined mentions elsewhere in the text (`--format=columnar/
#       candidates`). The union matters: `candidates` is a REAL --format value that appears only in
#       the `/` form, so harvesting the `|` list alone would have failed valid prose.
#   (B) flags printed with an uppercase METAVAR (`--order=MODE`), whose values live in the following
#       prose paragraph as `: value (…)` / `| value (…)`.
# A flag is then checked ONLY if this yields >=2 distinct values, i.e. only where --help demonstrably
# enumerates a closed set. That threshold is the safety valve: if --help is ever reformatted so a
# harvest stops matching, the flag silently drops OUT of value-checking (coverage lost, loudly zero
# false positives) rather than fabricating a wrong "permitted set" and failing honest prose.
: >"$TMP/enumpairs.txt"
grep -oE -- "$TOKEN_RE"'=[a-z][a-z0-9.-]*([|/][a-z][a-z0-9.-]*)*' "$TMP/help.txt" \
  | awk -F= '{ flag=$1; n=split($2,v,/[|\/]/); for(i=1;i<=n;i++) if(v[i]!="") print flag"\t"v[i] }' >>"$TMP/enumpairs.txt"
for metaFlag in $( grep -oE -- "$TOKEN_RE"'=[A-Z][A-Z0-9_]*' "$TMP/help.txt" | cut -d= -f1 | sort -u ); do
    awk -v f="$metaFlag" '
        $0 ~ "^ *" f "="        { p = 1 }
        p && /^ *--/ && $0 !~ "^ *" f "=" { p = 0 }
        p                       { printf "%s ", $0 }
    ' "$TMP/help.txt" \
      | grep -oE '[:|] *[a-z][a-z0-9]*(-[a-z0-9]+)* *\(' \
      | tr -d ':|()' | tr -d ' ' \
      | awk -v f="$metaFlag" 'NF { print f"\t"$0 }' >>"$TMP/enumpairs.txt"
done
sort -u "$TMP/enumpairs.txt" >"$TMP/enumvals.txt"
cut -f1 "$TMP/enumvals.txt" | uniq -c | awk '$1 >= 2 { print $2 }' | sort -u >"$TMP/enumflags.txt"
enumFlagCount=$( wc -l <"$TMP/enumflags.txt" | tr -d ' ' )

# ── the allowlist: TOKEN<TAB>reason, blank/# lines are comments; every entry must carry a reason ────
awk -F'\t' '!/^[[:space:]]*#/ && NF>=1 && $1!=""' "$ALLOWLIST" >"$TMP/allow_rows.txt"
cut -f1 "$TMP/allow_rows.txt" | sort -u >"$TMP/allow.txt"
while IFS=$'\t' read -r tok reason; do
    [ -z "$tok" ] && continue
    if [ -z "${reason:-}" ]; then
        echo "  BADROW  allowlist entry '$tok' has no reason (TOKEN<TAB>reason required)"
        badAllow=1
    fi
done <"$TMP/allow_rows.txt"

# ── the scanned prose: present/ scripts, README.md, and all three skill trees ───────────────────────
# addSource dedupes by RESOLVED directory (`cd … && pwd -P` follows symlinks, POSIX, no realpath dep)
# so .agents/skills -> .claude/skills is scanned once, not twice, and a FAIL is reported once.
SOURCES=()
seenKeys=""
addSource() {
    [ -f "$1" ] || return 0
    key="$( cd "$( dirname "$1" )" && pwd -P )/$( basename "$1" )"
    case "$seenKeys" in *"|$key|"*) return 0 ;; esac
    seenKeys="$seenKeys|$key|"
    SOURCES+=( "$1" )
}
for f in "$ROOT"/present/*.py "$ROOT"/present/*.js; do addSource "$f"; done
addSource "$ROOT/README.md"
for f in "$ROOT"/skills/*/SKILL.md;         do addSource "$f"; done
for f in "$ROOT"/.claude/skills/*/SKILL.md; do addSource "$f"; done
for f in "$ROOT"/.agents/skills/*/SKILL.md; do addSource "$f"; done

[ "${#SOURCES[@]}" -gt 0 ] || { echo "deckcheck: no prose sources found (present/*.py, present/*.js, README.md, */skills/*/SKILL.md all missing?)"; exit 2; }

fail=0
badValueCount=0
: >"$TMP/used_tokens.txt"
for f in "${SOURCES[@]}"; do
    rel="${f#$ROOT/}"
    # (1) flag EXISTENCE. sed strips the left-context guard char the PROSE_RE captured.
    while IFS=: read -r lineNo tok; do
        [ -z "$tok" ] && continue
        tok="--${tok#*--}"          # drop the left-context guard char PROSE_RE captured
        printf '%s\n' "$tok" >>"$TMP/used_tokens.txt"
        if grep -qxF -- "$tok" "$TMP/valid.txt"; then
            continue   # (a) real, documented flag
        fi
        if grep -qxF -- "$tok" "$TMP/allow.txt"; then
            continue   # (b) explained false positive
        fi
        printf '  FAIL  %s:%s: %s — not in `%s --help`, not in %s\n' "$rel" "$lineNo" "$tok" "$(basename "$BIN")" "$(basename "$ALLOWLIST")"
        fail=1
    done < <( grep -noE -- "$PROSE_RE" "$f" )

    # (2) flag VALUE, for the flags --help enumerates a closed set for. Only bare lowercase literals
    #     are judged; a placeholder (--top-k=N, --cache=PATH, --lego=I) is never a claim about a value.
    while IFS=: read -r lineNo pair; do
        [ -z "$pair" ] && continue
        pair="--${pair#*--}"
        pFlag="${pair%%=*}"; pVal="${pair#*=}"
        [ -z "$pVal" ] && continue
        grep -qxF -- "$pFlag" "$TMP/enumflags.txt" || continue
        grep -qxF -- "$( printf '%s\t%s' "$pFlag" "$pVal" )" "$TMP/enumvals.txt" && continue
        printf '  FAIL  %s:%s: %s=%s — %s is not a value `%s --help` lists for %s (permitted: %s)\n' \
            "$rel" "$lineNo" "$pFlag" "$pVal" "$pVal" "$(basename "$BIN")" "$pFlag" \
            "$( awk -F'\t' -v f="$pFlag" '$1==f{ printf "%s%s", sep, $2; sep="|" }' "$TMP/enumvals.txt" )"
        badValueCount=$((badValueCount + 1))
        fail=1
    done < <( grep -noE -- "$PROSE_RE"'=[a-z][a-z0-9.-]*' "$f" )
done

# ── allowlist rot: every entry must still be referenced by at least one scanned source ──────────────
sort -u "$TMP/used_tokens.txt" >"$TMP/used_unique.txt"
staleCount=0
while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    grep -qxF -- "$tok" "$TMP/used_unique.txt" && continue
    echo "  FAIL  allowlist entry '$tok' is unused — no scanned source mentions it anymore (stale exemption, remove it)"
    staleCount=$((staleCount + 1))
    fail=1
done <"$TMP/allow.txt"

usedCount=$( wc -l <"$TMP/used_unique.txt" | tr -d ' ' )
echo "deckcheck: scanned ${#SOURCES[@]} file(s), ${usedCount} distinct --flag token(s), ${validCount} known-valid (--help), $( wc -l <"$TMP/allow.txt" | tr -d ' ' ) allowlisted, ${staleCount} stale-allowlist, ${enumFlagCount} value-checked enum flag(s), ${badValueCount} bad value(s)"

# ── §P9 "amp= definition": --help must define amp= numerically and distinguish it from --impact's
# reaches=, not just print the bare token — a stray-flag scan (the rest of this gate) can't catch a
# documented-but-undefined attribute, so this is a narrow, separate content assertion.
HELPTXT="$( "$BIN" --help 2>&1 )"
printf '%s' "$HELPTXT" | grep -q 'amp = |direct callers|' \
    && ok_amp=1 || ok_amp=0
printf '%s' "$HELPTXT" | grep -q 'NOT the same quantity as --impact'"'"'s reaches=' \
    && ok_ampvsreaches=1 || ok_ampvsreaches=0
if [ "$ok_amp" = 1 ] && [ "$ok_ampvsreaches" = 1 ]; then
    echo "  PASS  --help defines amp= numerically and distinguishes it from --impact's reaches="
else
    echo "  FAIL  --help is missing the amp= numeric definition and/or its contrast with reaches= (amp_defined=$ok_amp vs_reaches=$ok_ampvsreaches)"
    fail=1
fi

if [ "${badAllow:-0}" = "1" ]; then
    echo "deckcheck: FAIL — malformed allowlist row(s) above"
    exit 1
fi
if [ "$fail" -ne 0 ]; then
    echo "deckcheck: FAILURES ABOVE"
    exit 1
fi
echo "deckcheck: ALL PASS — every --flag named in scanned prose is real (documented or allowlisted)"
exit 0
