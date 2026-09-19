# statcompat.sh — GNU-vs-BSD `stat` compat, in one place. SOURCED, not run.
#
# GNU coreutils' `-f` is a different, valid flag (filesystem stat, not BSD's format string): it
# succeeds with junk instead of failing, so a caller-local `stat -f ... || stat -c ...` one-liner never
# reaches its own fallback on Linux. Twelve gates hand-rolled that same detect-once-and-redefine fix
# independently before this file existed. Sourcing this gives every one of them a ready-to-call
# function; no caller branches on the flavour itself.
if stat --version >/dev/null 2>&1; then   # GNU coreutils
    mtime_of()        { stat -c '%Y'    "$1" 2>/dev/null; }
    inode_of()        { stat -c '%i'    "$1" 2>/dev/null; }
    mode_of()         { stat -c '%a'    "$1" 2>/dev/null; }
    size_of()         { stat -c '%s'    "$1" 2>/dev/null; }
    inode_mtime_of()  { stat -c '%i %Y' "$1" 2>/dev/null; }
else                                       # BSD / macOS
    mtime_of()        { stat -f '%m'    "$1" 2>/dev/null; }
    inode_of()        { stat -f '%i'    "$1" 2>/dev/null; }
    mode_of()         { stat -f '%Lp'   "$1" 2>/dev/null; }
    size_of()         { stat -f '%z'    "$1" 2>/dev/null; }
    inode_mtime_of()  { stat -f '%i %m' "$1" 2>/dev/null; }
fi
