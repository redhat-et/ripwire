### Fixed — Rust `#[test]` functions no longer read as dead code (#493)

A `#[test]` or `#[tokio::test]` function is run by the test harness, not called by name, so the call graph has no caller for it. `--quality-delta` reported every new test as a `dead-code` row. Those functions are now exempt the way `TEST` and `TEST_CASE` already are, and they count toward `register-macro-excluded=`. An attribute that only looks like the test attribute (`#[testing]`, `#[test_case]`, a `#[test]` inside a comment) does not exempt the function below it, and an ordinary uncalled function is still reported.
