# clean-env.sh — the ambient environment a gate must not inherit. SOURCED, not run. Source this FIRST,
# then set whatever homes, repos and variables the gate actually needs.
#
# TWO families, found the same way and fixed in the same place.
#
# (1) AGENT HOMES (#298, @s0undt3ch). CODEX_HOME/AGENTS_HOME/HERMES_HOME/CLAUDE_CONFIG_DIR/
#     RIPWIRE_DATA_HOME override the default an agent's tools derive from HOME, so a gate that only sets
#     HOME= per invocation is not sandboxed on a machine where any of these is already exported.
#
# (2) GIT REPOSITORY SELECTION (CodeRabbit on the train-13 branch). `git -C DIR` changes the working
#     DIRECTORY; it does NOT override the ENVIRONMENT, and every variable below outranks it. So a gate
#     that builds a throwaway repo and asks it a question — `git -C "$REPO" rev-parse HEAD`,
#     `git -C "$REPO" log` — gets an answer from SOMEBODY ELSE'S repository when any of these is set, and
#     then passes or fails on data it did not select. `git init` is affected too: with GIT_DIR set it
#     initialises there. The exposure is ordinary, not exotic — a git hook running the suite, a CI job
#     that exported GIT_DIR, `git rebase --exec`, a shell inside `git filter-branch`.
#
#     GIT_PREFIX is in the list for a different reason than the rest: git sets it for its own aliases and
#     subcommands, and a relative path inside a gate then resolves against it.
#
# Both families were first found as partial hand-rolled copies at the call sites — two for the git family
# (dispatchordercheck, pagingsweepcheck), each missing names the other had — which is why the clearing
# lives here and not there. test/gitenvhermeticcheck.sh pins the list and sweeps the tree for a gate that
# builds a repo without sourcing this file.
unset CODEX_HOME AGENTS_HOME HERMES_HOME CLAUDE_CONFIG_DIR RIPWIRE_DATA_HOME
# (3) THE MEMORY GUARD (#350): an exported limit or test trip changes what every gate's ripwire answers.
#     RIPWIRE_MEM_BUDGET_MB is the allocator line's own knob (memceiling.h) and belongs here for a stronger reason
#     than the others: an exported value that is not 0 or a whole MiB count of at least 64 refuses EVERY ordinary
#     invocation at exit 1, so a gate would fail before reaching whatever it meant to assert, and an exported small
#     value would refuse mid-run at exit 5. An arm that wants the line off still sets it per command.
unset RIPWIRE_MAX_MEMORY RIPWIRE_TEST_MEMGUARD RIPWIRE_MEM_BUDGET_MB
# (4) THE RUBY BASE-SCOPE SEAM (#325, resolve.h rubyBaseUnscopedTestSeam): forces every Ruby base onto the byName fallback.
unset RIPWIRE_TEST_RUBY_BASE_UNSCOPED
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX
