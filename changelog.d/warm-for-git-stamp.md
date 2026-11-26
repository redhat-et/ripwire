### Changed — a warm `--for` starts one git process instead of seven

A warm `--for` used to ask git seven questions on every call: the dirty-tree check plus six small answers (the HEAD commit,
asked twice, its time, the history window's boundary, the top level and whether the clone is shallow). The six small
answers are now kept in a small record in the cache directory, `ripwire-qstamp-*.bin`, and reused while the files git
reads for them are unchanged. The key is a content digest of HEAD, the branch ref, `packed-refs`, `shallow`, grafts,
alternates, every config file git reports reading, the `.git` file or directory chain, and the environment git depends on.
Any other `GIT_*` setting (inert ones such as `GIT_EDITOR` and `GIT_PAGER` aside), a config `include`, replace refs or the
reftable backend skip the record, and git is asked exactly as before. The dirty-tree check still runs on every call. It
now starts beside the snapshot load instead of after it, but only when every file the run writes is outside the work tree.
The output is byte-identical. Measured on a warm `--for` (Apple M5 Pro, Release build, median of 5): envoy 0.79 s → 0.68 s,
vscode 1.15 s → 1.00 s, llvm-project 5.30 s → 4.82 s. The flagless map is unchanged. `test/c1stampcheck.sh` covers the
process count and each invalidation: a commit, a branch switch, `pack-refs`, a config change, shallow on and off, a
detached HEAD, a worktree, `HOME`, `GIT_DIR` and a damaged record.
