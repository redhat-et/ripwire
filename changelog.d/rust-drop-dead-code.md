### Fixed — Rust `Drop::drop` no longer reads as dead code (#494)

The compiler runs `drop` when a value goes out of scope, and no call in the source names it. `--quality-delta` reported every `impl Drop` as a `dead-code` row. A Rust method named `drop` is now treated as invoked by the language, the same way C++ destructors already are. The rule reads only the name and the kind, so an inherent method named `drop` is treated the same way; that errs toward not reporting. A free function named `drop`, and a C++ method named `drop`, are still reported.
