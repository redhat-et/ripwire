# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please report it privately to the repository owner via GitHub's security vulnerability reporting feature (available on the repository's Security tab). Please do not open a public issue.

Provide as much detail as you can:

- A description of the vulnerability and its impact
- Steps to reproduce (if applicable)
- Affected version(s)
- Any proposed fix (optional)

## Scope

ripwire is a command-line indexing tool with the following security model:

- **Input:** Arbitrary source code repositories on the local filesystem
- **Output:** XML summaries and analysis results streamed to stdout or written to cache
- **Trust boundary:** The tool operates only on local files with the user's own permissions. It does not communicate over the network, with two named exceptions: a root given as a git URL is cloned into the cache (`git clone --depth=1`, with `protocol.ext.allow=never` and `protocol.file.allow=user` pinned on the command), and the tree-sitter registry is listed during initial setup
- **Subprocesses:** ripwire runs **read-only `git`** inside the analysed checkout (`status --porcelain`, `ls-files`, `log`, `diff --numstat`, `archive`, `rev-parse`), and — only for binary document formats, which are not collected by default — `markitdown`. Git honours the checkout's **own** `.git/config`. A *hook-form* `core.fsmonitor` there is a command git would run on every one of those calls, so ripwire neutralises that one key for its own git children at process start and says so (`--doctor`'s `git-config-trust` row; a stderr line carrying `git_harden=fsmonitor-hook`); boolean values, git's builtin daemon, are left alone. `git clone` never copies `.git/config`, so a repository you cloned yourself carries no such key — a tarball, a copied worktree or a shared checkout carries whatever its last owner wrote. Treat pointing ripwire at one as you would treat running `git status` there yourself

Security vulnerabilities relevant to this tool include:

- Memory safety issues (crashes, leaks, or corruption in the C++ implementation)
- Cache poisoning that could cause incorrect analysis results
- Path traversal or unintended file access
- Denial-of-service on valid inputs

## No Version Promises

This project is pre-1.0 and does not yet provide a compatibility guarantee. Security fixes may be released as patch versions, minor versions, or major versions depending on the nature and severity of the issue. We will update this policy when the project reaches 1.0.

## Safe Practices

When using ripwire:

- Run it only on code you trust (or inspect before analyzing) — including its `.git/config` and hooks when the checkout did not come from your own `git clone`
- Use `--no-cache` or manage your cache directory if analyzing untrusted repositories in sequence
- Keep your source code checkout up to date to receive security fixes
