### Changed — the Codex SessionStart primer no longer repeats a block already in AGENTS.md

The Claude Code primer stopped repeating a CLAUDE.md block earlier in this release (#744); the Codex primer (`skills/install.sh
--codex --hook`) still sent `ripwire wrap codex`'s block a second time when that block was already pasted into an AGENTS.md
Codex loads. It now stays silent when the global AGENTS.md (or AGENTS.override.md) in `${CODEX_HOME:-~/.codex}`, or the
file Codex takes in each directory from the Git root down to the working directory, holds the block word for word. The
match follows Codex's documented discovery conservatively: an AGENTS.override.md beside a file wins over it, a file above
the Git root does not count, nor does one that ends past the 32 KiB `project_doc_max_bytes` default (the global file
counted), and a `config.toml` naming `project_doc_max_bytes`, `project_doc_fallback_filenames` or `project_root_markers`
keeps the primer. A block that is absent, older or edited still gets the current one, unchanged from before.
`test/hookcheck.sh` (3i7) holds each case.
