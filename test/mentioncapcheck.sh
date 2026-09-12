#!/usr/bin/env bash
# mentioncapcheck.sh — the RANK-LIFT caps that cut a --for answer must SAY SO on the answer document.
#
# WHY THIS CLASS IS DIFFERENT FROM capdisclosurecheck's. The three caps that gate closed were caps on
# EMISSION: a row was found and then trimmed, and the element that carried it already had a shown=/total=
# vocabulary to grow a marker in. The caps here are caps on INDEXING — they decide what the ranker is
# allowed to LIFT, upstream of any element. Nothing downstream can tell that a mention was dropped, and
# no flag, budget or paging brings it back: the answer simply does not contain the thing the task named.
# That is non-negotiable #3's exact failure ("a zero means none found, never none exists"), one level
# further up the pipeline, and it was silent in two files:
#
#   src/mention.h   B8 query-mention anchoring — kMentionMaxRawTokens (16), kMentionMaxFiles (4),
#                   kMentionMaxDirectSymbols (8); R5 doc-mention surfacing — kDocMentionMaxDocsPerAnchor
#                   (2) and kDocMentionMaxDocsTotal (6).
#   src/gitmine.h   B3 co-change prior boost — kCoBoostMaxPartnerFiles (8) and, in the mining window it
#                   reads, kCoBoostMaxFilesPerCommit (30).
#
# THE RULE THE FIX APPLIES, stated here because it is what decides which caps got an attribute and which
# got a source comment instead: DISCLOSE WHEN THE CUT CONTENT IS NOT OTHERWISE VISIBLE IN THE ANSWER.
# kMentionMaxSymbolsPerFile (3) and kCoBoostMaxSymbolsPerFile (3) cut symbols out of a file the bundle
# NAMES on the rows it did serve — the caller can see the file and page into it — so they cost zero bytes
# and carry a measured comment at their declaration. kDocMentionMaxAnchors (8) is a window over the top of
# a ranked list the bundle prints in full; the anchors it declines to consult are on the screen. The seven
# above cut files, symbols, docs and whole commits that appear NOWHERE, so they carry a conditional
# attribute: `*_capped="1"`, plus `*_total="N"` wherever the true count is exactly computable.
#
# Every arm asserts THREE things (the capdisclosurecheck discipline, copied deliberately):
#   1. CROSSING — the fixture really crosses the cap, proved WITHOUT reading the new attribute. Arm A uses
#      a same-token-multiset word-ORDER contrast (BM25 is order-blind, so only the extraction window can
#      explain the difference); arms B/C/D read the pre-existing prose note's own count against a fixture
#      size the gate computes; arm E reads the partner list out of a DIFFERENT verb (--cochange, whose
#      cochangePartners path shares no code with applyCoChangeBoost's); arm F reads git itself.
#   2. DISCLOSURE — the crossed answer carries the marker.
#   3. SILENCE — the same verb on an UNCROSSED fixture does not (never `*_capped="0"`, never a total equal
#      to the shown count).
#
# MUTATION CONTROL: assertion 2 of every arm is exactly what a revert of this fix removes, and assertion 1
# proves the fixture still reaches the reverted code. Run against a binary built from the parent commit —
#   RIPWIRE_BIN=<base>/ripwire bash test/mentioncapcheck.sh
#
#   (H) A BARE BOOLEAN IS NOT A DISCLOSURE. mention_files_capped= and doc_mentions_capped= passed nullptr
#       as their total, so the caller learned that content was withheld and neither how much nor how to
#       get it — §9-3 unmet by the same file whose mention_tokens_capped/mention_syms_capped both carry
#       one. H1/H3 require the total beside each flag and require it to EXCEED the shown count; H2
#       requires it absent when the cap did not fire, so an uncut answer stays byte-identical.
# — and every assertion 2 must FAIL while every assertion 1 still passes. That is the red run this gate was
# written from, before the code existed.
#
# Usage:  bash test/mentioncapcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/mentioncapcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "mentioncapcheck: git required"; exit 2; }
echo "mentioncapcheck: BIN=$BIN"

run(){ "$BIN" "$@" --no-cache 2>/dev/null; }
# the B8 prose note's own counts, which exist on the base binary too — the CROSSING half of arms B and C
anchorFiles(){ printf '%s' "$1" | grep -o 'mention anchor: [0-9]* file' | grep -o '[0-9]*' | head -1; }
anchorSyms(){  printf '%s' "$1" | grep -o '+ [0-9]* symbols named' | grep -o '[0-9]*' | head -1; }
attr(){ printf '%s' "$2" | grep -o "$1=\"[0-9]*\"" | head -1; }
has(){ printf '%s' "$2" | grep -q "$1"; }
# attr() returns `name="N"` (the form the older arms compare as text); num() is its VALUE, for arithmetic.
num(){ attr "$1" "$2" | grep -o '[0-9]*' | head -1; }

# ===================================================================================================
# (A) kMentionMaxRawTokens=16 — the extraction window over the TASK TEXT
#
# The contrast is a WORD-ORDER contrast over an IDENTICAL token multiset. Both tasks name the same
# indexed path and the same 16 junk dotted tokens; only the position of the path differs (1st vs 17th).
# Every lexical signal in the tool is order-blind, so a difference between the two runs cannot come from
# ranking — the extraction window is the only thing that reads position. That is what makes assertion A1
# a real crossing proof rather than "the output changed".
# ===================================================================================================
echo "-- (A) task-text extraction window (kMentionMaxRawTokens)"
FA="$TMP/a"; mkdir -p "$FA/pkg"
cat > "$FA/pkg/zulu_target.py" <<'PY'
def zulu_target_fn(records):
    """Target routine."""
    return records
PY
cat > "$FA/main.py" <<'PY'
def dispatch_records_pipeline(records):
    """Dispatch the records through the pipeline stage."""
    return records
PY
JUNK=""
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16; do JUNK="$JUNK zz$i.qq$i"; done
A_EARLY="pkg/zulu_target.py dispatch the records pipeline stage$JUNK"    # path is mention token 1 of 17
A_LATE="dispatch the records pipeline stage$JUNK pkg/zulu_target.py"     # path is mention token 17 of 17
A_SHORT="fix pkg/zulu_target.py dispatch the records pipeline stage"     # 1 mention token — window untouched
aEarly="$( run "$FA" --for="$A_EARLY" )"
aLate="$(  run "$FA" --for="$A_LATE"  )"
aShort="$( run "$FA" --for="$A_SHORT" )"
if [ -n "$( anchorFiles "$aEarly" )" ] && [ -z "$( anchorFiles "$aLate" )" ]; then
    ok "A1 crossing: same tokens, path 1st anchors ($( anchorFiles "$aEarly" ) file) and path 17th anchors nothing — only the window reads order"
else
    no "A1 crossing: the window did not cut (early='$( anchorFiles "$aEarly" )' late='$( anchorFiles "$aLate" )') — probe broken"
fi
A_WANT='mention_tokens_capped="1" mention_tokens_total="17"'
if has "$A_WANT" "$aLate" && has "$A_WANT" "$aEarly"; then
    ok "A2 disclosure: both 17-token runs carry $A_WANT"
else
    no "A2 disclosure: a task whose mentions overflowed the window said nothing (early=$( attr mention_tokens_total "$aEarly" ) late=$( attr mention_tokens_total "$aLate" ))"
fi
if has 'mention_tokens_capped' "$aShort"; then
    no "A3 silence: a 1-mention task paid for the window attribute"
else
    ok "A3 silence: a task inside the window carries no mention_tokens_capped="
fi

# ===================================================================================================
# (B) kMentionMaxFiles=4 — how many mentioned FILES the anchor may lift
# ===================================================================================================
echo "-- (B) mentioned-file cap (kMentionMaxFiles)"
mkfilefix(){ # $1 = dir, $2 = how many same-basename files
    rm -rf "$1"; local n="$2" i=1
    while [ "$i" -le "$n" ]; do
        mkdir -p "$1/d$i"
        printf 'def helper_%s(items):\n    """Helper %s."""\n    return items\n' "$i" "$i" > "$1/d$i/shared_util.py"
        i=$(( i + 1 ))
    done
    cat > "$1/main.py" <<'PY'
def dispatch_records_pipeline(records):
    """Dispatch the records through the pipeline stage."""
    return records
PY
}
B_Q='fix the pipeline dispatch in `shared_util`'
mkfilefix "$TMP/b6" 6
mkfilefix "$TMP/b2" 2
bWide="$( run "$TMP/b6" --for="$B_Q" )"
bNarrow="$( run "$TMP/b2" --for="$B_Q" )"
B_SEEN="$( anchorFiles "$bWide" )"
B_HAVE="$( find "$TMP/b6" -name shared_util.py | wc -l | tr -d ' ' )"
if [ -n "$B_SEEN" ] && [ "$B_HAVE" -gt "$B_SEEN" ]; then
    ok "B1 crossing: $B_HAVE indexed files carry the mentioned basename, the anchor lifted $B_SEEN"
else
    no "B1 crossing: no cut (indexed=$B_HAVE lifted=${B_SEEN:-<none>}) — probe broken"
fi
if has 'mention_files_capped="1"' "$bWide"; then
    ok "B2 disclosure: the cut run carries mention_files_capped=\"1\""
else
    no "B2 disclosure: more files matched than the anchor lifts and nothing said so"
fi
if [ "$( anchorFiles "$bNarrow" )" = "2" ] && ! has 'mention_files_capped' "$bNarrow"; then
    ok "B3 silence: a 2-file fixture lifts both and pays no attribute"
else
    no "B3 silence: uncrossed fixture lifted '$( anchorFiles "$bNarrow" )' files / attribute present"
fi

# ---------------------------------------------------------------------------------------------------
# (B') a STOP is not a CUT. The file scan stops the instant the list holds kMentionMaxFiles, so files
# left unexamined prove nothing about whether a file the task NAMED was left out. The first cut of this
# disclosure read the stop as the cut and said mention_files_capped="1" on answers that lifted every file
# the task named: at exactly four matches with any later file in crawl order (B4), and whenever a later
# mention met a list an earlier one had filled — a mention naming nothing (B6), re-naming a kept file by a
# longer spelling (B9), or naming a symbol (B10). A false _capped is a wrong answer, not a cosmetic one: it
# tells the caller named files are missing and sends it looking for files that do not exist.
# B7/B8 are the other side — a full list that really does keep a named file out must still say so, on the
# path-suffix route and on the package-dir route — so the fix cannot pass by going quiet.
# Crossing halves read the prose note's counts and the fixture itself, never the attribute.
# ---------------------------------------------------------------------------------------------------
echo "-- (B') a stop is not a cut (kMentionMaxFiles)"
mkfilefix "$TMP/b4" 4                                   # d1..d4/shared_util.py, and main.py sorts AFTER them
bExact="$( run "$TMP/b4" --for="$B_Q" )"
B4_HAVE="$( find "$TMP/b4" -name shared_util.py | wc -l | tr -d ' ' )"
if [ "$( anchorFiles "$bExact" )" = "$B4_HAVE" ] && ! has 'mention_files_capped' "$bExact"; then
    ok "B4 silence at the boundary: all $B4_HAVE matching files lifted, main.py left unexamined — no attribute"
else
    no "B4 silence at the boundary: $B4_HAVE matching, lifted '$( anchorFiles "$bExact" )', got '$( attr mention_files_capped "$bExact" )' — a stop was reported as a cut"
fi

mkfullfix(){ # $1 = dir: four same-basename files sort LAST, so one mention fills the list at the corpus end
    rm -rf "$1"; local i=1
    while [ "$i" -le 4 ]; do
        mkdir -p "$1/z$i"
        printf 'def helper_%s(items):\n    """Helper %s."""\n    return items\n' "$i" "$i" > "$1/z$i/shared_util.py"
        i=$(( i + 1 ))
    done
    mkdir -p "$1/plugins/requests"
    printf 'def get(url):\n    """Fetch a url."""\n    return url\n' > "$1/plugins/requests/__init__.py"
    printf 'def write_report(rows):\n    """Write the rows out."""\n    return rows\n' > "$1/report_writer.py"
    cat > "$1/main.py" <<'PY'
def dispatch_records_pipeline(records):
    """Dispatch the records through the pipeline stage."""
    return records
PY
}
FF="$TMP/bfull"; mkfullfix "$FF"
b5="$( run "$FF" --for="$B_Q" )"
if [ "$( anchorFiles "$b5" )" = "4" ] && ! has 'mention_files_capped' "$b5"; then
    ok "B5 control: one mention fills the list at the last file — 4 lifted, no attribute, so B6..B8 isolate the SECOND mention"
else
    no "B5 control: fixture broken (lifted '$( anchorFiles "$b5" )', attribute '$( attr mention_files_capped "$b5" )')"
fi
b6="$( run "$FF" --for='fix the pipeline dispatch in `shared_util` and `ghost_module`' )"
if [ "$( anchorFiles "$b6" )" = "4" ] && [ -z "$( find "$FF" -name 'ghost_module*' )" ] && ! has 'mention_files_capped' "$b6"; then
    ok "B6 silence: a second mention naming no file meets a full list — nothing was cut, no attribute"
else
    no "B6 silence: a mention naming nothing was reported as a cut (lifted '$( anchorFiles "$b6" )', got '$( attr mention_files_capped "$b6" )')"
fi
# report_writer.py, not main.py: main.py's symbol is already the lexical #1 for this task's words, so lifting it
# moves nothing and the anchor note (the crossing half's only reading) never prints.
b7room="$( run "$FF" --for='fix the pipeline dispatch in `report_writer`' )"
b7="$( run "$FF" --for='fix the pipeline dispatch in `shared_util` and `report_writer`' )"
if [ "$( anchorFiles "$b7room" )" = "1" ] && [ "$( anchorFiles "$b7" )" = "4" ] && has 'mention_files_capped="1"' "$b7"; then
    ok "B7 disclosure: \`report_writer\` alone lifts report_writer.py; behind a full list it is kept out — and the answer says so"
else
    no "B7 disclosure: a named file kept out by a full list went unsaid (alone='$( anchorFiles "$b7room" )' full='$( anchorFiles "$b7" )')"
fi
b8room="$( run "$FF" --for='fix the pipeline dispatch in `requests`' )"
b8="$( run "$FF" --for='fix the pipeline dispatch in `shared_util` and `requests`' )"
if [ "$( anchorFiles "$b8room" )" = "1" ] && [ "$( anchorFiles "$b8" )" = "4" ] && has 'mention_files_capped="1"' "$b8"; then
    ok "B8 disclosure: \`requests\` alone lifts plugins/requests/__init__.py (package-dir route); behind a full list it is kept out — and said"
else
    no "B8 disclosure: a named package index kept out by a full list went unsaid (alone='$( anchorFiles "$b8room" )' full='$( anchorFiles "$b8" )')"
fi

mkdescentfix(){ # $1 = dir: the longest suffix's file sorts LAST; tools/widget_io.py answers only to the bare basename
    rm -rf "$1"; local n
    for n in alpha_mod beta_mod gamma_mod tools/widget_io zz/core/widget_io; do
        mkdir -p "$( dirname "$1/$n" )"
        printf 'def %s_fn(items):\n    """Helper."""\n    return items\n' "$( printf '%s' "$n" | tr '/' '_' )" > "$1/$n.py"
    done
}
FD="$TMP/bdesc"; mkdescentfix "$FD"
B9_FILL='fix `alpha_mod`, `beta_mod`, `gamma_mod`, zz/core/widget_io.py'
b9alone="$( run "$FD" --for='fix src/zz/core/widget_io.py' )"
b9bare="$( run "$FD" --for='fix `widget_io`' )"
b9fill="$( run "$FD" --for="$B9_FILL" )"
b9="$( run "$FD" --for="$B9_FILL and src/zz/core/widget_io.py" )"
if [ "$( anchorFiles "$b9alone" )" = "1" ] && [ "$( anchorFiles "$b9bare" )" = "2" ] && [ "$( anchorFiles "$b9fill" )" = "4" ] \
    && ! has 'mention_files_capped' "$b9fill"; then
    ok "B9 crossing: the longest suffix alone names 1 file, the bare basename 2, and the fill run lifts 4 without a stop"
else
    no "B9 crossing: fixture broken (alone='$( anchorFiles "$b9alone" )' bare='$( anchorFiles "$b9bare" )' fill='$( anchorFiles "$b9fill" )')"
fi
if [ "$( anchorFiles "$b9" )" = "4" ] && ! has 'mention_files_capped' "$b9"; then
    ok "B9 silence: re-naming a kept file by a longer spelling cuts nothing — the shorter suffix reaching tools/widget_io.py is never consulted"
else
    no "B9 silence: got '$( attr mention_files_capped "$b9" )' — a suffix an uncapped scan never consults was read as a cut"
fi

FS="$TMP/bsym"; mkfullfix "$FS"
mkdir -p "$FS/Gadget/emit_row"
printf 'def emit_pkg(items):\n    """Package."""\n    return items\n' > "$FS/Gadget/emit_row/__init__.py"
b10dir="$( run "$FS" --for='rework `Gadget.emit_row`' )"          # no class yet: the package-dir route lifts the index
mkdir -p "$FS/lib"
printf 'class Gadget:\n    def emit_row(self):\n        return 1\n' > "$FS/lib/gadget.py"
b10room="$( run "$FS" --for='rework `Gadget.emit_row`' )"         # the class exists: the mention names a SYMBOL
b10="$( run "$FS" --for='fix the pipeline dispatch in `shared_util` and `Gadget.emit_row`' )"
if [ "$( anchorFiles "$b10dir" )" = "1" ] && [ "$( anchorFiles "$b10room" )" = "0" ] && [ -n "$( anchorSyms "$b10room" )" ]; then
    ok "B10 crossing: with no class the dotted mention lifts Gadget/emit_row/__init__.py; once Gadget.emit_row exists it names the symbol instead"
else
    no "B10 crossing: fixture broken (dir-route='$( anchorFiles "$b10dir" )' sym-route files='$( anchorFiles "$b10room" )' syms='$( anchorSyms "$b10room" )')"
fi
if [ "$( anchorFiles "$b10" )" = "4" ] && ! has 'mention_files_capped' "$b10"; then
    ok "B10 silence: a mention that names a symbol meets a full list — no file was named, so none was cut"
else
    no "B10 silence: got '$( attr mention_files_capped "$b10" )' — a symbol mention was read as a cut file"
fi

# ===================================================================================================
# (C) kMentionMaxDirectSymbols=8 — how many Scope.name matches the anchor may lift
# ===================================================================================================
echo "-- (C) directly-named-symbol cap (kMentionMaxDirectSymbols)"
mksymfix(){ # $1 = dir, $2 = how many classes define Widget.emit_row
    rm -rf "$1"; mkdir -p "$1"; local n="$2" i=1
    while [ "$i" -le "$n" ]; do
        printf 'class Widget:\n    def emit_row(self):\n        return %s\n' "$i" > "$1/w$i.py"
        i=$(( i + 1 ))
    done
}
C_Q='rework `Widget.emit_row`'
mksymfix "$TMP/c10" 10
mksymfix "$TMP/c2" 2
cWide="$( run "$TMP/c10" --for="$C_Q" )"
cNarrow="$( run "$TMP/c2" --for="$C_Q" )"
C_SEEN="$( anchorSyms "$cWide" )"
C_HAVE="$( ls "$TMP/c10" | wc -l | tr -d ' ' )"
if [ -n "$C_SEEN" ] && [ "$C_HAVE" -gt "$C_SEEN" ]; then
    ok "C1 crossing: $C_HAVE definitions of the named Scope.name exist, the anchor lifted $C_SEEN"
else
    no "C1 crossing: no cut (defined=$C_HAVE lifted=${C_SEEN:-<none>}) — probe broken"
fi
C_WANT="mention_syms_capped=\"1\" mention_syms_total=\"$C_HAVE\""
if has "$C_WANT" "$cWide"; then
    ok "C2 disclosure: the cut run carries $C_WANT"
else
    no "C2 disclosure: got '$( attr mention_syms_total "$cWide" )', want mention_syms_total=\"$C_HAVE\""
fi
if [ "$( anchorSyms "$cNarrow" )" = "2" ] && ! has 'mention_syms_capped' "$cNarrow"; then
    ok "C3 silence: a 2-definition fixture lifts both and pays no attribute"
else
    no "C3 silence: uncrossed fixture lifted '$( anchorSyms "$cNarrow" )' symbols / attribute present"
fi

# ===================================================================================================
# (D) kDocMentionMaxDocsPerAnchor=2 / kDocMentionMaxDocsTotal=6 — R5 doc surfacing
# ===================================================================================================
echo "-- (D) doc-mention caps (kDocMentionMaxDocsPerAnchor / kDocMentionMaxDocsTotal)"
mkdocfix(){ # $1 = dir, $2 = how many docs backtick the same symbol
    rm -rf "$1"; mkdir -p "$1/pkg"
    cat > "$1/pkg/alpha.py" <<'PY'
def compute_widget_total(records):
    """Sum the confirmed item counts for a widget order."""
    return sum(r.count for r in records)
PY
    local n="$2" i=1
    while [ "$i" -le "$n" ]; do
        printf '# Extra doc %s\n\nPadding prose entry %s that discusses the `compute_widget_total` routine from angle %s.\n' \
               "$i" "$i" "$i" > "$1/DOC_$i.md"
        i=$(( i + 1 ))
    done
}
mkdocfix "$TMP/d4" 4
mkdocfix "$TMP/d1" 1
dWide="$( run "$TMP/d4" --for="compute_widget_total" )"
dNarrow="$( run "$TMP/d1" --for="compute_widget_total" )"
D_SEEN="$( attr doc_mentions "$dWide" | grep -o '[0-9]*' )"
D_HAVE="$( ls "$TMP/d4"/DOC_*.md | wc -l | tr -d ' ' )"
if [ -n "$D_SEEN" ] && [ "$D_HAVE" -gt "$D_SEEN" ]; then
    ok "D1 crossing: $D_HAVE docs discuss the anchor, $D_SEEN were surfaced"
else
    no "D1 crossing: no cut (docs=$D_HAVE surfaced=${D_SEEN:-<none>}) — probe broken"
fi
if has 'doc_mentions_capped="1"' "$dWide"; then
    ok "D2 disclosure: the cut run carries doc_mentions_capped=\"1\""
else
    no "D2 disclosure: docs a resolved anchor is discussed by were dropped and nothing said so"
fi
if has 'doc_mentions="1"' "$dNarrow" && ! has 'doc_mentions_capped' "$dNarrow"; then
    ok "D3 silence: a 1-doc fixture surfaces it and pays no attribute"
else
    no "D3 silence: uncrossed doc fixture — $( attr doc_mentions "$dNarrow" ) / attribute present"
fi

# ===================================================================================================
# (E) kCoBoostMaxPartnerFiles=8  and  (F) kCoBoostMaxFilesPerCommit=30
#
# The boost is OPT-IN and gated behind RIPWIRE_DEV=1 (see cochangeboostcheck.sh); the fixture is a
# scripted repo so this never reads ripwire's own history.
# ===================================================================================================
echo "-- (E/F) co-change prior boost caps (kCoBoostMaxPartnerFiles / kCoBoostMaxFilesPerCommit)"
export RIPWIRE_DEV=1
mkhist(){ # $1 = dir, $2 = partner count, $3 = bulk-commit file count (0 = none)
    local h="$1" np="$2" nb="$3" i r
    rm -rf "$h"; mkdir -p "$h"
    git -C "$h" init -q
    git -C "$h" config user.email t@t; git -C "$h" config user.name t; git -C "$h" config commit.gpgsign false
    cat > "$h/alpha.py" <<'PY'
def widget_pipeline_process(records):
    """Process widget records through the pipeline."""
    return [r for r in records if r]
def widget_records_pipeline(records):
    """Pipeline stage: validate widget records."""
    return records
def process_widget_records(records):
    """Process the records for each widget in the pipeline."""
    return len(records)
PY
    i=1
    while [ "$i" -le "$np" ]; do
        printf 'def partner_fn_%s(entries):\n    """Evict stale cache entries %s."""\n    return entries\n' "$i" "$i" > "$h/p$i.py"
        i=$(( i + 1 ))
    done
    git -C "$h" add -A; git -C "$h" commit -qm c1
    for r in 2 3 4 5; do
        printf '\n# rev %s\n' "$r" >> "$h/alpha.py"
        i=1
        while [ "$i" -le "$np" ]; do printf '\n# rev %s\n' "$r" >> "$h/p$i.py"; i=$(( i + 1 )); done
        git -C "$h" add -A; git -C "$h" commit -qm "c$r alpha+partners"
    done
    if [ "$nb" -gt 0 ]; then
        i=1
        while [ "$i" -le "$nb" ]; do printf 'def bulk_fn_%s():\n    return %s\n' "$i" "$i" > "$h/b$i.py"; i=$(( i + 1 )); done
        git -C "$h" add -A; git -C "$h" commit -qm "bulk $nb files"
    fi
}
E_Q="widget pipeline process records"
mkhist "$TMP/hwide" 12 40    # 12 partners (> the 8 cap) + one 40-file commit (> the 30 cap)
mkhist "$TMP/hnarrow" 2 0    #  2 partners (under both caps), no bulk commit
eWide="$(   run "$TMP/hwide"   --for="$E_Q" --cochange-boost )"
eNarrow="$( run "$TMP/hnarrow" --for="$E_Q" --cochange-boost )"
# CROSSING via a DIFFERENT verb: --cochange's cochangePartners shares no code with applyCoChangeBoost.
E_HAVE="$( run "$TMP/hwide" --cochange=alpha.py | grep -o '<f p="p[0-9]*\.py"' | wc -l | tr -d ' ' )"
E_SEEN="$( printf '%s' "$eWide" | grep -o 'in [0-9]* files that historically' | grep -o '[0-9]*' | head -1 )"
if [ -n "$E_SEEN" ] && [ "$E_HAVE" -gt "$E_SEEN" ]; then
    ok "E1 crossing: --cochange reports $E_HAVE qualifying partner files, the boost promoted $E_SEEN"
else
    no "E1 crossing: no cut (partners=$E_HAVE promoted=${E_SEEN:-<none>}) — probe broken"
fi
E_WANT="coboost_partners_capped=\"1\" coboost_partners_total=\"$E_HAVE\""
if has "$E_WANT" "$eWide"; then
    ok "E2 disclosure: the cut run carries $E_WANT"
else
    no "E2 disclosure: got '$( attr coboost_partners_total "$eWide" )', want coboost_partners_total=\"$E_HAVE\""
fi
if has 'coboost_partners_capped' "$eNarrow"; then
    no "E3 silence: a 2-partner fixture paid for the partner-cap attribute"
else
    ok "E3 silence: a fixture inside the partner cap carries no coboost_partners_capped="
fi
# (F) the bulk-commit cap in the mining window. CROSSING is read from git itself.
F_BULK="$( git -C "$TMP/hwide" log --format=tformat:__C__ --name-only \
           | awk '/^__C__$/{ if( n > 30 ) big++; n = 0; next } NF { n++ } END { if( n > 30 ) big++; print big + 0 }' )"
F_ALL="$( git -C "$TMP/hwide" rev-list --count HEAD )"
if [ "$F_BULK" -ge 1 ]; then
    ok "F1 crossing: the mined window holds $F_BULK commit(s) above the per-commit file cap (of $F_ALL)"
else
    no "F1 crossing: the fixture has no bulk commit — probe broken"
fi
F_WANT="coboost_commits_capped=\"1\" coboost_commits_total=\"$F_ALL\""
if has "$F_WANT" "$eWide"; then
    ok "F2 disclosure: the cut run carries $F_WANT"
else
    no "F2 disclosure: got '$( attr coboost_commits_total "$eWide" )', want coboost_commits_total=\"$F_ALL\""
fi
if has 'coboost_commits_capped' "$eNarrow"; then
    no "F3 silence: a fixture with no bulk commit paid for the commit-cap attribute"
else
    ok "F3 silence: a window with no dropped commit carries no coboost_commits_capped="
fi

# ===================================================================================================
# (G) the disclosures are DEFINED where the reader meets them, reach the JSON dialect, and cost nothing
#     when nothing fired — plus determinism and well-formedness of every document produced above.
# ===================================================================================================
echo "-- (G) definition, JSON parity, zero-cost silence, determinism"
# legendcoveragecheck's DEFINITIONAL predicate is `name=` inside the leading comment block. The prose
# clause carries the attribute verbatim, so the reader meets the definition on the same screen.
if printf '%s' "$cWide" | grep -o '<!--.*-->' | head -1 | grep -q 'mention_syms_capped='; then
    ok "G1 the leading comment defines mention_syms_capped= where the attribute rides"
else
    no "G1 the cut bundle's legend does not define mention_syms_capped="
fi
cJson="$( run "$TMP/c10" --for="$C_Q" --json )"
if printf '%s' "$cJson" | python3 -c '
import json, sys
d = json.load( sys.stdin )
sys.exit( 0 if d.get("mention_syms_capped") is True and d.get("mention_syms_total") == 10 else 1 )
' 2>/dev/null; then
    ok "G2 the --json dialect carries the same fact as a key pair"
else
    no "G2 --json did not carry mention_syms_capped/mention_syms_total"
fi
# ZERO COST: an ordinary conceptual query on the tool's own source pays nothing for any of the six.
gPlain="$( run "$ROOT/src" --for="rank symbols by pagerank" )"
if printf '%s' "$gPlain" | grep -q 'mention_tokens_capped\|mention_files_capped\|mention_syms_capped\|coboost_'; then
    no "G3 an ordinary query paid for a B8/B3 cap attribute that never fired"
else
    ok "G3 an ordinary query pays zero bytes for the caps that did not fire"
fi
g1="$( run "$TMP/c10" --for="$C_Q" )"; g2="$( run "$TMP/c10" --for="$C_Q" )"
if [ "$g1" = "$g2" ]; then ok "G4 a disclosed bundle is byte-identical run to run"; else no "G4 the disclosed bundle is not deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
    xf=0
    for doc in "$aLate" "$bWide" "$cWide" "$dWide" "$eWide"; do
        printf '%s' "$doc" | xmllint --noout - >/dev/null 2>&1 || xf=1
    done
    if [ "$xf" -eq 0 ]; then ok "G5 every disclosed document is well-formed XML"; else no "G5 a disclosed document is ill-formed"; fi
else
    ok "G5 (skipped: no xmllint)"
fi

# ── (H) A BARE BOOLEAN IS NOT A DISCLOSURE ─────────────────────────────────────────────────────────
# mention_files_capped= and doc_mentions_capped= were noteCap(..., nullptr, ...): the caller was told that
# something had been withheld and neither how much nor how to get it. docs/METHODOLOGY.md §9-3 says a cut
# is terminal only when the caller can finish in one more KNOWN call, and the sibling caps in the same
# file — mention_tokens_capped, mention_syms_capped — have always passed a total. Both now do.
if has 'mention_files_capped="1"' "$bWide"; then
    hTot="$( num mention_files_total "$bWide" )"
    hSeen="$( anchorFiles "$bWide" )"
    if [ -n "$hTot" ] && [ -n "$hSeen" ] && [ "$hTot" -gt "$hSeen" ]; then
        ok "H1 mention_files_capped=\"1\" carries mention_files_total=\"$hTot\" against $hSeen lifted — the gap is nameable"
    else
        no "H1 the file cut disclosed no usable total (total='$hTot' lifted='$hSeen') — a bare boolean is not a disclosure"
    fi
else
    no "H1 fixture broken: the wide file fixture no longer discloses a cut"
fi
# the total must be ABSENT when the cap did not fire — a zero-cost run stays zero-cost
if has 'mention_files_total' "$bNarrow"; then
    no "H2 an uncut run paid for mention_files_total= — the attribute is not gated on the cut"
else
    ok "H2 an uncut run carries no mention_files_total= (the disclosure costs nothing when nothing was cut)"
fi
# the doc half, on the tool's own tree: doc_mentions= is the shown count, doc_mentions_total= the choice set
hDoc="$( run "$ROOT" --for="pagerank power iteration" )"
if has 'doc_mentions_capped="1"' "$hDoc"; then
    dTot="$( num doc_mentions_total "$hDoc" )"
    dSeen="$( num doc_mentions "$hDoc" )"
    if [ -n "$dTot" ] && [ -n "$dSeen" ] && [ "$dTot" -gt "$dSeen" ]; then
        ok "H3 doc_mentions_capped=\"1\" carries doc_mentions_total=\"$dTot\" beside doc_mentions=\"$dSeen\""
    else
        no "H3 the doc cut disclosed no usable total (total='$dTot' shown='$dSeen')"
    fi
else
    ok "H3 (no doc cut on this tree today — nothing to check, and nothing claimed)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
