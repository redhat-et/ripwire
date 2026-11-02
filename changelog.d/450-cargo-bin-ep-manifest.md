### Added — `--for` shows a Cargo `[[bin]]` entry and the `main` it names (#450)

- `--for` manifest entry points now read Cargo.toml `[[bin]]` tables (group `bin`), resolving each bin path to its `main` function, with gate coverage in `test/epmanifestcheck.sh` (issue #450).
