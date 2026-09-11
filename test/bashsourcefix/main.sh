#!/usr/bin/env bash
# Every shape resolveBashSource has to answer, one per line, in one file.
source ./lib/helper.sh                 # literal, explicitly file-relative
. "$ROOT/lib/helper.sh"                # $VAR anchor, literal tail -> root-relative
source "$LIBDIR/util.sh"               # ${...}-free var anchor, bare tail
. "$( dirname "$0" )/util.sh"          # command substitution as the anchor
source "$1"                            # FLOOR: the whole specifier is a positional param
source "$d/$n.sh"                      # FLOOR: the FILENAME itself is a variable
source /etc/profile                    # absolute literal, outside the crawl
main_entry() { echo main; }
