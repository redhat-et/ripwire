#!/usr/bin/env bash
# AMBIGUITY control: with an unknown anchor the tail `shared.sh` is answered BOTH
# relative-to-this-file (sub/shared.sh) and relative-to-the-crawl-root (shared.sh).
# Two distinct files => degrade to NO edge, never pick one.
. "$SOMEDIR/shared.sh"
inner_fn() { echo inner; }
