#!/usr/bin/env bash
# shapes.sh — hand-verified metrics fixture for jsmetricscheck.sh (Bash side).
# Every function's loc/params/nest/cbo below is counted BY HAND from the source text (Bash functions
# take no formal parameter LIST in the grammar sense, so params=0 is the expected/correct value for
# every function here — the gate asserts that explicitly rather than assuming JS-style params).

# leaf_sh: 0 nesting, 0 calls, loc = 4
leaf_sh()
{
    echo "$(( $1 + 1 ))"
}

# deep_nest_sh: 3 levels of control nesting (if > for > if), calls nothing in-repo (cbo=0)
deep_nest_sh()
{
    if [ "$1" -gt 0 ]; then
        for i in $(seq 1 "$2"); do
            if [ "$i" -gt "$3" ]; then
                echo "$i"
            fi
        done
    fi
}

# calls_leaf_and_deep_sh: 0 nesting, calls leaf_sh() and deep_nest_sh() -> cbo=2
calls_leaf_and_deep_sh()
{
    leaf_sh "$1"
    deep_nest_sh "$1" 1 2
}
