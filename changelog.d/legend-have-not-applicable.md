### Fixed — `--legend-have=` on a non-XML answer says `not-applicable` instead of nothing

`--legend-have=` on `--situ`, `--recall`, `--report`, `--mermaid`, `--html`, `--plan-lanes`, `--sarif` and the evaluation surfaces now prints one stderr line, `ripwire: --legend-have=: not-applicable — <surface> answers with no XML legend the legend dictionary reduces, so it is served whole; nothing was saved`, as `--for` already did, instead of saying nothing. Stdout and the exit code are unchanged, and a stale value is still refused first. Lane S1 (`35b71f385`); `test/legendhavecheck.sh` arm (S).
