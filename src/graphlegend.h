#pragma once

// graphlegend.h — the ONE floor marker and the ONE shared legend wording for the five GRAPH-COUNT verbs
// (--uses, --callers, --callees, --impact, --edit-check).
//
// WHY A HEADER AND NOT FIVE STRING LITERALS. Each of these verbs answers with a NUMBER a reader treats as
// exhaustive ("count=1 caller, so one call site to fix"). §H4 proved the number can be silently short: a
// plainly written `ns::inner::fn()` produced no reference at all, so --edit-check said callers="1" about a
// symbol with two callers and nothing in the document hinted otherwise. The widening (option A) fixed the
// qualified-call class; it did NOT — and no static extractor can — fix dynamic dispatch, callbacks, macros
// or most-vexing-parse declarations. So the counts stay FLOORS, and every one of the five has to say so in
// the SAME words: the round-series' standing law is that a CLI legend and its MCP twin are byte-identical
// wording, and the §B4 failure family is exactly "the clause landed at 3 of its 5 echo sites".
//
// THE ATTRIBUTE. `counts_floor="1"` (XML) / `"counts_floor":true` (JSON), appended LAST on the root element
// of all five verbs, in every dialect they ship (XML, --format=columnar, --json, and the MCP payloads).
// It is deliberately NOT spelled with the `_capped` suffix of src/pageview.h rule 4: that marker means "a
// CAP or a BUDGET stopped the scan before it finished counting", which is a property of THIS RUN and is
// raisable with limit=N. This one means "the underlying graph does not model every call", which no flag can
// raise. Two different facts under one attribute name is the §P8 collision class, so they get two names.
// It is a constant "1" today because the tool cannot detect the absence it is disclosing — a 0 would be a
// claim of exhaustiveness that nothing in the pipeline can support.
//
// Gate: test/floormarkcheck.sh (all five verbs, CLI ≡ MCP wording, and the retired absolutism absent).

#include <string>

namespace rw
{

// The floor sentence. Shared verbatim by all five verbs on every surface that can carry prose. Written with
// NO "--" digraph anywhere: this string is spliced into an XML comment, where "--" is a well-formedness
// error (G4), which is why the verbs are named bare here ("the uses verb") rather than with their flags.
inline constexpr const char* kGraphCountFloorLegend =
    "counts_floor=\"1\" means every count on this element is a FLOOR, never a total. Call edges are extracted "
    "from source text by NAME, so a call that reaches its target through dynamic dispatch (a virtual, interface "
    "or duck-typed receiver), a callback or function pointer, a macro-generated call site, or a declaration "
    "that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. "
    "Read a zero as \"none found\", never as \"none exists\". ";

// The COUNTING-UNIT clause (the L-CS routing item).
//
// V3 H-1 REWRITE, and the reason it is worth reading before touching this string. The first version said all
// four non-uses verbs "count DISTINCT (caller,callee) PAIRS". That was FALSE for three of them and it
// contradicted the sentence printed 300 bytes earlier in the same comment (kCallHierarchyLegendOpen's
// "count= the number of DISTINCT neighbour symbols"), which is what the emitters actually implement:
//   * callers/callees dedup by neighbour NodeId (main.cpp's `seen[]`), so `--callers=buf` reports 8 caller
//     SYMBOLS even though push_back calls BOTH defs of buf — 2 (caller,callee) pairs, 1 row.
//   * --impact's reaches= is |transitiveCallers()|, a node-SET size; there are no pairs in it at all.
//   * --edit-check's callers= is callerIds.size(), a 1-hop distinct-symbol count.
//   * --graph-query's count= is the size of the node set the expression selected.
//   * V4 MED-3: --pr-context is the SEVENTH surface counting off this graph — hundreds of per-symbol
//     `<s … callers="N">` attributes read from the same in-edge CSR --callers reads, plus `<impact
//     dependents=>` reach counts. Both units are already named above, so it joins the shared clause by NAME
//     rather than getting a wording of its own.
// Only the map header's edges= is pair-counted (graph.h's accumulator keys on (from,to), so N calls from one
// caller to one callee become ONE edge whose multiplicity lives in nref/weight). A disclosure that states the
// wrong unit is a new false claim inside the honesty fix, which is strictly worse than the silence it
// replaced — so the clause below names the unit PER VERB FAMILY and nothing else.
//
// V3 L-5: the map header's edges= is still named, because the reader who compares these numbers against it
// is exactly the reader this clause exists for — but the sentence now says outright that the map carries
// neither this marker nor this clause, so no one can read the disclosure as covering that document.
inline constexpr const char* kCallCountUnitLegend =
    "COUNTING UNIT, and it differs by verb — which is why two of them report different numbers for one symbol. "
    "The callers, callees, edit-check, graph-query and pr-context counts are DISTINCT SYMBOLS: repeated calls "
    "from one caller, and calls to two overloads of one name, collapse into ONE row, their multiplicity "
    "surviving only in the call graph's edge weight. The reach counts (impact's reaches=, pr-context's "
    "dependents=) are the size of a transitive reach SET, each symbol counted once — not a count of calls or "
    "edges. The uses verb counts call SITES, one row per occurrence, so "
    "a larger count= there for the same symbol is these units agreeing, not disagreeing. The map header's "
    "edges= is a unit again different — distinct (caller,callee) PAIRS — and that document carries neither "
    "this marker nor this clause, so its numbers answer a different question. ";

// The two clauses in the order every legend prints them, so a caller that just wants "the shared tail" cannot
// get the order wrong. Returned by value (std::string) because the two constants cannot be concatenated at
// compile time through `const char*`; every call site splices it once, into a legend built at most once per run.
inline std::string graphCountDisclosure()
{
    return std::string( kGraphCountFloorLegend ) + kCallCountUnitLegend;
}

// The root-element attribute, one spelling per dialect. Appended LAST (after the page disclosure and after
// --edit-check's at= stamp) so no existing attribute ADJACENCY assertion in test/ can break on it — the same
// placement rule gitstamp::atAttr already follows in editcheck.h.
inline constexpr const char* kGraphCountFloorAttrXml = " counts_floor=\"1\"";
inline constexpr const char* kGraphCountFloorAttrJson = ",\"counts_floor\":true";

// ---- the per-verb legend OPENERS that more than one emitter prints -------------------------------------
// Each of these had TWO byte-identical copies (a CLI one in main.cpp, an MCP one in mcpverbs.h) before this
// header. They are hoisted verbatim-minus-the-fix so the pair cannot drift; the REST of each verb's legend
// stays with its own emitter, because the CLI and MCP bodies genuinely differ (the CLI --uses legend
// documents the file:name selector attributes, which the MCP verb does not emit, and describing them there
// would be a new false claim).

// §H4 disclosure item 2: the retired absolutism. This opener used to read "every use-site of SYM", which the
// widening round proved false and which no extractor can make true — the sentence promised exhaustiveness
// over a name-based, statically-extracted reference index. Restated as what IS true.
inline constexpr const char* kUsesLegendOpen =
    "<!-- ripwire uses: the STATICALLY RESOLVABLE use-sites of SYM (role=call|read|write|import|extends; "
    "p=file:line) — a floor, see counts_floor below. ";

// --impact's opener, identical on both surfaces before this header.
inline constexpr const char* kImpactLegendOpen =
    "<!-- ripwire impact: transitive blast radius — symbols that reach SYM via calls (review before changing SYM). ";

// --callers / --callees shipped NO legend at all (0 bytes on both, which is why every one of their root
// attributes sits in test/legendcoverage_baseline.txt). ONE legend serves both forms: the two verbs are one
// code path with the edge direction flipped, and giving them two descriptions is precisely the per-verb
// vocabulary §3.4 forbids.
inline constexpr const char* kCallHierarchyLegendOpen =
    "<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form "
    "lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector "
    "you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and "
    "count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. ";

} // namespace rw
