### Fixed — the comparison table says which build its ripwire column came from

The "How ripwire compares" header said "default settings" and named ripwire 0.7.0, but not that the
ripwire column is a profile-guided release build. Only `docs/EVALS.md` §2b said so, behind a link, so
a reader of the table could reasonably take the figures for a plain `cmake --build build` — which is what the
Quick start recommends, and which this same file prices 6-16% slower cold. The header now
names the build and points at `scripts/pgobuild.sh`. Prose only: no number in any table moved.
