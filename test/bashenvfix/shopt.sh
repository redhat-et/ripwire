#!/usr/bin/env bash
# shopt.sh — inputs from the #688 review (CodeRabbit 4614203135): a `shopt` that runs in a child shell changes the
# CHILD's options. With lastpipe on, `printf x | read -r X` sets X in the script, so each SH_*_KEEP read is satisfied.
shopt -s lastpipe
(shopt -u lastpipe)
printf x | read -r SH_SUB_KEEP
: "${SH_SUB_KEEP:?}"
sh_out=$(shopt -u lastpipe)
printf x | read -r SH_SUBST_KEEP
: "${SH_SUBST_KEEP:?} $sh_out"
shopt -u lastpipe &
wait
printf x | read -r SH_BG_KEEP
: "${SH_BG_KEEP:?}"
{ shopt -u lastpipe; } | cat
printf x | read -r SH_GRP_KEEP
: "${SH_GRP_KEEP:?}"
# … but a foreground `shopt -u` in the script's own shell turns lastpipe off for the pipelines after it, and a child's
# `shopt -s` does not turn it back on: these two reads are the caller's.
shopt -u lastpipe
printf x | read -r SH_FG_OFF
: "${SH_FG_OFF:?}"
(shopt -s lastpipe)
printf x | read -r SH_SUB_OFF
: "${SH_SUB_OFF:?}"
