# Changelog

## Unreleased

- Fixed the RuntimeError raised during eviction of a pinned page in the page
  cache during flush. The traceback pointed at runpy and at the exec of
  run_globals in _run_module_as_main, so the failure read as a startup fault
  rather than as an eviction of a pinned page during a cache flush.
