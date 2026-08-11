#!/usr/bin/env bash
# dependencypincheck.sh — dependencies are VENDORED in-repo, and their provenance pins are immutable.
#
# Two properties, and they are different claims:
#   (A) provenance — every FetchContent_Declare still records the exact upstream commit its vendored
#       tree was cut from (a tag can be force-moved server-side; a SHA cannot), so CMakeLists.txt and
#       THIRD_PARTY.md remain checkable against upstream by anyone, forever.
#   (B) hermeticity — the build never reaches the network. A comment cannot prove that, so the last
#       arm actually runs `cmake` with FETCHCONTENT_FULLY_DISCONNECTED=ON, which turns any attempted
#       fetch into a hard configure error. Configure is the right — and only — step to test:
#       FetchContent downloads at configure time, not at build time.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CMAKE="$ROOT/CMakeLists.txt"
DEPS="$ROOT/third_party/deps"
SWIFT_COMMIT="31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# ── (A) provenance pins ───────────────────────────────────────────────────────────────────────────
if grep -q "$SWIFT_COMMIT" "$CMAKE"; then
    ok "Swift grammar records the audited immutable commit"
else
    no "Swift grammar does not record the audited immutable commit"
fi

swiftBlock="$( sed -n '/tree-sitter-swift.git/,+4p' "$CMAKE" )"
if printf '%s\n' "$swiftBlock" | grep -Eq 'with-generated-files|GIT_TAG[[:space:]]+(main|master|HEAD)([[:space:]]|$)'; then
    no "Swift declaration still contains a moving ref"
else
    ok "Swift declaration contains no moving ref"
fi

# Every GIT_TAG must be a 40-hex commit id (or the variable holding one). A bare tag name would
# silently re-point the recorded provenance if the declares ever went live again.
badTags="$( grep -nE '^[[:space:]]*GIT_TAG[[:space:]]' "$CMAKE" \
            | grep -vE 'GIT_TAG[[:space:]]+([0-9a-f]{40}|\$\{[A-Za-z0-9_]+\})[[:space:]]*(#.*)?$' || true )"
if [ -n "$badTags" ]; then
    no "GIT_TAG provenance pin is not a 40-hex commit id:"
    printf '%s\n' "$badTags" | sed 's/^/          /'
else
    ok "every GIT_TAG provenance pin is a 40-hex commit id"
fi

# ── (B) vendored, not fetched ─────────────────────────────────────────────────────────────────────
if grep -q 'ripwire_use_vendored_source' "$CMAKE"; then
    ok "dependencies are adopted from the in-repo vendored trees"
else
    no "CMakeLists.txt no longer adopts the vendored dependency trees"
fi

# The shared ~/.cache clone is exactly the escape hatch vendoring removed. If it comes back, a machine
# with a primed cache builds green while a stranger's fresh clone silently fetches from github — the
# worst kind of green, because the person who can see the failure is never the person who ran the gate.
if grep -qE '\.cache/[a-z_]+-deps|ripwire_use_shared_source' "$CMAKE"; then
    no "CMakeLists.txt still has a shared-source-cache fallback (a network path by another name)"
else
    ok "no shared-source-cache fallback remains"
fi

missing=""
for dep in bash c cpp csharp cuda go java javascript json objc python ruby rust swift toml yaml; do
    [ -f "$DEPS/$dep/src/parser.c" ] || missing="$missing$dep/src/parser.c
"
    [ -f "$DEPS/$dep/LICENSE" ]      || missing="$missing$dep/LICENSE
"
done
for f in ts_typescript/typescript/src/parser.c ts_typescript/tsx/src/parser.c \
         ts_typescript/common/scanner.h ts_typescript/LICENSE \
         tree_sitter/lib/src/lib.c tree_sitter/lib/include/tree_sitter/api.h \
         tree_sitter/CMakeLists.txt tree_sitter/LICENSE \
         doctest/doctest/doctest.h doctest/LICENSE.txt; do
    [ -f "$DEPS/$f" ] || missing="$missing$f
"
done
if [ -n "$missing" ]; then
    no "vendored dependency tree is incomplete (pruned too far):"
    printf '%s' "$missing" | sed 's/^/          /'
else
    ok "every vendored dependency ships its compiled sources and its LICENSE"
fi

# ── (B') the hermeticity proof: a real disconnected configure ─────────────────────────────────────
if ! command -v cmake >/dev/null 2>&1; then
    no "cmake not found — the disconnected-configure proof cannot run (a skip here would be a green lie)"
else
    SCRATCH="$( mktemp -d )"
    trap 'rm -rf "$SCRATCH"' EXIT
    if cmake -S "$ROOT" -B "$SCRATCH/b" -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DRIPWIRE_TESTS=ON \
         > "$SCRATCH/cfg.log" 2>&1; then
        ok "configure succeeds with FETCHCONTENT_FULLY_DISCONNECTED=ON (nothing is fetched)"
    else
        no "configure FAILED with FETCHCONTENT_FULLY_DISCONNECTED=ON — something still wants the network:"
        tail -20 "$SCRATCH/cfg.log" | sed 's/^/          /'
    fi
    # A populated <name>-src under the scratch tree's _deps would mean FetchContent cloned after all.
    cloned="$( find "$SCRATCH/b/_deps" -maxdepth 1 -name '*-src' 2>/dev/null || true )"
    if [ -n "$cloned" ]; then
        no "FetchContent still materialised source clones under _deps:"
        printf '%s\n' "$cloned" | sed 's/^/          /'
    else
        ok "no dependency source was cloned into the build tree"
    fi
fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
