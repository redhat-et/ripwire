#!/bin/bash
# #700 / #701 (reported by jflowers): a `local` that ran in a child shell, and a `declare -g`, leave the name global.
sc_sub() { (local SC_SUB=1); SC_SUB=2; }
sc_sub
: "${SC_SUB:?}"
sc_cmd() { v=$(local SC_CMD=1; echo x); SC_CMD=2; }
sc_cmd
: "${SC_CMD:?}"
sc_pipe() { local SC_PIPE=1 | cat; SC_PIPE=2; }
sc_pipe
: "${SC_PIPE:?}"
sc_glob() { local SC_GLOB; declare -g SC_GLOB=1; }
sc_glob
: "${SC_GLOB:?}"
sc_gonly() { declare -g SC_GONLY=1; }
sc_gonly
: "${SC_GONLY:?}"
# Negatives: these reads stay requirements.
sc_plain() { local SC_PLAIN; SC_PLAIN=2; }
sc_plain
: "${SC_PLAIN:?}"
sc_inner() { (local SC_INNER; SC_INNER=2); }
sc_inner
: "${SC_INNER:?}"
sc_noloc() { (SC_NOLOC=2); }
sc_noloc
: "${SC_NOLOC:?}"
sc_rel() { local SC_REL; (declare -g SC_REL=1); SC_REL=2; }
sc_rel
: "${SC_REL:?}"
sc_twice() { (local SC_TWICE=1); local SC_TWICE; SC_TWICE=2; }
sc_twice
: "${SC_TWICE:?}"
# #720 review: `local X &` is a child shell too; `declare -g` sets the global even when a later write sets the local.
sc_bg() { local SC_BG=1 & SC_BG=2; wait; }
sc_bg
: "${SC_BG:?}"
sc_glob2() { local SC_GLOB2; declare -g SC_GLOB2=1; SC_GLOB2=local; }
sc_glob2
: "${SC_GLOB2:?}"
# Negatives: a { } group is no child shell; a child's later `local` ends before the function's; plain declare sets it.
sc_grp() { { local SC_GRP; }; SC_GRP=2; }
sc_grp
: "${SC_GRP:?}"
sc_outer() { local SC_OUTER; (local SC_OUTER); SC_OUTER=2; }
sc_outer
: "${SC_OUTER:?}"
sc_decl() { local SC_DECL; declare SC_DECL=1; }
sc_decl
: "${SC_DECL:?}"
