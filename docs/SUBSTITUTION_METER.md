# The substitution meter

`hooks/ripwire-nudge.sh` has two jobs. The first is the advisory nudge: when an agent reaches for a
native default, say the ripwire verb that answers the same question. The second — this document — is
the **substitution meter**: append one JSONL row per observed tool call, so the question *"does an
agent with ripwire installed actually reach for it?"* has a number behind it instead of an anecdote.

Both jobs ship in one script, are registered by one command, and are opt-in together:

```bash
bash skills/install.sh --hook
```

## Why the unit is a tool call

The obvious instrument — run agents on tasks, score task success with and without ripwire — is dead,
and it is worth stating why so nobody rebuilds it. The power arithmetic puts the minimum detectable
effect at 8.5–26 pp against a pilot that measured **parity**; at 96 instances there is no version of
that experiment that resolves the question. See `docs/EVALS.md` and the agent-loop pilot it records.

A PreToolUse hook sits somewhere the task-level eval cannot: at the exact moment a default is chosen,
hundreds of times per session. So the unit of observation is one **tool call**, and the metric is a
rate over calls:

```
substitution rate = ripwire calls / (ripwire calls + native retrieval calls)
```

This is a weaker claim than "ripwire makes agents better" and it is measurable, which is the trade.

## Where the log lives

One **global** file, all repos:

| | |
| --- | --- |
| Default path | `~/.ripwire/substitution.jsonl` |
| Override the directory | `RIPWIRE_HOME=/some/dir` → `/some/dir/substitution.jsonl` |
| Override the file | `RIPWIRE_METER_LOG=/some/file.jsonl` |
| Optional config | `~/.ripwire/meter.conf` — `enabled=0` / `arm=control`, one `key=value` per line |
| Turn counting off | `RIPWIRE_METER=0` (the nudge keeps working) |

The hook is registered once per user but runs in whatever repository the session is in, so every row
carries `repo` (absolute path) and `tag` (its basename). One file plus a repo field is what makes
both the cross-repo and the per-repo view available from the same data; two files would not.

The file and its directory are created lazily, on the first observed call. Full local paths are
recorded on purpose — this log never leaves the machine.

**Failure is silent by contract.** No `HOME`, an unwritable directory, no `date`, no `jq`, a full
disk: every write path returns quietly. Nothing in the meter may change the hook's exit status, its
stdout, or the tool call it is watching. A tool that breaks the thing it measures has no readings.

## The row schema (v1)

One JSON object per line. Field order is stable; new fields are added at the end and bump `v`.

| Field | Type | Meaning |
| --- | --- | --- |
| `v` | int | Schema version. `1`. |
| `ts` | string | ISO-8601 UTC, **second** resolution. Not a tiebreaker — see `seq`. |
| `seq` | int | Per-session monotonic counter, 1-based. The ordering key. |
| `session` | string | The agent's session id, or `ppid<N>` when the payload carries none. |
| `repo` | string | Git top level of the call's `cwd`, or the `cwd` itself outside a repo. |
| `tag` | string | Basename of `repo` — the short name to group by. |
| `tool` | string | Raw tool name: `Bash`, `Read`, `Grep`, `Glob`, `mcp__ripwire__…`, `SessionStart`. |
| `class` | string | Fine classification — the table below. |
| `family` | string | `ripwire` · `native` · `git` · `other` · `meta`. |
| `nudged` | 0/1 | A nudge fired **on this call**. |
| `nudge` | string | Why it did or did not: `fired` · `dedup` · `gated` · `control` · `none`. |
| `post_nudge` | 0/1 | A nudge had **already** fired earlier in this session, before this call. |
| `arm` | string | `treatment` (default) or `control`. |
| `detail` | string | The command line, file path, or pattern — control characters stripped, 200 chars. |

Example:

```json
{"v":1,"ts":"2026-08-11T15:29:17Z","seq":1,"session":"a1b2","repo":"/src/ripwire","tag":"ripwire","tool":"Grep","class":"grep","family":"native","nudged":1,"nudge":"fired","post_nudge":0,"arm":"treatment","detail":"needle"}
```

### `seq`, and why not `ts`

Several tool calls routinely land in the same wall-clock second, so a second-resolution timestamp
cannot order them. `seq` is a per-session counter implemented as the size of a marker file that each
row appends exactly one byte to; a one-byte append is atomic, so two concurrent calls cannot collide
on a number. `session` + `seq` therefore order every row in a session unambiguously, which is what
makes reconstructing **chains** (`grep → read → read`) possible at all.

### `nudged`, `nudge`, `post_nudge` — the confound, kept separable

The hook's own nudge is a *cause* of the next ripwire call, so a single pooled rate would partly
measure the hook talking to itself. Rather than correct for that, the meter records enough to see it:

- `post_nudge=0` rows are the calls a session made **before** any nudge fired — the closest thing to
  an unprompted baseline this log contains.
- `post_nudge=1` rows are everything after.
- `nudged=1` marks the single call each nudge fired on.

Read those groups apart. Averaging them produces a number that means nothing.

## The classifier

Two inputs: the tool name, and (for `Bash`) the command line.

### By tool

| Tool | `class` | `family` |
| --- | --- | --- |
| `Read` | `read` | native |
| `Grep` | `grep` | native |
| `Glob` | `glob` | native |
| `mcp__ripwire__*` | `ripwire-mcp` | ripwire |
| `Bash` | see below | see below |
| anything else | *no row* | — |

The `--session-start` mode of the hook writes one `session-start` / `meta` row per session boundary,
so sessions are countable. It is registered for startup, resume and clear, so a long-lived session can
legitimately produce more than one.

### By command line (`Bash`)

Resolution order, first match wins:

1. **Strip the prefix.** Leading `VAR=value` assignments and the transparent wrappers `sudo`,
   `command`, `env`, `time`, `nice`, `nohup`, `exec`, `builtin` are removed, then the **rtk unwrap**
   (below). What remains is the leading word; it is reduced to its basename, so `/usr/bin/rg` and
   `./build/ripwire` classify like `rg` and `ripwire`.
2. **Leading word:**

| Leading word | `class` | `family` |
| --- | --- | --- |
| `ripwire` | `ripwire-cli` | ripwire |
| `grep` `egrep` `fgrep` `zgrep` `rg` `ag` `ack` `ack-grep` `ugrep` | `grep` | native |
| `find` `fd` `fdfind` | `find` | native |
| `cat` `head` `tail` `less` `more` `bat` `nl` `tac` | `read` | native |
| `ls` **with `-R` (in any cluster) or a recursive long flag** | `find` | native |
| `awk` `gawk` `mawk` **whose program starts with a `/…/` pattern** | `grep` | native |
| `sed` **with `-n`** | `read` | native |
| `git grep` | `grep` | native |
| `git diff` | `git-diff` | git |
| `git log` | `git-log` | git |
| `git show` with a stat summary | `git-show-stat` | git |

3. **The nudge's own verdict**, when the leading word declined but the nudge chain matched — this
   covers forms that lead with neither verb, such as `cd sub && git diff`.
4. **Vocabulary scan.** If the leading word is not a retrieval verb but the *line* names one anywhere
   — a pipeline, a loop body, `xargs`, a subshell — the row is written as `unclassified` / `other`.
5. **Otherwise, no row.** `cmake --build build -j`, `git status`, `npm test` are not observations this
   meter makes, and the hook bails as fast as it did before the meter existed.

Note the deliberate asymmetries. `ls` without a recursive flag is a directory listing, not a search.
`awk '{print $1}' /tmp/x` is not a search, which is why the awk rule anchors on a quote immediately
followed by a slash. `sed -i` is an edit. Plain `git status`, and every state-changing git subcommand,
stay out of both jobs.

### The rtk unwrap

On a machine where rtk rewrites dev commands through its own PreToolUse hook,
what this hook is handed is `rtk grep …`, not `grep …`. A meter that scored that as "not a grep" would
report a substitution rate that is a pure artifact of another tool's hook. So `rtk` and `rtk proxy`
are stripped as prefixes before classification:

| Command line as the hook sees it | `class` |
| --- | --- |
| `rtk grep -rn needle .` | `grep` |
| `rtk proxy rg needle src/` | `grep` |
| `rtk git log -5` | `git-log` |

### `unclassified` is a row, never a drop

An ambiguous command line is still an observation, and dropping it would bias the denominator toward
whatever the classifier happens to be good at. Those rows are excluded from the headline rate — the
honest treatment of a call this tool could not read — but they are counted and printed, and their
`detail` field is the evidence for which rule is missing. A growing `unclassified` count is a bug
report about this table.

## Known undercount: what the meter cannot see

Stated plainly, because a numerator that is quietly short makes the rate look worse than reality and
an unstated one makes it untrustworthy:

- **MCP verbs are visible only through the matcher, and only in Claude Code.** A PreToolUse hook sees
  a tool call only if the registered matcher names it, so the installer writes
  `Read|Glob|Grep|Bash|mcp__ripwire__`. Two gaps follow. A `settings.json` written by an **older
  installer** carries the narrower matcher and will miss every MCP call until `--hook` is re-run —
  which is why re-running now refreshes a stale matcher in place. And Cursor, Codex, Windsurf, aider
  and the rest have **no equivalent hook at all**: for those clients both the numerator and the
  denominator are entirely unobserved, and no row is better than a wrong row.
- **Only the four matched tool families are observed.** A retrieval that happens inside a subagent, a
  slash command, or a tool this matcher does not name is invisible.
- **Classification is lexical, not semantic.** It reads two words and a few flags. It does not know
  whether a `cat` was a retrieval or a heredoc, and it never executes anything.
- **`detail` is truncated at 200 characters**, so a very long pipeline is recorded in part. Without
  `jq` on `PATH` the hook falls back to a flat field extractor that stops at the first quote in the
  payload, so `detail` can be shorter still — `class` is unaffected, and the row stays valid JSON.
- **`nudge=gated`** rows come from a call outside a git repository or with no `ripwire` on `PATH`.
  They are counted; they were never nudgeable.

The meter does not estimate around any of this. An unobserved call is absent, and absent is not zero
— the same rule the rest of the tool's output follows.

## The A/B toggle: built now, dormant now

Default behaviour is **always-on observation with nudges enabled** — exactly what the hook did before
the meter, plus counting. The toggle exists so that switching on a real control-vs-treatment
comparison later costs one environment variable and no code:

| Arm | Nudge | Counted | Row says |
| --- | --- | --- | --- |
| `treatment` (default) | yes | yes | `arm":"treatment"` |
| `control` (`RIPWIRE_METER_ARM=control`, or `arm=control` in `meter.conf`) | **no** | yes | `arm":"control"`, `nudge":"control"` |

Only the literal `control` selects the control arm; any other value reads as the default, and the row
records what was actually used rather than what was asked for.

**Nothing alternates on its own.** Assignment is per session, by whoever sets the variable. Phase 2 —
a pre-registered alternation with a stated band — is a separate decision, and the point of shipping
the mechanism inert is that the decision is then cheap and the data before it is not contaminated by
a half-built one.

## Reading the log

```bash
python3 bench/substitution_report.py                        # ~/.ripwire/substitution.jsonl
python3 bench/substitution_report.py /path/to/log.jsonl
python3 bench/substitution_report.py -h                     # repo filter, row limit
```

Stdlib only, deterministic, counts only. Four sections: the rate split by nudge exposure and by arm;
the class composition of both sides; a per-repo breakdown; and **within-session class n-grams**
(bigrams and trigrams in `seq` order). That last section is the one to watch — the hypothesis worth
testing is that the real opportunity is a recurring *chain* (`grep → read → read`) that a single verb
could absorb whole, not any single call. The script prints counts and no interpretation; which chain
is worth absorbing is a judgment made elsewhere.

## Gate

`test/hookcheck.sh` section (11), arms M1–M27b: a row is written at the default global path with the
full field set; the rtk unwrap; the `unclassified` fallback; out-of-scope calls writing no row; the
`nudged`/`dedup`/`post_nudge`/`seq` fields; both arms; one global log across two repos; and — the arm
that matters most — an unwritable log costing the hooked command nothing.
