### Fixed — `--quality-delta` default legend now defines `fix=` on a row with no `why=`

A complexity row carrying a repeated-decision facet (`fix="name the decision once: …"` or `fix="name the loop once: …"`)
has no `why=`, and the default (compact) legend defined `fix=` only inside the `why=` reading. A range whose printed
rows carried `fix=` without `why=` (for example one minor complexity row) therefore met an undefined attribute, and
`legendcoveragecheck` arm (G) failed with `quality-delta-refs-default | r@fix`. The compact dictionary now has its own
`r fix=` reading, which steps aside wherever an `r` row carries `why=`, so other answers keep their bytes.
The full legend already carried the QD-REPEATED-DECISION sentence. `repeateddecisioncheck` arm (L2) pins the
default legend on a two-commit range.
