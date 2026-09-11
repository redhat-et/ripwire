#!/usr/bin/env bash
# One `source` per container kind, to prove the walk enters each of them.
if [ -f x ]; then
  source ./lib/helper.sh
fi
in_function() {
  . ./lib/util.sh
}
for i in 1 2; do source ./lib/loopdep.sh; done
while false; do . ./lib/whiledep.sh; done
case "$1" in a) source ./lib/casedep.sh ;; esac
{ source ./lib/groupdep.sh; }
( source ./lib/subdep.sh )
[ -f y ] && source ./lib/anddep.sh
