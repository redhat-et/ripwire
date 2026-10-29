### Security — `skills/install.sh` takes the installer hardening list from #293 (hardening from #293 by @s0undt3ch)

@s0undt3ch's #293 proposed moving skill and hook installation into the binary. We kept the installer a script, but
its four review rounds produced a list of ways an installer can be talked into writing or deleting the wrong thing,
and every item that applies to a shell installer now lives in `skills/install.sh` (#293, thanks @s0undt3ch):

- **Absolute roots only.** A relative or empty `HOME`, `CLAUDE_CONFIG_DIR`, `AGENTS_HOME`, `CODEX_HOME` or
  `HERMES_HOME` is refused with status 2 instead of installing relative to the current directory (an empty `HOME`
  used to mean `/.claude`). Windows drive paths still count as absolute; an explicit destination argument still
  resolves against the current directory.
- **Nothing it creates is group- or world-writable.** The umask is only tightened, so `umask 000` no longer yields a
  0777 skills directory or a 0666 `settings.json`, and a stricter `umask 077` is left alone.
- **`settings.json` / `hooks.json` are merged safely.** A symlinked file (a dotfiles setup) is written through and the
  link kept, the temp file is built beside the target so the final rename is atomic, and the file's mode survives the
  merge (CWE-732).
- **The hook command is quoted** when its path needs it, so a checkout under a path with a space registers a hook
  that runs; the ordinary path is registered byte-for-byte as before, and re-runs still recognise the entry.
- **`jq` is found only through absolute `PATH` entries** (CWE-426): an empty or relative entry no longer runs a
  `jq` planted in the current directory.
- **No stray temp files.** The installer's temp files are removed on any exit, including a killed run.
- **The prune removes only what is provably ripwire's:** a symlink the previous manifest recorded, a dangling one, or
  one pointing into this checkout (compared by whole path components, never a string prefix). A live symlink of your
  own that happens to be named `ripwire-*`, and a regular file with such a name, are kept and reported.

The items that apply only to the embedded store (byte-comparing it against the binary, `lstat` of its key and
intermediate directories) have no counterpart here: this installer links straight to the checkout. Windows behaviour is
unchanged. Gate: `test/skillinstallcheck.sh` sections (J)-(Q), each red against the previous script.
