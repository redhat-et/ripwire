### Added — `--for` shows a package.json `bin` / `main` entry and the file it names (#451)

- `--for` manifest entry points now read the `bin` and `main` fields of `package.json`, and resolve each to the file it names, with gate coverage in `test/epmanifestcheck.sh`.
