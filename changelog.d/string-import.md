### Added — a dotted string that names a shown Python definition

`--for` and `--callers` now print `<dotted_strings>` when a Python string literal whose whole value is a dotted path resolves to a row
the answer shows: `_builtin_context_processors = ("django.template.context_processors.csrf",)` beside `csrf`, with the function that
names the constant and calls `import_string`. A `%`-template handed to an import sink (`import_module("%s.base" % name)`) gets a hedged
row when the directories of two or more shown files fill it. The string is matched through its whole path, never a bare name; whether it
reaches the sink is not traced, so nothing enters a count, `reaches=` or `--impact`. `kParserVer` 269 → 274. `RIPWIRE_NO_DOTTED_STRINGS=1` turns it off.
