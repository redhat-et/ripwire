# changelog.d — one file per change

Every user-visible change adds ONE new file here instead of editing `CHANGELOG.md`, so two open pull
requests never touch the same lines. Name it after the pull request (`431-short-slug.md`) or, before
there is one, a short slug (`short-slug.md`): lower case, digits, `.`, `_`, `-`, ending `.md`.

The file is the entry exactly as it will read in the release section:

```markdown
### Fixed — `--uses` stops listing built-in calls on a literal receiver (#411, thanks @handle)

What changed, for whom, the measurement and its method, and what it does NOT mean.
```

- Line 1 is `### <Section> — <title>`; the section is one of Added, Changed, Deprecated, Removed, Fixed,
  Security, Documented. Line 2 is blank; a non-empty body follows. One `### ` heading per file.
- Credit a contributor as `(thanks @handle, #N)` or `(#N, thanks @handle)`; a fragment that credits
  someone names the pull request.
- `versions.md` is the one shared fragment: the "versions this release moves, stated once" paragraph
  (`kParserVer`, cache and snapshot schemes, the legend dictionary). It always assembles last.

`python3 scripts/changelog_assemble.py check` validates this directory (`test/changelogfragcheck.sh`
runs it); `… print` shows the assembled section. At release, `… release X.Y.Z YYYY-MM-DD` folds every
fragment, in file-name order, under the new version's heading in `CHANGELOG.md` and deletes them.
