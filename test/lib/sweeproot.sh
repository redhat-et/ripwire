# sweeproot.sh — the root a gate asks the git-SWEEP verbs (--whereis, --stray-content, their MCP twins) from.
#
# Those verbs read every local branch of the repository enclosing the crawl root and refuse past crossref kMaxRefs (512).
# That refusal is a product answer, pinned on its own fixture (substrfiltercheck E); it is not the property a gate that runs
# them on this checkout reads. A CI checkout has no local branch; a long-lived developer clone can carry hundreds (the one
# where this was found had 518 lane branches), and every linked worktree of it shares them — so every gate that asked a
# sweep verb on this checkout was red there and green in CI. Each caller says so at its call site.
#
# sweepRoot ROOT DEST prints ROOT when its repository is under the cap. Past it, it builds DEST: a --shared clone (no object
# copy) checked out DETACHED at ROOT's HEAD with every local branch deleted — CI's ref shape over the same committed tree
# — and prints DEST. Uncommitted edits in ROOT are not in DEST; the arms that use it read legends and paging, not those.
# If DEST cannot be built it prints ROOT, and the arms show the refusal they always showed. Its git runs under
# test/lib/clean-env.sh (in a subshell, so the caller's environment is untouched): an exported GIT_DIR must not choose the
# repository it counts or clones.
SWEEPROOT_LIB="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
sweepRoot()
(
    . "$SWEEPROOT_LIB/clean-env.sh"
    root="$1" dest="$2"
    heads="$( git -C "$root" for-each-ref refs/heads --format='%(refname)' 2>/dev/null | wc -l | tr -d ' ' )"
    if [ "${heads:-0}" -le 512 ]; then
        printf '%s' "$root"
        return 0
    fi
    sha="$( git -C "$root" rev-parse --verify -q HEAD )" || { printf '%s' "$root"; return 0; }
    if git clone -q --shared --no-checkout "$root" "$dest" >/dev/null 2>&1 \
        && git -C "$dest" checkout -q --detach "$sha" >/dev/null 2>&1 \
        && git -C "$dest" for-each-ref refs/heads --format='delete %(refname)' | git -C "$dest" update-ref --stdin >/dev/null 2>&1
    then
        printf '%s' "$dest"
        return 0
    fi
    printf '%s' "$root"
)
