#!/usr/bin/env bash
# ci-windows-skills-check.sh — the windows-package job's proof that a skills/install.sh run left USABLE skills (#334).
#
# On a Windows machine without symlink privilege, Git Bash's `ln -sfn DIR DEST` exits 0 and leaves an EMPTY directory;
# the 0.6.3 installer trusted that exit status and announced sixteen empty directories as active skills. An MSYS tool
# reading through an MSYS-only link can also see a file that no native program can. So this script asks the two
# questions an agent's skill loader would, of every ripwire-* entry in DIR:
#   1. does a NATIVE program (python, given the Windows spelling of the path) read a non-empty SKILL.md there?
#   2. does the installer's manifest declare exactly the entries that pass (1), no more and no fewer?
# and requires WANT of them. Runs unchanged on POSIX (cygpath absent: the path is used as is), where it proves the
# script's own logic rather than the Windows behaviour.
# Usage:  bash scripts/ci-windows-skills-check.sh <skill dir> <expected user-facing skill count>
set -u
dir="${1:?usage: ci-windows-skills-check.sh <skill dir> <want>}"
want="${2:?usage: ci-windows-skills-check.sh <skill dir> <want>}"
py="$( command -v python || command -v python3 )"
[ -n "$py" ] || { echo "ci: no python to read the skills natively" >&2; exit 1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

usable=""
n=0
for entry in "$dir"/ripwire-*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue      # the literal glob when nothing matches
    name="$( basename "$entry" )"
    if "$py" -c 'import sys; sys.exit(0 if len(open(sys.argv[1], "rb").read()) > 0 else 1)' "$( native "$entry/SKILL.md" )" 2>/dev/null; then
        usable="$usable$name
"
        n=$(( n + 1 ))
    else
        echo "ci: $entry has no SKILL.md a native program can read (kind: $( [ -L "$entry" ] && echo link || echo dir ), entries: $( find "$entry/" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ' ))" >&2
    fi
done
declared="$( sed -n 's/^skill=//p' "$dir/.ripwire-manifest-v1" 2>/dev/null | sort )"
have="$( printf '%s' "$usable" | sort )"
echo "$dir: $n of $want skills natively readable; manifest declares $( printf '%s\n' "$declared" | grep -c . )"
[ "$n" -eq "$want" ] || { echo "ci: expected $want usable skills in $dir, found $n" >&2; exit 1; }
[ "$declared" = "$have" ] || { echo "ci: the manifest in $dir does not declare exactly the usable skills" >&2; exit 1; }
