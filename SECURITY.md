# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please report it privately to the repository owner via GitHub's security vulnerability reporting feature (available on the repository's Security tab). Please do not open a public issue.

Provide as much detail as you can:

- A description of the vulnerability and its impact
- Steps to reproduce (if applicable)
- Affected version(s)
- Any proposed fix (optional)

## Scope

ctxpack is a command-line indexing tool with the following security model:

- **Input:** Arbitrary source code repositories on the local filesystem
- **Output:** XML summaries and analysis results streamed to stdout or written to cache
- **Trust boundary:** The tool operates only on local files with the user's own permissions; it does not download code or communicate over the network (except to list grammars from the tree-sitter registry during initial setup)

Security vulnerabilities relevant to this tool include:

- Memory safety issues (crashes, leaks, or corruption in the C++ implementation)
- Cache poisoning that could cause incorrect analysis results
- Path traversal or unintended file access
- Denial-of-service on valid inputs

## No Version Promises

This project is pre-1.0 and does not yet provide a compatibility guarantee. Security fixes may be released as patch versions, minor versions, or major versions depending on the nature and severity of the issue. We will update this policy when the project reaches 1.0.

## Safe Practices

When using ctxpack:

- Run it only on code you trust (or inspect before analyzing)
- Use `--no-cache` or manage your cache directory if analyzing untrusted repositories in sequence
- Keep your source code checkout up to date to receive security fixes
