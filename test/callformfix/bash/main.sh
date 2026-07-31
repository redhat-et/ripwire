#!/usr/bin/env bash
# BASH CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
# Bash has no qualified call form at all, so this fixture is the sibling control that says so.
# Expected counts are literals read off this file.

plainFn() { echo p; }

argsFn() { echo "$1"; }

substFn() { echo s; }

pipeLeftFn() { echo l; }

pipeRightFn() { cat; }

condFn() { return 0; }

callerBash() {
    plainFn                       # 1. plain command call
    argsFn one two                # 2. call with arguments
    local v
    v="$( substFn )"              # 3. command substitution
    pipeLeftFn | pipeRightFn      # 4. both sides of a pipeline
    if condFn; then               # 5. call in an if-condition
        echo "$v"
    fi
}
