---
name: emitting-output
description: Writing or converting formatted output in ripwire's C++ source — std::print/std::format via rw::emitTo, emitRaw and formatTo, which printf specifier maps to which format spec, and how to prove a conversion moved zero bytes. Use when adding any output call site, converting a printf-family one, or touching a help/legend string.
---

# Emitting output in ripwire

Every byte this tool prints feeds G4 (minified XML), the determinism contract, `docs/EVALS.md`'s
recorded numbers, and the stored captures. Output code is therefore held to byte-exactness, not taste.

## The three primitives (`src/infra/emit.h`)

| You have | Use | Why |
| --- | --- | --- |
| A format string **with arguments**, going to a stream | `rw::emitTo( stream, "…{}…", args )` | The choke point: `std::print` where the library has it, `std::format`+`fputs` where it does not |
| **Literal text, no arguments** | `rw::emitRaw( stream, "…" )` | `std::format_string` is *consteval*; there is nothing to format, and huge literals do not compile |
| A **caller-owned char buffer** | `rw::formatTo( buf, cap, "…{}…", args )` | Keeps the stack buffer — `std::format` into a `std::string` puts an allocation on hot paths (G2) |

Never add a printf-family call site (`CONTRIBUTING.md` §3). Do not vendor `fmt` — the standard library
has the feature, so a vendored copy is a G3 regression.

## The specifier mapping — measured, not remembered

Proven byte-identical on this toolchain (218 checks; see the lane's `fmtparity.cpp`):

```
%s %u %d %zu %zd %lu %ld %llu %lld %i   ->  {}
%.*s  (precision, pointer)               ->  {}  with std::string_view( ptr, len )
%10s -> {:>10}      %-11s -> {:<11}      %.9s -> {:.9}
%016llx -> {:016x}  %llx -> {:x}  %llX -> {:X}  %o -> {:o}
%.3f -> {:.3f}      %6.1f -> {:6.1f}     %.0f -> {:.0f}
%.6g -> {:.6g}      %.3g -> {:.3g}       (explicit precision only)
```

**The one unsafe mapping.** A `%g` or `%f` with *no* precision is NOT `{}`. printf's `%g` prints six
significant digits; `{}` prints the shortest round-trip. `0.1+0.2` is `0.3` under `%g` and
`0.30000000000000004` under `{}`. Give the format spec an explicit precision or leave the site alone.

## Three traps that are invisible at the call site

1. **`%%` inverts.** In a printf format a literal percent is `%%`. Text handed to `emitRaw` is no longer
   a format, so `%%` there prints *two* characters — collapse it to one `%`. This is how garbage reached
   a generated `docs/COMMANDS.md`.
2. **Braces invert the other way.** `emitTo` needs `{{` and `}}` for literal braces; `emitRaw` needs bare
   `{` and `}`. JSON emitters are where this bites.
3. **`format_to_n` is not `snprintf`.** `snprintf( p, S, … )` writes at most `S-1` chars *plus a NUL*;
   `format_to_n( p, S, … )` writes up to `S` and terminates nothing. Swapping one for the other widens the
   buffer by a byte and drops the terminator. Use `rw::formatTo`, whose contract is snprintf's exactly —
   including its return value, the would-have-written length.

## Proving a conversion moved zero bytes

1. `bash test/printffmtparitycheck.sh` — per-verb SHA-256 of stdout and stderr. **If it does not have a
   label for the verb you touched, it proves nothing about your change: add the label and pin it first.**
   `UPDATE_GOLDEN=1` re-pins; the diff must be additions only. Pinning refuses any verb whose output
   embeds the git stamp (`at="<sha>"`), because such a verb cannot hold a pin at all.
2. **A green fence is not coverage.** Measure it: a coverage build showed only 25% of one batch's call
   sites were ever executed by the corpus. Widen at the gaps — `--json` is a whole second output path.
3. **Differential-test against the pre-conversion binary on a REAL tree.** Build the base commit into a
   scratch worktree and diff both binaries' bytes over `src/`, `test/`, `docs/` and the repo root,
   normalising only the git stamp. A toy fixture cannot reach a truncation branch; a real tree does it by
   accident. This is what caught the `format_to_n` byte, with all 40 labels green.
