# Changelog

Fixture for test/changelogfragcheck.sh: a release fold must reproduce golden.md byte for byte.

---

## [Unreleased]

Entries for the next release are files under [`changelog.d/`](changelog.d/README.md), one per change; this section
stays this one paragraph. At release, the step in CONTRIBUTING.md ("Cutting a release") folds the files in
under the new version's heading.

## [1.1.0] — 2030-02-02

### Fixed — a twelve sorts before a three by bytes (#12, thanks @fixture-handle)

- One bullet.
- Two bullets, the second naming `C:\…` as a drive path, which is not a private path.

### Added — beta, credited in the body

Body text (thanks @fixture-handle, #3) and a `#### ` sub-heading below.

#### a sub-heading is allowed

More.

### Removed — a slug name, no pull request yet

Gone.

### Changed — the versions this release moves, stated once

`kParserVer` 1 → 2.

## [1.0.0] — 2030-01-01

### Added — the first release

It shipped.
