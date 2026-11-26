### Changed — the first-edit check gets its own randomized arm, independent of the primer (2x2)

On the owner's ruling, the before-the-first-edit check (`hooks/ripwire-nudge.sh` §FIRSTEDIT) now has its own assignment. That gives four cells: neither, primer only, check only, both.

- **Assignment.** While the meter is counting, an unforced session is hashed on or off by 32-bit FNV-1a of `ripwire-first-edit/v1:` + the session id. It is a different hash family from the primer's `cksum`, because a salted CRC would be correlated with the primer. With counting off, the check is off, as in the previous release.
- **Primer unchanged.** The primer assignment is the same function as before, so every session id keeps its historical primer arm.
- **Forcing.** `first_edit=1|0` in `meter.conf`, or `RIPWIRE_FIRST_EDIT=1|0`, force the check and override the hash. Forced sessions are logged as `forced-on` or `forced-off`.
- **The primer no longer gates the check.** A primer-control session whose check arm is on gets the check.
- **Schema v4.** Every meter row now carries `primer` (the same value as `arm`) and `first_edit` (`on|off|forced-on|forced-off`).
- **Readout.** `bench/substitution_report.py` prints the 2x2 table, with sessions per cell, forced and mixed-label sessions set apart, and a rate per cell. The primer-only comparison is still the `by arm` block, pooled over the check arm.
- **New seam.** `ripwire-nudge.sh --arm-cells` prints the assignment for a list of session ids.

Over 1,000 fixed ids the cells are 233 / 257 / 255 / 255. Gate: `test/hookcheck.sh` section (17), FX1–FX8, plus FE5/FE6 rewritten for the independent arm.
