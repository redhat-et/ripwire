# abiarchfixture.sh — the corpora test/abiarchretirecheck.sh reads. SOURCED, never run.
#
# Built, not committed, for the reason abicheck.sh and crossrefcheck.sh give: --abi reads git refs, so its corpus has to be a
# real repository with a real ref graph, and --arch's baseline modes write a sidecar beside the rules file. The caller exports
# fixed GIT_AUTHOR_*/GIT_COMMITTER_* identities and dates; with the fixed content below every sha the answers print is
# byte-reproducible, which is what lets the gate compare against committed goldens.
#
#   aaf_abi_repo DIR         a repository whose branches reach every row shape the retired attributes rode on
#   aaf_arch_tree DIR [go]   a two-layer tree with two violations and a root-level file; `go` adds a no-file-edge language

# feat-break     adds a field                      drift, size_delta=4   (size_differs was 1)
# feat-repack    same size, other slots            drift, size_delta=0   (size_differs was 0 on a real break)
# feat-vanish    renames the struct away           absent: no ref_size= at all
# feat-unmod     adds a bitfield                   unknown, with a <ref_caveat>
# feat-rename    renames the fields only           rename: a ref whose every row is excluded (excluded_refs=)
# feat-mix       a drift and a rename              a ref with more rows than it lists (its excluded= was 1)
# feat-many      widens 14 structs in one file     past the 12-row display cap: dropped=2, <more structs="2"/>
# feat-sidecar   comments a file HEAD then widens  head-moved
aaf_abi_repo(){
    local R="$1" i
    mkdir -p "$R"
    aaf_g(){ git -C "$R" "$@" >/dev/null 2>&1; }
    aaf_put(){ printf '%b' "$2" > "$R/$1"; }
    aaf_branch(){ aaf_g checkout -q main; aaf_g checkout -qb "$1"; }
    aaf_g init -q -b main
    aaf_g config commit.gpgsign false
    aaf_put shader.h  '#pragma once\nstruct Uniforms\n{\n    float x;\n    float y;\n};\n'
    aaf_put sidecar.h '#pragma once\nstruct Sidecar\n{\n    float a;\n    float b;\n};\n'
    aaf_put pair.h    '#pragma once\nstruct Pair\n{\n    int first;\n    int second;\n};\n'
    : > "$R/many.h"
    for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14; do printf 'struct Row%s\n{\n    int a;\n};\n' "$i" >> "$R/many.h"; done
    aaf_g add -A; aaf_g commit -qm base

    aaf_branch feat-break
    aaf_put shader.h '#pragma once\nstruct Uniforms\n{\n    float x;\n    float y;\n    float z;\n};\n'
    aaf_g commit -qam "add z"
    aaf_branch feat-repack
    aaf_put shader.h '#pragma once\nstruct Uniforms\n{\n    float x;\n    unsigned short p;\n    unsigned short q;\n};\n'
    aaf_g commit -qam "repack y"
    aaf_branch feat-vanish
    aaf_put shader.h '#pragma once\nstruct UniformsV2\n{\n    float x;\n    float y;\n};\n'
    aaf_g commit -qam "rename the struct away"
    aaf_branch feat-unmod
    aaf_put shader.h '#pragma once\nstruct Uniforms\n{\n    float x;\n    float y;\n    unsigned int flags : 4;\n};\n'
    aaf_g commit -qam "add a bitfield"
    aaf_branch feat-rename
    aaf_put shader.h '#pragma once\nstruct Uniforms\n{\n    float a;\n    float b;\n};\n'
    aaf_g commit -qam "rename the fields"
    aaf_branch feat-mix
    aaf_put shader.h '#pragma once\nstruct Uniforms\n{\n    float x;\n    float y;\n    double w;\n};\n'
    aaf_put pair.h   '#pragma once\nstruct Pair\n{\n    int left;\n    int right;\n};\n'
    aaf_g commit -qam "a drift and a rename"
    aaf_branch feat-many
    sed 's/int a;/int a; int b;/' "$R/many.h" > "$R/many.h.new" && mv "$R/many.h.new" "$R/many.h"
    aaf_g commit -qam "widen every row struct"
    aaf_branch feat-sidecar
    aaf_put sidecar.h '#pragma once\n// a comment only\nstruct Sidecar\n{\n    float a;\n    float b;\n};\n'
    aaf_g commit -qam "comment sidecar.h"
    aaf_g checkout -q main
    aaf_put sidecar.h '#pragma once\nstruct Sidecar\n{\n    float a;\n    float b;\n    float c;\n};\n'
    aaf_g commit -qam "widen Sidecar on the live line"
}

# render/ and test/ are built-in layer names, so `deny test -> render` makes test/main.cpp and test/extra.cpp violations.
# top.h sits at the root: its module is the root's own directory. With `go`, notes/ holds a Go file, a language this build
# draws no file edges for, so <metrics> carries zone_unknown= and the legend its clause.
aaf_arch_tree(){
    local D="$1"
    mkdir -p "$D/render" "$D/test"
    printf '#pragma once\nstruct Shader { int id; };\n'                 > "$D/render/shader.h"
    printf '#include "../render/shader.h"\nint main() { return 0; }\n'   > "$D/test/main.cpp"
    printf '#include "../render/shader.h"\nint extra() { return 1; }\n'  > "$D/test/extra.cpp"
    printf '#pragma once\nstruct Top { int t; };\n'                     > "$D/top.h"
    printf 'deny test -> render\n'                                       > "$D/rules.txt"
    if [ "${2:-}" = go ]; then
        mkdir -p "$D/notes"
        printf 'package notes\n\nfunc Note() int { return 1 }\n'         > "$D/notes/n.go"
    fi
}
