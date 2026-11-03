### Changed — Slice 6c: language receiver and comment rules moved to LangFacts columns (#447, thanks @lennix1337)

Move the language predicates `implicitReceiverLang`, `memberNeverReachesFreeFunction`,
`moduleCallReachesFunctionsOnly`, `classNameReceiverLang`, and `langUsesHashComment`
into `constexpr` columns of `struct LangFacts` (`implicitReceiver`, `memberNeverReachesFreeFunction`,
`moduleCallReachesFunctionsOnly`, `classNameReceiver`, and `hashComment`) in `src/langfacts.h`.
Call sites in `src/receiverevidence.h`, `src/graph.h`, and `src/quality.h` now read `langFacts( l )`
directly, eliminating Type-2 clone group 99 (`langUsesHashComment` / `classNameReceiverLang`) from
`--clones` output and lowering the shared-file `== Lang::` ratchet ceiling in `test/langidentity/ratchet.tsv`
from 333 to 326. `isJsTsLitRecv` remains in `src/model.h` as it partitions `RecvKind` rather than `Lang`.
Output across the repository is verified byte-identical with 0 quality-delta regressions.
