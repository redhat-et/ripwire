### Added — `--for` shows a Cargo `[[bin]]` entry and the `main` it names (#450)

- `--for` manifest entry points now read Cargo.toml `[[bin]]` tables (group `bin`), resolving each bin path to its `main` function; an omitted `path` follows Cargo's default (`src/main.rs` for the package's own name, `src/bin/<name>.rs` otherwise), and a crate with no `[[bin]]` lists its own bin at `src/main.rs`. Gate coverage in `test/epmanifestcheck.sh` (issue #450). Thanks to @llvm-x86 for the reader, the fixtures and the Cargo inference cases.
