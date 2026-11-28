### Changed — the Codex SessionStart primer no longer repeats a block already in AGENTS.md

The Claude Code primer stopped repeating a CLAUDE.md block earlier in this release (#744); the Codex primer (`skills/install.sh
--codex --hook`) still sent `ripwire wrap codex`'s block a second time when that block was already pasted into an AGENTS.md
Codex loads. It now stays silent when the global AGENTS.md (or an AGENTS.override.md with text in it) in `${CODEX_HOME:-~/.codex}`, or the
file Codex takes in each directory from the Git root down to the working directory, holds the block word for word;
project files count only for a project the user config.toml marks `trust_level = "trusted"` (the working directory's own
entry first, the Git root's only when it has none, as Codex resolves it), since Codex loads none for an untrusted one, and
not at all when another config layer (system, managed, a profile or the project's) mentions project trust, when a
config file holds a TOML multi-line string, or when a trust entry is spelled in a way the hook does not read. The
match follows Codex's documented discovery conservatively: an AGENTS.override.md beside a project file wins over it even when empty, a file above
the Git root does not count, nor does one that ends past the 32 KiB `project_doc_max_bytes` default (the global file
counted), and a `config.toml` (system `/etc/codex`, user, profile or project) naming `project_doc_max_bytes`, `project_doc_fallback_filenames` or `project_root_markers`
keeps the primer. A block that is absent, older or edited still gets the current one, unchanged from before.
`test/hookcheck.sh` (3i7) holds each case.
