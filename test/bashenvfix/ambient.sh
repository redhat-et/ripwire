#!/usr/bin/env bash
# ambient.sh — names Bash or the login always sets: real reads, tagged ambient="1", never unsupplied.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "$here $PWD $HOME $RANDOM $SHLVL $HOSTTYPE"
echo "$NOT_AMBIENT_SUPPLIED"
