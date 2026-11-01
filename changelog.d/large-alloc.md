### Fixed — macOS peak footprint about halved: freed large blocks leave the process

The default macOS zone keeps freed large blocks resident, and an index frees many: each parse worker's reference array
doubles through 8-65 MB blocks. `operator new` of 256 KiB or more now gets its own mmap region and goes back to the OS on
delete (`src/largealloc.cpp`, macOS only, off under sanitizers). Peak footprint of `--deps --no-cache`, interleaved
runs: Envoy 1,515 to 767 MB, cockroach 1,848 to 984, vscode 2,873 to 1,482. Answers are byte-identical; CPU time is flat and wall stays within load noise.
`--max-memory` reads the footprint between phases, and the blocks the route returns early are gone from that reading, so a run
can now peak above its cap, pass every reading and finish. That is not stopped; it is said: one stderr line on any verb,
`memory_peak=` in the default map's header, `_memory_peak` in the MCP envelope, naming the peak and the cap and noting that the
cap is a rule of thumb against running out of memory, not an exact line (the 65 % default is not a measured threshold). The
disclosure is on in builds that link the route. `test/largeallocpeakcheck.sh` keeps the peak ratio and pins the disclosure. A chunked worker store removed only 0-17 % and was not kept. Linux has no route: on a generated
fixture glibc's max RSS moved 2 % with a fixed mmap threshold. Windows was not measured.
