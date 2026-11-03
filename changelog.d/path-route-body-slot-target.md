### Fixed — an unreached `--path` whose `to=` is stored in a struct field no longer prints the caller's body

A `--path` whose target is a function stored in a struct field (`--path=real_main,ToolBrowse` on ninja's tool table,
`--path=Row_display,LinuxProcess_rowWriteField` on htop's class table) answers `reachable="0"` with a `<bridge>` whose last row
carries `via="slot"`, `slot_callers=` and `slot_fns=`. Its `<bodies of="route">` used to print the `from=` function's body without
that hedge: a body holding a call through a field, not a call to `to=` (+4.0 KB on ninja, +1.1 KB on htop, against the answer
without it). The row whose only next step is the slot crossing into `to=` is now left out of the route bodies; a slot crossing in
the middle of a route keeps its hedged body, and `next=` still names `--callers=`, which lists the call through the field.
A C++ class that names a template parameter as its base (`template <class B> class M : B`) joins no in-tree class's family for
the name-template dispatch either, as it already did not for the member-pointer candidates.
