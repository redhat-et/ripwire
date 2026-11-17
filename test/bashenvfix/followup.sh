#!/usr/bin/env bash
# followup.sh — inputs from the #641 merge review (CodeRabbit on 9bb9419ef). Each FU_* read is the caller's.
# 1. A pipeline component or a background job runs in a child shell: its writes never reach the script.
printf x | read -r FU_PIPE_READ
: "${FU_PIPE_READ:?}"
FU_BG=internal &
wait
: "${FU_BG:?}"
printf x | while read -r fu_line; do FU_LOOP=internal; echo "$fu_line"; done
: "${FU_LOOP:?}"
{ FU_GROUP=internal; } &
: "${FU_GROUP:?}"
# … but && / || and the redirections 2>&1 and &> are not pipes or jobs: these writes are the script's own.
false || FU_OR=internal
: "${FU_OR:?}"
FU_DUP=internal 2>&1
: "${FU_DUP:?}"
FU_AMPREDIR=internal &>/dev/null
: "${FU_AMPREDIR:?}"
# lastpipe runs a pipeline's LAST command in the script's own shell; the others still run in children.
shopt -s lastpipe
printf x | read -r FU_LASTPIPE
: "${FU_LASTPIPE:?}"
FU_NOTLAST=internal | cat
: "${FU_NOTLAST:?}"
shopt -u lastpipe
# 2. An assignment to a name the function made `local` changes the local, not the script's variable.
fu_fn() { local FU_LOCAL_LATER FU_LOCAL_READ; FU_LOCAL_LATER=internal; read -r FU_LOCAL_READ; }
fu_fn
: "${FU_LOCAL_LATER:?} ${FU_LOCAL_READ:?}"
# 3. A substitution at command position is the command NAME, so what follows it are arguments.
$(printf printf) FU_CMDPOS=internal
: "${FU_CMDPOS:?}"
fu_val=$(printf x)
echo "$fu_val"
# 4. A redirection does not end an assignment-only command.
FU_REDIR=internal >/dev/null
: "${FU_REDIR:?}"
FU_REDIR_SP=internal > /dev/null
: "${FU_REDIR_SP:?}"
# 5. In an UNQUOTED expansion's word '…' quotes (no reads inside); inside "…" a ' is an ordinary byte.
: ${FU_OUTER:-'${FU_LITERAL:?}'}
: "${FU_DQ_OUTER:-'${FU_DQ_INNER:?}'}"
: ${FU_MIX_OUTER:-"'${FU_MIX_INNER:?}'"}
# 5b. A `|` between case patterns is an alternative, not a pipe: fu_arch is the script's own.
case "$(uname -m)" in arm64|aarch64) fu_arch=arm64 ;; *) fu_arch=other ;; esac
echo "$fu_arch"
# 6. LAST, because before the fix the heredoc below never closed: `\"` inside "…" is part of the delimiter.
cat <<"FU\"EOF"
FU_HD_BODY=internal
FU"EOF
: "${FU_HD_BODY:?} ${FU_AFTER_ESC:?}"
