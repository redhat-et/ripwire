# The substitution meter

`hooks/ripwire-nudge.sh` has two jobs. The first is the advisory nudge: when an agent reaches for a
native default, say the ripwire verb that answers the same question. The second — this document — is
the **substitution meter**: append one JSONL row per observed tool call, so the question *"does an
agent with ripwire installed actually reach for it?"* has a number behind it instead of an anecdote.

Both jobs ship in one script, are registered by one command, and are opt-in together:

```bash
bash skills/install.sh --hook
```

The installer's own banner (printed before it writes anything) discloses this in the same terms as
this document: `detail` carries a raw file path, raw grep/glob pattern, or the first 200 B of a raw
Bash command in cleartext, the file stays local and is never transmitted, and there is no automatic
retention limit — the log grows for as long as counting stays on (`RIPWIRE_METER=0` opts out of
counting only; the nudge itself keeps working either way). That is a disclosure, not a behavior
change: nothing about what the meter captures changed here, only what the installer says about it
up front. An operator who wants less identifying detail in the log today has one option, opt out
entirely (`RIPWIRE_METER=0`); a `RIPWIRE_METER_REDACT=1` mode — hash `session`/`repo`, and reduce
`detail` to a basename/verb rather than the full raw value — is a real idea but an **owner decision**,
not implemented here: it would change the schema and the report scripts that read it, and an active
measurement window is running against the current schema right now.

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
| Optional config | `~/.ripwire/meter.conf` — `enabled=0` / `arm=control\|treatment\|auto` / `sweep=0` / `sweep_n=N` / `dedup_cooldown=N` / `dedup_cap=N`, one `key=value` per line |
| Turn counting off | `RIPWIRE_METER=0` (the nudge keeps working) |
| Declare a test harness | `RIPWIRE_METER_FIXTURE=1` — see [Fixture isolation](#fixture-isolation) |
| Turn the sweep escalation off | `RIPWIRE_SWEEP=0` (counting and the one-time nudges keep working) |
| Change the sweep threshold | `RIPWIRE_SWEEP_N=4` (default 3) |
| Change the dedup re-arm cooldown | `RIPWIRE_DEDUP_COOLDOWN=N` (default 20 — eligible observations of the same class since the last delivery before it can fire again) |
| Change the per-class delivery cap | `RIPWIRE_DEDUP_CAP=N` (default 3 — per tier; see [Dedup/cooldown policy](#dedup-cooldown-policy)) |

The hook is registered once per user but runs in whatever repository the session is in, so every row
carries `repo` (absolute path) and `tag` (its basename). One file plus a repo field is what makes
both the cross-repo and the per-repo view available from the same data; two files would not.

The file and its directory are created lazily, on the first observed call. Full local paths are
recorded on purpose — this log never leaves the machine.

**Failure is silent by contract.** No `HOME`, an unwritable directory, no `date`, no `jq`, a full
disk: every write path returns quietly. Nothing in the meter may change the hook's exit status, its
stdout, or the tool call it is watching. A tool that breaks the thing it measures has no readings.

<a id="fixture-isolation"></a>
### Fixture isolation: a test run may never reach this file

The hook has a gate, `test/hookcheck.sh`, which drives it with invented PreToolUse payloads by the
dozen. Those invocations produce rows in the ordinary way, and a fixture row is **indistinguishable
from a real one at analysis time** — same schema, same classes, a plausible session id. Until
2026-08-12 the gate ran with the ambient environment, so the meter resolved the operator's real
`$HOME` and every gate run appended a burst of synthetic rows to the live log. The contamination is
not uniform, which is what makes it dangerous rather than merely noisy: a gate run is a burst of
nudge-firing *native* calls with no ripwire call in it at all, so it drags the headline rate toward
zero and lands specifically in the nudge-efficacy denominator.

The contract is now that **a gate run cannot touch the default log**, held up by two independent
layers, because one layer is a thing a future test can forget:

| | |
| --- | --- |
| **Named destination** | The gate exports `RIPWIRE_METER_LOG` (and `RIPWIRE_HOME`, so `meter.conf` comes from the sandbox too) once, at the top. Every invocation inherits it, including one added later by someone who never read the comment. |
| **`RIPWIRE_METER_FIXTURE`** | Set by the gate to declare "a harness is driving this hook". If a destination has *not* been named — an invocation that strips the environment — the hook refuses to fall back to `$HOME` and **writes no row at all**, rather than writing to the real log. |

Refusing is silent, like every other meter failure: the meter stays subordinate to the tool call it
observes, and that rule gets no exception for the case where the meter is under test. A harness that
wants rows says where they go; a harness that says nothing gets none.

`test/hookcheck.sh` section (13) asserts both layers held. Its central arm does **not** compare byte
sizes — on a machine where the hook is installed, a real session can append while the gate runs, so a
size assertion is flaky in exactly the situation it exists for. It asserts *provenance* instead:
every fixture repository in that gate lives under a per-run `mktemp -d` path that no other process
can produce, so a row in the operator's log naming it is proof that this run leaked, and concurrent
real activity cannot forge one.

If you write another harness that invokes the hook, do both: name a destination, and set
`RIPWIRE_METER_FIXTURE=1`.

### Repairing a log that was already polluted

A guard stops new pollution; it cannot repair a log that already has some. `bench/substitution_scrub.py`
separates fixture rows from real observations in an existing log:

```bash
python3 bench/substitution_scrub.py                                  # read-only report
python3 bench/substitution_scrub.py LOG --out cleaned.jsonl          # + write the clean copy
python3 bench/substitution_scrub.py LOG --out cleaned.jsonl --ids-only
```

It is **never destructive**: the input is opened read-only, `--out` names a new file and is refused
if it resolves to the input, and with no `--out` the run is a report. Four rules are tried in order,
and each removed row is attributed to the first that matched, so the counts partition the removals:

| Rule | Removes |
| --- | --- |
| `fixture-session-id` | The session id is one `test/hookcheck.sh` writes — an exact list, not a guess. |
| `synthetic-session-id` | The session id is neither a UUID (what an agent harness issues) nor the hook's own `ppid<N>` fallback: somebody hand-drove the hook. |
| `fixture-repo-temp` | `repo` is inside a temp tree — where throwaway gate fixtures live and real work does not. |
| `fixture-payload` | A synthetic payload (`needle`, `alpha`, `**/*.cpp`) **and** a fixture repo basename. Deliberately narrow: the net for a fixture that reused a real-looking session id, not a content filter. |

Every rule's count and a sample of its evidence are printed whichever mode runs, so an operator can
see what a heuristic *would* have taken before allowing it; `--ids-only` keeps everything the three
heuristics matched. Line order and bytes are preserved exactly — the cleaned file is the input minus
some lines, never a re-serialization — and a line that does not parse is carried through rather than
dropped. The report ends with the surviving session ids and their row counts, which is the number a
baseline recomputation actually needs.

Rerun `bench/substitution_report.py` against the cleaned copy; any baseline taken before the scrub is
a reading off a contaminated instrument.

## The row schema (v2)

One JSON object per line. Field order is stable; new fields are added at the end and bump `v`.

**v1 → v2 (2026-08-12).** Added `post_sweep`, added the `sweep<N>` value of `nudge`, and widened the
classifier (below). The widening means **row counts are not comparable across the boundary** — a v2
log records build/gate/git-state/shell commands that a v1 log dropped, and it reads `cd <dir> && …`
lines that a v1 log filed as `unclassified`. Compare v1 to v2 only by replaying the v1 rows'
`detail` through the current classifier; `v` is on every row so which side a row is on is never a
guess.

| Field | Type | Meaning |
| --- | --- | --- |
| `v` | int | Schema version. `2`. |
| `ts` | string | ISO-8601 UTC, **second** resolution. Not a tiebreaker — see `seq`. |
| `seq` | int | Per-session monotonic counter, 1-based. The ordering key. |
| `session` | string | The agent's session id, or `ppid<N>` when the payload carries none. |
| `repo` | string | Git top level of the call's `cwd`, or the `cwd` itself outside a repo. |
| `tag` | string | The **repository** to group by — see the note below. Not simply the basename of `repo`. |
| `tool` | string | Raw tool name: `Bash`, `Read`, `Grep`, `Glob`, `mcp__ripwire__…`, `SessionStart`. |
| `class` | string | Fine classification — the table below. |
| `family` | string | `ripwire` · `native` · `git` · `other` · `meta`. |
| `nudged` | 0/1 | A nudge was actually **delivered** (text emitted) on this call. Always 0 in the `control` arm. |
| `nudge` | string | Why it did or did not: `fired` · `sweep<N>` · `dedup` · `gated` · `control` · `suppressed-control` · `none`. `control`/`suppressed-control` are the control arm's **counterfactual** — see below. |
| `post_nudge` | 0/1 | A nudge had **already** fired (or, in the control arm, would-have-fired) earlier in this session, before this call. |
| `post_sweep` | 0/1 | A **sweep escalation** had already fired (or would-have-fired) earlier in this session. |
| `arm` | string | `treatment` (default) or `control`. See [The A/B toggle](#the-ab-toggle) for how a session lands on one or the other. |
| `detail` | string | The command line, file path, or pattern — control characters stripped, 200 chars. |

Example:

```json
{"v":2,"ts":"2026-08-11T15:29:17Z","seq":1,"session":"a1b2","repo":"/src/ripwire","tag":"ripwire","tool":"Grep","class":"grep","family":"native","nudged":1,"nudge":"fired","post_nudge":0,"post_sweep":0,"arm":"treatment","detail":"needle"}
```

### `tag` is the repository, not the directory (2026-09-02)

`tag` used to be the basename of `repo`, and every **linked git worktree** of one repository therefore
reported as its own repo: a dozen `~/.claude/worktrees/<name>` checkouts of ripwire appeared in the
report as a dozen different "repos", each with its own tiny sample. That is the worst place for this
error to land, because the per-repo cut is precisely the one that controls for repository composition
— the confound that makes a pooled cross-repo rate uninterpretable.

`tag` now comes from the repo's **git common dir** (`git rev-parse --path-format=absolute
--show-toplevel --git-common-dir`, one invocation for both facts), with the trailing `/.git` stripped
and the basename taken. A linked worktree shares its common dir with its main worktree, so the two
fold together; two genuinely different repositories still get two different tags. Outside a repo — or
on a git older than 2.31, which rejects `--path-format` — it falls back to the directory basename,
which is the pre-2026-09-02 behaviour.

`repo` is deliberately **not** folded. It still names the worktree the call actually happened in:
grouping the tag must not falsify the path, or a row stops saying where it came from.

**Schema note.** Rows written before this change keep the old per-worktree tag. `v` did not bump — no
field was added, removed or retyped — so a per-repo analysis that spans the boundary sees one
repository under several names on the older side. Group by `repo`'s common prefix, or restrict the
window, rather than trusting a `tag` histogram across it.

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
- `post_sweep=1` is the same idea one level up, for the sweep escalation only: everything after an
  escalation fired in that session. It is the grouping variable of the pre-registered efficacy
  readout in `docs/EVALS.md` §4, and it is recorded at observation time rather than reconstructed,
  so the analysis reads an assignment instead of inferring one.

Read those groups apart. Averaging them produces a number that means nothing.

## The literal-grep cede (P4.2, 2026-08-29)

Agents correctly drop to `rg`/`grep` for a known-literal hunt — our own docs concede the case (see
the `ripwire-efficient`/`ripwire-orient`/`ripwire-navigate` skills) — and the base one-time nudge used
to fire on that first call regardless of what the pattern looked like, nagging about a comparison it
loses. The base tier's `grep`/`bash-grep` categories are now gated: `category` is demoted back to `""`
(the identical "observed, no nudge pattern applies" verdict a single-file, non-recursive grep already
gets) unless the pattern shows one of two narrow, purely syntactic signals —

- a literal `|` (alternation) in the pattern, or
- two or more standalone `-e` pattern flags on the Bash command line (`grep -e foo -e bar`).

A short single literal (`rg "exact string"`) shows neither, so the row logs `class":"grep"` (still
counted; the meter's denominator is unaffected) with `nudge":"none"` — the base tip simply never fires.
This is a gate on the EXISTING base tier, not a new tracking mechanism: `mclass` (what the sweep
counters below key on) is untouched, so three single-literal greps in a row still escalate at the
sweep threshold exactly as before, and a grep-then-read *chain* still gets a nudge — via the
(unmodified) read category's own base tier, the moment the agent opens the file the grep pointed at —
with no new code. The heuristic is syntactic on purpose (a `-e`/`|` inside an unrelated argument can
misfire in either direction); the accepted failure mode is silence, never a wrong or noisy nudge.

## The sweep escalation

The base nudges say the verb; the **sweep escalation** fires at the **Nth** call of a class (default
N=3) and says the whole command, built from what was observed:

| Sweep class | What the escalation names |
| --- | --- |
| `grep` | `--for="<the last up-to-3 patterns this session, space-joined>"`, plus `--pack-task` and `--grep` |
| `read` | `--pack-task` and `--expand`, scoped to the directory of the file just read |
| `git-diff` `git-log` `git-show-stat` | `--situ`, plus `--pr-context` and `--map-diff` |
| `glob` | `--for`, plus the flagless map |

A firing row carries `nudged":1` and `nudge":"sweep<N>"`; every later row in that session carries
`post_sweep":1`. It obeys every posture the base nudges obey — advisory only, never a `deny`, silent
when the target is not a git repo or `ripwire` is off `PATH`, silent in the `control` arm (see
[Dedup/cooldown policy](#dedup-cooldown-policy) for what "silent" now means there). It no longer
retires the base tier's marker on firing — see that section for why the two tiers now dedup
independently rather than sharing one counter.

## Dedup/cooldown policy {#dedup-cooldown-policy}

**Old policy (2026-08-11 – 2026-08-19): fire once per class per session, ever.** The base tip fired on
the first eligible call of a category and a plain marker file silenced every later one, for the rest
of the session, regardless of how many more times the trigger condition recurred. The sweep escalation
had the same shape — one delivery, ever, per class, and firing it also retired the base tier's marker.
Measured against the 2026-08-19 readout (4,209-row snapshot): the trigger condition was met 1,546
times but delivered only 17 times (1.1%) — a nudge or two near session start, then silence for a
session that can run thousands of rows. `grep`-class native calls, the largest and cleanest
substitution target (931 occurrences, dominant pattern a literal `grep -n SYM file`), went
unaddressed 95.9% of the time.

**New policy: a re-arming cooldown, capped.** Each tier — the base one-time tip and the sweep
escalation — tracks its own eligible-observation count, delivery count, and the observation count at
its last delivery. A call delivers when either no delivery has happened yet this tier this session
(same "fires on first sight" as before), or at least `dedup_cooldown` MORE eligible observations of
the class have occurred since the last delivery **and** fewer than `dedup_cap` deliveries have
happened so far for that tier. Defaults: cooldown 20, cap 3 per tier (so a class with both tiers —
grep/read/glob/git-*  — can receive up to 3 generic tips and 3 escalated tips across a session, not an
unbounded stream and not a single shared 3). Both are overridable
(`RIPWIRE_DEDUP_COOLDOWN`/`RIPWIRE_DEDUP_CAP`, or `dedup_cooldown`/`dedup_cap` in `meter.conf`).

The two tiers dedup **independently** rather than sharing one counter — tried and reverted: the base
tier's observation stream (only nudge-eligible calls) and the sweep tier's (every occurrence of the
class) advance at different rates, and whichever tier reached its own threshold first would silently
spend a shared delivery slot, turning "escalate at exactly the Nth occurrence" into "escalate at the
Nth occurrence, unless the generic tip got there first." Two small independent caps are simpler to
reason about than one shared counter with an order-dependent race.

**The control arm rides the same policy.** A control-arm call runs through the identical
`.obs`/`.deliv`/`.last` bookkeeping a treatment call does, so `nudge":"control"` means this call is the
counterfactual delivery under the CURRENT (re-arming) policy, and `nudge":"suppressed-control"` means
a treatment session would be within cooldown here too — not the old policy's flat "control" for every
eligible call.

**The observation window restarts with this policy.** Every row logged before this change used the
old fire-once-forever policy; every row from this change onward uses the re-arming one.
`nudge":"dedup"` (or `"suppressed-control"`) in an old row and the same value in a new one are not the
same measurement — the new one means "within cooldown of the last delivery," not "will never fire
again this session." Any before/after comparison spanning this change is comparing two different
instruments, not measuring drift in one.

The patterns quoted back at the agent are sanitized where they are captured, not where they are
emitted: anything outside `[A-Za-z0-9_.:-]` becomes a space, runs of spaces collapse, each pattern is
capped at 60 characters and the join at 100. Word splitting does not honour quotes, so `rg "foo bar"`
contributes `foo`, not `foo bar` — the escalation is built to be pasteable, not to be a shell.

**Per-call cost.** One byte appended to a per-class counter file plus one fork-free `$(<file)` read
of it, on the nudgeable path only; the `control` arm and calls outside a git repo pay nothing.
Measured against the pre-change hook, 80 reps per payload, two runs on a busy machine: `Read`
27.19 → 28.30 ms then 32.49 → 30.49 ms, `Grep` 27.24 → 28.49 ms then 29.43 → 30.46 ms, a Bash
retrieval line 34.81 → 34.30 ms then 36.24 → 36.09 ms, a non-matching tool 7.44 → 7.66 ms. The run
spread is ±2 ms, which is larger than the effect, so the honest statement is **+1 ms or under, below
this harness's noise floor** — not a point estimate. Every figure includes the whole `bash <hook>`
process spawn, which dominates all of them.

**Turning it off is a config flip, on purpose:** `RIPWIRE_SWEEP=0`, or `sweep=0` in `meter.conf`.
`docs/EVALS.md` §4 pre-registers the one-week efficacy readout and its band, and a null readout
disables the escalation — the switch exists so that decision costs no code.

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

0. **Un-escape.** `fields3` fetches `cwd`, `session_id` and the command in one `jq` spawn by joining
   them with tabs, so `jq` escapes every newline inside the value. An agent's Bash command is
   routinely multi-line (`cd <worktree>\ngit diff`), so the literal `\n` sequences are turned back
   into separators before anything reads the line. Skipping this step is what made 742 of the first
   log's 924 `unclassified` rows: `cd /a/b\ngit` is one word whose basename is `b\ngit`, which
   matches no rule at all. `detail` keeps the un-substituted single-line form.

   The substitute is `;`, not a space. **A newline is a command separator in shell**, and calling it
   whitespace glued a multi-line command into one unsplittable segment that the walk in step 3 could
   not read: `cd /w⏎for g in …⏎do bash test/$g.sh⏎done` arrived as one line whose leading word is
   `for` and whose command is four words further in.
1. **Strip the prefix, repeatedly.** Leading `VAR=value` assignments, the transparent wrappers
   `sudo`, `command`, `env`, `time`, `nice`, `nohup`, `exec`, `builtin`, the compound-statement
   keywords `do` `then` `else` `elif` `done` `fi` `esac`, the separators `&&`, `||`,
   `;`, `&`, a **`cd`/`pushd` and its directory operand**, and the **rtk unwrap** (below) are removed
   in a loop, in any order and any number of times — `cd x && VAR=y grep …` unwraps to `grep`, and
   `cd x && cd sub && cat f` unwraps to `cat`. `git`'s own pre-subcommand options (`-C DIR`, `-c
   K=V`, `--git-dir=`, `--work-tree=`, `--no-pager`) are skipped too, so `git -C /w diff` classifies
   as `git diff`. What remains is the leading word, reduced to its basename, so `/usr/bin/rg` and
   `./build/ripwire` classify like `rg` and `ripwire`.

   The `cd` strip is not a nicety. **816 of the first log's 927 unclassified rows began with
   `cd <path> && …`** — the worktree-session idiom of a repo with dozens of checkouts — and every
   one of them was scored as a line this tool could not read.
2. **Leading word:**

| Leading word | `class` | `family` |
| --- | --- | --- |
| `ripwire` | `ripwire-cli` | ripwire |
| `grep` `egrep` `fgrep` `zgrep` `rg` `ag` `ack` `ack-grep` `ugrep` | `grep` | native |
| the same **with a count-only or quiet flag** (`-c`, `-q` in any lowercase cluster, `--count`, `--quiet`) | `build-poll` | **meta** |
| `ps` `pgrep` — including `ps aux \| grep "[t]hing"`, where the grep filters a process table | `process-poll` | **meta** |
| `find` `fd` `fdfind` | `find` | native |
| `cat` `head` `tail` `less` `more` `bat` `nl` `tac` — **without** a `>` redirect | `read` | native |
| the same **with** `>` (`cat > f <<EOF`) — a write, not a read | `shell-misc` | other |
| `ls` **with `-R` (in any cluster) or a recursive long flag** | `find` | native |
| `awk` `gawk` `mawk` **whose program starts with a `/…/` pattern** | `grep` | native |
| `sed` **with `-n`** | `read` | native |
| `git grep` | `grep` | native |
| `git diff` | `git-diff` | git |
| `git log` | `git-log` | git |
| `git show` with a stat summary | `git-show-stat` | git |
| `git push` `fetch` `pull` `clone` `remote` `ls-remote` `submodule`, and `gh` | `git-remote` | git |
| any other `git` subcommand — `status` `add` `commit` `checkout` `worktree` `show` … | `git-misc` | git |
| `cmake` `make` `ninja` `xcodebuild` `gradle` `mvn` `bazel` `clang` `gcc` `c++` `swiftc` `tsc` `rustc` | `build` | other |
| `cargo` `go` `npm` `yarn` `pnpm` `dotnet` — with `test` | `gate-run` | meta |
| the same, with anything else | `build` | other |
| `pytest` `ctest` `tox`; anything under `test/…`; `python3`/`bash`/`sh` pointed at `test/…`, `*check.sh`, `pargates`, `regression.sh`; those scripts run directly | `gate-run` | meta |
| `python3` `python` `bash` `sh` `zsh` `node` `ruby` `perl` `osascript` — with **anything else**: an inline program (`-c`, `-e`, `-`, a heredoc) or a non-gate script path | `script-run` | other |
| `cd` `mkdir` `cp` `mv` `rm` `touch` `chmod` `echo` `wc` `export` `sleep` `stat` `diff` `cmp` `tr` `sort` `uniq` `cut` `tee` `seq` `realpath` `:` … , and `ls` without `-R` | `shell-misc` | other |

3. **The segment walk.** A compound line is not one command, and reading only its first word was the
   largest single source of `unclassified` in the log: the first word is routinely plumbing
   (`echo "=== x ==="`, `mkdir -p $D`, a `for` header) and the command the agent actually ran is one
   segment further along. Steps 1–2 are therefore re-run over the **sequenced** segments — `;`,
   `&&`, `||` — and the first one they decide wins. Three rules govern it:

   - **Pipeline stages are not walked.** `A | B` hands B the output of A, so B filters that output
     rather than retrieving anything. Descending into it would score every `… | head -40` as a
     native `read`, filling the rate's denominator with pagers. So `ls test | grep -i doc` keeps the
     verdict step 5 gives it, and `ls docs/ | head -40` is `shell-misc`.
   - **A heredoc ends the walk.** Everything past `<<MARKER` is body text — a commit message, a
     fixture file, a Python program — and an inline program (`python3 -c …`) is not walked at all.
     Reading the next line of either as a shell command is how a classifier invents observations.
   - **A retrieval class found by the walk outranks a non-retrieval class found at the head.**
     `git reset -q HEAD~1 && ./build/ripwire . --quality-delta` is a ripwire call; the v1→v2
     correction established that undercounting the tool's own invocations is this instrument's most
     damaging failure mode, and this is the same shape one separator further along. The cost is
     stated rather than hidden: such a line contributes its retrieval row and *not* a
     `build`/`git-misc`/`script-run` row, so the S4 command-mix survey sees one fewer of those.
4. **The nudge's own verdict**, when the leading word declined *or* returned `shell-misc` but the
   nudge chain matched — this covers forms that lead with neither verb, such as
   `echo "=== git log ===" && git log --oneline`.
5. **Vocabulary scan.** If neither the head nor the walk named a command this table knows, but the
   *line* names a retrieval verb anywhere — a pipeline, a loop body, `xargs`, a subshell — the row is
   written as `unclassified` / `other`. Two exclusions keep that scan from firing on things that are
   not invocations:

   - **A path component is not a command word.** A `/` immediately after the word disqualifies it:
     `/opt/homebrew/share/ripwire/hooks/…` names a *directory* called ripwire. A `/` before the word
     is not disqualifying, so `xargs /usr/bin/grep …` still counts.
   - **`head` `tail` `less` `more` `bat` `nl` `tac` are not in the scan's vocabulary.** As a leading
     word the table above already reads them as `read`, and in a later sequenced segment so does the
     walk; the only position left for the scan to catch them in is a pipeline stage, where they page
     another command's output. The residue is the rare `$(head -1 f)`, which writes no row.
6. **Otherwise, no row.** `npx create-thing`, `brew upgrade`: not observations this meter makes, and
   the hook bails as fast as it did before the meter existed.

Note the deliberate asymmetries. `ls` without a recursive flag is a directory listing, not a search.
`awk '{print $1}' /tmp/x` is not a search, which is why the awk rule anchors on a quote immediately
followed by a slash. `sed -i` is an edit. The state-changing git subcommands are still **never
nudged** — that rule predates the meter and does not change — they are merely counted now.

And note where `shell-misc` sits: it is the one leading-word family checked **after** the vocabulary
scan rather than before it. `ls test | grep -i doccommand` is evidence about a grep; a leading-word
rule that returned first would destroy that evidence. A bare `ls -la docs/` has none to destroy.

### The two poll classes (2026-09-02)

`build-poll` and `process-poll` were split out of `grep` after mining the A/B window for the readout
in [`EVALS.md` §4](EVALS.md): **~14% of that window's `grep`-class rows were polls, not searches**, and
they were not evenly distributed across the arms, which made the resulting bias directional rather
than merely noisy.

- **`build-poll`** — a grep whose only output is a count or a boolean: `grep -c Building <buildlog>`
  ("how far has the build got"), `grep -q PARGATES_EXIT <taskfile>` ("has the gate run finished").
- **`process-poll`** — `ps` or `pgrep` as the leading word, which is the liveness check on a
  background job. It is decided at the **head**, before the vocabulary scan, so the grep inside
  `ps aux | grep "[t]hing"` filters a process table and never becomes the observation.

Both are family `meta` and therefore outside the substitution rate, for the same reason `gate-run` is:
**a poll retrieves no content, so there is no ranked map that could have answered it instead.** Leaving
them in put calls in the denominator that this tool is not competing for.

Two costs, stated rather than hidden. A legitimate "count the occurrences in this source file"
`grep -c` is swept up too — accepted, because a count is not a thing this tool returns either. And the
flag test is deliberately **lowercase-only**: `-C` is grep's *context* flag and must not match, which
is why the character class is not case-insensitive. `git grep -c` still classifies as `grep`, because
the git subcommand table decides before the flag test runs.

**Schema note.** Rows written before this change carry `grep` for exactly these command shapes. There
is no way to reclassify them in place — `detail` is capped at 200 characters and a long line can be cut
mid-flag — so a rate computed across the boundary mixes two denominators. The correction is small and
its direction is known: removing the polls from the A/B window raises the treatment arm's share by a
factor of 1.09 and the control arm's by 1.02.

### Why the non-retrieval classes exist

`build`, `gate-run`, `git-remote`, `git-misc`, `script-run`, `shell-misc`, `build-poll` and
`process-poll` are **not** part of the
substitution rate — their families are `other`, `meta` and `git`, and §1 of the report divides
ripwire by native only. They exist because Track B §S4 ranks the rtk-absorption queue from *the
command mix an agent actually runs*, and a command class that writes no row is a class that survey
can never see.

`script-run` is the newest of them and the one that needs defending, because it moves rows out of
`unclassified` and that could be mistaken for tidying the number away. It is a **disclosure, not a
claim**: a lexical classifier cannot see what a program does, so an interpreter handed an inline
program or a script path is named as exactly that. The distinction that matters is what the two
labels *mean to a reader*. `unclassified` means "this table is missing a rule" — the section below
says so, and a growing count is read as a bug report. A `python3 -c "…"` needs no rule; the rows
that used to land there did so only because the script's own text happened to contain the word `cat`
or `sed`, which was never evidence of anything. Both classes are excluded from the rate either way,
so nothing about this changes the substitution number; when the opacity of the corpus is the
question being asked, count `unclassified` and `script-run` together.

The cost is stated rather than hidden: commands that used to bail at the fast path now write a row,
so a v2 log is larger than a v1 log of the same activity, and no logged call became slower (a build
line now takes the same logged path a `Read` always took: ~22 ms → ~36 ms in the local harness,
against ~34 ms for a Bash retrieval line that was always logged).

### What the correction did to the headline number

Replaying the v2 classifier over a frozen 2,155-row v1 log:

| | v1, as logged | v2, replayed |
| --- | --- | --- |
| `unclassified` | 924 (42.9% of the log) | **160** (7.4%) — **−82.7%** |
| substitution rate, overall | 1.05% (9/859) | **5.62%** (73/1298) |
| pre-nudge (`post_nudge=0`) | 1.09% | **6.14%** |
| post-nudge (`post_nudge=1`) | 0.79% | **0.79%** |

ripwire's own calls were undercounted **8×** (9 → 73), because `cd <worktree> && ./build/ripwire …`
is exactly the form the prefix strip was missing. Any analysis that quotes the 0.8% headline is
quoting a broken instrument; `docs/EVALS.md` §4 states both numbers and registers its band against
the corrected one.

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

## What the A/B found — both nudge tiers are RETIRED (2026-09-02) {#what-the-ab-found}

`arm=auto` (below) went live 2026-08-19 and produced the first randomized population this instrument
ever had. **Window 2** — every row with `ts >= 2026-08-19T12`, `ts < 2026-09-02T00`, and
`session != smoketest` — is a roughly balanced treatment/control sample across several hundred
sessions. The readout is registered, with its argv, its per-session bootstrap CI, its `n`s and its
confounds, in [`EVALS.md` §4, "PreToolUse nudge A/B"](EVALS.md). Its verdict, in one line:

> **No cut separates the arms.** Not the pooled substitution share inside a single repository, not
> the per-session median with sessions as the unit, and not the before/after around the moment a
> nudge fires — where the treatment arm's dip is reproduced, larger, by the control arm's own
> counterfactual. The dip is regression to the mean after a sweep, not an effect of the advice.

The consequence was applied rather than written down. Both tiers stop emitting text:

- the **base tier** (the §CEDE-gated one-time tips) — the hook's own header had recorded, from the
  2026-08-11 first-12-hours readout, that it converts at ~0%; the A/B is the randomized confirmation;
- the **sweep escalation** — resolved against *its own* pre-registered band in `EVALS.md` §4, which
  asked for a `post_sweep=1` substitution rate of ≥ 3×B to KEEP and < ~1.4×B to DISABLE over ≥ 200
  rate-eligible calls in ≥ 10 sessions. The minimum data is met several times over and the reading is
  **below 1×B**: escalated sessions substitute slightly *less* after the escalation than before it,
  and less than the control arm's counterfactual over the same window. That is a DISABLE by the rule
  as written, and the rule was written before the data existed.

**What "retired" changed, and what it deliberately did not.** The advice is gone. Everything else
runs exactly as before: the same eligibility rules, the same `.obs`/`.deliv`/`.last` counters, the
same cooldown policy, in both arms — so the log still records *which call would have been spoken to*.
That is what keeps "how often was the moment even reached" answerable for the next instrument, and it
is the covariate the Claude Code prompt router's readout will want.

**Schema note — the `nudge` vocabulary changed at this commit.** Rows written before it use the old
values; rows after it use the new ones. `v` did not bump, because no field was added, removed or
retyped — only the set of strings one field takes. A before/after comparison across this commit must
map them:

| Before 2026-09-02 | After | Meaning |
| --- | --- | --- |
| `fired` (treatment) · `control` (control, base tier) | `retired` | this call was the base tier's delivery moment |
| `dedup` (treatment) · `suppressed-control` (control) | `dedup` | eligible, but inside the cooldown |
| `sweep<N>` (treatment) · `control` (control, sweep tier) | `retired-sweep` | this call was the escalation moment |
| `gated` · `none` | unchanged | precondition failed · no pattern applied |

`nudged` is now **always 0**, and `post_nudge`/`post_sweep` are pure counterfactual markers — "an
eligible base-tier / sweep-tier moment already occurred in this session" — identical in both arms.
None of the three fields was dropped: a schema that deletes a field cannot be compared across its own
boundary.

**The arm still means something.** It now separates exactly one behaviour: the **SessionStart
primer**, which the control arm does not receive. That is the lever the 2026-08-10 finding actually
credited — concentration (skill and `CLAUDE.md` text), never the PreToolUse hook — so the live A/B
from here is primer-vs-no-primer, and the PreToolUse path is byte-identical in both arms.
`RIPWIRE_SWEEP` / `sweep=` still resolve, and still gate the sweep tier's **counters**; they no longer
gate any delivery, because there is none left to gate.

## The A/B toggle {#the-ab-toggle}

Default behaviour (nothing named in the environment or `meter.conf`) is still **always-on observation
with nudges enabled**, unchanged from before the meter existed. Three literal `arm` values select
something other than that default:

| Arm | Nudge | SessionStart primer | Counted | Row says |
| --- | --- | --- | --- | --- |
| unset (default) / `treatment` | **retired — none** | yes | yes | `arm":"treatment"`, `nudge` one of `retired`/`retired-sweep`/`dedup`/`gated`/`none` |
| `control` | **retired — none** | **no** | yes | `arm":"control"`, and the same `nudge` values: since 2026-09-02 the PreToolUse path is arm-independent |
| `auto` | *depends — see below* | *depends* | yes | `arm` is `treatment` or `control`, decided by a hash of the session id |

`auto` is what makes the arm a real per-session coin flip instead of an all-or-nothing switch: it
resolves to `treatment` or `control` via a stable hash of the session id (`meter_auto_arm` in the
hook), landing roughly half of sessions on each side, with the SAME split recomputed identically on
every PreToolUse call in that session — no marker file needed, because a pure function of an
unchanging input is already "decided once, stable for the session." Set it once, at the config layer
(`arm=auto` in `~/.ripwire/meter.conf`, or `RIPWIRE_METER_ARM=auto`), to turn on a real A/B
population; leave it unset to keep the pre-2026-08-19 always-treatment behavior. Any value other than
`control`/`auto` reads as `treatment` — a typo in `meter.conf` fails toward "still nudges," not toward
"silently starts a coin flip nobody asked for."

**Control-arm rows carry the counterfactual, not just a flat "control" flag (2026-08-19).** A
control-arm call runs through the exact same per-category and per-class bookkeeping a treatment call
does — the same dedup marker, the same sweep counter — so the row can say which of the two things a
treatment session would have done: `nudge":"control"` means the trigger condition was met AND this is
the call that would have fired or escalated; `nudge":"suppressed-control"` means the trigger condition
was met but a treatment session would have been silent too (already delivered for this
category/class, within its cooldown). Before this fix every eligible control-arm call recorded a flat
`"control"`, which threw away exactly the eligibility signal a control arm exists to carry — with it,
"how often would the nudge have had something to say" is measurable on the control side too, not just
inferred from what treatment shows.

**What "no nudge" covers, and two ways it did not (fixed 2026-08-12, before `auto` existed).** The
toggle shipped inert and, being inert, shipped broken in exactly the configuration that will first use
it. Both faults are gated by `test/hookcheck.sh` arms A1–A4, and both still hold under `auto`, since
`auto` resolves to a literal `control`/`treatment` before anything downstream runs:

- **The arm is resolved before the log is.** `meter_init` used to parse `RIPWIRE_METER_ARM` *after*
  the "no log destination, nothing to write" early return, so a control-arm run with no named
  destination — a fixture-guarded harness, and the shape a control session runs in — kept the
  `treatment` default and was nudged anyway. The arm is not a property of the log: it decides whether
  the agent is *spoken to*, so a run with nowhere to write still honours it.
- **The SessionStart primer honours the arm.** That branch injects the whole use-when blurb, by a
  wide margin the largest thing this hook ever says, and it never consulted the arm. A control arm
  that is silent at every PreToolUse moment and is then handed the manual at startup is not a control
  arm; it would have made the first A/B measure the primer and call it the nudge. The session-start
  *row* is still written in both arms — the control arm is counted, only never spoken to.

A control arm that silently does not control is worse than no control arm, because the data it
produces looks valid.

**From 2026-08-11 through 2026-08-19 the arm was 100% `treatment` on every row ever logged (4,209
rows, 21 sessions) — not because of either bug above, but because no code path could ever produce a
MIXED population.** The only way to reach `control` at all was an operator setting it globally, for
the whole machine, by hand; nobody did. `arm=auto` (this fix) is the first mechanism that can actually
populate both arms from ordinary use. A log or a readout written before a deployment turned `auto` on
is describing a **level**, not a **difference** — a single arm's data supports no causal claim about
the nudge, however the log gets sliced.

**Nothing alternates on its own unless `auto` is named.** Assignment under `auto` is per session, by
the hash of its id — deterministic, not re-rolled, and not something a config change mid-session can
retroactively flip for calls already logged.

## Reading the log

```bash
python3 bench/substitution_report.py                        # ~/.ripwire/substitution.jsonl
python3 bench/substitution_report.py /path/to/log.jsonl
python3 bench/substitution_report.py -h                     # repo filter, row limit
```

Scrub first if the log predates 2026-08-12 — it may carry gate fixtures (above), and the report has
no way to tell them from real rows.

Stdlib only, deterministic, counts only. Five sections: the rate split by nudge exposure and by arm;
the class composition of both sides; a per-repo breakdown; **within-session class n-grams** (bigrams
and trigrams in `seq` order); and **terminality by verb** (below). The n-gram section is the one to
watch — the hypothesis worth testing is that the real opportunity is a recurring *chain* (`grep →
read → read`) that a single verb could absorb whole, not any single call. The script prints counts
and no interpretation; which chain is worth absorbing is a judgment made elsewhere.

## Terminality (§5)

An output only saves tokens if it **ends** the question that prompted it. One that spawns the next
command is net-additive: the map is paid for and then the sweep is paid for as well. §4 asks which
chains recur; §5 asks the sharper question underneath it — of the chains that *start* with ripwire,
how many end there. It is the per-verb instrument the enrichment work is ranked by, and it doubles as
a release-over-release ledger for output quality.

### The definition, in full

For every **ripwire-family** row in the log (`ripwire-cli` and `ripwire-mcp`), look ahead inside its
own session, in `seq` order:

| | |
| --- | --- |
| **Window** | The calls after it, up to — whichever comes **first** — the next ripwire call, the end of the session, or **5** calls. |
| **TERMINAL** | No *sweep-class* call appears in that window. |
| **Follow-up** | When it is not terminal, the **first** sweep-class call in the window is recorded as the follow-up class. Three greps in a row contribute one follow-up, not three. |
| **Sweep set** | `grep` `read` `glob` `find` — and `git-diff` `git-log` `git-show-stat`. |
| **Excluded** | `session-start` rows are session boundaries, not calls an agent chose to run, and are dropped before windowing (the same rule §4 uses). |

Two of those lines are choices worth defending rather than defaults.

**The sweep set is wider than the `native` family.** `git diff` / `git log` / `git show` with a stat summary are
history *retrieval*: a map followed by a raw git-history sweep did not terminate the question any
more than a map followed by `grep` did. They stay outside §1's substitution ratio — there they are a
different **question**, not a different tool for the same one — and they count here, where the
question is whether the answer landed. The state-changing git classes (`git-misc`, `git-remote`) are
not retrieval and are in neither.

**An empty window counts as TERMINAL** — the next observed call was another ripwire call, or the
session ended, so no sweep happened. That is the definition applied honestly, and it is also the
definition's softest spot, so the count of empty windows is **printed under the table** instead of
being folded in silently. A run of consecutive ripwire calls manufactures terminal windows; the
disclosure is what lets a reader discount them.

### Which verb a row asked for

An MCP row carries its verb in the tool name (`mcp__ripwire__for` → `mcp:for`). A CLI row carries a
whole command line in `detail`, so the verb is read lexically: find the leading word whose basename
is `ripwire` — it may be `./build/ripwire`, an absolute path, or sit behind `cd X && VAR=y` — then
take the **first flag after it**, stopping at the first pipe, redirect or separator so a pipeline's
own flags are never mistaken for the verb. A run with no flag is the core map, `(map)`.

The 200-character `detail` cap defeats that in three ways, and each is **named rather than guessed
at** — a real log hit two of them on the metric's first reading:

| Cut | Label |
| --- | --- |
| before the ripwire word | `(unparsed)` |
| after it, with no flag and no shell break yet — the verb may be one character past the cap | `(truncated)` |
| in the middle of the flag | that flag with a trailing `...` |

The third case is why the marking exists at all: a half-written flag filed under the prefix that
survived would split one verb's n across two rows and understate both. A *complete* flag that happens
to end a 200-character line cannot be told from a cut one, and is marked the same way — the label
errs toward saying so.

A short list of **verb-agnostic options** (`--no-cache`, `--token-budget`, `--top-k`, `--rank-by`,
`--format`, `--exclude`, …) is skipped while scanning. That list is deliberately *not* a mirror of
the binary's ~70-row dispatch table: a mirror would rot silently, and the cost of being wrong here is
one row attributed to a modifier — which the table then shows by name, under that modifier, rather
than hiding.

### Small n is stated, never smoothed

Every row prints its **n** beside its percentage, and a verb whose n is under **10** gets an explicit
`NOTE: n=… (<10)` row under it. This is not a significance test — there is no test to run on a
non-randomized single-operator log — it is a floor under the reader. A terminality percentage read
without its n and its window rule is a number somebody will quote wrong.

As everywhere else in this document, the mechanism is public and the **levels are not**: concrete
readings are operator telemetry and live in the local ledger, not in the repository.

## Gate

`test/hookcheck.sh` section (11), arms M1–M27b and T1–T11: a row is written at the default global path with the
full field set; the rtk unwrap; the `unclassified` fallback; out-of-scope calls writing no row; the
`nudged`/`dedup`/`post_nudge`/`post_sweep`/`seq` fields; both arms; one global log across two repos;
and — the arm that matters most — an unwritable log costing the hooked command nothing.

Arms **T1–T11** pin §5 against a **synthetic fixture log** whose right answer is known by
construction — a terminal `--for`, a non-terminal one followed by three greps, windows truncated by
the next ripwire call and by session end, the k=5 window edge asserted from *both* sides (five
non-sweep calls put a grep out of the window, four leave it in), a git-history follow-up, an n<10
verb with its NOTE row and an n≥10 verb without one, an MCP row, and a flagless map behind a `cd`
prefix and ahead of a pipeline carrying flags of its own. The assertions are exact table values, not
"it did not crash": every count, percentage and follow-up in the fixture's table is spelled out in
the gate. The gate's own sink cannot serve here — its contents change with every arm anyone adds
above it, so nothing about it is known in advance.

Section (12), arms S1–S14, covers the sweep escalation and the widened classifier: three same-class
calls produce exactly one escalation carrying the paste-ready command; two do not; a fourth is
silent; the classes dedup independently; the row carries `nudge":"sweep3"` and the next row
`post_sweep":1`; `RIPWIRE_SWEEP=0` and the `control` arm never escalate and leave the first two calls
**byte-identical** to a run with the escalation on; a missing `ripwire` or a non-git directory
degrades to silence; and the classifier fixtures pin the `cd`-prefix strip (including
`cd x && VAR=y grep …` and the multi-line form), `build`, `gate-run`, `git-remote`, `git-misc`,
`shell-misc`, and the still-working rtk unwrap.

Section (12b), arms C4–C11 and A1–A4, covers the classifier-gap round and the arm contract. C4 pins
the segment walk against ten compound shapes read off the live log; C5 the newline-as-separator on a
multi-line loop; C6 the one that is easy to get wrong — the walk resumes after the segment the
*prefix strip* handed to the head, not after the first segment, or `cd /w && bash -n f.sh &&
./build/ripwire …` silently stops counting as a ripwire call; C7 the pipeline pair, where `| head`
must not become a native read and `| grep` must keep its evidence; C8 the path-component exclusion
with `xargs /usr/bin/grep` as its counter-case; C9 `script-run`, its family, the un-walked inline
program, and that four script runs are counted yet never nudged; C10 `cat >` as a write and the
heredoc stop; C11 that this document carries the contract. A1–A4 are the arm: silent control with no
named destination, control recorded and treatment still speaking with one, the primer suppressed
under control, and — the positive control without which A3 would pass on a hook that suppressed the
primer unconditionally — the primer still emitted under treatment.

The retired fixture in arm M16 is part of the same round and is worth knowing about: it used to be
`for f in *.c; do grep needle $f; done`, which the walk now reads correctly. Its replacement puts the
retrieval inside a command substitution — a place the walk deliberately does not go — so the arm
still gates what it was written to gate.

Section (13), arms I1–I6, is the fixture-isolation contract: the rows sections (1)–(10) used to leak
now land in the gate's own sink rather than being dropped (the positive control, without which the
canary could pass for the wrong reason); `RIPWIRE_METER_FIXTURE` with no named destination writes no
row while the nudge still fires; the production `$HOME` fallback still resolves, in the one arm that
deliberately runs without the guard; `bench/substitution_scrub.py` empties a gate-written log,
refuses to overwrite its input and leaves it byte-identical; and the canary — no row in the
operator's real log carries this run's scratch path.
