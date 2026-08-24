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
    "or duck-typed receiver), or a declaration "
    "that parses without a call expression (C++ most-vexing-parse) contributes no edge and is missing here. "
    "A call through a function pointer or callback resolves only when ONE function is bound to that variable in "
    "scope (C-family; a reassigned, table-indexed, lambda-bound or escaped pointer — its address taken or "
    "reference-bound — still contributes no edge). A binding written as a plain name rather than an address-of "
    "(fp = handler, not fp = &handler) is read as a function only when the variable is PROVEN able to hold one: "
    "a function-pointer declarator, or a function-pointer typedef declared in the SAME FILE, or a type the "
    "parse cannot pin down at all (auto, a template type). Under any other concrete written type it is a value "
    "copy and contributes no edge, so a variable whose function-pointer typedef lives in a HEADER is missed. "
    "A macro-generated call site contributes a role=\"macro\" edge when its name uniquely names an indexed "
    "function-like #define (C-family, t=\"macro\"); a name shared with any non-macro definition stays a plain "
    "call for the resolver, and an unindexed macro's call site contributes no edge. "
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

// ---- the root-relative path disclosure, ONE sentence for every verb that emits root= --------------------
// R-E fix (2026-08-19): the root-relative round gave 30 first screens a root= attribute and defined it in
// none of them. test/legendcoveragecheck.sh caught it, and its baseline file may only be edited DOWNWARD —
// so the fix is the TEXT, not a baseline line. Hoisted here rather than pasted into eighteen legends: it is
// one claim, --grep already shipped it, and a second wording would be exactly the §B4 echo-site drift this
// header exists to stop. Each emitter concatenates it into its own legend (a trailing "%s" before the -->).
// It is emitted as its OWN comment, immediately after the verb's legend and before the root element, rather
// than spliced into eighteen string literals: legendcoveragecheck's legendOf() reads the whole LEADING RUN
// of comments, so an adjacent comment IS the legend, and one shared literal cannot drift from itself the way
// eighteen hand-edited tails can. Emit it through rootRelPathsLegend( bool ) so the text appears exactly when
// root= does — a legend that defines an attribute the document did not emit is the mirror-image false claim.
inline constexpr const char* kRootRelPathsLegend =
    "<!-- root= on this element is the crawl root every p= below is RELATIVE to (single-root runs only; "
    "absent => p= is the path ingest itself used, unchanged). -->";

// `on` is the emitter's own root=-present condition, never a re-derivation of it.
inline const char* rootRelPathsLegend( bool on ) noexcept { return on ? kRootRelPathsLegend : ""; }

// W3-S item 5 (2026-08-19) — the ONE deliberate second wording of the clause above, for the ONE call site
// (--for's two dialects: CLI main.cpp forLensHeaderText, MCP mcpverbs.h) that cannot afford the 159 B full
// form: at --token-budget=800 pasting kRootRelPathsLegend verbatim pushed a real fixture from
// est_tokens=799 to 811 (+1.4%), red test/fornotesbudgetcheck.sh. Recalibrating the shared ceiling
// constants (serialize.h kMinBytesPerToken/kBudgetHeadroom/kCeilingFirstEntryTolerance) to absorb 33 B for
// one verb would move every other budget-pinned gate in the tree — a blast radius wildly out of proportion
// to a 21-byte gap after shortening, so a smaller spelling was the chosen trade-off, not a floor move.
// Deliberately still only TWO spellings tool-wide (this one, and kRootRelPathsLegend for the other eighteen
// legends) rather than a third-per-verb drift: both --for dialects share this exact string, the same way
// they already share every other opener in this file.
inline constexpr const char* kForRootRelPathsLegendShort =
    "<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's "
    "own path, unchanged). -->";

inline const char* forRootRelPathsLegendShort( bool on ) noexcept { return on ? kForRootRelPathsLegendShort : ""; }

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
    "<!-- ripwire uses: the STATICALLY RESOLVABLE use-sites of SYM (role=call|macro|read|write|import|extends|type; "
    "p=file:line) — a floor, see counts_floor below. That role list is the whole vocabulary. role=\"type\" is a bare TYPE "
    "mention — SYM named as a type in a signature, a declaration or a template argument — and it carries no call edge: "
    "a type dependency is real, but it is not an invocation, so it never reaches the call graph, PageRank or the ranked "
    "map. It is captured for C/C++/ObjC only, and only where the type is spelled as a plain leaf name, so a mention "
    "written through a qualified or aliased spelling still contributes no row. A base clause is role=\"extends\" rather "
    "than role=\"type\" (that relation is modelled separately), and a type\'s own DEFINITION is never a use of itself. "
    "role=\"macro\" is the call-shaped invocation of a name "
    "that uniquely names an indexed function-like #define — never labelled role=\"call\", because an expansion "
    "is not a plain call; a name shared with a non-macro definition stays role=\"call\" for the resolver. "
    "Rows are ordered SOURCE first, then test/bench, then docs, and by path within a tier. "; // LB-G

// --impact's opener, identical on both surfaces before this header.
inline constexpr const char* kImpactLegendOpen =
    "<!-- ripwire impact: transitive blast radius — symbols that reach SYM via calls (review before changing SYM). ";

// ── LB-H (r10 GitNexus round) — the IMPORT TIER's own definition ─────────────────────────────────────────
// --impact answered "what breaks if I change this" with CALL reach only. On webpack, --impact=ChunkGraph
// returned 25 reaching symbols and no trace of the 8 files that require("./ChunkGraph") — not the files
// and not a count saying they were uncounted, so the omission was invisible at the point of use.
//
// The two reaches are reported SIDE BY SIDE AND NEVER SUMMED (CLAUDE.md non-negotiable #3): they are
// different units (symbols vs files) measured over different evidence (a named call vs a named file), so
// one merged number would be a quantity nothing in the tool can define. Hence a second count with its own
// noun-prefixed shown_/capped pair (pageview.h rule 6, the SECONDARY-listing form) and its own row tag,
// rather than extra rows inside reaches=.
//
// legendcoveragecheck's rule: every root attribute a reader meets on the first screen is defined where
// they meet it — importers=, shown_importers=, importers_capped= and the via=/lazy= row attributes are all
// here.
//
// lazy= (kParserVer 72, fnbody-require lane): a TS/JS `require("./x")` / dynamic `import("./x")` written
// INSIDE A FUNCTION BODY is still a real dependency — the importer tier must still name the file — but a
// WEAKER one than a top-level require: it only fires if and when that function actually runs (webpack's
// own lib/index.js lazy-getter barrel, `get ChunkGraph() { return require("./ChunkGraph"); }`, is the
// shape that motivated capturing it at all). lazy="1" on a row means EVERY edge from that importer into
// SYM's def file(s) is one of these function-body calls; lazy="0" means at least one is an ordinary
// top-level (unconditional) require/import, so the dependency also holds at module-load time.
inline constexpr const char* kImpactImportTierLegend =
    "importers= is a SECOND, weaker reach: the files that directly include/import a file defining SYM, listed as "
    "<f via=\"import\" p=\"…\" lazy=\"0|1\"/> rows after the symbol rows. It is not call reach and is never added to "
    "reaches= — the two count different units (files vs symbols) over different evidence, and an importer may use a "
    "different symbol from that file, or none at all. It is DIRECT (one hop), never the transitive include cone. "
    "lazy=\"1\" (TS/JS only) means every one of that importer's edges into SYM's file is a require()/import() written "
    "INSIDE A FUNCTION BODY rather than at module load time — still a real dependency, but one that only fires if "
    "and when that function runs; lazy=\"0\" means at least one edge is an ordinary top-level require/import. "
    "shown_importers=/importers_capped= disclose that listing's own truncation (importers= stays the full count); "
    "limit=/offset= window the symbol rows only. ";

// The columnar form re-serializes the SYMBOL rows as parallel arrays and has no row shape for a second
// listing, so it carries importers= alone. Said in band rather than left as a shape difference a reader
// has to notice: a count with no rows beside it otherwise reads as a bug.
//
// G4: this string is emitted INSIDE an XML comment, so it may not contain a double hyphen. Naming the
// sibling dialect as "--json" put one there and xmllint caught it on the first run — the flag spelling is
// written without its dashes here for that reason, not by oversight.
inline constexpr const char* kImpactImportTierColumnarLegend =
    "importers= is a SECOND, weaker reach: the files that directly include/import a file defining SYM. It is not "
    "call reach and is never added to reaches=. Under format=columnar the import-tier rows are not emitted in this "
    "form (it re-serializes the symbol rows only) — the count is the whole of it here; the default XML form and the "
    "json dialect carry the per-file rows. ";

// --callers / --callees shipped NO legend at all (0 bytes on both, which is why every one of their root
// attributes sits in test/legendcoverage_baseline.txt). ONE legend serves both forms: the two verbs are one
// code path with the edge direction flipped, and giving them two descriptions is precisely the per-verb
// vocabulary §3.4 forbids.
inline constexpr const char* kCallHierarchyLegendOpen =
    "<!-- ripwire callers/callees: the 1-hop call hierarchy read straight off the call graph. The callers form "
    "lists the symbols that CALL of=; the callees form lists the symbols of= itself calls. of= is the selector "
    "you passed, defs= how many DEFINITIONS that name resolved to (the rows UNION every def's neighbours), and "
    "count= the number of DISTINCT neighbour symbols (a floor, per counts_floor=), which the rows window with limit= and offset=. "
    "A neighbour that is an indexed function-like #define is a macro row (t=\"macro\", role=\"macro\" on the XML row): "
    "the edge crosses a macro expansion, not a plain call — rows carry no role= otherwise. "
    "Rows are ordered SOURCE first, then test/bench, then docs, and by path within a tier. "; // LB-G

// V1 fix (verifier finding 3, 2026-08-15): bodyless_defs= is a CALLEES-only attribute — main.cpp's emitter
// gates it behind `!wantCallers`, so a --callers document can never carry it. It used to sit inside
// kCallHierarchyLegendOpen above, which both forms print, so every --callers call paid ~235 B for a clause
// it could never need. Appended only on the callees form (see the call site in main.cpp), so the clause
// still appears verbatim wherever the attribute CAN appear — legendcoveragecheck's callees-side coverage is
// unaffected; only the callers-side dead weight is gone.
inline constexpr const char* kCallHierarchyLegendCalleesOnly =
    "When emitted by callees, bodyless_defs= (when present) counts how many of the defs= are declarations with no body (header-only or forward-declared); "
    "zero callees may mean no body to read callees from rather than truly no dependencies. ";

// The composed opener, one call for the caller — keeps the wantCallers/callees branch out of
// runCallHierarchy (already this file's largest dispatcher) rather than adding a ternary at the call site.
inline std::string callHierarchyLegendOpen( bool wantCallers )
{
    return wantCallers ? std::string( kCallHierarchyLegendOpen )
                       : std::string( kCallHierarchyLegendOpen ) + kCallHierarchyLegendCalleesOnly;
}

// ── LB-G (r10 GitNexus round) — the DISPLAY-CAP clause the neighbour verbs share ─────────────────────────
// --callers/--callees/--uses grew a default row cap (pageview.h kCallHierarchyRowCap / kUseSiteRowCap), so
// their first screen can now carry shown=/capped= — and by legendcoveragecheck's rule an attribute a reader
// meets on the first screen has to be defined where they meet it. One literal for three verbs, for the same
// reason kRootRelPathsLegend was hoisted out of eighteen: a second wording is echo-site drift waiting to
// happen. It supersedes kPageRaiseCapClause for these three (that fragment defines limit= alone; this one
// defines the whole pair the cap actually emits) — --grep and --impact keep the shorter one, which is what
// their own baselines and gates are pinned against.
//
// EMITTED CONDITIONALLY, by capLegendClause() below. That is not byte-shaving for its own sake: these three
// verbs shipped for their whole life with no cap, so an answer that drops nothing must stay byte-identical
// to what it was — and THE TRUNCATION VOCABULARY (pageview.h) names exactly this shape conformant, citing
// --skill-scan, which emits the shown=/capped= pair only on a capped scan. Same rule the callees-only
// clause above already follows: a call never pays for vocabulary it cannot emit.
inline constexpr const char* kNeighbourCapLegend =
    "shown= is how many rows this answer PRINTED and capped=\"1\" says a default display cap dropped some; "
    "count= above stays the true total, never the page's length. Raise the default cap with limit=N "
    "(offset=M pages, which also adds total=/has_more=/next_offset= so a paging loop can terminate); on the "
    "root, limit=\"0\" means no explicit limit was given and the verb's own default page size shaped the "
    "window — never a zero-row page. ";

// `active` is pageDisclosure()'s own activity decision, passed in rather than re-derived, so the clause and
// the attributes it defines can never disagree about whether they are present.
inline const char* capLegendClause( bool active ) noexcept
{
    return active ? kNeighbourCapLegend : "";
}

} // namespace rw
