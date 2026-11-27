# Skills that ship inside the binary: `ripwire skills install`, for mise, aqua and every other channel

You are making a ripwire binary carry its own agent skills. A deterministic CMake step embeds them at
build time, and a new `ripwire skills install` subcommand writes them into an agent's skill directory.
After this, `ripwire wrap <agent>` gives a runnable skills command however ripwire was installed: the
curl installer, mise or aqua through the aqua registry, a distro package, or a release tarball unpacked
by hand. The skills an agent gets are then always the ones built with the binary that installed them.

The report is [#225](https://github.com/redhat-et/ripwire/issues/225), by @s0undt3ch. It proposed two
directions. **The maintainers chose direction (1)** in
[this comment](https://github.com/redhat-et/ripwire/issues/225#issuecomment-5700517946): embed the
skills (and consider the hooks) in the binary, and add `ripwire skills install`. This kit takes that
decision as given. It gives you the code, a reproduction of today's gap, the design questions the
plan must still answer, and slices small enough to land one at a time. Claim the issue before you
start.

> **Status (2026-11-26): the direction is unsettled. Ask on #225 before you plan.** The record
> disagrees with itself:
>
> - 2026-09-16: direction (1) agreed on #225, and @s0undt3ch's spec v2 accepted.
> - 2026-09-19: PR #293 (embedded skills plus `ripwire skills install`) opened.
> - 2026-10-07: on #293, the maintainers decided **not** to embed skills and hooks in the binary,
>   because per-client install layouts change too often to track inside a release. A Packslip
>   manifest, published from the release job, was to carry the skills for `mise` users instead;
>   hooks and agent config stay with `skills/install.sh`. Nothing in the tree mentions Packslip yet.
> - 2026-10-31: #293 closed. Its installer hardening landed in `skills/install.sh` through #482.
> - 2026-11-01 and 2026-11-22: the #225 issue-body notes and a check-in still describe direction (1)
>   and spec v2.
>
> `main` at `09995f4b` has no `skills install` subcommand. Symptoms 1 and 2 below were re-checked
> there on an archive-shaped fixture (the clone-pointer line, and the Codex absolute `command =`);
> re-check 3 and 4 in your S0 arms. Whichever direction stands, S0 (red arms on fixtures), S4 (doctor honesty about
> launchers) and S5 (paths that survive an upgrade, including the Codex `command =`) are needed;
> S1 to S3 exist only under direction (1). The cache-directory issue, #303, is separate and has its
> own open PR (#532, `RIPWIRE_CACHE_DIR`); do not touch the cache directory here.

Work in a git worktree, not the main checkout. Never edit the tree while a build is running. Do not
install mise or aqua to do this work: the reproduction below builds fake layouts with a copy of your
own binary.

---

## Why it matters

The aqua registry now carries ripwire (`pkgs/redhat-et/ripwire/registry.yaml`), and mise installs
through it. A user of either sees four things go wrong, and no error is shown for any of them:

1. **`wrap claude` never wires the skills.** The recipe prints
   `# skills not found locally — clone https://github.com/redhat-et/ripwire and run skills/install.sh`,
   although the release archive put `skills/install.sh` right next to the binary.
2. **`wrap codex` writes a path that expires.** The Codex stanza's `command =` is the binary's resolved
   path, and under a package manager that path contains the version. Before the old version is removed,
   Codex keeps running the old binary. After it is removed, the server does not start.
3. **`--doctor` reports a healthy install as broken.** Its `binary-path` row compares the `ripwire` on
   PATH (a shim, or a link to a proxy) with the running binary. The bytes differ, so the row says
   `ok="0"` with a STALE hint telling the user to reinstall. `--doctor --agent=claude` and
   `--agent=codex` do the same in their binary rows.
4. **The doctor's skills hint names a command a package-manager user cannot run:**
   `run bash skills/install.sh --claude`.

@s0undt3ch's second point is why the direction is (1): once the skills live outside the curl
installer's own directory, nothing keeps them in step with `ripwire --version`. Skills compiled into
the binary cannot drift from it, and every install channel gets the same command. It also follows the
project's rule that a new surface lives in the one executable.

---

## Background: what exists, with file pointers

| File | What it tells you |
| --- | --- |
| `CMakeLists.txt`, "configure-time query embedding" | **The precedent to copy.** `queries/<language>/tags.scm` stays the editable source; CMake writes `generated/embedded_queries.h` with `file( WRITE … )`/`file( APPEND … )`, and adds each source to `CMAKE_CONFIGURE_DEPENDS` so an edit re-runs the step. No script, no host tool |
| `test/selfcontainedcheck.sh` | The gate for that header: it compiles a probe against the generated interface and compares every embedded byte with the tree. Your skills header needs the same kind of arm |
| `test/ripwirepubliccheck.sh`, the `generated = {…}` set | Generated headers are named there, not pattern-matched. A new generated header is one more name |
| `skills/` | One `ripwire-*` directory per skill. Some carry reference files beside `SKILL.md` (for example `ripwire-orient/`, `ripwire-quality-bar/`, `ripwire-mcp/`), so **a skill is a directory, not one file**. Also `skills/hermes/`, `skills/CONSOLIDATION.md` and `skills/install.sh`. About 384 KB in total |
| `skills/install.sh` | Today's installer. Per agent it resolves a destination (`CLAUDE_CONFIG_DIR`, `AGENTS_HOME`, `CODEX_HOME`, `HERMES_HOME`, or an explicit path), prunes `ripwire-*` entries it no longer ships, **symlinks** each wanted directory from its own location, and writes `.ripwire-manifest-v1`. A skill whose front matter says `audience: contributor` is linked only with `--contributor`. `--hook` registers hooks by absolute path and recognises an existing entry by its **script name**, so a re-run repairs a moved install |
| `hooks/` | Five shell scripts: `ripwire-nudge.sh`, the Claude route and tool-route scripts, and the Codex nudge and route scripts. Settings files point at them **by path** |
| `src/wrap.h`, `wrapPrintSkillsLine` | The skills line: (a) `./skills/install.sh` relative to the working directory (a checkout); (b) `<exeDir>/../share/ripwire/skills/install.sh` (the curl installer's staged copy); (c) otherwise, the clone-pointer comment. Rows without a `skillsRoot` print nothing |
| `src/wrap.h`, `kAgentTargets` | One row per agent: the skills root (with its env override spelled in), the installer flag (`--codex`, `--hermes`, `--openclaw`), whether a hook slot exists. The subcommand reads its destinations from **this** table; a second list is how agents drift apart |
| `src/wrap.h`, `wrapCommandToken`, and `wrapEmitCliFirst`'s `McpForm::Toml` case | The MCP command token (the bare word `ripwire` when PATH has one, else the absolute path), and Codex's deliberate absolute path, because Codex Desktop may not inherit the shell PATH |
| `src/wrap.h`, header comment | `wrap` is **pure**: it prints, it never writes configuration. `skills install` is the verb that writes |
| `src/main.cpp`, `main` | `wrap` is dispatched as a subcommand by `argv[1] == "wrap"` before `parseArgs`. `skills` would sit beside it |
| `src/verbs_doctor.h`, `selfExecutablePath` | The running binary's own path, **realpath'd**. A shim or symlink resolves to the versioned target, and the unresolved shim path is gone |
| `src/verbs_doctor.h`, `runDoctor` check 1 and `doctorBinaryPathVerdictAttr` | `binary-path`: the `ripwire` that `os::which` finds on PATH against self, by inode, then by content (`doctorCompareFileBytes`). Different bytes fail the row with a STALE hint; an unreadable copy fails it as UNVERIFIED |
| `src/codexdoctor.h`, `binaryCheck`, `resolveExecutable`, `skillsCheck`, `skillManifest`, `claudeInspect` | The `--agent=claude/codex` rows. `skillsCheck` compares `.ripwire-manifest-v1` (skill **names** only) with the live `ripwire-*` directories, and its hint names `bash skills/install.sh` |
| `src/pathguard.h` | The house predicate and reasoning for never writing through a symlink at a destination |
| `scripts/install.sh` | The curl installer. It stages `$prefix/share/ripwire/{skills,hooks}` with `rm -rf` and `cp -R` on every install, so that directory is stable across versions |
| `.github/workflows/release.yml`, the Package step | The archive: `ripwire-<version>-<os>-<arch>/` holding `ripwire`, `README.md`, `LICENSE`, `skills/` and `hooks/`, **side by side** |
| `test/wrapverbscheck.sh`, section 7 | The gate for the skills line: fixture layouts built from a **copied** binary, one arm per case, and a byte-determinism arm per case |
| `test/skillinstallcheck.sh`, `test/hookcheck.sh`, `test/hermesinstallcheck.sh` | Installer behaviour: link, prune, manifest, contributor filter, hook registration |
| `test/claudeconfigdircheck.sh` | A **census** gate: every executable site that resolves Claude's config directory must honour `CLAUDE_CONFIG_DIR`. A new C++ destination resolver is one of those sites |
| `test/doctorcheck.sh` (F), (F2); `test/codexdoctorcheck.sh` | The stale-binary arms (one flipped byte stays `ok="0"`; identical bytes with an older mtime pass) and the agent rows |
| `test/releaseinstallcheck.sh` | Pins the archive and curl-installer contract |
| **Parsers of the skills line** | `scripts/verify-agent-integration.sh` phase 1, `test/hermesinstallcheck.sh` (wrap arm), `test/skillinstallcheck.sh` arm 6, `test/wrapverbscheck.sh` section 7. They read `^bash skills/install\.sh`, the flag after `install.sh`, and `# deploy to <dir> (drift-gated)` |
| `INSTALL.md` | Documents the curl installer and the source build, and nothing about package-manager installs |

**How the shims work, per each tool's own documentation.** A mise shim is a symlink to the `mise`
binary; it picks the version from the config for the **current directory**. aqua puts symlinks to
`aqua-proxy` in `$AQUA_ROOT_DIR/bin`; the proxy runs `aqua exec`, which reads `aqua.yaml` from the
current directory upward and can **install a package on first use**. Both then run the real binary, so
`selfExecutablePath` sees the versioned target. mise can also put the install directory itself on PATH
(`mise activate`), with no shim. Confirm on your own machine how your tool behaves, and record it.

---

## Orient with ripwire first

Before you open files, run `./build/ripwire . --for="wrapPrintSkillsLine skills install discovery
doctor binary-path launcher"` and read what it ranks first; `./build/ripwire . --uses=kAgentTargets`
lists every reader of the agent table, and `--callers=selfExecutablePath` the code that trusts the
binary's own location. Before you write a new helper or gate arm, run
`./build/ripwire . --exemplar="<what you are writing>"`. Before you call it done, run
`./build/ripwire . --quality-delta --legend=compact`, then `./build/ripwire . --test-gate`.

---

## Reproduce the gap

No mise or aqua is needed. Build three layouts from a copy of your plain dev build, and run `wrap` and
`--doctor` through each one. **Copy the binary, don't symlink it.** The binary realpaths itself, so a
symlink to `build/ripwire` resolves back into your build tree (section 7's own note). The shim scripts
below stand in for mise's shim and `aqua-proxy`. They are different files from the real ones, but they
exercise the same code paths.

```bash
B="$PWD/build/ripwire"; F="$( mktemp -d )"; F="$( cd "$F" && pwd -P )"; mkdir -p "$F/cwd" "$F/home" "$F/cache"
A=ripwire-0.0.0-macos-arm64                      # the archive's top directory name; the value does not matter
# curl-installer layout (the control): <prefix>/bin + <prefix>/share/ripwire/skills
mkdir -p "$F/curl/bin" "$F/curl/share/ripwire/skills"; cp "$B" "$F/curl/bin/ripwire"; : >"$F/curl/share/ripwire/skills/install.sh"
# aqua-like: archive unpacked under pkgs/, bin/ripwire -> a proxy that execs the real binary
P="$F/aqua/pkgs/github_release/github.com/redhat-et/ripwire/v0.0.0/$A.tar.gz/$A"
mkdir -p "$P/skills" "$P/hooks" "$F/aqua/bin"; cp "$B" "$P/ripwire"; : >"$P/skills/install.sh"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$P/ripwire" >"$F/aqua/bin/aqua-proxy"; chmod +x "$F/aqua/bin/aqua-proxy"
ln -s aqua-proxy "$F/aqua/bin/ripwire"
# mise-like: installs/<tool>/<version>/…, shims/ripwire execs the real binary
M="$F/mise/installs/ripwire/0.0.0/$A"
mkdir -p "$M/skills" "$M/hooks" "$F/mise/shims"; cp "$B" "$M/ripwire"; : >"$M/skills/install.sh"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$M/ripwire" >"$F/mise/shims/ripwire"; chmod +x "$F/mise/shims/ripwire"

for D in "$F/curl/bin" "$F/aqua/bin" "$F/mise/shims"; do
  echo "== $D"
  ( cd "$F/cwd" && PATH="$D:/usr/bin:/bin" ripwire wrap claude | grep -E 'install\.sh|skills not found|mcp add' )
  ( cd "$F/cwd" && PATH="$D:/usr/bin:/bin" ripwire wrap codex  | grep -E '^command = ' )
  ( cd "$F/cwd" && HOME="$F/home" TMPDIR="$F/cache" PATH="$D:/usr/bin:/bin" ripwire . --doctor --agent=claude --no-cache \
      | grep -oE '<c n="(binary-path|claude-binary|claude-skills)"[^>]*>' )
done
```

What a build of `main` prints. The capture used a 0.6.1 build whose `src/wrap.h`, `src/verbs_doctor.h`
and `src/codexdoctor.h` are identical to `main` at `f8e6087c`. Paths are shortened. Re-capture from
your own binary, and do not trust this table over it.

| Layout | Skills line | `wrap codex` `command =` | `binary-path` | `claude-binary` |
| --- | --- | --- | --- | --- |
| curl | `bash "<prefix>/share/ripwire/skills/install.sh"   # deploy to …` | `<prefix>/bin/ripwire` | `ok="1" same_file="1"` | `ok="1"` |
| aqua-like | `# skills not found locally — clone … and run skills/install.sh` | `…/pkgs/…/v0.0.0/<archive>.tar.gz/<archive>/ripwire` | `ok="0" same_bytes="0"`, `hint="STALE: …/aqua/bin/ripwire is older than …"` | `ok="0"`, reinstall hint |
| mise-like | the same clone pointer | `…/installs/ripwire/0.0.0/<archive>/ripwire` | `ok="0"`, STALE hint naming the shim | `ok="0"`, reinstall hint |

On both package-manager layouts, `claude mcp add ripwire -- ripwire --mcp` keeps the bare word, because
a shim is on PATH. Run the unpacked binary by absolute path with nothing on PATH, and `claude mcp add`
writes the versioned path too. In this capture the shim and the binary had **equal** mtimes, and the
STALE hint still called the shim "older".

**If you use mise or aqua yourself**, record the real thing next to the fixture: where the binary
landed, what `wrap` and `--doctor` print, and what happens to an installed skill and a written Codex
command after an upgrade and after the old version is removed. Running `mise which ripwire` or
`aqua which ripwire` **by hand** is fine for this. ripwire's own code must never do it (see
Constraints).

---

## The questions your plan must answer

The direction is settled. These are the decisions inside it.

1. **What is embedded, and how.**
   - Every file of each shipped `ripwire-*` directory, not only `SKILL.md`: the reference files travel
     with their skill. Say whether `skills/hermes/` is embedded, and whether `skills/CONSOLIDATION.md`
     (maintainer notes) is excluded.
   - The generated header: one CMake step next to the query embedding, reading only the tree, with no
     network and no host tool beyond CMake and the compiler (no Python, `xxd` or shell in the step). Its
     bytes must be identical across machines, checkouts and configure runs: a sorted file list, no
     timestamps, no absolute paths.
   - Every embedded file is in `CMAKE_CONFIGURE_DEPENDS`, so an edited `SKILL.md` re-runs the step.
   - How a skill's text survives as a C++ literal: raw-string delimiter collisions, bytes that are not
     UTF-8, and any compiler limit on literal length.
2. **Hooks.** Decide whether `hooks/` is embedded the same way. Settings files reference a hook by
   **absolute path**, so an embedded hook has to be written somewhere first. Which directory, why it
   survives an upgrade, and what the subcommand's `--hook` does to an entry an older `install.sh`
   registered (today entries are recognised by script name). If hooks are not embedded, say exactly
   how `wrap` and `skills install --hook` find them without looking for a sibling directory.
3. **The subcommand's surface.**
   - Flags that keep today's installer vocabulary: `--codex`, `--codex-legacy`, `--hermes`,
     `--openclaw`, `--contributor`, `--hook`, an explicit destination.
   - Destinations come from `kAgentTargets` and honour the same env overrides (`CLAUDE_CONFIG_DIR`,
     `AGENTS_HOME`, `CODEX_HOME`, `HERMES_HOME`). `claudeconfigdircheck` will hold a new C++ resolver
     to that.
   - It **copies** (a binary has no directory to link to), prunes `ripwire-*` entries it no longer
     ships, applies the `audience: contributor` filter, and writes `.ripwire-manifest-v1`.
   - What it does with a destination entry that is a **symlink** left by an older `install.sh`: remove
     the link itself and write, or refuse and say how to fix it. Never write through it.
   - Idempotence, what it prints, exit codes, a dry-run or print-only form, `--help`, and
     `docs/COMMANDS.md`.
4. **`skills/install.sh` becomes a thin wrapper** that calls the binary, so there is one install path to
   maintain. Which binary it calls and how it finds it: the build next to a checkout, or the prefix's
   `bin/`, never whatever a shim on PATH selects for the current directory. What happens to the curl
   installer's staged `share/ripwire/skills` directory, and to `scripts/install.sh`'s own call.
5. **The skills line `wrap` prints.** Either keep its shape, so the four parsers above keep reading it,
   or change it and update all four in the same PR. A new spelling that none of them recognises can pass
   as "no skills line" instead of failing. If the line now names `ripwire skills install`, say how its
   command token is chosen (the `wrapCommandToken` rules) and what an agent gets on each layout.
6. **Paths that survive an upgrade.** What gets written into agent configuration: the Codex `command =`,
   the `mcp add` lines, and hook commands. A resolved, versioned path works today, keeps running the old
   binary after an upgrade, and fails once the old version is removed. A shim path survives upgrades,
   but only while the shim manager can resolve a version from the directory the agent starts the server
   in. `selfExecutablePath` realpaths the shim away, while a PATH walk (the one `wrapCommandToken`
   already does) still sees it. Say which you write, per agent, and how the recipe discloses the choice.
7. **`--doctor` reports provenance.** Where the installed skills came from (embedded by a named
   version, linked from a checkout, linked from a prefix share, unknown), and whether they match the
   running binary's embedded copy. The manifest today records names only; say what it gains (a version,
   a content hash) and how an older manifest still reads. Separately: how `binary-path` tells a launcher
   (a shim or proxy) from a stale copy **without running it**. A stale copy is still a ripwire binary; a
   launcher is not. Row (F) must stay red for a one-byte-flipped copy.
8. **The `skills` word.** Today `ripwire skills` maps a directory named `skills`, and this repository has
   one. `wrap` already shadows a directory named `wrap` the same way. Say how the dispatch recognises the
   subcommand (for example, only `skills` followed by a known action), how `ripwire ./skills` keeps
   mapping the directory, and how the shadowing is documented.

---

## Slices: each lands on its own, gate first

**S0. Red arms only, no C++.** Write the arms your plan promises and observe them RED on a `main`
binary:
- a `skills install` arm set against a temporary `HOME` and each env override (copies land, prune,
  manifest, contributor filter, idempotence, an existing symlink at the destination);
- section 7 of `test/wrapverbscheck.sh` with the aqua-like and mise-like fixtures above, expecting the
  new line;
- doctor arms: provenance reported, a launcher on PATH not called STALE, while (F) and (F2) stay as they
  are.

**S1. The embedding step.** The generated header, plus a gate in the `selfcontainedcheck` style that
compares every embedded byte with `skills/`, and a determinism arm: two configure runs in two build
directories produce identical headers. Nothing user-visible yet, or a read-only listing if your plan
wants one to test through.

**S2. `ripwire skills install`** for Claude and Codex first, then the other agents, with the S0 arms
flipping green. `wrap`'s skills line and its four parsers change here, together, if they change at all.

**S3. Hooks and the thin wrapper.** Hooks per question 2. `skills/install.sh` delegates to the binary,
and `test/skillinstallcheck.sh`, `test/hookcheck.sh` and `test/hermesinstallcheck.sh` stay green through
the wrapper.

**S4. Doctor honesty.** The provenance attribute, launchers reported as unverified rather than STALE, and
a skills hint that names `ripwire skills install` instead of `bash skills/install.sh`. The legend in
`doctorLegendComment` explains every new attribute. If the "older" wording for equal mtimes has not been
fixed separately by then, fix it here.

**S5. Upgrade survival.** A two-version fixture (`…/0.0.1/…` and `…/0.0.2/…`): skills installed by the
old binary, `--doctor --agent` run from the new one, then the old directory deleted. The arms assert what
your answer to question 6 promises for the Codex command, the `mcp add` lines, the skills and the hooks.
Add a short `INSTALL.md` section for package-manager installs that says only what the gates prove.

**Optional stopgap, only if a maintainer asks for one.** Before S2 lands, `wrapPrintSkillsLine` could
recognise the release archive's own layout (`skills/install.sh` beside the binary, which aqua keeps
because it unpacks the whole archive) and print a runnable command. It is small, but it becomes dead code
once the embedded path lands, so do not start it without agreement. If it is taken: read files only,
never execute them; require evidence that the sibling `skills/` is ripwire's (its `ripwire-*`
directories); keep the line's shape; and assert the probe order against cases (a) and (b).

---

## Constraints: the non-negotiables

- **Discovery never executes anything.** That includes a shim, `aqua-proxy`, `mise which`, `aqua which`
  and `<candidate> --version`. mise and aqua choose a version from config in the current directory and
  its parents, and aqua may install on first use. Running a shim inside a repository lets that repository
  decide what answers, and it can start a download.
- **Nothing is decided by the working directory or by a PATH entry a repository controls.** That covers a
  relative entry, `.`, and an empty entry, which POSIX reads as the current directory. `wrapCommandToken`
  skips empty entries. The last-resort PATH search in `selfExecutablePath` and `resolveExecutable` in
  `src/codexdoctor.h` treat an empty entry as `.`, so do not build on them. Derive paths from the running
  binary's own resolved location, from `kAgentTargets` and its env overrides, or from an explicit flag.
- **A deterministic build step.** No network, no host tools beyond the build, identical bytes on every
  machine (guardrail G3). The embedded skills are data compiled in, never files shipped beside the
  binary.
- **Writing into an agent's skill directory.** Never write through a symlink at the destination, and do
  not resolve a destination link and then write to its target; that is the outcome to prevent.
  `src/pathguard.h` holds the house predicate. Keep the `ripwire-*` name scope: an entry under any other
  name can replace a user's own skill (see the comment on the Hermes loop in `skills/install.sh`). Write
  each file atomically, the way the installer writes its manifest.
- **A path printed for a shell to paste.** The skills line wraps paths in double quotes, which does not
  stop `$` or a backtick from expanding. Escape such a path or refuse to print it;
  `test/hermesinstallcheck.sh` already fails when an advertised path carries shell metacharacters.
- **`wrap` stays pure.** It prints and never writes. Installing is `skills install`.
- **Determinism.** `wrap` output and the `skills install` report are byte-identical per case. Nothing
  depends on directory iteration order or timestamps. `--doctor` is exempt from byte-identity, but it
  names its live fields in `volatile=`.
- **Honesty in output.** "Not found" is never "does not exist". A doctor check that compared zero skills
  has verified nothing and must say so. `DISCLOSE` compiles out in Release, so a user-visible
  degrade is disclosed in the output, not only by an alert.
- **Gate before code**, observed RED (`CONTRIBUTING.md` §2). A control mutates real input and re-runs the
  identical command; prove the mutation took before trusting the result.
- **No network, no host tools in gates.** Fixtures are directories and copied binaries. No gate may need
  mise, aqua or a network.
- **House style** (`CONTRIBUTING.md` §3): Allman braces, braces on every body, spaces inside parens,
  output through `rw::emitTo`, no `std::map` or `std::unordered_map`. Build paths with
  `std::filesystem`, never by string concatenation. After a branch switch that touches headers, rebuild
  with `cmake --build build --clean-first -j`.

---

## Related work: shared code, conflicts, sequencing

- **#230, exposing only `ripwire-router` and loading the other skills progressively.** This changes
  **which** skills an agent sees; #225 is about **how** they reach it. Not a duplicate, but they meet in
  `skills install`: router-only exposure would be one of its modes. Do not let the embedded format
  freeze today's flat list of skills. #49, now closed, is the context-budget background for both.
- **#44 (the native Windows port, merged) and `src/infra/os.h` (on `main`).** `selfExecutablePath`'s
  platform switch is `rw::os::exepath` now, and `test/osswitchcheck.sh` refuses OS tests and raw POSIX
  calls outside that header. Any system call you add goes through `rw::os::`, and environment reads
  use its helpers (`HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `CODEX_HOME`, `CLAUDE_CONFIG_DIR` are listed
  in its header comment), never raw `getenv`. Take the binary's location from the `executablePath`
  that `runWrap` already receives, not from a new platform call. Windows destinations are out of
  scope, but do not make them harder.
- **#146, #68 and #69: live verification of the published wiring** on Cursor, Windsurf, Gemini CLI,
  opencode and aider (#146), openclaw (#68) and Hermes (#69). `scripts/verify-agent-integration.sh`
  parses the skills line, so a new line **shape** breaks it; in the worst case its flag extraction comes
  back empty and reads as "no skills line". #146's claim P, that a desktop app may not inherit the shell
  PATH, is evidence for question 6. #68 has a claimant mid-run, so change the line shape only in the PR
  that updates every parser. None of the three is a duplicate.
- **#224** (the doctor's layout row) and **#233** have merged, so `src/verbs_doctor.h` and
  `test/doctorcheck.sh`'s named row set already include them; read the current row list before adding
  one.

---

## Acceptance criteria

1. A reproduction for each layout, on fixtures, plus a real mise or aqua run if you have one, with
   versions and paths redacted.
2. Every new arm observed RED on a `main` binary before your change, and green after. Section 7's
   existing cases (a), (b) and (c) keep their bytes unless the PR that changes them updates all four
   parsers.
3. The generated header is byte-identical across two build directories, and a gate proves every embedded
   byte equals its file in `skills/` (and `hooks/`, if embedded).
4. `ripwire skills install` passes the installer arms that `skills/install.sh` passes today (destinations
   and overrides, prune, manifest, contributor filter), plus the symlink-at-destination arm.
5. The answers to the eight questions are written down in the PR, and each one the change implements has
   a gate arm.
6. `--doctor` states where the installed skills came from and whether they match the running binary, and
   no longer calls a launcher STALE. Row (F) still fails a genuinely stale copy.
7. `INSTALL.md` says what package-manager users run and what they must re-run after an upgrade, and
   nothing the gates do not prove.
8. **Done means** gates green in the foreground: `test/wrapverbscheck.sh`, `test/skillinstallcheck.sh`,
   `test/hookcheck.sh`, `test/hermesinstallcheck.sh`, `test/claudeconfigdircheck.sh`,
   `test/doctorcheck.sh`, `test/codexdoctorcheck.sh`, `test/selfcontainedcheck.sh`,
   `test/releaseinstallcheck.sh`, `test/legendcoveragecheck.sh` (if a legend changed),
   `test/docscommandscheck.sh` and `test/printffmtparitycheck.sh` (if `--help` changed), `test/deckcheck.sh`
   (it scans `INSTALL.md`), `test/ripwirepubliccheck.sh`, `test/manifestcheck.sh`, `test/gateexitcheck.sh`,
   and `bash -n` on any script you touched. Then `python3 test/pargates.py . ./build/ripwire -j 6`.

---

## Known traps

1. **A symlinked fixture binary resolves back to your build tree.** Copy the binary, then point the shim
   or link at the copy.
2. **`/tmp` is `/private/tmp` on macOS.** Compare against `pwd -P`, the way section 7 uses `REAL_TMP`.
3. **Configure-time generation goes stale silently.** If a skill file is missing from
   `CMAKE_CONFIGURE_DEPENDS`, editing it rebuilds nothing, and the binary keeps the old text while every
   build reports success. Test the dependency: edit a skill, build, and read the new bytes back.
4. **A new skill directory is not an edited file.** Adding `skills/ripwire-new/` changes the file list,
   which a per-file dependency does not notice. Decide how the step sees additions and deletions (a glob
   with `CONFIGURE_DEPENDS`, or a committed list a gate checks) and pin it with an arm.
5. **The skills line has at least four parsers**, listed in the Background table. Change its shape in one
   PR with all of them, or not at all.
6. **Empty equals agreement.** An install that copied zero skills has installed nothing. A doctor check
   that compared zero entries has verified nothing.
7. **The word "ripwire" appears in a shim's own text.** A shim script contains the path it runs, so a
   launcher test that greps for the name will call a shim a ripwire binary.
8. **Your shell's PATH is not the agent's PATH.** A shim directory that works in your terminal may be
   invisible to a desktop app (#146, claim P).
9. **Skill scanners read example text as an attack.** `ripwire-security-scan`'s `SKILL.md` shows sample
   scanner output, and a third-party scanner flags it (runkids/skillshare#279, noted on #225). If
   `skills install` scans what it writes, run it over the embedded set first and decide what a finding
   in ripwire's own skill does.
10. **Do not reshape your environment to make a recipe look right.** Adding a `share/ripwire` symlink by
    hand is the FAIL, not the fix.
11. **A new gate file has more than one registration:** `test/regression.sh`, the count from
    `python3 docs/gatecount_build.py`, a weight in `.github/pargates-shard-weights.json`, and the
    `EXEMPT` table in `test/binoverridecheck.sh` if the gate never runs the binary. Extending existing
    gates avoids all four. Editing any gate file wakes `test/gateexitcheck.sh` and
    `test/manifestcheck.sh`, so run both.
12. **Personal paths.** `test/ripwirepubliccheck.sh` rejects absolute home paths in committed files.
    Redact them in fixtures, captures and the PR text.

---

## Scope

**In:** the embedding step; `ripwire skills install`; hooks per your plan; `skills/install.sh` as a thin
wrapper; the skills line and its parsers; what `wrap` writes as the server command and how it discloses
that; `--doctor` provenance and launcher honesty; the upgrade story; an `INSTALL.md` section; the gates
for all of it.

**Out:**
- **Upstream packaging.** Changing the aqua registry or mise; file upstream and link it if needed.
- **Windows destinations** (#44).
- **Which skills are exposed** (#230), beyond keeping the format open to it.
- **Live agent verification** (#146, #68, #69).
- **Network calls.** No update check and no download, from any verb.
- **Executing a shim**, from any verb.

## Difficulty

**Large.** S0 and S1 are small and make a reasonable first contribution: shell fixtures, one CMake step
and one comparison gate. The finish line crosses `CMakeLists.txt`, `src/main.cpp`, `src/wrap.h`, `src/codexdoctor.h`, `src/verbs_doctor.h`,
`skills/install.sh`, the doctor legend and four parsers of one output line. The hard part is not code;
it is stating honestly what survives an upgrade.

---

## What the PR description should contain

- The layouts reproduced (fixture and real), the tool versions, and the paths redacted.
- The chosen answer to each question, and what it rules out.
- Each arm with its RED run on `main` and its green run after.
- The generated header's size, and the identical-bytes evidence from two build directories.
- `wrap`, `skills install` and `--doctor` output before and after, for the curl, aqua-like and mise-like
  layouts.
- What survives an upgrade and what does not, stated plainly, plus what the user must re-run.
- What you did not cover: Windows, a real shim manager you did not have, any slice deferred.

---

**Write the plan: your answers to the eight questions, the slices in the order you will land them, the
fixture layouts and arms in red-first order, which direction #225 confirmed and on what date, and how
you will sequence around #230. Post it on #225, then STOP for a maintainer's go-ahead.**
