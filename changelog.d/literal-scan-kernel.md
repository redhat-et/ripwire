### Changed — the literal scan finds a pattern 2-9x faster (`--grep` and the `--for` literal blocks)

A literal scan used `std::string::find`, which stops at every copy of the pattern's first byte. It now calls
`rw::strkern::find( hay, needle, from )` (`src/infra/strkern.h`), a first-and-last-byte filter with NEON, AVX2 and a portable
scalar twin side by side, which returns exactly what `std::string_view::find` returns for every input. The hits, their order and
every count are byte-identical. Over vscode's 251 MB, one thread, a scan for `parsed` went from 67 ms to 16 ms and
`onDidChangeConfiguration` from 186 ms to 21 ms. A pattern whose first byte is already rare gains less: `IExtensionService` went
from 25 ms to 14 ms. End to end, the CPU of a warm `--grep` or `--for` is unchanged within measurement noise: the scan is a small part of those verbs once the file sieve has skipped the files that cannot match. `find3`, the trigram probe the regex prefilter uses, now shares the same loop. CONTRIBUTING.md §3 names
`rw::strkern::find` as the one string-find utility for hot loops over file text.
