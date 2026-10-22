#!/usr/bin/env bash
# stemblendcheck — light stem blended into BM25 before saturation.
#
# tf' = tf_exact + 0.35 * tf_stem_only / max(tf_stem_only), one idf over documents that contain either form.
# A stem is admitted only while its stem-only document frequency is <= max(8, S/64).
# Dividing by the max keeps the strongest stem hit at 0.35, under one exact token.
#
# The two rounds that left RIPWIRE_QSTEM off (docs/EVALS.md §7) are the controls here:
#   (cap)  a common stem ("split", the .split() displacement) contributes nothing, and a
#          section that actually says "splits" still ranks. The rejected stem does not enter df.
#   (rare) an admitted stem ranks, and the exact surface outranks it at the same count.
#          The full-weight fold let a rare variant ("compressed" -> "compress") displace a
#          thin exact hit. 0.35 on the stem-only count does not.
#   (pile) one exact "copying" outranks a pile of "copy".
#   (pair) one exact term outranks two stem terms; two stem terms outrank one stem term.
#   (file) "files" meets "file" (both "fil"), and an exact "file" heading outranks the plural.
#          "filling" does not meet "file".
#   (hash) routing/route, classes/class, cookies/cookie, simply/simple, assembling/assembly,
#          staffing/staff, and cancelled/canceled each share a hash. A decoy stays at zero.
#   (par)  warm cache and --no-cache agree.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok(){ printf '  PASS  %s\n' "$*" || { FAIL=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; FAIL=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "stemblendcheck: BIN=$BIN"

score_of(){ # file, exact name
    python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
want = sys.argv[2]
best = None
for m in re.finditer(r'<cand r="\d+" s="([^"]+)" n="([^"]*)"', text):
    if m.group(2) == want:
        s = float(m.group(1))
        if best is None or s > best:
            best = s
print("" if best is None else repr(best))
PY
}

# ── exact section beats the stemmed section, and "files" meets "file" ───────────────────────────
COPY="$TMP/copy"
mkdir -p "$COPY"
cat > "$COPY/exact.md" <<'EOF'
# copying file

The exact wording.
EOF
cat > "$COPY/stemmed.md" <<'EOF'
# copy file

The base wording.
EOF
cat > "$COPY/plural.md" <<'EOF'
# files only

files files
EOF
cat > "$COPY/fileexact.md" <<'EOF'
# file heading

file
EOF
cat > "$COPY/filling.md" <<'EOF'
# filling only

filling filling
EOF

runq(){ env -u TMPDIR XDG_CACHE_HOME="$TMP/xdg" "$BIN" "$1" --no-route --query="$2" --format=candidates --top-k=40 ${3:-}; }
mkdir -p "$TMP/xdg"
runq "$COPY" "copying file" --no-cache > "$TMP/copy.xml" 2>/dev/null
EXACT="$( score_of "$TMP/copy.xml" "copying file" )"
STEM="$( score_of "$TMP/copy.xml" "copy file" )"
python3 - "$EXACT" "$STEM" <<'PY'
import sys
exact, stem = sys.argv[1], sys.argv[2]
sys.exit(0 if exact and stem and float(exact) > float(stem) > 0 else 1)
PY
[ $? -eq 0 ] && ok "(exact) 'copying file' outranks 'copy file', and the stem scores above zero" \
    || no "(exact) scores exact=${EXACT:-absent} stem=${STEM:-absent}"

runq "$COPY" "file" --no-cache > "$TMP/files.xml" 2>/dev/null
PLURAL="$( score_of "$TMP/files.xml" "files only" )"
FILEEX="$( score_of "$TMP/files.xml" "file heading" )"
FILL="$( score_of "$TMP/files.xml" "filling only" )"
python3 - "$PLURAL" "$FILEEX" "$FILL" <<'PY'
import sys
plural, exact, fill = sys.argv[1:]
fill_out = fill in ("", "0", "0.0")
ok = plural and exact and float(exact) > float(plural) > 0 and fill_out
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] && ok "(file) 'files' meets 'file', the exact heading outranks it, 'filling' stays out" \
    || no "(file) plural=${PLURAL:-absent} exact=${FILEEX:-absent} filling=${FILL:-absent}"

# Relevant pairs share a hash. Each corpus is two documents so the stem is under the df cap.
hash_pair(){ # label query hit-title hit-body miss-title miss-body
    local label="$1" query="$2" hit="$3" hitbody="$4" miss="$5" missbody="$6"
    local dir="$TMP/hash-$label"
    mkdir -p "$dir"
    printf '# %s\n\n%s\n' "$hit" "$hitbody" > "$dir/hit.md"
    printf '# %s\n\n%s\n' "$miss" "$missbody" > "$dir/miss.md"
    runq "$dir" "$query" --no-cache > "$TMP/hash-$label.xml" 2>/dev/null
    local hs ms
    hs="$( score_of "$TMP/hash-$label.xml" "$hit" )"
    ms="$( score_of "$TMP/hash-$label.xml" "$miss" )"
    python3 - "$hs" "$ms" <<'PY'
import sys
hit, miss = sys.argv[1], sys.argv[2]
miss_out = miss in ("", "0", "0.0")
sys.exit(0 if hit and float(hit) > 0 and miss_out else 1)
PY
    [ $? -eq 0 ] && ok "(hash) $label" || no "(hash) $label hit=${hs:-absent} miss=${ms:-absent}"
}
hash_pair "route" "routing" "the route" "route" "the root" "root"
hash_pair "class" "classes" "the class" "class" "the classic" "classic"
hash_pair "cookie" "cookies" "one cookie" "cookie" "one cook" "cook"
hash_pair "simple" "simply" "the simple" "simple" "the sample" "sample"
hash_pair "assembly" "assembling" "the assembly" "assembly" "the assembler" "assembler"
hash_pair "staff" "staffing" "the staff" "staff" "the stuff" "stuff"
hash_pair "cancel" "cancelled" "was canceled" "canceled" "the cancer" "cancer"

# ── common stem dropped; exact surface kept (the split displacement) ────────────────────────────
CAP="$TMP/cap"
mkdir -p "$CAP"
for i in $( seq 1 16 ); do
    printf '# noise %02d\n\nsplit\n' "$i" > "$CAP/n$( printf '%02d' "$i" ).md"
done
cat > "$CAP/real.md" <<'EOF'
# real splits

splits
EOF
runq "$CAP" "splits" --no-cache > "$TMP/cap.xml" 2>/dev/null
REAL="$( score_of "$TMP/cap.xml" "real splits" )"
NOISE="$( score_of "$TMP/cap.xml" "noise 01" )"
python3 - "$REAL" "$NOISE" <<'PY'
import sys
real, noise = sys.argv[1], sys.argv[2]
noise_out = noise in ("", "0", "0.0")
sys.exit(0 if real and float(real) > 0 and noise_out else 1)
PY
[ $? -eq 0 ] && ok "(cap) common stem 'split' is dropped; 'real splits' still ranks" \
    || no "(cap) real=${REAL:-absent} noise01=${NOISE:-absent}"

# ── one exact token beats a pile of the same stem, and beats two stem terms ─────────────────────
PILE="$TMP/pile"
mkdir -p "$PILE"
# "copying" and "copy" share a hash. One exact token of the surface outranks a pile of the base.
cat > "$PILE/exact.md" <<'EOF'
# copying once
EOF
{
    printf '# copy pile\n\n'
    for i in $( seq 1 40 ); do printf 'copy '; done
    printf '\n'
} > "$PILE/pile.md"
runq "$PILE" "copying" --no-cache > "$TMP/pile.xml" 2>/dev/null
P_EXACT="$( score_of "$TMP/pile.xml" "copying once" )"
P_PILE="$( score_of "$TMP/pile.xml" "copy pile" )"
python3 - "$P_EXACT" "$P_PILE" <<'PY'
import sys
exact, pile = sys.argv[1], sys.argv[2]
sys.exit(0 if exact and pile and float(exact) > float(pile) > 0 else 1)
PY
[ $? -eq 0 ] && ok "(pile) one exact 'copying' outranks forty 'copy' tokens" \
    || no "(pile) exact=${P_EXACT:-absent} pile=${P_PILE:-absent}"

# ── under the cap, one exact term beats two stem terms, which beat one stem term ────────────────
PAIR="$TMP/pair"
mkdir -p "$PAIR"
# "copying" stems to the same hash as "copy", and "jumping" to the same hash as "jump".
# Filenames stay off those words so a basename does not join the term.
cat > "$PAIR/a.md" <<'EOF'
# copying zzzz zzzz
EOF
cat > "$PAIR/b.md" <<'EOF'
# copy jump zzzz
EOF
cat > "$PAIR/c.md" <<'EOF'
# copy zzzz zzzz
EOF
cat > "$PAIR/d.md" <<'EOF'
# jumping zzzz zzzz
EOF
cat > "$PAIR/e.md" <<'EOF'
# jump zzzz zzzz
EOF
runq "$PAIR" "copying jumping" --no-cache > "$TMP/pair.xml" 2>/dev/null
ONE="$( score_of "$TMP/pair.xml" "copying zzzz zzzz" )"
BOTH="$( score_of "$TMP/pair.xml" "copy jump zzzz" )"
ONLY="$( score_of "$TMP/pair.xml" "copy zzzz zzzz" )"
python3 - "$ONE" "$BOTH" "$ONLY" <<'PY'
import sys
one, both, only = sys.argv[1:]
ok = one and both and only and float(one) > float(both) > float(only) > 0
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] && ok "(pair) one exact term outranks two stem terms, which outrank one stem term" \
    || no "(pair) one=${ONE:-absent} both=${BOTH:-absent} only=${ONLY:-absent}"

# ── warm cache matches the scan path ─────────────────────────────────────────────────────────────
runq "$COPY" "copying file" --cache="$TMP/copy.rich" > "$TMP/warm.xml" 2>/dev/null
runq "$COPY" "copying file" --no-cache > "$TMP/cold.xml" 2>/dev/null
cmp -s "$TMP/warm.xml" "$TMP/cold.xml" \
    && ok "(par) warm stem row and --no-cache scan are byte-identical" \
    || no "(par) warm and scan rankings differ"

[ "$FAIL" -eq 0 ] && echo "stemblendcheck: ALL PASS" || echo "stemblendcheck: FAILURES"
exit "$FAIL"
