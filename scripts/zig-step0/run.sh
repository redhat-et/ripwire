#!/usr/bin/env bash
# Re-run the Zig STEP 0 measurement for redhat-et/ripwire issue #166.
#
# Links both documented tree-sitter-zig pins against this tree's vendored
# tree-sitter core, parses the pinned corpora, and rewrites RESULTS.md next
# to this script. Does not vendor the grammar and does not extract symbols.
#
# Needs cc, git, python3, and network access the first time. Checkouts go to
# ${XDG_CACHE_HOME:-$HOME/.cache}/ripwire-zig-step0 and are not committed.
# A later run with the cache filled is offline.
set -euo pipefail

ROOT=$( cd "$( dirname "$0" )/../.." && pwd )
CACHE=${ZIG_STEP0_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ripwire-zig-step0}
BUILD=$CACHE/build
TS=$ROOT/third_party/deps/tree_sitter
TIMEOUT_MS=${ZIG_STEP0_TIMEOUT_MS:-10000}

PIN_TAG_SHA=b670c8df85a1568f498aa5c8cae42f51a90473c0
PIN_MASTER_SHA=6479aa13f32f701c383083d8b28360ebd682fb7d

mkdir -p "$CACHE/grammars" "$CACHE/corpora" "$BUILD" "$CACHE/tsv"

fetch_grammar() {
    local dest=$1 sha=$2
    if [[ -f $dest/.pin ]] && [[ $( cat "$dest/.pin" ) == "$sha" ]]; then
        return
    fi
    rm -rf "$dest"
    mkdir -p "$dest"
    git -C "$dest" init -q
    git -C "$dest" remote add origin https://github.com/tree-sitter-grammars/tree-sitter-zig.git
    git -C "$dest" fetch --depth 1 origin "$sha"
    git -C "$dest" checkout -q --detach FETCH_HEAD
    printf '%s\n' "$sha" > "$dest/.pin"
    local got
    got=$( git -C "$dest" rev-parse HEAD )
    if [[ $got != "$sha" ]]; then
        echo "grammar pin mismatch: $got" >&2
        exit 1
    fi
}

fetch_zig_std() {
    local dest=$1 tag=$2 sha=$3
    if [[ -f $dest/.pin ]] && [[ $( cat "$dest/.pin" ) == "$sha" ]]; then
        return
    fi
    rm -rf "$dest"
    git clone --depth 1 --filter=blob:none --sparse --branch "$tag" \
        https://github.com/ziglang/zig.git "$dest"
    git -C "$dest" sparse-checkout set lib/std lib/std.zig
    local got
    got=$( git -C "$dest" rev-parse HEAD )
    if [[ $got != "$sha" ]]; then
        echo "zig pin mismatch for $tag: $got" >&2
        exit 1
    fi
    printf '%s\n' "$sha" > "$dest/.pin"
}

fetch_ghostty() {
    local dest=$1 tag=$2 sha=$3 zigver=$4
    if [[ -f $dest/.pin ]] && [[ $( cat "$dest/.pin" ) == "$sha" ]]; then
        return
    fi
    rm -rf "$dest"
    git clone --depth 1 --branch "$tag" https://github.com/ghostty-org/ghostty.git "$dest"
    local got
    got=$( git -C "$dest" rev-parse HEAD )
    if [[ $got != "$sha" ]]; then
        echo "ghostty pin mismatch for $tag: $got" >&2
        exit 1
    fi
    if ! grep -q "minimum_zig_version = \"$zigver\"" "$dest/build.zig.zon"; then
        echo "ghostty $tag does not declare minimum_zig_version $zigver" >&2
        exit 1
    fi
    printf '%s\n' "$sha" > "$dest/.pin"
}

echo "cache $CACHE"
fetch_grammar "$CACHE/grammars/v1.1.2" "$PIN_TAG_SHA"
fetch_grammar "$CACHE/grammars/6479aa13" "$PIN_MASTER_SHA"
fetch_zig_std "$CACHE/corpora/zig-std-0.14.1" 0.14.1 d03a147ea0a590ca711b3db07106effc559b0fc6
fetch_zig_std "$CACHE/corpora/zig-std-0.15.1" 0.15.1 3db960767d12b6214bcf43f1966a037c7a586a12
fetch_ghostty "$CACHE/corpora/ghostty-1.2.3" v1.2.3 6d2dd585a5d87fa745d48188dd096ca6e63014d0 0.14.1
fetch_ghostty "$CACHE/corpora/ghostty-1.3.1" v1.3.1 332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28 0.15.2

# Same feature macros the in-tree fuzz target uses so le16toh/fdopen are real.
cc -std=c11 -O2 -D_POSIX_C_SOURCE=200112L -D_DEFAULT_SOURCE \
    -I"$TS/lib/include" -I"$TS/lib/src" \
    -c "$TS/lib/src/lib.c" -o "$BUILD/libtree-sitter.o"
cc -std=c11 -Wall -Wextra -Werror -O2 -I"$TS/lib/include" \
    -c "$ROOT/scripts/zig-step0/measure.c" -o "$BUILD/measure.o"

build_pin() {
    local name=$1 src=$2
    # parser.c is about 6 MB and the generated file forces -O0. Rebuild only
    # when the pinned source is newer than the object.
    if [[ ! -f $BUILD/parser-$name.o || $src/src/parser.c -nt $BUILD/parser-$name.o ]]; then
        cc -std=c11 -O0 -w -I"$src/src" -c "$src/src/parser.c" -o "$BUILD/parser-$name.o"
    fi
    cc -o "$BUILD/measure-$name" "$BUILD/measure.o" "$BUILD/parser-$name.o" "$BUILD/libtree-sitter.o" -lm
}

build_pin v1.1.2 "$CACHE/grammars/v1.1.2"
build_pin 6479aa13 "$CACHE/grammars/6479aa13"

smoke() {
    local name=$1
    local dir=$BUILD/smoke-$name
    rm -rf "$dir"
    mkdir -p "$dir"
    cat > "$dir/ok.zig" <<'EOF'
const std = @import("std");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add" {
    try std.testing.expect(add(1, 2) == 3);
}
EOF
    cat > "$dir/bad.zig" <<'EOF'
pub fn add(a: i32, b: i32) i32 {
    return a + ;
}
EOF
    cat > "$dir/usingnamespace.zig" <<'EOF'
pub usingnamespace struct {
    pub const x: i32 = 1;
};
EOF
    "$BUILD/measure-$name" "$dir" "$dir/out.tsv" "$TIMEOUT_MS" >/dev/null
    python3 - "$dir/out.tsv" <<'PY'
import sys
rows = {}
for line in open(sys.argv[1], encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    rows[p[0]] = p
def need(path, status):
    got = rows[path][2]
    if got != status:
        raise SystemExit(f"smoke {path}: expected {status}, got {got}")
need("ok.zig", "clean")
need("bad.zig", "error")
need("usingnamespace.zig", "clean")
bad_err = int(rows["bad.zig"][3])
bad_len = int(rows["bad.zig"][1])
if bad_err == 0 or bad_err > bad_len:
    raise SystemExit(f"smoke bad.zig err_bytes {bad_err} out of range for {bad_len}")
print("smoke", sys.argv[1], "ok")
PY
}

smoke v1.1.2
smoke 6479aa13

: > "$CACHE/manifest.tsv"
printf '%s\n' $'corpus_id\tzig\tcorpus_sha\troot\tpin_id\ttsv' >> "$CACHE/manifest.tsv"

run_cell() {
    local corpus=$1 zig=$2 sha=$3 root=$4 pin=$5
    local tsv=$CACHE/tsv/${corpus}__${pin}.tsv
    echo "measure $corpus $pin"
    "$BUILD/measure-$pin" "$root" "$tsv" "$TIMEOUT_MS"
    printf '%s\n' "${corpus}"$'\t'"${zig}"$'\t'"${sha}"$'\t'"${root}"$'\t'"${pin}"$'\t'"${tsv}" >> "$CACHE/manifest.tsv"
}

run_cell zig-std-0.14.1 0.14.1 d03a147ea0a590ca711b3db07106effc559b0fc6 \
    "$CACHE/corpora/zig-std-0.14.1" v1.1.2
run_cell zig-std-0.14.1 0.14.1 d03a147ea0a590ca711b3db07106effc559b0fc6 \
    "$CACHE/corpora/zig-std-0.14.1" 6479aa13
run_cell zig-std-0.15.1 0.15.1 3db960767d12b6214bcf43f1966a037c7a586a12 \
    "$CACHE/corpora/zig-std-0.15.1" v1.1.2
run_cell zig-std-0.15.1 0.15.1 3db960767d12b6214bcf43f1966a037c7a586a12 \
    "$CACHE/corpora/zig-std-0.15.1" 6479aa13
run_cell ghostty-1.2.3 0.14.1 6d2dd585a5d87fa745d48188dd096ca6e63014d0 \
    "$CACHE/corpora/ghostty-1.2.3" v1.1.2
run_cell ghostty-1.2.3 0.14.1 6d2dd585a5d87fa745d48188dd096ca6e63014d0 \
    "$CACHE/corpora/ghostty-1.2.3" 6479aa13
run_cell ghostty-1.3.1 0.15.2 332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28 \
    "$CACHE/corpora/ghostty-1.3.1" v1.1.2
run_cell ghostty-1.3.1 0.15.2 332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28 \
    "$CACHE/corpora/ghostty-1.3.1" 6479aa13

python3 "$ROOT/scripts/zig-step0/summarize.py" "$CACHE/manifest.tsv" "$ROOT/scripts/zig-step0/RESULTS.md"
echo "wrote $ROOT/scripts/zig-step0/RESULTS.md"
