### Fixed — `--flags` Bash reads: child shells, `local` scope, redirections and quoting no longer hide a caller's variable (#641 follow-up)

Eight findings from the #641 merge review, each with a fixture row in `test/bashenvfix/followup.sh` that failed on main first:

- A write in a pipeline component (`printf x | read -r X`, `X=1 | cat`), a background job (`X=1 &`), or a compound command in a pipeline or in the background (`cmd | while read -r l; do X=1; done`, `{ X=1; } &`) runs in a child shell, so it no longer hides a later `${X:?}`. Inside its own command or loop body it still does. `&&`, `||`, `2>&1`, `&>` and a `|` between case patterns are not pipes or jobs. After `shopt -s lastpipe` a pipeline's last command runs in the script's own shell (read in file order).
- A `( … )` subshell is a pipeline component like any command: after `tar cf - . | (cd /dst && tar xf -)` the pipeline ends at the newline, so a variable set on the next line is the script's own (review of #685).
- `&` backgrounds the whole `&&` / `||` list: in `X=1 && cmd &` the write of `X` ran in the child too, so a later `${X:?}` is the caller's. A `;`, a newline or the `&` itself ends the list (review of #685).
- A later assignment to a name a function made `local` (`local X; X=v`, `read X`, `: ${X:=d}`) stays in that function, like the `local` itself.
- A `$( … )` at command position is the command name, so `$(printf printf) X=1` passes `X=1` as an argument. `X=$( … )` is still an assignment.
- A redirection no longer ends an assignment-only command: `X=1 >/dev/null`, `X=1 > f` and `X=1 2>&1` all set `X`.
- In an unquoted expansion's word, `'…'` quotes, so `: ${A:-'${B:?}'}` reads no `B`. Inside `"…"` a `'` is an ordinary byte, so `"${A:-'${B:?}'}"` still reads `B`.
- A heredoc delimiter `<<"E\"OF"` closes at `E"OF`: inside `"…"` a backslash escapes `$`, `` ` ``, `"` and `\`.
- The read lookup is linear. 160,000 `(X=1)` lines followed by 160,000 reads of `X` (2.1 MB) took about 56 s; they now take about 1 s.
- A file `--flags` cannot open, or cannot read to its end, is disclosed as `unreadable="N"` on the root (and in `--json` and the legend). It used to be skipped silently, and a read error part-way through harvested the prefix as if it were the whole file.

On this repository, fullsend-ai's agents tree and fullsend, every gate is byte-identical to before except one read that becomes correct: `$line` in `test/compactlegendcheck.sh` is set by `eval` at top level, and the `line=` writes that used to hide it are `local` to `softPair()`. Precision stays lexical within one file.
