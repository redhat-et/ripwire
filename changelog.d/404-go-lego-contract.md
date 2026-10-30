### Changed — `--lego` reads a Go interface's method contract (#404, thanks @sharmis-tp)

Before: `--lego=TYPE` on a Go interface printed `methods="0" caveat="not-extracted-for-lang"` and no `<m>` rows, although
the interface's methods were already indexed (goreleaser/nfpm `--lego=Packager`). Now it prints one `<m>` row per method
the interface's own body declares (`Package(info *Info, w io.Writer) error`, `ConventionalFileName(info *Info) string`) and
no caveat. The languages whose contract is read are a column of the per-language facts table (`langfacts.h`
`legoContract`), not a `Lang::` compare.

Not changed: a Go struct keeps the caveat (its methods are declared by receiver, outside its body), and so do TypeScript,
Java, Rust and the other languages that had it. The ranked `<lego>` section of `--for` lists only interfaces with
implementors and is byte-identical on the measured trees.

Limits: an embedded interface is not read, so a Go interface's `<m>` rows are the methods its own body declares (the full
legend says so): an interface that only embeds others lists none. A method of an interface literal written in a member's
signature (`Walk(n interface{ Pos() int })`) is not listed as the interface's. A signature with an inline type literal
prints cut at its first `{`, as it already does on every other signature surface.
