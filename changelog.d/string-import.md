### Added — a dotted string that names a shown Python definition

`--for` and `--callers` now print `<dotted_strings>` when a Python string literal whose whole value is a dotted path resolves to a row
the answer shows: `_builtin_context_processors = ("django.template.context_processors.csrf",)` beside `csrf`, with the function in which
the constant's name reaches an import sink's argument through that function's own assignments. A `%`-template handed to an import sink (`import_module("%s.base" % name)`) gets a hedged
row when the directories of three or more shown files fill it. The string is matched through its whole path, never a bare name; whether it
reaches the sink is not traced, so nothing enters a count, `reaches=` or `--impact`. `RIPWIRE_NO_DOTTED_STRINGS=1` turns it off.

The compact legend entry for a tests-only `<dotted_strings s= next=>` no longer contains a double hyphen, which made the whole `--callers` answer ill-formed XML (an XML comment cannot hold it) when the only site of a string was in a test path.
