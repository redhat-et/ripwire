### Documented — the contributor prompts match `main` again, eight kits are marked solved, and a kit for the slice issues

Every prompt under `prompts/` and `prompts/help-wanted/` was checked against the 0.7.0-dev binary
(`--help=all`), the tree and the issue tracker on 2026-11-26.

- **Eight help-wanted kits are marked solved**, each with a note at its top naming the pull request, the
  gate that proves it and any part still open. Thank you to the contributors who landed them:
  @lennix1337 (the `--doctor` layout row, #224, and the `--uses` twin of the literal-receiver fix, #411),
  @aniruddhaadak80 (`--uses` on a `::` selector, #231), @csy20 (TS/JS literal receivers, #244),
  @llvm-x86 (Kotlin scope functions, #438, and Django and unittest hooks kept out of dead code, #437) and
  @qinghuanandejiangshi (inherited Python hooks, #237). Maintainer trains landed the nested `std::`,
  nesting-refusal and TS alias/workspace kits (#331, #336, #340). Two solved kits keep a named remainder:
  ObjC++ in the nested-`std::` kit, and sparse checkouts in the unchanged-tree kit.
- **The open kits were brought up to date.** The language kits now point at the data-first layout
  (`queries/<lang>/tags.scm`, the `kLangFacts` row). Stale "PR #N is open" status lines are now true, and
  helpers that had been renamed are corrected. Each open kit now has a step that orients with
  `ripwire --for` or `--pack-task` before reading files, plus a "Done means" line naming its gate. The
  Visual Basic kit lost 52 lines of duplicated history.
- **New kit: `prompts/help-wanted/ready-to-claim-slice.md`.** It is the workflow for the 13 open,
  fully specified slice issues that had no kit (#487, #488, #552, #550, #551, #490, #489, #546, #547, #543,
  #544, #672, #726): claim the issue, reproduce it red, change shared code by data, and prove byte-identity
  with `test/langidentitycheck.sh`.
- `prompts/help-wanted/README.md` links each open kit to its issue and lists the solved kits with credit.

No binary behavior changed.
