### Added — an allocator-level memory ceiling, on by default at the memory guard's own limit

`--max-memory`, `RIPWIRE_MAX_MEMORY` and the default 65%-of-RAM cap were read only at phase boundaries, in the
crawl/parse workers and in the file graph's fold. A run that grows inside one call sees none of them: on
2026-11-18 a run over llvm-project grew about 5 GB/s inside `buildGraph`'s resolve loop and reached 149.7 GB
before the OS killed it, because nothing between the `graph-tables` and `graph-end` readings reads memory.

The guard now has a second reading site at `operator new`, where every growth passes, so it sees inside a loop
with no call site in it. It is **on by default**, and its ceiling IS the guard's existing hard limit — there is
one limit and one knob, not two: `--max-memory` and `RIPWIRE_MAX_MEMORY` move this line too, and a refusal
exits **5**, the memory-refusal code everywhere in ripwire. `RIPWIRE_MEM_BUDGET_MB=<MiB>` sets a ceiling for
this line alone and `RIPWIRE_MEM_BUDGET_MB=0` turns it off; a value that is neither 0 nor a whole number of at
least 64 MiB refuses the run (exit 1) rather than being ignored. A refusal is one stderr line naming the limit,
the footprint, the next request and the phase, written from a stack buffer with no allocation. It does not flush
pending stdio, so a map still being assembled prints **nothing** — but `_Exit(5)` cannot retract bytes already
written, so a command that had streamed part of an answer leaves that partial stdout behind, and the refusal line
says as much ("any output already printed above is cut, not complete"). **Exit 5 means the run answers nothing: a
caller must discard whatever stdout holds rather than parse it.**

An allocation of 256 KiB or more reads the footprint before the block is taken; smaller ones read once per
64 MiB per thread. Disarmed the cost is one relaxed atomic load per `operator new`. **It only reads — it never
changes what is computed**, and a run under the ceiling prints byte-identical stdout, stderr and exit code with
the line on, off, or armed far above the need. `--mcp` and `--lsp` do not arm it, because its refusal ends the
process and a server must survive a refused request; a build whose `operator new` is not replaced (a sanitizer
or `RIPWIRE_ALLOC_COUNT` build) cannot arm it and says so when asked explicitly. What this line still cannot
see — `malloc` called directly by tree-sitter, `mmap`, and small allocations between readings — stays covered
by the guard's existing `memory_peak=` disclosure. Gate: `test/memceilingcheck.sh`.
