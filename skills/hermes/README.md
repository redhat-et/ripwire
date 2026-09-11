# Hermes skills

Hermes-format counterpart to the `ripwire-*` skill family. Kept in its own namespace (not
`skills/ripwire-*`) so `skills/install.sh` — which symlinks every `ripwire-*` directory into
Claude Code / Codex skill roots — never installs it into those agents.

Install into a Hermes profile:

```bash
cp -r skills/hermes/ripwire-repo-map ~/.hermes/skills/software-development/
```

Requires the `ripwire` binary on PATH (upstream release tarball, see repo README).
