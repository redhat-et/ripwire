# strayfixture.sh — a throwaway git repo with KNOWN refs for the --stray-content / cross-ref probes.
#
# Sourced (not executed) by precedencecheck.sh, substrfiltercheck.sh and mcpclidiffcheck.sh. verify-wave1 R3
# (capture-audit 2026-09-04): those three probed `--stray-content=lane` / `=main` against the OPERATOR'S OWN
# checkout, so they were green only on a machine that happened to carry a `lane/*` branch and a `main` head —
# red on every fresh clone, in CI, and on this repo the day the round's lane/ca-* heads were pruned. A probe
# about the verb must own its refs (the pattern mergescoutcheck.sh's fixture already uses).
#
#   mkStrayFixture DIR   — DIR becomes a git repo: branch `main` (one commit, one .cpp) and a divergent
#                          branch `lane/probe` (one more commit that changes a symbol); HEAD is back on main,
#                          so `--stray-content=lane` from DIR sees exactly one stray candidate and `=main`
#                          sees only the branch it is standing on.
#
# Every git command is -C DIR: this helper never touches the caller's repo. Author/committer dates are fixed
# so two runs build byte-identical histories (the determinism gate applies to fixtures too).

mkStrayFixture()
{
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "dev@x.com"
    git -C "$dir" config user.name  "Dev"
    git -C "$dir" checkout -q -b main 2>/dev/null || git -C "$dir" symbolic-ref HEAD refs/heads/main
    printf 'int probeOne( int x ) { return x + 1; }\nint probeTwo( int x ) { return probeOne( x ) * 2; }\n' >"$dir/probe.cpp"
    git -C "$dir" add -A
    GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
        git -C "$dir" commit -qm "init"
    git -C "$dir" checkout -qb lane/probe
    printf 'int probeOne( int x ) { return x + 100; }\nint probeTwo( int x ) { return probeOne( x ) * 2; }\n' >"$dir/probe.cpp"
    GIT_AUTHOR_DATE="2026-06-01T13:00:00" GIT_COMMITTER_DATE="2026-06-01T13:00:00" \
        git -C "$dir" commit -qam "lane changes probeOne"
    git -C "$dir" checkout -q main
}

# strayFixtureHasRef DIR — presence guard: the ref the probes filter on exists (a gate must observe what it
# asserts before asserting the property). Prints nothing; exit status is the answer.
strayFixtureHasRef()
{
    [ -n "$( git -C "$1" branch --list 'lane/*' 2>/dev/null )" ]
}
