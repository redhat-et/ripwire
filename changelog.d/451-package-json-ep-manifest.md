### Added — `--for` shows a package.json `bin` / `main` entry and the file it names (#451)

- `--for` manifest entry points now read the top-level `bin` and `main` fields of `package.json`, and resolve each to the file it names (its first exported function, else the file's module body); a `package.json` inside `node_modules` is a dependency's and is not read. Gate coverage in `test/epmanifestcheck.sh` (issue #451). Thanks to @llvm-x86 for the reader and the fixtures.
- The Python, Cargo and package.json readers share one format table, one file-path resolver and one set of TOML helpers; a Cargo or package.json group is a manifest key, so no code is scanned for it as a loader literal, and the legend says so.
