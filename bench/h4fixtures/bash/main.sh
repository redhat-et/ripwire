#!/bin/bash
greet() { echo hi; }
function bye { echo bye; }

caller() {
    greet                 # 1. bare command call
    bye "arg"             # 2. call with args
    result=$(greet)       # 3. command substitution
    greet | bye           # 4. pipeline
    if greet; then bye; fi  # 5. condition position
}
caller
