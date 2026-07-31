---
name: ctxpack-orient
description: >
  Understand an unfamiliar codebase or subsystem FAST, before editing. Use when you land cold in a repo,
  are asked "how does X work", "where is Y", "what matters here", or need an architecture overview. Runs
  ctxpack (the deterministic "ripgrep of AI context", on PATH) to map the code instead of blind grep +
  whole-file reads. Prefer this over reading many files when orienting.
allowed-tools: Bash, Read
---

# Orient with ctxpack

`ctxpack` is on your PATH. First call on a tree parses (~1s even at 1500 files); every call after is warm
(auto-cached, ~instant). Use `<dir>` = the repo root or the specific subsystem you're working in.

Recipe (run top-down, stop when oriented):

0. **Recall what you already KNOW** — `ctxpack <dir> --recall="<the task>"` — the most relevant docs.
1. **Architecture summary** — `ctxpack <dir> --report` — modules, god-files, cycles, top symbols.
2. **Task-relevant code** — `ctxpack <dir> --for="<the task in your own words>"` — ranked signatures.
3. **File-by-file map** — `ctxpack <dir> --tree` — each file with its top symbols.
4. **Budget it** if the map is large — add `--max-tokens=8000` or `--top-k=50`.

Then read the specific files ctxpack surfaces — don't grep blindly.
