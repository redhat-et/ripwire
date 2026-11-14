### Added — `--for` names the call that makes a head name's value, and the declaration that holds a dispatch candidate (DECL-PRINT)

Two rows for answers that already rank the right head (cards 3 and 4 of the 11-12 residual pass by Fable):

- `<syms>` gains `by="init"` rows. When one of the first five `<d>` rows, or the re-export walk's `<def>` row, names a value that a module-level declaration makes with one call (`export const Component: ComponentDecorator = makeDecorator(…)`, `registry = make_registry()`), the row names that call's callee, with `of=` the name and `at=` the declaration. The call must be a file-scope call that resolves to exactly one definition, and a callee a shown row already stands on is not repeated. `RIPWIRE_NO_INIT_ROWS=1` turns the rule off.
- `<dispatch>` gains `<s held="member|local">` rows. When no non-test constructor call makes a shown candidate's type, the by-value declarations that hold it are printed with their line as text: a C++ field (ninja's `RealDiskInterface disk_interface_;` in `NinjaMain`) or a function's local. Pointers, references, parameters and test code give no row. There are two rows per call, and `capped="1"` when more exist.
