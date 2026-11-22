### Added — an allocator-level memory ceiling, on by default at the memory guard's own limit

`--max-memory`, `RIPWIRE_MAX_MEMORY` and the default 65%-of-RAM cap were read only at phase boundaries, in the
crawl/parse workers and in the file graph's fold. A run that grows inside one call sees none of them: on
2026-11-18 a run over llvm-project grew about 5 GB/s inside `buildGraph`'s resolve loop and reached 149.7 GB
before the OS killed it, because nothing between the `graph-tables` and `graph-end` readings reads memory.

The guard now has a second reading site at `operator new`, where every growth passes, so it sees inside a loop
with no call site in it. It is **on by default** at the guard's existing hard limit — one limit and one knob,
not two: `--max-memory` and `RIPWIRE_MAX_MEMORY` move this line too, and a refusal exits **5**, the
memory-refusal code everywhere in ripwire. **The limit is shared; the quantity measured against it is not.**
This line reads **this process's own footprint** and nothing else, while the guard's phase-boundary lines take
the larger of that and the cgroup v2 leaf's unreclaimable charge. So in a Linux leaf with a finite
`memory.max`, shared with other processes, the allocator line can admit after the leaf's charge has already
passed the limit, and that case stays covered at the guard's phase boundaries only. What this line exists to
catch — one process growing without bound inside a single loop — is exactly what the process footprint shows. `RIPWIRE_MEM_BUDGET_MB=<MiB>` sets a ceiling for
this line alone and `RIPWIRE_MEM_BUDGET_MB=0` turns it off; a value that is neither 0 nor a whole number of at
least 64 MiB refuses the run (exit 1) rather than being ignored. A refusal is one stderr line naming the limit,
the footprint, the next request and the phase, written from a stack buffer with no allocation. It does not flush
pending stdio, so a map still being assembled prints **nothing** — but `_Exit(5)` cannot retract bytes already
written, so a command that had streamed part of an answer leaves that partial stdout behind, and the refusal line
says as much ("any output already printed above is cut, not complete"). **Exit 5 means the run answers nothing: a
caller must discard whatever stdout holds rather than parse it.**

**One region refuses nothing, on purpose.** An edit verb commits the file with `atomicWrite` and then rebuilds
the index for its post-check. Ending the process there would leave the edit applied with no receipt, and a
caller that retried could insert the same text twice — so the line is **suspended for that region and only
there**: a crossing inside it is recorded rather than fatal, and every edit receipt now carries a
`memory_ceiling` field saying which of the three things happened — the ceiling was not armed for this run, or
it was suspended and the limit was not reached, or it was suspended and the check **passed** the limit, with
the peak and the count. The field is always present, on both the CLI and MCP receipts, so no receipt can imply
a ceiling-checked post-check; MCP receipts say "not armed", since a server never arms the line. The
suspension is reachable from no flag and no environment variable, every pre-write check stays armed, and the
memory guard's own phase-boundary stop still applies inside the region (it reports `post_check: "not run: …"`
and exits 0). The accepted cost: growth inside one loop is unbounded again in that one bounded region.

An allocation of 256 KiB or more reads the footprint before the block is taken; smaller ones read once per
64 MiB per thread. Disarmed the cost is one relaxed atomic load per `operator new`. **It only reads — it never
changes what is computed**, and a run under the ceiling prints byte-identical stdout, stderr and exit code with
the line on, off, or armed far above the need. `--mcp` and `--lsp` do not arm it, because its refusal ends the
process and a server must survive a refused request; a build whose `operator new` is not replaced (a sanitizer
or `RIPWIRE_ALLOC_COUNT` build) cannot arm it and says so when asked explicitly. What this line still cannot
see — `malloc` called directly by tree-sitter, `mmap`, and small allocations between readings — stays covered
by the guard's existing `memory_peak=` disclosure. macOS uses the existing allocator hook; Linux, Windows and macOS with `RIPWIRE_LARGE_ALLOC=OFF` get `src/memceiling_new.cpp`, first proven by CI. Measured on llvm-project with the pre-fix resolver: `RIPWIRE_MEM_BUDGET_MB=9000` refused with rc 5 at a 5,689 MiB footprint before a 3,520 MiB request, inside the class-identity step that held the runaway, where the OS had killed the run before. Commits `fbd3b192d`, `ec810904f`. Gate: `test/memceilingcheck.sh`.
