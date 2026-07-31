#!/usr/bin/env bash
# flagsurfacecheck.sh — every flag ripwire ADVERTISES in --help must actually PARSE.
#
# The gap this closes: deckcheck.sh proves every flag named in PROSE exists in --help (prose -> help).
# Nothing proved the other direction (help -> parser). --help is a hand-maintained string literal in
# cli.h, and parseArgs was a 146-arm chain in the same file (now 141 arms: 91 tabled + 50 hand-written); a flag can be advertised and never wired,
# renamed in one place only, or lost in a merge, and no gate would notice. This matters most right
# before parseArgs is refactored (PLAN_dispatchRefactor_2026-07-27.md §6.4): a table-driven rewrite is
# only safe if something asserts the ADVERTISED SURFACE still parses afterwards.
#
# The assertion is deliberately narrow: a flag must not produce the specific "unknown flag" error.
# Any OTHER refusal is fine and expected — --gateability refuses without --doc-drift, --anchor is
# RIPWIRE_DEV-gated, --arch wants a file. Those are deliberate messages; "unknown flag" means the
# parser has never heard of it.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }

echo "flagsurfacecheck: BIN=$BIN"

# A DELIBERATELY NONEXISTENT root. Argument parsing runs BEFORE root validation, so an unknown flag still
# reports "unknown flag" while every recognised flag stops at "root path does not exist" — in ~4 ms, without
# parsing a corpus, spawning git, or walking history. Probing against a real corpus made this gate the
# slowest in the suite (300 s under parallel load) purely to re-answer a question about argv.
NOROOT="$TMP/definitely-not-a-root"

# the advertised surface: long flags only, from --help itself (single source of truth, same as deckcheck)
# NOTE the scrape must accept bracketed/parenthesised forms too — --help writes optional knobs as
# "[--around-depth=N]" and alternatives as "(--regex)"; anchoring on whitespace alone silently misses them
# and then reports a documented flag as undocumented.
"$BIN" --help 2>&1 | grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u > "$TMP/flags.txt"
COUNT="$( wc -l < "$TMP/flags.txt" | tr -d ' ' )"
[ "$COUNT" -ge 80 ] && ok "harvested $COUNT advertised long flags from --help" \
                    || { no "only $COUNT flags harvested — the --help scrape broke, not the parser"; echo "ALL FAIL"; exit 1; }

# Server-mode entry points are excluded from the PROBE (not from the surface): --mcp reads stdin until
# EOF and --listen binds a socket and serves, so probing them hangs the gate rather than answering a
# question about argv. They are exercised by the MCP gates instead. Everything else is probed.
SKIP_PROBE=" --mcp --listen --mcp-token --allow-remote-edits "

unknown=""
for f in $( cat "$TMP/flags.txt" ); do
    case "$SKIP_PROBE" in *" $f "*) continue ;; esac
    # bare form first, then =VALUE — a flag is fine if EITHER shape is recognised
    err1="$( "$BIN" "$NOROOT" "$f"   </dev/null 2>&1 >/dev/null | head -3 )"
    case "$err1" in
        *"unknown flag"*)
            err2="$( "$BIN" "$NOROOT" "$f=1" </dev/null 2>&1 >/dev/null | head -3 )"
            case "$err2" in
                *"unknown flag"*) unknown="$unknown $f" ;;
            esac
            ;;
    esac
done

if [ -z "$unknown" ]; then
    ok "every advertised flag is recognised by the parser (no \"unknown flag\" on any of $COUNT)"
else
    no "advertised but NOT parsed:$unknown"
fi

# The converse direction, cheaply: a flag the parser knows but --help never mentions is undiscoverable.
# Harvested from the parser's own string literals in cli.h rather than by guessing.
# COMMENTS ARE STRIPPED FIRST. This harvest greps quoted `"--…"` literals out of src/cli.h, and a comment
# that QUOTES a flag spelling reads to it as a parsed flag: §B5's new EmptyValue enum documented its Refuse
# arm with the words "--flag=" and this gate reported `--flag` as a real, undocumented flag. The failure was
# a comment, not a surface. `sed 's|//.*||'` is enough here because cli.h uses no /* */ blocks and no `//`
# appears inside a string literal in it (both re-checked when this line was added).
sed 's|//.*||' src/cli.h | grep -oE '"--[a-z][a-z0-9-]+' | tr -d '"' | sort -u > "$TMP/parsed.txt"
undocumented=""
for f in $( cat "$TMP/parsed.txt" ); do
    grep -qx -- "$f" "$TMP/flags.txt" || undocumented="$undocumented $f"
done
# Deliberately parsed-but-unadvertised — each with its reason, so the NEXT reader can tell an intentional
# omission from an accidental one. Anything NOT in this list is a flag a user can only find by reading
# source, which is a documentation bug. Keep the reasons; a bare list rots into a dumping ground.
#   --stable, --most-important-last, --no-auto-order  deprecated/hidden aliases of --order= (warn + redirect)
#   --anchor                                          RIPWIRE_DEV-gated, a recorded negative-result experiment
#   --cochange-boost                                  EXPERIMENTAL opt-in; held-out was +0.0pp, default OFF
#   --no-prefilter                                    debug: the full-scan soundness oracle for --regex
#   --route                                           back-compat no-op (routing is the default now)
ALLOW_UNDOC=" --stable --most-important-last --no-auto-order --anchor --cochange-boost --no-prefilter --route "
filtered=""
for f in $undocumented; do
    case "$ALLOW_UNDOC" in *" $f "*) ;; *) filtered="$filtered $f" ;; esac
done
undocumented="$filtered"
if [ -z "$undocumented" ]; then
    ok "every parsed flag is advertised in --help (or a known deprecated alias)"
else
    no "parsed but undocumented (undiscoverable):$undocumented"
fi

# A negative control, so a broken harvest cannot pass silently.
ctl="$( "$BIN" "$NOROOT" --definitely-not-a-real-flag </dev/null 2>&1 >/dev/null | head -2 )"
case "$ctl" in
    *"unknown flag"*) ok "control: a fabricated flag IS reported as unknown (the probe is live)" ;;
    *)                no "control: a fabricated flag was NOT reported unknown — this gate proves nothing" ;;
esac

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
