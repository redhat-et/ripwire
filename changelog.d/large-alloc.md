### Fixed — macOS peak footprint about halved: freed large blocks leave the process

The default macOS zone keeps freed large blocks resident, and an index frees many: each parse worker's reference array
doubles through 8-65 MB blocks. `operator new` of 256 KiB or more now gets its own mmap region and goes back to the OS on
delete (`src/infra/largealloc.cpp`, macOS only, off under sanitizers). Peak footprint of `--deps --no-cache`, interleaved
runs: Envoy 1,515 to 767 MB, cockroach 1,848 to 984, vscode 2,873 to 1,482. Answers are byte-identical and wall did not
move. `--max-memory` reads the same kernel footprint, so a cap holds as before; `test/largeallocpeakcheck.sh` keeps the
ratio and proves that. A chunked worker store removed only 0-17 % and was not kept. Linux has no route: on a generated
fixture glibc's max RSS moved 2 % with a fixed mmap threshold. Windows was not measured.
