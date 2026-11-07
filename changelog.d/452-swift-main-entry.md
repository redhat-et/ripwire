### Added — Swift `@main` types are program entries (#452)

The map inventory's entry rule gains a fourth style. In C a caller-less `main` is the entry, in Java a
static `Main`; in Swift the entry is the TYPE carrying `@main` — the type itself is the entry row
(`<entry p="Tool.swift" n="Tool">`), its static `main()` the first callee, and what `main` itself calls
rides the same row, so the row reads "Tool — main — run" instead of a dead end. The attribute is detected
at parse time (an `extension` is not a new type and never claims an entry) and kept in the per-def cache
record.

Three rules the review round pinned: the attribute is the claim, so another file or test constructing
`Tool()` cannot veto the entry; a `main` nested one type deeper belongs to the inner type, so
`@main struct Outer { struct Inner { static func main() } }` is an entry with no main row; and a non-static
`main` is accepted (the index carries no static bit — Swift itself rejects the program at compile time).
Past the entry cap, `entries_next` lists the Swift class defs, the shape a cut attribute entry rides.
