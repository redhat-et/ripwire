### Changed — the cross-branch verbs answer in repositories with more than 512 local branches

`--whereis`, `--stray-content` (with `--plan` and `--abi`), `--eval-stray` and the MCP `whereis` and `stray_content` tools used
to refuse when a repository had more than 512 local branches, which a long-lived clone with many lane branches does. They now
read the newest 512 branches by committer date and print `refs_omitted=K` on the answer's root for the K older ones they did not
read. `--whereis` drops `complete="1"` whenever refs were left out, and `--eval-stray` reads every labelled branch first, so a
labelled branch is scored, not left out. A ref-name substring (`--stray-content=SUBSTR`, or `kind=` over MCP) chooses which
branches fill the 512.

The window stays at 512 because both sweeps cost about the same per branch at any count. `--stray-content` runs about two git
processes per branch: 77 s at 511 branches and 278 s at 2,048 on an M2, with peak memory flat at 13-19 MB. `--whereis` holds
every branch's tree listing at once: 849 MB at 8,192 branches of a 200-file tree, and 0.7-1.0 GB at 524 branches of a 5,239-file
tree. With the window, `--whereis` over 8,192 branches peaks at 69 MB. Below 512 branches nothing changes.
