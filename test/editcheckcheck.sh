#!/usr/bin/env bash
# editcheckcheck.sh — gate for --edit-check=SYM (B11/L5): the fast per-symbol
# post-edit contract check. "Did MY edit change a contract someone depends on" at edit time (--quality-delta
# answers the same question per-DIFF at commit time — this is the targeted, single-symbol entry point).
#
# Covers, per the plan's gate spec:
#   (a) body-only edit                       -> status="unchanged"
#   (b) param added                          -> status="contract-change" with correct was/now + the
#                                                incompatible caller flagged
#   (c) brand-new symbol                     -> status="new-symbol"
#   (d) unknown SYM                          -> refuses loudly (nonzero exit, stderr message)
#   determinism x3, clean-tree -> "unchanged", and a WARM-TIME assertion (<= 100 ms on ripwire's own src/,
#   after the qheadsnap/qsnap HEAD-snapshot cache is primed).
#
# Operates on a private temp git repo (never touches the real repo). Needs git.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/editcheckcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # BOTH seams: `bash test/editcheckcheck.sh asan/ripwire` and RIPWIRE_BIN=
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

WORK="$( mktemp -d )"; SHRINK="$( mktemp -d )"; trap 'rm -rf "$WORK" "$SHRINK"' EXIT
mkdir -p "$WORK/src"
cat > "$WORK/src/a.cpp" <<'EOF'
int helper( int x ) { return x + 1; }
int useit( int a ) { return helper( a ); }
EOF
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )

echo "editcheckcheck: BIN=$BIN  (temp git repo)"

ec(){ ( cd "$WORK" && "$BIN" . --edit-check="$1" --no-cache 2>/dev/null ); }
ecrc(){ ( cd "$WORK" && "$BIN" . --edit-check="$1" --no-cache >/dev/null 2>&1; echo $? ); }

# ── (1) clean tree -> unchanged, exit 0, and lists the one known caller ────────────────────────────────
OUT1="$( ec helper )"
{ printf '%s' "$OUT1" | grep -q 'status="unchanged"' && [ "$( ecrc helper )" = 0 ]; } \
    && ok "clean tree: helper() -> status=unchanged, exit 0" \
    || { no "clean tree should report unchanged (exit $( ecrc helper ))"; printf '%s\n' "$OUT1"; }
# pull just the <c .../> caller rows out of the ELEMENT (not the leading <!-- comment -->, which itself
# prose-describes the incompatible="1" attribute and would false-positive a naive whole-output grep).
rows(){ printf '%s' "$1" | grep -oE '<c [^>]*/>'; }
printf '%s' "$OUT1" | grep -q '<edit-check sym="helper"' && printf '%s' "$OUT1" | grep -q 'callers="1"' \
    && rows "$OUT1" | grep -q 'n="useit"' \
    && ok "clean tree: 1-hop caller useit() listed, not flagged incompatible" \
    || { no "clean tree: caller listing wrong"; printf '%s\n' "$OUT1"; }
rows "$OUT1" | grep -q 'incompatible="1"' \
    && no "clean tree: caller wrongly flagged incompatible (precision)" \
    || ok "clean tree: no false-positive incompatible flag"

# ── (a) body-only edit -> unchanged (the contract is params+publicness, NOT the body) ──────────────────
cat > "$WORK/src/a.cpp" <<'EOF'
int helper( int x ) { return x + 2; }
int useit( int a ) { return helper( a ); }
EOF
OUTA="$( ec helper )"
{ printf '%s' "$OUTA" | grep -q 'status="unchanged"' && [ "$( ecrc helper )" = 0 ]; } \
    && ok "(a) body-only edit -> status=unchanged" \
    || { no "(a) body-only edit should stay unchanged"; printf '%s\n' "$OUTA"; }

# ── (b) param added -> contract-change, correct was/now, incompatible caller flagged ────────────────────
cat > "$WORK/src/a.cpp" <<'EOF'
int helper( int x, int y ) { return x + y; }
int useit( int a ) { return helper( a ); }
EOF
OUTB="$( ec helper )"
printf '%s' "$OUTB" | grep -q 'status="contract-change"' \
    && ok "(b) param added -> status=contract-change" || { no "(b) expected contract-change"; printf '%s\n' "$OUTB"; }
printf '%s' "$OUTB" | grep -q 'params_was="1" params_now="2"' \
    && ok "(b) correct params was/now (1 -> 2)" || { no "(b) wrong params was/now"; printf '%s\n' "$OUTB"; }
printf '%s' "$OUTB" | grep -q 'public_was="0" public_now="0"' \
    && ok "(b) publicness reported, unchanged (0 -> 0)" || { no "(b) publicness was/now missing/wrong"; printf '%s\n' "$OUTB"; }
rows "$OUTB" | grep -q 'n="useit".*incompatible="1"' \
    && ok "(b) the now-incompatible caller useit() is flagged" || { no "(b) incompatible caller not flagged"; printf '%s\n' "$OUTB"; }
[ "$( ecrc helper )" = 0 ] && ok "(b) contract-change still exits 0 (a report, not a gate)" || no "(b) unexpected nonzero exit"

# ── (c) brand-new symbol -> new-symbol, zero callers ─────────────────────────────────────────────────
cat >> "$WORK/src/a.cpp" <<'EOF'
int brandnew( int z ) { return z; }
EOF
OUTC="$( ec brandnew )"
printf '%s' "$OUTC" | grep -q 'status="new-symbol"' \
    && ok "(c) brand-new symbol -> status=new-symbol" || { no "(c) expected new-symbol"; printf '%s\n' "$OUTC"; }
printf '%s' "$OUTC" | grep -q 'callers="0"' \
    && ok "(c) brand-new symbol has zero callers" || { no "(c) unexpected callers on a brand-new symbol"; printf '%s\n' "$OUTC"; }
printf '%s' "$OUTC" | grep -q 'params_was=' \
    && no "(c) new-symbol should not report was/now (nothing to compare against)" \
    || ok "(c) new-symbol correctly omits was/now"

# ── (d) unknown SYM -> refuses loudly (nonzero exit, a stderr message, never a crash / empty map) ──────
ERR_OUT="$( cd "$WORK" && "$BIN" . --edit-check=totallyNoSuchSymbol --no-cache 2>&1 >/dev/null )"
ERR_RC="$( ecrc totallyNoSuchSymbol )"
{ [ "$ERR_RC" -ne 0 ] && printf '%s' "$ERR_OUT" | grep -qi 'not found'; } \
    && ok "(d) unknown SYM refuses loudly (exit $ERR_RC, stderr names it)" \
    || { no "(d) unknown SYM should refuse loudly"; printf 'rc=%s err=%s\n' "$ERR_RC" "$ERR_OUT"; }

# ── determinism x3 (fixed tree state = the current (b) edit) ────────────────────────────────────────────
D1="$( ec helper )"; D2="$( ec helper )"; D3="$( ec helper )"
{ [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; } \
    && ok "deterministic (byte-identical x3)" || no "non-deterministic --edit-check output"

# ── xml well-formed ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$D1" | xmllint --noout - 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── file:name disambiguation (reuse of the --around/--lego resolveFocus path) ───────────────────────────
mkdir -p "$WORK/src2"
cat > "$WORK/src2/dup.cpp" <<'EOF'
int shared_name( int q ) { return q; }
EOF
( cd "$WORK" && git add -A && git commit -qm "add src2" >/dev/null 2>&1 )
OUTF="$( cd "$WORK" && "$BIN" . --edit-check="src2/dup.cpp:shared_name" --no-cache 2>/dev/null )"
printf '%s' "$OUTF" | grep -q 'sym="shared_name"' \
    && ok "file:name disambiguation resolves the qualified symbol" \
    || { no "file:name disambiguation failed"; printf '%s\n' "$OUTF"; }

# ── (e) §B11.3 THE OVERLOAD FOLD IS DISCLOSED ──────────────────────────────────────────────────────────
# This verb collapses every same-(file,scope,name) definition into ONE contract and reports params_was/
# params_now as the MAX over that set. The failure this arm pins: a purely ADDITIVE overload — a new, WIDER
# definition beside an unchanged one, where no existing call site breaks — used to read exactly like a
# widened single definition (status="contract-change") while carrying zero incompatible rows, p= naming the
# definition that did NOT change, and no defs= at all. The two shapes must be tellable apart from the output.
defs_of(){ printf '%s' "$1" | sed 's/.*-->//' | grep -oE '<edit-check [^>]*' | grep -oE 'defs="[0-9]+"'; }
defrows(){ printf '%s' "$1" | sed 's/.*-->//' | grep -oE '<def [^>]*/>'; }
incompat_attr(){ printf '%s' "$1" | sed 's/.*-->//' | grep -oE '<edit-check [^>]*' | grep -oE 'incompatible="[0-9]+"'; }

mkdir -p "$WORK/ovl"
cat > "$WORK/ovl/o.cpp" <<'EOF'
int folded( int x ) { return x; }
int callsit( int a ) { return folded( a ); }
EOF
( cd "$WORK" && git add -A && git commit -qm "ovl base" >/dev/null 2>&1 )
# ADDITIVE: the 1-param definition is untouched; a 3-param sibling appears beside it.
cat > "$WORK/ovl/o.cpp" <<'EOF'
int folded( int x ) { return x; }
int folded( int x, int y, int z ) { return x + y + z; }
int callsit( int a ) { return folded( a ); }
EOF
OUTE="$( ec folded )"
[ "$( defs_of "$OUTE" )" = 'defs="2"' ] \
    && ok "(e) additive overload: the fold is disclosed as defs=\"2\"" \
    || { no "(e) additive overload must disclose defs=\"2\" (the MAX over a 2-definition set)"; printf '%s\n' "$OUTE"; }
[ "$( incompat_attr "$OUTE" )" = 'incompatible="0"' ] \
    && ok "(e) additive overload: root incompatible=\"0\" — the zero is a NUMBER, not an absence" \
    || { no "(e) root incompatible= count missing or wrong on the additive shape"; printf '%s\n' "$OUTE"; }
printf '%s' "$OUTE" | grep -q 'params_was="1" params_now="3"' \
    && ok "(e) additive overload: was/now still the MAX pair (1 -> 3)" || { no "(e) wrong was/now"; printf '%s\n' "$OUTE"; }
# the DISAMBIGUATOR: a def row still carrying the baseline's own parameter count proves nothing existing
# widened. Without the rows, this shape is byte-shaped like a real break.
{ [ "$( defrows "$OUTE" | wc -l | tr -d ' ' )" = 2 ] \
  && defrows "$OUTE" | grep -q 'params="1"' && defrows "$OUTE" | grep -q 'params="3"'; } \
    && ok "(e) additive overload: both folded definitions listed, one still at params=\"1\"" \
    || { no "(e) def rows missing — an additive overload is indistinguishable from a widened definition"; printf '%s\n' "$OUTE"; }
rows "$OUTE" | grep -q 'incompatible="1"' \
    && no "(e) additive overload wrongly flags a caller (no existing definition changed)" \
    || ok "(e) additive overload: no caller flagged (precision)"

# the CONTRAST shape: one definition genuinely widened. Same status, and everything else must differ.
cat > "$WORK/ovl/o.cpp" <<'EOF'
int folded( int x, int y ) { return x + y; }
int callsit( int a ) { return folded( a ); }
EOF
OUTW="$( ec folded )"
{ [ "$( defs_of "$OUTW" )" = 'defs="1"' ] && [ "$( incompat_attr "$OUTW" )" = 'incompatible="1"' ] \
  && [ -z "$( defrows "$OUTW" )" ]; } \
    && ok "(e) widened single definition: defs=\"1\", incompatible=\"1\", no def rows" \
    || { no "(e) the widened-definition contrast shape is wrong"; printf '%s\n' "$OUTW"; }
{ printf '%s' "$OUTE" | grep -q 'status="contract-change"' && printf '%s' "$OUTW" | grep -q 'status="contract-change"'; } \
    && ok "(e) both shapes report status=contract-change — which is WHY the fold has to be disclosed" \
    || no "(e) expected contract-change on both shapes"

# defs= is UNCONDITIONAL: absent-at-1 would mean a reader never learns the attribute exists.
{ defs_of "$OUT1" | grep -q 'defs="1"' && defs_of "$OUTC" | grep -q 'defs="1"'; } \
    && ok "(e) defs= present on status=unchanged AND status=new-symbol, not only on contract-change" \
    || { no "(e) defs= must be emitted unconditionally"; printf 'unchanged=%s new=%s\n' "$( defs_of "$OUT1" )" "$( defs_of "$OUTC" )"; }

# ARITHMETIC, not prose: root incompatible= == the number of flagged <c> rows, on every shape seen so far.
arith_ok=1
for _o in "$OUT1" "$OUTA" "$OUTB" "$OUTC" "$OUTE" "$OUTW"; do
    _claim="$( incompat_attr "$_o" | grep -oE '[0-9]+' )"
    _real="$( rows "$_o" | grep -c 'incompatible="1"' )"
    [ "${_claim:-x}" = "$_real" ] || { arith_ok=0; printf '    claim=%s real=%s in: %s\n' "$_claim" "$_real" "$_o"; }
done
[ "$arith_ok" = 1 ] && ok "(e) root incompatible= equals the flagged <c> row count on all 6 shapes" \
                     || no "(e) root incompatible= disagrees with its own rows"

# the LEGEND must define both new attributes and the def row — an undefined attribute is the §A10.11 class.
LEG="$( printf '%s' "$OUTE" | grep -oE '<!--.*-->' )"
{ printf '%s' "$LEG" | grep -q 'defs=' && printf '%s' "$LEG" | grep -q 'incompatible=' \
  && printf '%s' "$LEG" | grep -qi 'def row'; } \
    && ok "(e) legend defines defs=, incompatible= and the def row" \
    || { no "(e) legend does not define the disclosure vocabulary it emits"; printf '%s\n' "$LEG"; }

# (f) MCP PARITY — the MCP edit_check verb and the CLI share editCheckBundleText, so the disclosure must
# arrive on both surfaces without a second implementation. Compare the ELEMENT (roots differ by spelling).
if command -v python3 >/dev/null 2>&1; then
    cat > "$WORK/ovl/o.cpp" <<'EOF'
int folded( int x ) { return x; }
int folded( int x, int y, int z ) { return x + y + z; }
int callsit( int a ) { return folded( a ); }
EOF
    MCP_OUT="$( printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":"%s","symbol":"folded"}}}\n' "$WORK" \
                | "$BIN" --mcp 2>/dev/null \
                | python3 -c 'import sys,json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except Exception: continue
    c=d.get("result",{}).get("content")
    if c: print(c[0].get("text",""))' )"
    { [ "$( defs_of "$MCP_OUT" )" = 'defs="2"' ] && [ "$( incompat_attr "$MCP_OUT" )" = 'incompatible="0"' ] \
      && [ "$( defrows "$MCP_OUT" | wc -l | tr -d ' ' )" = 2 ]; } \
        && ok "(f) MCP edit_check carries the SAME fold disclosure (defs, incompatible, def rows)" \
        || { no "(f) MCP arm drifted from the CLI on the fold disclosure"; printf '%s\n' "$MCP_OUT"; }
else
    printf '  SKIP  (f) MCP parity (no python3)\n'
fi

# ── (g) THE FOLD'S OTHER DIRECTION — an overload REMOVED below the MAX ─────────────────────────────────
# Arm (e) covers the fold's FALSE ALARM: an added wider overload raises params_now and nothing broke. The
# same MAX has a second consequence, opposite in direction and strictly more dangerous — a FALSE
# REASSURANCE. Deleting an overload whose parameter count is BELOW the max leaves params_was == params_now
# on both sides of the comparison, so the folded pair reports no movement at all, while the call site that
# used the deleted definition no longer compiles. The verb's whole value is the headline word, and
# status="unchanged" printed beside incompatible="1" is a document contradicting itself.
#
# Its own git repo, so no other arm's committed baseline is disturbed and this one cannot inherit theirs.
mkdir -p "$SHRINK/s"
cat > "$SHRINK/s/s.cpp" <<'EOF'
int widget( int a ) { return a; }
int widget( int a, int b ) { return a + b; }
int callerOne( void ) { return widget( 1 ); }
int callerTwo( void ) { return widget( 1, 2 ); }
EOF
( cd "$SHRINK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
sec(){ ( cd "$SHRINK" && "$BIN" . --edit-check="$1" --no-cache 2>/dev/null ); }

OUTG0="$( sec widget )"
{ printf '%s' "$OUTG0" | grep -q 'status="unchanged"' && [ "$( defs_of "$OUTG0" )" = 'defs="2"' ] \
  && [ "$( incompat_attr "$OUTG0" )" = 'incompatible="0"' ]; } \
    && ok "(g) shrink baseline: two overloads, both call sites fine -> unchanged, defs=\"2\", incompatible=\"0\"" \
    || { no "(g) the shrink arm's committed baseline is not the shape it needs"; printf '%s\n' "$OUTG0"; }

# working tree: delete ONLY the 1-arg overload. callerOne no longer compiles; the MAX is still 2.
cat > "$SHRINK/s/s.cpp" <<'EOF'
int widget( int a, int b ) { return a + b; }
int callerOne( void ) { return widget( 1 ); }
int callerTwo( void ) { return widget( 1, 2 ); }
EOF
OUTG="$( sec widget )"

# the EVIDENCE half: the break really is proven and named, so the arm below is about the HEADLINE only.
{ [ "$( incompat_attr "$OUTG" )" = 'incompatible="1"' ] && rows "$OUTG" | grep -q 'n="callerOne".*incompatible="1"'; } \
    && ok "(g) overload removed: callerOne is flagged incompatible=\"1\"" \
    || { no "(g) the removal did not produce the proven-incompatible caller this arm is built on"; printf '%s\n' "$OUTG"; }
# the arm would pass for the wrong reason if the folded MAX pair had MOVED — then ANY status would be honest
# and the shape would prove nothing. Pin that it did not: both sides are the surviving max.
printf '%s' "$OUTG" | grep -q 'params_was="2" params_now="2"' \
    && ok "(g) the folded MAX pair is blind to the removal (params_was=\"2\" params_now=\"2\") — which is the point" \
    || { no "(g) params_was/params_now moved, so this shape no longer isolates the MAX's blind spot"; printf '%s\n' "$OUTG"; }
# THE ARM.
printf '%s' "$OUTG" | grep -q 'status="unchanged"' \
    && { no "(g) status=\"unchanged\" on a shrunk definition set — the MAX's blind spot is still the verdict's"; printf '%s\n' "$OUTG"; } \
    || ok "(g) a shrunk definition set is not reported as unchanged"
# defs_was is the WAS-VS-NOW fact that carries it, and the root's defs= is its now half.
{ printf '%s' "$OUTG" | grep -q 'defs_was="2" defs_now="1"' && [ "$( defs_of "$OUTG" )" = 'defs="1"' ]; } \
    && ok "(g) defs_was=\"2\" defs_now=\"1\" against defs=\"1\" — the cardinality the MAX cannot express" \
    || { no "(g) defs_was= missing or not the baseline cardinality"; printf '%s\n' "$OUTG"; }
printf '%s' "$OUTG" | grep -q 'change="defs,broken-callers"' \
    && ok "(g) change= names the fact that carried the verdict, with the flagged caller as corroboration" \
    || { no "(g) change= must name defs first and broken-callers as corroboration"; printf '%s\n' "$OUTG"; }

# THE COROLLARY, and the reason broken-callers is not a verdict-carrier of its own: incompatible= is measured
# against the CURRENT definitions from NAME-BASED call edges, so it is nonzero on this repo's own clean tree
# (a `find` method: 151 flagged of 169 callers, nothing edited). If that count alone moved the headline, an
# untouched checkout would report contract-change. Asserted live on the repo, and it FAILS rather than skips
# if the selector stops resolving — a pin that quietly stops measuring is trap #20.
#
# The extraction must come from the ROOT ELEMENT, not from the whole document. incompatible= appears twice
# over: once on <edit-check> as the COUNT, and once per flagged <c> row as the per-caller flag. A whole-
# document `grep -oE` therefore returned 152 lines here ("151" followed by 151 "1"s), `[ -gt ]` failed with
# "integer expression expected", and the arm fell into its own else branch and printed
# `PASS … reports incompatible="0"` — the exact opposite of the measured 151, on every run since it was
# written, and only ever in the case the arm exists to cover (a document with flagged rows in it). Anchored
# to the root element, which is also the only place the COUNT lives.
if [ -d "$ROOT/src" ] && [ -e "$ROOT/.git" ]; then
    # rc and stderr are PRESERVED (the P4 lesson): a sanitizer abort, a refusal and a genuinely
    # unresolvable pin are three different failures, and 2>/dev/null once collapsed them into the
    # misleading "no longer resolves" message below (CI round 3, asan/x86-64).
    _gerr="$WORK/arm_g_stderr"
    OUTR="$( cd "$ROOT" && "$BIN" . --edit-check=src/graph.h:find 2>"$_gerr" | sed 's/.*-->//' )"; _grc=$?
    if ! printf '%s' "$OUTR" | grep -q '<edit-check '; then
        no "(g) the clean-tree pin produced no <edit-check element (rc=$_grc, stdout bytes=${#OUTR}) — crash, refusal, or the pin src/graph.h:find no longer resolves"
        printf '    [arm-g] stderr follows (first 15 lines):\n'; head -15 "$_gerr" | sed 's/^/    [arm-g] /'
    else
        _ric="$( printf '%s' "$OUTR" | grep -oE '<edit-check [^>]*' | grep -oE 'incompatible="[0-9]+"' | grep -oE '[0-9]+' )"
        if ! printf '%s' "${_ric:-}" | grep -qE '^[0-9]+$'; then
            no "(g) the clean-tree pin could not read ONE incompatible= count off the root element (got: ${_ric:-<empty>})"
        elif [ "$_ric" -gt 0 ]; then
            printf '%s' "$OUTR" | grep -q 'change="broken-callers"' \
                && { no "(g) a flagged-caller count alone moved the headline on an unedited definition (incompatible=$_ric)"; printf '%s\n' "$OUTR"; } \
                || ok "(g) incompatible=\"$_ric\" on an unedited definition does NOT carry the headline by itself"
        else
            ok "(g) the repo pin resolves and reports incompatible=\"0\" (nothing to corroborate)"
        fi
    fi
else
    printf '  SKIP  (g) clean-tree pin (not running inside the ripwire repo checkout)\n'
fi

# change= is defined in the legend and is emitted ONLY where it means something.
{ printf '%s' "$OUTG" | grep -oE '<!--.*-->' | grep -q 'change='; } \
    && ok "(g) legend defines change=" || { no "(g) change= is emitted but never defined"; }
{ printf '%s' "$OUTG" | grep -oE '<!--.*-->' | grep -q 'defs_was='; } \
    && ok "(g) legend defines defs_was=" || { no "(g) defs_was= is emitted but never defined"; }
for _u in "$OUT1" "$OUTA" "$OUTG0"; do
    printf '%s' "$_u" | sed 's/.*-->//' | grep -qE 'change=|defs_was=|defs_now=' \
        && { no "(g) change=/defs_was= leaked onto an unchanged document (they describe a contract-change only)"; break; }
done
printf '%s' "$OUT1$OUTA$OUTG0" | sed 's/<!--[^>]*-->//g' | grep -qE 'change=|defs_was=' \
    || ok "(g) change=/defs_was= absent on every status=unchanged document"

# (h) MCP PARITY on the shrink shape — both surfaces call the one bundle assembler, so the escalated
# verdict must arrive on both without a second implementation. Structural, and gated rather than assumed.
if command -v python3 >/dev/null 2>&1; then
    MCPG="$( printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"edit_check","arguments":{"path":"%s","symbol":"widget"}}}\n' "$SHRINK" \
             | "$BIN" --mcp 2>/dev/null \
             | python3 -c 'import sys,json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except Exception: continue
    c=d.get("result",{}).get("content")
    if c: print(c[0].get("text",""))' )"
    { printf '%s' "$MCPG" | grep -q 'incompatible="1"' && ! printf '%s' "$MCPG" | sed 's/.*-->//' | grep -q 'status="unchanged"' \
      && printf '%s' "$MCPG" | grep -q 'defs_was="2" defs_now="1"' && printf '%s' "$MCPG" | grep -q 'change="defs,broken-callers"'; } \
        && ok "(h) MCP edit_check reports the same escalated verdict on the shrink shape" \
        || { no "(h) MCP arm drifted from the CLI on the removed-overload shape"; printf '%s\n' "$MCPG"; }
else
    printf '  SKIP  (h) MCP parity on the shrink shape (no python3)\n'
fi

# ── (i) THE IMPLICIT-RECEIVER EXEMPTION THE LEGEND PROMISES MUST ACTUALLY FIRE ─────────────────────────
# The legend says a variadic, defaulted or implicit-receiver definition is never flagged. For Python that
# promise was unreachable: the exemption keys on kind==Method, and Python's tags.scm captures every `def` —
# including one nested in a class — as @definition.function, so a method arrived with a FIXED arity whose
# `params` counts the `self` the call site never writes. `self.bump( 2 )` was measured against `def bump(
# self, k )` and came back one argument short. Measured before the fix: 12 of the 19 nonzero incompatible=
# counts across this repo's 1378 function/method definitions on an untouched, compiling tree were this shape.
#
# Two arms, and the SECOND is the one that stops the fix from being a delete-the-feature: the exemption is
# scoped to definitions that really carry an implicit receiver, so a module-level Python function called with
# the wrong number of arguments must STILL be flagged. An exemption that silences both would pass arm 1 while
# destroying the signal.
#
# Own temp corpus, written by the gate: adding a fixture FILE to test/ would move the repo's own files=/
# symbols= counts, and a corpus the gate controls is also the only kind that cannot drift out from under the
# assertion as the repo grows (trap #31). Non-git root -> status="new-symbol"; the caller flags this arm reads
# are computed from the working tree either way, so no commit is needed.
PYFIX="$( mktemp -d )"
cat > "$PYFIX/mod.py" <<'EOF'
class Widget:
    def __init__( self ):
        self.n = 0

    def bump( self, k ):
        self.n = self.n + k

    def run( self ):
        self.bump( 2 )


def freefn( a, b ):
    return a + b


def caller():
    return freefn( 1 )
EOF
pyec(){ "$BIN" "$PYFIX" --edit-check="$1" --no-cache 2>/dev/null; }

OUTI_M="$( pyec mod.py:bump )"
OUTI_F="$( pyec mod.py:freefn )"
# both selectors must resolve, or the two arms below assert nothing (trap #20: a pin that stops measuring).
if ! printf '%s%s' "$OUTI_M" "$OUTI_F" | grep -q '<edit-check '; then
    no "(i) the Python fixture did not resolve — the implicit-receiver arms measured nothing"
else
    { [ "$( incompat_attr "$OUTI_M" )" = 'incompatible="0"' ] && printf '%s' "$OUTI_M" | grep -q 'callers="1"'; } \
        && ok "(i) self.bump( 2 ) against def bump( self, k ) is NOT flagged — the implicit receiver is exempt, and the caller is still seen" \
        || { no "(i) an implicit-self call is flagged incompatible — the exemption the legend promises does not fire"; printf '%s\n' "$OUTI_M"; }
    { [ "$( incompat_attr "$OUTI_F" )" = 'incompatible="1"' ] && rows "$OUTI_F" | grep -q 'n="caller".*incompatible="1"'; } \
        && ok "(i) freefn( 1 ) against a module-level def freefn( a, b ) IS still flagged — the exemption is scoped, not an off-switch" \
        || { no "(i) the exemption silenced a genuinely wrong arity on a module-level function"; printf '%s\n' "$OUTI_F"; }
fi
rm -rf "$PYFIX"

# ── WARM-TIME budget: <= 100 ms on ripwire's OWN src/, after the qheadsnap/qsnap cache is primed ────────
# The 100 ms figure is a PLAIN-build budget. A sanitizer build runs this same path at 120-130 ms on the same
# machine — measured on the pre-change BASE asan binary too, so it is the instrumentation, not a regression —
# which made the whole gate permanently red under RIPWIRE_BIN=asan/ripwire and hid every real arm behind
# expected noise. Detected by ASKING THE BINARY (ASan prints its own flag help on any ASan-linked program)
# rather than by matching "asan" in the path, which a differently-named build directory defeats silently.
# This is a SKIP, not a FAIL: unlike a degrade-path assertion (trap #3), a perf budget on an instrumented
# binary is not an assertion that cannot be OBSERVED, it is one that is not being MADE.
SANITIZED=0
ASAN_OPTIONS=help=1 "$BIN" --version 2>&1 | grep -q 'AddressSanitizer' && SANITIZED=1
if [ "$SANITIZED" = 1 ]; then
    printf '  SKIP  warm-time budget (sanitizer build: the 100 ms figure is a plain-build budget)\n'
elif [ -d "$ROOT/src" ] && [ -e "$ROOT/.git" ]; then   # .git is a FILE (gitlink) inside a worktree, a DIR in a normal clone
    ( cd "$ROOT" && "$BIN" src --edit-check=resolveFocus >/dev/null 2>&1 )   # cold — primes the auto-cache + qsnap
    ( cd "$ROOT" && "$BIN" src --edit-check=resolveFocus >/dev/null 2>&1 )   # warm once more before timing
    # single warm-timed sample, in ms, or "" if this platform has no nanosecond-resolution date
    warm_edit_check_ms()
    {
        local s e
        s=$( date +%s%N 2>/dev/null || echo 0 )
        ( cd "$ROOT" && "$BIN" src --edit-check=resolveFocus >/dev/null 2>&1 )
        e=$( date +%s%N 2>/dev/null || echo 0 )
        if [ "$s" != "0" ] && [ "$e" != "0" ]; then echo $(( (e - s) / 1000000 )); else echo ""; fi
    }
    MS="$( warm_edit_check_ms )"
    if [ -z "$MS" ]; then
        printf '  SKIP  warm-time budget (no nanosecond-resolution date on this platform)\n'
    elif [ "$MS" -le 100 ]; then
        ok "warm --edit-check on ripwire's own src/ <= 100 ms (${MS} ms)"
    else
        # exactly one disclosed retry (fix policy): a shared/loaded machine can miss the budget on a single
        # sample without the underlying warm path being slow. Never a silent weakening, never a retry loop —
        # the retry is measured against the SAME unchanged 100 ms budget, and both samples stay visible.
        printf '  NOTE  budget missed under load (%s ms) — one disclosed re-measure\n' "$MS"
        MS2="$( warm_edit_check_ms )"
        if [ -n "$MS2" ] && [ "$MS2" -le 100 ]; then
            ok "warm --edit-check on ripwire's own src/ <= 100 ms on retry (first=${MS} ms, retry=${MS2} ms)"
        else
            no "warm --edit-check exceeded the 100 ms budget on both measurements (first=${MS} ms, retry=${MS2:-n/a} ms)"
        fi
    fi
else
    printf '  SKIP  warm-time budget (not running inside the ripwire repo checkout)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
# CA4 §B15 / trap #27: this file used to stop at the line above and return 0 — `||`'s echo succeeds, so
# every FAIL printed above rode along green, because regression.sh's verdict is the EXIT CODE. Proven by
# forced-fail mutant (exit 0 before, exit 1 after). test/gateexitcheck.sh is the sweep that keeps it true.
exit "$fail"
