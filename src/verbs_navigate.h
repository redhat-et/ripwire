#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_navigate.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

// verbs_navigate.h — the navigate family, moved VERBATIM from main.cpp in the 2026-08-29 split:
// printJsonSymbolRows (the JSON row array --callers/--callees/--impact share), the nine navigate verb
// handlers (--callers/--callees, --graph-query, --uses, --safe-delete, --slice, --verify,
// --external-surface, --path, --connect, --impact, --mentions) and runAround. Same contract as every
// verbs_*.h: reopens main.cpp's unnamed namespace — one TU, one unnamed namespace, internal linkage
// unchanged, zero new API surface — under the RIPWIRE_MAIN_TU guard.

namespace
{

// L2: the `[{"t":..,"n":..,"p":"file:line"},...]` JSON row array shared by --callers/--callees/--impact's
// --json branches (identical shape, different surrounding header fields — see each call site). Avoids
// carrying two copies of the same per-row loop (--quality-delta flagged the pre-extraction duplicate).
// File-scope (not inside `using namespace rw;`, unlike its callers) — every rw:: type/fn spelled out.
// R-E (2026-08-17 harvest): rootPrefix empty ⇒ p= stays the ing.files[] spelling unchanged (multi-root, or
// a caller with no single root to strip) — same convention as serialize()'s pathRel.
// A6: `testReach` is optional (nullptr on a caller that has not computed the lens) — when given, a row
// reached by an indexed test (rw::isTestedByReach, the SAME predicate --test-gate's untested= excludes by)
// gains `"tested":true`; the key is OMITTED otherwise, matching the tested= "absence-meaningful, never
// false" convention every other tested= site in this tree already follows (serialize.h/verbs_for.h) — zero
// extra bytes on the untested row, the common case.
inline void printJsonSymbolRows( const rw::IngestResult& ing, const std::vector<rw::NodeId>& ids, std::size_t begin, std::size_t end,
                                 std::string_view rootPrefix = {}, const std::vector<char>* testReach = nullptr )
{
    for( std::size_t i = begin; i < end; ++i )
    {
        const rw::Symbol&      s = ing.symbols[ ids[i] ];
        const std::string_view p = rootPrefix.empty() ? std::string_view( ing.files[ s.fileId ] )
                                                       : rw::sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix );
        std::printf( "%s{\"t\":\"%s\",\"n\":\"%s\",\"p\":\"%s:%u\"%s}", i == begin ? "" : ",",
                     rw::symTag( s.kind ), rw::jsonStr( s.name ).c_str(), rw::jsonStr( p ).c_str(), s.line,
                     ( testReach && rw::isTestedByReach( ing, *testReach, ids[i] ) ) ? ",\"tested\":true" : "" );
    }
}

// The nine navigate verbs — --callers/--callees, --graph-query, --uses, --external-surface, --path,
// --connect, --impact, --mentions, --affected — were nine independent top-level branches of a single
// 478-line runNavigateVerbs. Each is now its own handler with the `std::optional<int>( const MainDispatch& )`
// shape the file's other 23 handlers already use; the bodies are cut VERBATIM and main() calls them in the
// SAME order the chain evaluated them. That order is observable (passing two verb flags picks exactly one
// answer) and nothing pinned it before — test/dispatchordercheck.sh does now.

// macro-edges round: the role attribute a callers/callees XML row carries iff the neighbour is an indexed
// function-like #define — the edge crosses a macro expansion, not a plain call (rows carry no role=
// otherwise, and NEVER role="call"). Kind-derived, so the columnar/JSON dialects disclose the same fact
// through their t="macro"; kept out of runCallHierarchy's row loop as a call, not another branch.
inline const char* macroRoleAttr( rw::SymKind k ) noexcept
{
    return k == rw::SymKind::Macro ? " role=\"macro\"" : "";
}

// A6's HopTestedPartition + computeHopTestedPartition, and the row COLLECTION this dispatcher used to do
// inline, now live in callhierarchy.h — the MCP twins (find_referencing_symbols / find_symbol) call the
// same code rather than walking the CSR their own way and losing defs=/hop_tested=/tested= on the way out.
// See that file's header for the drift this closed.
using rw::CallHierarchyRows;
using rw::HopTestedPartition;

std::optional<int> runCallHierarchy( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         chSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  chRootPrefix = chSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  chEsc;
    const std::string  chRootAttr   = chSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], chEsc ) ) + "\"" ) : std::string();

    // --callers=SYM / --callees=SYM: sharp 1-hop call hierarchy from the graph (in-edges = callers,
    // out-edges = callees). LSP's incomingCalls/outgoingCalls — crisper than the --around neighbourhood.
    if( !cfg.callers.empty() || !cfg.callees.empty() )
    {
        const bool             wantCallers = !cfg.callers.empty();
        const std::string_view sym         = wantCallers ? cfg.callers : cfg.callees;
        // callhierarchy.h owns the resolution, the neighbour union, the bodyless-def count and the
        // tier-then-path order — the MCP twins run the identical call, so the two surfaces cannot disagree
        // about WHICH rows the question has.
        const CallHierarchyRows   chRows  = rw::callHierarchyRows( ing, g, sym, wantCallers );
        const std::vector<NodeId>& matches = chRows.matches;
        if( matches.empty() )
        {
            const std::string verb = std::string( wantCallers ? "--callers" : "--callees" );   // one arm, two spellings
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: " + verb + " symbol not found: ",
                                                                   sym, verb + "=" ).c_str() );   // §B4.2 shared refusal
            return 1;
        }
        const std::vector<NodeId>& result = chRows.rows;

        const char*       tag = wantCallers ? "callers" : "callees";
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

        // A6 (survey card A6, agent-lsp): tested/untested partition — reuses the identical isTestSymbol-
        // seeded forwardReach --safe-delete/computeQMetrics already run (graph.h::testSymbolForwardReach),
        // never a second lens. A row is a partition, never a filter: count= is unchanged and every row still
        // prints; hop_tested=/hop_untested= sum to result.size() over the FULL (un-windowed) result set, the
        // same convention reaches=/impact_reaches= already use for radius_tested=/radius_untested=.
        const HopTestedPartition chTested = computeHopTestedPartition( ing, g, result );

        // Bodyless definitions (a declaration with no body) are counted by callhierarchy.h, callees-only.
        const std::size_t bodylessDefsCount = chRows.bodylessDefs;

        // T2 + §P8 G1: paginate the sorted result. count= stays the un-windowed total (V3 L-4: "TRUE" is the
        // word this comment used, and it contradicts the counts_floor= marker the emitter ten lines below now
        // prints — the total is true of the PAGE, never of the world); the disclosure appears only
        // when paging is active — discloseCap=false because these two verbs have NO display cap of their own
        // (an un-paginated --callers always emitted every caller), so the un-paged opening tag stays
        // byte-identical. See src/pageview.h, THE TRUNCATION VOCABULARY.
        // LB-G: the family's DEFAULT display cap (pageview.h kCallHierarchyRowCap), where these two verbs
        // had none. count= stays the un-windowed total, so the cap costs no honesty. discloseCap is the
        // answer's OWN capped state, not a constant true — these verbs shipped uncapped for their whole
        // life, and THE TRUNCATION VOCABULARY names that shape conformant (its --skill-scan precedent).
        const PageWindow  pw = pageWindow( result.size(), effectiveRowCap( cfg.pageLimit, rw::kCallHierarchyRowCap ), cfg.pageOffset );
        const bool        chDiscloseCap = ( pw.end - pw.begin ) < result.size();
        char              pab[ kPageDisclosureCap ];

        // §H4 §3.4: the FIRST legend these two verbs have ever shipped (0 bytes before — which is why every
        // one of their root attributes sits in test/legendcoverage_baseline.txt), and the floor marker that
        // is the round's honest half. ONE opener for both forms, printed BEFORE the format branches so the
        // columnar and default shapes carry the identical disclosure. JSON has no comment-node analogue, so
        // there the marker travels as the counts_floor key on the root object instead.
        // V1 fix (verifier finding 3): bodyless_defs= is callees-only (main.cpp gates the attribute itself
        // behind !wantCallers a few lines up), so its defining sentence rides along only on the callees
        // form — a --callers call no longer pays for vocabulary it can never emit. The wantCallers branch
        // lives in rw::callHierarchyLegendOpen (graphlegend.h), not here, so it does not add to this
        // already-large dispatcher's own complexity.
        if( !cfg.json )
        {
            // M12: under multi-root this verb carries no root= at all (correctly — no single root exists)
            // and, before this, disclosed nothing about the `<label>/` prefix every p= below carries.
            std::printf( "%s%s%s-->%s%s", rw::callHierarchyLegendOpen( wantCallers ).c_str(),
                         rw::capLegendClause( rw::computePageDisclosure( pw.end - pw.begin, result.size(), pw.end,
                                                                        cfg.pageLimit, cfg.pageOffset, chDiscloseCap ).active ),
                         rw::graphCountDisclosure().c_str(), rw::rootRelPathsLegend( chSingleRoot ),
                         rw::multiRootTableLegend( ing.rootLabels.size() >= 2 ) );
        }

        // --format=columnar (RESEARCH lever 1): the same page window, re-encoded as a path-table + parallel
        // arrays (dedups the repeated per-row markup + paths). Default --format=xml is byte-identical below.
        if( cfg.columnar )
        {
            std::vector<NodeId> page( result.begin() + pw.begin, result.begin() + pw.end );
            // §B1.1: composed into a std::string, NEVER a fixed `char attrbuf[]`. `of=` echoes a
            // caller-supplied symbol NAME, which is unbounded (a markdown SECTION heading routinely runs
            // 200-600 chars), so the old 288-byte buffer truncated it mid-attribute at exit 0 — invalid
            // XML past ~185 chars once paging flags widened the string, and at a boundary length a
            // well-formed tag whose next_offset=/offset=/limit= had been silently amputated. Same
            // composition runImpact already used; the columnar-capable family is exactly
            // {callers, callees, uses, impact} and this is the last shared site of the first two.
            const std::string attr = "of=\"" + ex( sym ) + "\" defs=\"" + std::to_string( matches.size() )
                                   + "\" count=\"" + std::to_string( result.size() ) + "\""
                                   + ( !wantCallers && bodylessDefsCount > 0 ? " bodyless_defs=\"" + std::to_string( bodylessDefsCount ) + "\"" : "" )
                                   + chTested.xmlAttr   // A6: hop_tested=/hop_untested=, the same partition on every dialect
                                   + chRootAttr   // R-E: same root= the XML/JSON branches carry
                                   + pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, result.size(), pw.end,
                                                     cfg.pageLimit, cfg.pageOffset, chDiscloseCap )
                                   + rw::graphCountFloorAttrXml( g );   // §H4 §3.4 — every dialect carries the marker
            emitColumnarSymbolRows( stdout, ing, tag, attr, page, chRootPrefix, &chTested.testReach );
            return 0;
        }

        // L2: --json — same rows, keys mirror the XML attr names (of/count/offset/limit/t/n/p).
        // §A4c: the page disclosure is pageDisclosure()'s JSON row of the syntax table now, not a hand-rolled
        // `offset`+`limit` pair — the SAME seven fields the XML tag two lines below carries (discloseCap=false
        // for the same reason: these two verbs have no display cap of their own, so un-paged discloses nothing).
        if( cfg.json )
        {
            std::printf( "{\"of\":\"%s\",\"defs\":%zu,\"count\":%zu", jsonStr( sym ).c_str(), matches.size(), result.size() );
            if( !wantCallers && bodylessDefsCount > 0 )
            {
                std::printf( ",\"bodyless_defs\":%zu", bodylessDefsCount );
            }
            // R-E: the JSON twin of the XML root= below — right after the leading identifying fields.
            if( chSingleRoot ) { std::printf( ",\"root\":\"%s\"", jsonStr( cfg.roots[0] ).c_str() ); }
            std::printf( ",\"hop_tested\":%zu,\"hop_untested\":%zu", chTested.tested, chTested.untested );   // A6
            std::printf( "%s%s", pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, result.size(), pw.end,
                                        cfg.pageLimit, cfg.pageOffset, chDiscloseCap, kJsonPageSyntax ),
                         rw::graphCountFloorAttrJson( g ).c_str() );   // §H4 §3.4 — the JSON dialect's spelling of the same marker
            std::printf( ",\"%s\":[", tag );
            printJsonSymbolRows( ing, result, pw.begin, pw.end, chRootPrefix, &chTested.testReach );
            std::printf( "]}" );
            return 0;
        }

        // §P10.6: defs= = resolved definitions this name matched (matches.size()) — the rows below UNION the
        // neighbors of every def, which --uses/--impact already disclose and these two verbs silently hid.
        std::printf( "<%s of=\"%s\" defs=\"%zu\" count=\"%zu\"%s", tag, ex( sym ).c_str(), matches.size(), result.size(), chRootAttr.c_str() );
        if( !wantCallers && bodylessDefsCount > 0 )
        {
            std::printf( " bodyless_defs=\"%zu\"", bodylessDefsCount );
        }
        std::printf( "%s", chTested.xmlAttr.c_str() );   // A6: hop_tested=/hop_untested=
        std::printf( "%s%s>", pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, result.size(), pw.end,
                                    cfg.pageLimit, cfg.pageOffset, chDiscloseCap ),
                     rw::graphCountFloorAttrXml( g ).c_str() );
        rw::writeMultiRootTable( stdout, ing );   // M12: the roots list this element's own root= cannot carry
        for( std::size_t i = pw.begin; i < pw.end; ++i )
        {
            const Symbol&           s  = ing.symbols[ result[i] ];
            const std::string_view  rp = chSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], chRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            // A6: tested="1" only (never a literal 0) — the same absence-meaningful convention tested=
            // already follows everywhere else (serialize.h/verbs_for.h), so an untested row costs 0 bytes.
            std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"%s%s/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line,
                         macroRoleAttr( s.kind ), rw::isTestedByReach( ing, chTested.testReach, result[i] ) ? " tested=\"1\"" : "" );
        }
        std::printf( "</%s>", tag );
        return 0;
    }
    return std::nullopt;
}

std::optional<int> runGraphQuery( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         gqSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  gqRootPrefix = gqSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();

    // --graph-query=EXPR (ABS-5): composable node-set operators over the call graph — a FIXED, closed set
    // (sources name()/all; filters kind/cx/fanin/file/layer; bounded transitive-closure callers()/callees(); set
    // joins and/or/not). NOT a Datalog engine. Evaluates to a deterministic sorted node-set, serialized like
    // --callers so the agent can compose questions the fixed verbs did not pre-anticipate.
    if( !cfg.graphQuery.empty() )
    {
        query::Eval         ev( ing, g, cfg.graphQuery );
        std::vector<NodeId> result = ev.run();
        if( !ev.ok )
        {
            std::fprintf( stderr, "ripwire: --graph-query: %s\n", ev.err.c_str() );
            return 1;
        }
        // §P0.5b: a name() literal matching NO indexed symbol is a typo — refuse it the way the eleven other
        // symbol-taking verbs do, with the shared did-you-mean. Only the literal is judged: a name that does
        // resolve while the composed query legitimately selects nothing still reports count="0" below.
        if( !ev.unresolvedNames.empty() )
        {
            const std::string& missingName = ev.unresolvedNames.front();
            std::fprintf( stderr, "%s\n", withDidYouMean( ing, missingName,
                          "ripwire: --graph-query: name(\"" + missingName + "\") matches no symbol in the indexed tree" ).c_str() );
            return 1;
        }
        // Rank the matched set by importance (PageRank) so a BROAD query leads with what matters, and cap it
        // to --top-k (default 200). A node-set query like kind(all,fn) can match the whole graph; emitting all
        // of it is a token bomb, so we never dump more than --top-k and report the true total. Order is
        // (rank desc, id asc) — the id tie-break makes the top-K deterministic, exactly as the default map.
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this listing IS PageRank-ordered
        const std::size_t        total = result.size();
        std::sort( result.begin(), result.end(), [ & ]( NodeId a, NodeId b )
                   {
            if( rank[a] != rank[b] ) { return rank[a] > rank[b];
}
            return a < b; } );
        // §P15/§P16: result is now a real, deterministically-ordered (rank desc, id asc) row list — --limit
        // overrides the --top-k display cap exactly like --graph-query's siblings' packTopN/effectiveRowCap
        // composition, and --offset finally pages past it. count= stays the un-windowed total, unaffected by
        // either — a floor over the modelled graph, never an exhaustive one (counts_floor=, V3 L-4).
        const int         gqHistCap = cfg.topK > 0 ? cfg.topK : int( total );
        const PageWindow  gqPw      = pageWindow( total, effectiveRowCap( cfg.pageLimit, gqHistCap ), cfg.pageOffset );
        const std::size_t keep      = gqPw.end - gqPw.begin;

        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §H4 §3.4 / V3 M-1: --graph-query is the SIXTH surface that counts off this same call graph — its
        // `callers(name("X"),1)` reports the identical number --callers does — and it shipped the marker on
        // neither. That is the §B4 echo-site shape src/graphlegend.h's own header indicts, so the shared
        // constants land here too rather than a sixth wording.
        std::printf( "<!-- ripwire graph-query: a fixed-operator node-set query over the call graph (sources "
                     "name/all; filters kind/cx/fanin/file/layer; bounded closure callers/callees; joins and/or/not), "
                     "ranked by importance + capped at the top-k limit (default 200); narrow the query or raise top-k for more. NOT Datalog. "
                     "%s%s-->", rw::graphCountDisclosure().c_str(), rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str() );
        // §P8 vocabulary (see src/pageview.h, THE TRUNCATION VOCABULARY): count= is the true total and
        // shown= the --top-k slice, but capped= was missing — so a caller reading a 200-row answer had to
        // know the default top-k to tell a complete result from a truncated one. Rule 3: the bit is always
        // emitted alongside shown=, so "no capped attribute" is never something a parser must interpret.
        char gqAb[ kPageDisclosureCap ];
        const std::string gqRootAttr = gqSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();
        std::printf( "<query expr=\"%s\" count=\"%zu\"%s%s%s%s>",
                     ex( cfg.graphQuery ).c_str(), total,
                     pageDisclosure( gqAb, sizeof( gqAb ), keep, total, gqPw.end, cfg.pageLimit, cfg.pageOffset, true ),
                     rw::graphCountFloorAttrXml( g ).c_str(), gqRootAttr.c_str(), rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ).c_str() );
        for( std::size_t ri = gqPw.begin; ri < gqPw.end; ++ri )
        {
            const NodeId            c  = result[ ri ];
            const Symbol&           s  = ing.symbols[c];
            const std::string_view  rp = gqSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], gqRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>",
                         symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
        }
        std::printf( "</query>" );
        return 0;
    }
    return std::nullopt;
}

// §P10.2: --uses' selector-parsing seam, factored out so the file:name fix adds a new small symbol
// instead of growing the already-hot runUses. fileQualified excludes a canonical id ("::") — that was
// never a use-site match key and stays byte-identical. siteMatchName filters sites (name-only, can't
// split per-def); suggestName is the NAME half for did-you-mean (--expand/--outline's Lane H rule), so a
// "file:" prefix never again poisons the suggester (the constant "srcmut_sigchange" bug). defsOfName is the
// un-narrowed def count for the disclosure attribute — meaningful only when fileQualified.
struct UsesSelector { bool fileQualified; std::string_view siteMatchName; std::string_view suggestName; std::size_t defsOfName; };
inline UsesSelector resolveUsesSelector( const rw::IngestResult& ing, std::string_view sym, std::size_t defsCount )
{
    UsesSelector u;
    if( !sym.empty() && sym.front() == '@' )
    {
        // @FILE:LINE line-seed: the site scan matches NAMES, so the seed must rebind to the innermost
        // enclosing definition's name — pre-fix the raw @-spec was the match key and every site vanished
        // into a silent count="0" (atcheck (13b)). fileQualified=true so the call-role sites narrow to the
        // seed's own def (usesChosenCallers), exactly the file:name semantics the seed is sugar for.
        const rw::AtSeed seed = rw::resolveAtSeed( ing, sym.substr( 1 ) );
        if( seed.fault == rw::AtFault::None )
        {
            const std::string& seedName = ing.symbols[ seed.chain.back() ].name;
            u.fileQualified = true;
            u.siteMatchName = seedName;
            u.suggestName   = seedName;
            u.defsOfName    = rw::resolveAllByName( ing, seedName ).size();
            return u;
        }
        // faulted seed: leave the (unmatchable) spec as the key so defs and sites stay empty and the
        // qualified-refusal arm fires — selectorFaultClause's @-arm speaks the diagnosis. Never external="1".
        u.fileQualified = true;
        u.siteMatchName = sym;
        u.suggestName   = sym;
        u.defsOfName    = 0;
        return u;
    }
    u.fileQualified = sym.find( "::" ) == std::string_view::npos && sym.find( ':' ) != std::string_view::npos;
    std::string_view file;
    if( u.fileQualified )
    {
        rw::splitQualifiedSpec( sym, file, u.siteMatchName );
    }
    else
    {
        u.siteMatchName = sym;
    }
    rw::splitQualifiedSpec( sym, file, u.suggestName );
    u.defsOfName = u.fileQualified ? rw::resolveAllByName( ing, u.siteMatchName ).size() : defsCount;
    return u;
}

// §A6b: the file:name qualifier must narrow the ANSWER, not just the label. Pre-fix it narrowed defs= alone,
// so --uses=src/notes.h:empty and --uses=src/scipoverlay.h:empty returned byte-identical 1211-row sets — the
// selector looked honoured and was not. What CAN be narrowed soundly is the CALL role: a call site's resolved
// target is exactly what the call graph already records, so "keep the call sites whose enclosing symbol has a
// resolved edge to one of the chosen defs" is --callers' own narrowing read in the other direction — same
// relation, same evidence, no new guess. read/write/import/extends carry no resolution at all (a Reference
// holds a NAME), so they stay name-matched and the header says so.
//
// Returns a per-enclosing-symbol flag array (indexed by NodeId), never a set of sites: the ONE pass over
// ing.references that collects sites then tests membership in O(1), instead of re-walking the graph per site.
inline std::vector<char> usesChosenCallers( const rw::IngestResult& ing, const rw::Graph& g, std::span<const rw::NodeId> defs )
{
    using namespace rw;
    std::vector<char> isChosenCaller( ing.symbols.size(), 0 );
    const auto*       ro = g.inEdges.rowOffsets();
    const auto*       ci = g.inEdges.colIndices();
    for( NodeId def : defs )
    {
        if( def >= ing.symbols.size() )
        {
            continue;
        }
        for( std::uint32_t k = ro[def]; k < ro[def + 1]; ++k )
        {
            if( NodeId c = ci[k]; c < isChosenCaller.size() )
            {
                isChosenCaller[c] = 1;
            }
        }
    }
    return isChosenCaller;
}

// ONE use-site row: (file, line, role, enclosing canonical id). File scope ⇒ `in` empty.
struct UseSite { std::uint32_t fileId; std::uint32_t line; rw::RefRole role; std::string in; };

// The use-site scan: references whose NAME matches the selector and that carry a real use-site role. Markdown
// doc-mentions / wikilinks and HAS-A compose edges are NOT name use-sites (excluded). Returns the rows in the
// deterministic emission order (file path, line, role, enclosing-id) plus `callSitesOfName` — the call-role
// total BEFORE the §A6b narrowing, which is what the disclosure attribute reports.
//
// M12: `rootForId` is fielduses.h's OWN `rootForId` convention (`singleRoot ? root : {}`) — the caller's
// single-root spelling, or empty on multi-root/no-root (canonicalIdForEmit's own degrade then emits the
// stored, already-labeled spelling verbatim). Before this parameter existed, `in` was built from the RAW
// ing.files[...] path, so a relative-root run's in_id carried a leading "./" (`in_id="./src/eval.h::…"`)
// that never matched the row's own root-relative p=, the map's id=, or a git path — the M6/L1/M0-5 finding.
inline std::pair<std::vector<UseSite>, std::size_t>
collectUseSites( const rw::IngestResult& ing, const UsesSelector& sel, std::span<const char> isChosenCaller,
                 std::string_view rootForId = {} )
{
    using namespace rw;
    std::vector<UseSite> sites;
    std::size_t          callSitesOfName = 0;
    for( const Reference& r : ing.references )
    {
        if( r.calleeName != sel.siteMatchName )
        {
            continue;
        }
        if( r.isCompose || r.isDocLink )
        {
            continue; // type edge / doc mention — not a use-site
        }
        if( r.lang == Lang::Markdown )
        {
            continue; // markdown [[wikilink]] — not a code use-site
        }
        if( r.role == RefRole::Call )
        {
            ++callSitesOfName;
        }
        // the file: qualifier's call-role narrowing. A file-scope call site (fromSymbol==kNoNode) carries no
        // resolved edge to test, so it cannot be SHOWN to reach the chosen def and is dropped with the rest —
        // call_sites_of_name= keeps the size of what was dropped visible.
        if( sel.fileQualified && r.role == RefRole::Call && ( r.fromSymbol >= isChosenCaller.size() || !isChosenCaller[r.fromSymbol] ) )
        {
            continue;
        }
        std::string in;
        if( r.fromSymbol != kNoNode && r.fromSymbol < ing.symbols.size() )
        {
            in = canonicalIdForEmit( ing, ing.symbols[ r.fromSymbol ], rootForId );   // M12: root-relative, no leading "./"
        }
        sites.push_back( { r.fileId, r.line, r.role, std::move( in ) } );
    }

    // LB-G (r10 §5): TIER before path, filter.h's shared key — `--uses=bulk_create` was 207 django rows
    // in whatever sequence the directory names happened to fall in.
    const std::vector<std::uint8_t> tierOfFile = rw::pathTierIndexOver( ing, sites, [ ]( const UseSite& u ) { return u.fileId; } );
    std::sort( sites.begin(), sites.end(), [ & ]( const UseSite& a, const UseSite& b )
               {
        if( const int c = rw::compareTierThenPath( ing, tierOfFile, a.fileId, b.fileId ); c != 0 ) { return c < 0;
}
        if( a.line   != b.line ) {   return a.line < b.line;
}
        if( a.role   != b.role ) {   return std::uint8_t( a.role ) < std::uint8_t( b.role );
}
        return a.in < b.in; } );
    return { std::move( sites ), callSitesOfName };
}

// §A6b(ii): the refusal for a file: qualifier that names a file defining nothing of that name. Pre-fix --uses
// ANSWERED such a selector — with the name-wide site set and external="1" — so the one spelling that is
// certainly a mistake got the most confident-looking answer, while --callers/--impact/--edit-check all
// refused it. The sibling prefix ("symbol not found:") is kept verbatim because that is what an agent greps
// for; what is added is the list of files that DO define the name, so the retry is one paste away.
//
// §B4.2: that MESSAGE now lives in selectorrefuse.h and every SYM-taking verb speaks it — this arm is what
// it was generalized FROM, so what stays here is only the exit code. The wording is unchanged (a file-list
// cap with an explicit remainder is the one addition, shared by all six arms).
inline int refuseUsesFileQualifier( const rw::IngestResult& ing, std::string_view sym, const UsesSelector& )
{
    std::fprintf( stderr, "%s\n", rw::selectorNotFoundMessage( ing, "ripwire: --uses symbol not found: ",
                                                                sym, "--uses=" ).c_str() );
    return 1;
}

// §P8 G1 — --uses was the one verb that disclosed NOTHING: it accepted --limit/--offset, ignored both, and
// carried no shown=/capped= either, so a 118-site listing looked the same as a 3-site one to a parser. It
// pages now, with NO display cap: completeness is this verb's whole contract, so a bare --uses must keep
// printing every site (discloseCap=false, byte-identical un-paginated) and only an explicit --limit windows.
std::optional<int> runUses( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         usSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  usRootPrefix = usSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  usEsc;
    const std::string  usRootAttr   = usSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], usEsc ) ) + "\"" ) : std::string();

    // --uses=SYM (ABS-3): the use-site index for SYM — the resolvable places its name is referenced, with a
    // §H4 note: NOT "complete". The index is a FLOOR (counts_floor=, src/graphlegend.h), and the word this
    // comment used to carry is the same absolutism the legend shipped for eight rounds.
    // ROLE (call/read/write/import/extends) and p="file:line", plus the enclosing symbol. Reference-name-based
    // (same heuristic level as the call edges), so a BARE name shared by several symbols reports the union of
    // all their use-sites. external="1" when SYM has NO in-corpus definition at all. §P10.2/§A6b: SYM also
    // accepts "file:name" (resolveUsesSelector) — that narrows defs= AND the call-role sites (usesChosenCallers);
    // the other roles stay name-matched, and defs_of_name=/call_sites_of_name= disclose both gaps.
    // Deterministic: use-sites sorted by (file path, line, role, enclosing-id); every value XML-escaped.
    if( !cfg.usesSym.empty() )
    {
        const std::string_view sym = cfg.usesSym;

        // resolveAllByNameQualified — the SAME resolver --callers/--impact/--expand/--path use — so --uses
        // finally accepts "file:name" too; byte-identical to the old resolveAllByName on a bare name/id.
        const std::vector<NodeId> defs = resolveAllByNameQualified( ing, sym );
        const UsesSelector        sel  = resolveUsesSelector( ing, sym, defs.size() );

        // member-variable round (card A3): ONE resolved field takes the per-site path (fielduses.h — the renderer
        // the MCP twin returns); a bare field name declared by several owners refuses with the Owner.field
        // spellings; a member selector on an unserved language refuses by language name. One arm, one branch.
        if( const std::optional<int> memberExit = memberUsesArm( ing, g, defs, sym, usSingleRoot, cfg.roots[ 0 ], cfg.pageLimit, cfg.pageOffset ); memberExit )
        {
            return *memberExit;
        }

        // §A6b(iii): external="1" is the claim "this name has NO definition in the indexed tree" — it may only
        // be made when that is what was measured. With a file: qualifier defs= is a NARROWED count, so the
        // un-narrowed defs_of_name= is the one that can license the claim; pre-fix a non-defining qualifier
        // printed external="1" beside defs_of_name="3", which says the opposite in the same element.
        const bool external = defs.empty() && sel.defsOfName == 0;
        VERIFY( !( external && sel.defsOfName > 0 ) );

        // §A6b(i): the call sites that resolve to the CHOSEN defs (empty ⇒ nothing narrows, every role stays
        // name-matched, and the un-qualified output is byte-identical).
        const std::vector<char> isChosenCaller = sel.fileQualified ? usesChosenCallers( ing, g, defs ) : std::vector<char>{};

        // the sorted use-sites, plus the un-narrowed call-role total the disclosure reports.
        const auto [ sites, callSitesOfName ] = collectUseSites( ing, sel, isChosenCaller,
                                                                 usSingleRoot ? std::string_view( cfg.roots[0] ) : std::string_view{} );

        // §A6b(ii): a file: qualifier naming a file with NO definition of the name is a WRONG SELECTOR — its
        // three siblings all refuse it, and so does this one now.
        if( defs.empty() && sel.fileQualified )
        {
            return refuseUsesFileQualifier( ing, sym, sel );
        }

        // r27-emitters T3 / §P10.2: external="1" is a real answer, a typo is not — distinguished by the
        // sites, not the defs. The message states only what defs.empty() proves (no indexed definition),
        // never "no reference site" (sites ignores any file: qualifier, so its emptiness isn't a property
        // of the typed selector — the old wording was also false whenever the file:name bug this fixes
        // made defs wrongly empty for a selector that DID resolve).
        if( defs.empty() && sites.empty() )
        {
            std::fprintf( stderr, "%s\n", withDidYouMean( ing, sel.suggestName,
                          "ripwire: --uses selector matched no indexed definition: " + std::string( sym ) ).c_str() );
            return 1;
        }

        // §A6b: the qualifier disclosure, built once for both emitters. defs_of_name= is the un-narrowed DEF
        // count; narrowed_roles="call" names which roles the qualifier actually narrowed and call_sites_of_name=
        // is that role's un-narrowed total, so "how much did the qualifier drop" is arithmetic, not a guess.
        const std::string selectorAttrs = sel.fileQualified
            ? " defs_of_name=\"" + std::to_string( sel.defsOfName ) + "\" narrowed_roles=\"call\" call_sites_of_name=\"" + std::to_string( callSitesOfName ) + "\""
            : std::string{};

        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §P8 G1: the page window over the sorted sites; count= stays the un-windowed total (note above
        // runUses) — of the sites the extractor RESOLVED, which counts_floor= is there to say (V3 L-4).
        // LB-G: a DEFAULT cap on the SITE unit (pageview.h kUseSiteRowCap), and discloseCap is the
        // answer's own capped state — the callers arm's reasoning verbatim.
        const PageWindow  upw      = pageWindow( sites.size(), effectiveRowCap( cfg.pageLimit, rw::kUseSiteRowCap ), cfg.pageOffset );
        const std::size_t pageRows = upw.end - upw.begin;
        const bool        usDiscloseCap = pageRows < sites.size();
        // §H4 §3.4 item 2: the opener is shared with the MCP twin (src/graphlegend.h) — the two were
        // byte-identical copies of a sentence that promised "every use-site of SYM", which the qualified-call
        // round proved false and which a name-based static reference index cannot make true.
        std::printf( "%s"
                     "Reference-name-based (same heuristic level as call edges) — verify in source if a name is overloaded. "
                     "external=\"1\" ⇒ SYM has no definition in the indexed tree under ANY spelling (stdlib/third-party) — "
                     "never merely none in the file you qualified with (that spelling refuses instead). "
                     "A \"file:name\" SYM narrows defs= AND the role=\"call\" sites, which are kept only where the call RESOLVES to a "
                     "chosen def (the callers verb's own narrowing, read the other way, so the two agree); read/write/import/extends carry no "
                     "resolution and stay name-matched across every def sharing the name. narrowed_roles= names what narrowed, and "
                     "defs_of_name=/call_sites_of_name= (file: qualifier only) are the un-narrowed totals. "
                     "%s%s-->%s%s", rw::kUsesLegendOpen,
                     rw::capLegendClause( rw::computePageDisclosure( pageRows, sites.size(), upw.end,
                                                                    cfg.pageLimit, cfg.pageOffset, usDiscloseCap ).active ),
                     rw::graphCountDisclosure().c_str(), rw::rootRelPathsLegend( usSingleRoot ),
                     // M12: same multi-root roots-table disclosure --callers/--callees gained.
                     rw::multiRootTableLegend( ing.rootLabels.size() >= 2 ) );
        char              upab[ kPageDisclosureCap ];
        const char* const upage    = pageDisclosure( upab, sizeof( upab ), pageRows, sites.size(), upw.end, cfg.pageLimit, cfg.pageOffset, usDiscloseCap );

        // --format=columnar (RESEARCH lever 1): the use-site rows as a path-table + parallel arrays.
        if( cfg.columnar )
        {
            std::vector<std::uint32_t> ufiles, ulines;
            std::vector<RefRole>       uroles;
            std::vector<std::string>   uins;
            ufiles.reserve( pageRows ); ulines.reserve( pageRows ); uroles.reserve( pageRows ); uins.reserve( pageRows );
            for( std::size_t i = upw.begin; i < upw.end; ++i )
            { const UseSite& u = sites[i];  ufiles.push_back( u.fileId ); ulines.push_back( u.line ); uroles.push_back( u.role ); uins.push_back( u.in ); }
            // §B1.1: std::string composition, not a fixed `char attrbuf[]` — the 512-byte buffer here cut
            // `of=` mid-value (invalid XML at exit 0) once the echoed symbol name passed ~480 chars, which
            // a markdown SECTION heading reaches routinely. Same shape as runImpact / the callers arm.
            const std::string attr = "of=\"" + ex( sym ) + "\" defs=\"" + std::to_string( defs.size() )
                                   + "\" external=\"" + ( external ? "1" : "0" ) + "\" count=\"" + std::to_string( sites.size() ) + "\""
                                   + selectorAttrs + usRootAttr + upage + rw::graphCountFloorAttrXml( g );   // §H4 §3.4
            emitColumnarUseSites( stdout, ing, attr, ufiles, ulines, uroles, uins, usRootPrefix );
            return 0;
        }

        std::printf( "<uses of=\"%s\" defs=\"%zu\" external=\"%d\" count=\"%zu\"%s%s%s%s>",
                     ex( sym ).c_str(), defs.size(), external ? 1 : 0, sites.size(), selectorAttrs.c_str(), usRootAttr.c_str(), upage,
                     rw::graphCountFloorAttrXml( g ).c_str() );
        rw::writeMultiRootTable( stdout, ing );   // M12: the roots list this element's own root= cannot carry
        for( std::size_t siteIndex = upw.begin; siteIndex < upw.end; ++siteIndex )
        {
            const UseSite&          u  = sites[ siteIndex ];
            const std::string_view  rp = usSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ u.fileId ], usRootPrefix ) : std::string_view( ing.files[ u.fileId ] );
            std::printf( "<u role=\"%s\" p=\"%s:%u\"", refRoleTag( u.role ), ex( rp ).c_str(), u.line );
            // §P8 collision: `in=` means three things tool-wide — enclosing NAME (--grep/--match/--lint),
            // fan-in COUNT (--for/--pack-task/--exemplar), and here the enclosing symbol's canonical ID. The
            // first two are load-bearing and stay; this one had ZERO consumers, so it is the one that moves.
            // `in_id=` keeps the "enclosing" sense while saying it is an ID, per the index-vs-count rule.
            if( !u.in.empty() )
            {
                std::printf( " in_id=\"%s\"", ex( u.in ).c_str() );
            }
            std::printf( "/>" );
        }
        std::printf( "</uses>" );
        return 0;
    }
    return std::nullopt;
}

// ── lane/safe-delete: --safe-delete=SYM — "can I delete this?" answered as FACTS, never a verdict ──────
//
// Composes four signals this tool already computes elsewhere, over ONE already-resolved selector, instead
// of a new analysis: the transitive blast radius (rw::transitiveCallers, --impact's own walk), every
// read/write/import/call/extends use-site (resolveUsesSelector/collectUseSites, --uses' own machinery,
// called verbatim — this verb never takes the file: qualifier --uses does, so the selector is always
// name-wide), whether an indexed test transitively reaches the symbol and how much of its blast radius
// does too (the same forward test-seed BFS computeQMetrics's tested= column runs, re-derived locally here
// rather than reached through MainDispatch's testedPtr — that pointer is null unless --metrics/--for/
// --exemplar is ALSO given, and a single-symbol BFS has nothing to amortize against that gate), and
// dead-code candidacy (--dead-code's own high-confidence shape — sourceHasStaticToken/deadCodeEligibleKind
// above — asked about one already-resolved definition instead of the whole tree).
//
// The legend --safe-delete prints, hoisted out of runSafeDelete for the reason situ.h states of
// kTestGateLegend: it is a paragraph, not control flow, and its three conditional clauses are decisions
// ABOUT THE DOCUMENT, not about the walk that produced it.
//
// 2026-09-02 (lane B, density round): the legend was 2,433 B of own prose ahead of a 376 B payload on a
// one-caller symbol. Three clauses now follow the same rule the quality-delta legend does — a definition is
// emitted when the thing it defines is in the document. The defs union caveat prints only when defs really
// is above one; the ambiguity caveat only when a caller in THIS document is ambiguous; and risk= gets the
// sentence for the value this run reports rather than a glossary of all three, because a reader needs their
// own verdict spelled out, not the other two. The shared graphCountDisclosure() tail is untouched, byte for
// byte: test/floormarkcheck.sh arm (4) pins it across seven other verbs and a private shorter copy here
// would be exactly the dialect divergence that gate exists to catch.
//
// §G4: an XML comment may never contain the literal byte pair "--", so every sibling-verb mention below is
// spelled WITHOUT its leading flag dashes (impact/uses/callers/dead-code) — the one departure from how this
// file's prose comments spell them elsewhere.
inline void emitSafeDeleteLegend( std::size_t defCount, std::size_t ambiguousCallers, std::string_view risk, bool singleRoot )
{
    std::printf( "<!-- ripwire safe-delete: composes signals the tool already computes into one \"can I delete this?\" READ "
                "— never a verdict. defs= is resolveAllByNameQualified's match count, exactly as the impact/uses/callers "
                "verbs already disclose it. callers= is the 1-hop caller count (the callers verb's own walk over defs' "
                "in-edges); impact_reaches= is the FULL transitive blast radius (the impact verb's own walk); uses= is every "
                "read/write/import/call/extends SITE of the name (the uses verb's own walk), reference-name-based, so an "
                "overloaded name unions every definition's sites. All three are counts_floor= FLOORS, never totals — see "
                "COUNTING UNIT below. tested_self= is 1 when an indexed test transitively CALLS this symbol (the tested= "
                "lens; a test symbol itself is never counted, matching the metrics/for/exemplar verbs' rule), and "
                "radius_tested= plus radius_untested= partition impact_reaches= by that same lens — radius_untested= equal "
                "to impact_reaches= means NOTHING downstream is covered by an indexed test, the strongest signal here. "
                "dead_code_candidate= is 1 ONLY when this selector resolves to exactly ONE definition and it is the "
                "dead-code verb's own high-confidence shape (a source free function, non-header, internal/static linkage, "
                "zero direct callers); a 0 never means \"in use\", only that this narrow detector's preconditions do not "
                "hold here — run the dead-code verb for the full-corpus scan. ambiguous_callers= counts callers whose OWN "
                "outgoing calls include at least one that resolved to more than one candidate definition (g.ambOut, the "
                "same counter a ranked row's amb= reads). %s%srisk= NAMES what was found, never a go/no-go verdict, and "
                "this run reports %s%s-->%s",
                // The union caveat, only when there is a union to caveat.
                defCount > 1
                    ? "defs= is above 1 here, so EVERY count in this element UNIONS more than one physical definition "
                      "sharing this name. "
                    : "",
                // The ambiguity caveat, only when a caller in this document actually is ambiguous. With the count at
                // zero there is no row to be careful about, and the warning describes nothing on screen.
                ambiguousCallers > 0
                    ? "That is a caveat that one of the callers below MAY be reaching a different same-named definition, "
                      "never proof that this one is (such a caller row carries amb=K, K its ambiguous calls, the map row's amb=); read the source if which-target "
                      "matters. "
                    : "",
                // One risk= value, the one in force. A verdict a reader has to look up in a glossary of three is a
                // marker string legible only to whoever wrote it.
                  risk == "none-found"
                      ? "none-found: zero callers AND zero uses — an ABSENCE of evidence, never evidence of absence. "
                  : risk == "untested-radius"
                      ? "untested-radius: callers or uses exist, and NONE of the transitive blast radius is test-covered. "
                      : "uses-exist: callers or uses exist, and at least part of the radius is test-covered. ",
                rw::graphCountDisclosure().c_str(), rw::rootRelPathsLegend( singleRoot ) );
}

// risk= NAMES what was found, never a go/no-go verdict: "none-found" (zero 1-hop callers AND zero use
// sites of any role — an ABSENCE of evidence, never evidence of absence: dynamic dispatch, callbacks and
// unindexed macros contribute no edge either, same as every call-graph surface here), "untested-radius"
// (callers/uses exist and NONE of the transitive blast radius is test-covered), or "uses-exist" (callers/
// uses exist and at least part of the radius is tested).
std::optional<int> runSafeDelete( const MainDispatch& d )
{
    using namespace rw;
    const Config&        cfg = d.cfg;
    const IngestResult&  ing = d.ing;
    const Graph&         g   = d.g;

    if( cfg.safeDeleteSym.empty() )
    {
        return std::nullopt;
    }

    // file:name disambiguates like --around/--lego/--edit-check/--impact/--uses/--callers.
    const std::vector<NodeId> defs = resolveAllByNameQualified( ing, cfg.safeDeleteSym );
    if( defs.empty() )
    {
        // §B4.2: the shared did-you-mean refusal every SYM-taking verb speaks (selectorrefuse.h).
        std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --safe-delete symbol not found: ",
                                                               cfg.safeDeleteSym, "--safe-delete=" ).c_str() );
        return 1;
    }

    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool        sdSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string sdRootPrefix = sdSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    const auto         sdPathRel   = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return sdSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ fileId ], sdRootPrefix ) : std::string_view( ing.files[ fileId ] );
    };

    // 1-hop callers: the --callers walk (in-edges), unioned over every def this selector matched.
    std::vector<char>   sdSeenCaller( ing.symbols.size(), 0 );
    std::vector<NodeId> callerIds;
    {
        const auto* ro = g.inEdges.rowOffsets();
        const auto* ci = g.inEdges.colIndices();
        for( NodeId def : defs )
        {
            if( def >= ing.symbols.size() )
            {
                continue;
            }
            for( std::uint32_t k = ro[def]; k < ro[def + 1]; ++k )
            {
                if( NodeId c = ci[k]; c < sdSeenCaller.size() && !sdSeenCaller[c] ) { sdSeenCaller[c] = 1; callerIds.push_back( c ); }
            }
        }
    }
    std::sort( callerIds.begin(), callerIds.end(), [ & ]( NodeId a, NodeId b )
    {
        const Symbol& sa = ing.symbols[a];  const Symbol& sb = ing.symbols[b];
        if( sa.fileId != sb.fileId )
        {
            return ing.files[sa.fileId] < ing.files[sb.fileId];
        }
        return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name;
    } );

    // transitive blast radius: the --impact walk, verbatim.
    const std::vector<NodeId> reach = rw::transitiveCallers( g, defs );

    // every use-site: the --uses walk, verbatim. Always a bare-name selector (fileQualified is only ever
    // set by resolveUsesSelector when SYM itself carries a file: prefix, which still works here — --uses'
    // own selector grammar, unchanged).
    const UsesSelector        sel            = resolveUsesSelector( ing, cfg.safeDeleteSym, defs.size() );
    const std::vector<char>   isChosenCaller = sel.fileQualified ? usesChosenCallers( ing, g, defs ) : std::vector<char>{};
    const auto                sitesPair      = collectUseSites( ing, sel, isChosenCaller,
                                                                 sdSingleRoot ? std::string_view( cfg.roots[0] ) : std::string_view{} );
                                                                                               // .second (the un-narrowed
                                                                                               // call-site total) is not read here;
                                                                                               // .in_id is unused on this verb too, root
                                                                                               // threaded anyway so a future reader of
                                                                                               // sites gets the correct spelling for free
    const std::vector<UseSite>& sites        = sitesPair.first;

    // tested= lens: an indexed test transitively CALLS the symbol — the identical rule computeQMetrics
    // applies for --metrics/--for/--exemplar (a test symbol is a SEED, never a covered production row
    // itself), re-derived here rather than reached through MainDispatch's testedPtr for the reason in the
    // header comment above. A6: the seed loop + forwardReach + exclusion now live in graph.h's
    // testSymbolForwardReach/isTestedByReach — --impact/--callers share this exact pair too.
    const std::vector<char> testReach = rw::testSymbolForwardReach( ing, g );
    const auto isTested = [ & ]( NodeId n ) -> bool { return rw::isTestedByReach( ing, testReach, n ); };

    bool testedSelf = false;
    for( NodeId def : defs )
    {
        if( isTested( def ) ) { testedSelf = true; break; }
    }
    std::size_t radiusTested = 0;
    for( NodeId n : reach )
    {
        if( isTested( n ) ) { ++radiusTested; }
    }
    const std::size_t radiusUntested = reach.size() - radiusTested;

    // dead-code candidacy: --dead-code's own high-confidence shape, asked about ONE already-resolved
    // definition. Only meaningful at defs=1 — a contract is per definition site (same reasoning
    // --edit-check's overload fold states) — so a multi-def selector withholds the claim rather than
    // guessing which definition it would apply to.
    bool deadCodeCandidate = false;
    if( defs.size() == 1 && callerIds.empty() )
    {
        const Symbol& only = ing.symbols[ defs[0] ];
        if( deadCodeEligibleKind( ing, only ) )
        {
            std::FILE* file = std::fopen( diskPath( ing, only.fileId ).c_str(), "rb" );
            if( file )
            {
                std::fseek( file, 0, SEEK_END );
                const long byteCount = std::ftell( file );
                std::fseek( file, 0, SEEK_SET );
                std::string source;
                if( byteCount > 0 )
                {
                    source.resize( std::size_t( byteCount ) );
                    const std::size_t bytesRead = std::fread( source.data(), 1, std::size_t( byteCount ), file );
                    source.resize( bytesRead );
                }
                std::fclose( file );
                deadCodeCandidate = sourceHasStaticToken( source, only.sigStartByte, only.sigEndByte );
            }
        }
    }

    // amb=: callers whose OWN outgoing calls include at least one that resolved to more than one candidate
    // definition (g.ambOut, the identical per-symbol counter a map row's amb= reads) — a caveat that ONE of
    // the callers below may in fact be reaching a DIFFERENT same-named definition, never proof that this
    // one is. Disclosed in aggregate on the root and per-row below (read the source if which-target
    // matters — the same limit --edit-check/--for's amb= already carry).
    std::size_t ambiguousCallers = 0;
    for( NodeId c : callerIds )
    {
        if( c < g.ambOut.size() && g.ambOut[c] > 0 ) { ++ambiguousCallers; }
    }

    const bool  anyEvidence = !callerIds.empty() || !sites.empty();
    const char* risk        = !anyEvidence                                    ? "none-found"
                            : ( !reach.empty() && radiusTested == 0 )         ? "untested-radius"
                            :                                                   "uses-exist";

    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    // §G4: an XML comment may never contain the literal byte pair "--", so every sibling-verb mention below
    // is spelled WITHOUT its leading flag dashes (impact/uses/callers/dead-code, never --impact/--uses/
    // --callers/--dead-code) — the one departure from how this file's prose comments spell them elsewhere.
    //
    // 2026-09-02 (lane B, density round): this legend was 2,433 B of own prose ahead of a 376 B payload on a
    // one-caller symbol. Two sections now follow the SAME rule the quality-delta legend does — a definition
    // is emitted when the thing it defines is in the document. The defs union caveat is printed only when
    // defs really is above one, and risk= gets the sentence for the value THIS run reports rather than all
    // three, because a reader needs their own verdict spelled out, not a glossary of the other two. The
    // shared graphCountDisclosure() tail is untouched, byte for byte: test/floormarkcheck.sh pins it across
    // seven other verbs and a private shorter copy here would be exactly the dialect divergence it exists
    // to catch.
    emitSafeDeleteLegend( defs.size(), ambiguousCallers, risk, sdSingleRoot );

    const Symbol&      lead = ing.symbols[ defs[0] ];   // resolveAllByNameQualified walks ascending id — defs[0] is the
                                                        // lowest, same convention --impact/--uses/--callers's of=/defs=
                                                        // pairing relies on for orientation when defs > 1.
    const PageWindow   cw   = pageWindow( callerIds.size(), effectiveRowCap( cfg.pageLimit, 40 ), cfg.pageOffset );
    char               cab[ kPageDisclosureCap ];
    const std::string  sdRootAttr = sdSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();
    std::printf( "<safe-delete sym=\"%s\" t=\"%s\" p=\"%s:%u\" defs=\"%zu\" callers=\"%zu\" ambiguous_callers=\"%zu\" "
                "impact_reaches=\"%zu\" uses=\"%zu\" tested_self=\"%d\" radius_tested=\"%zu\" radius_untested=\"%zu\" "
                "dead_code_candidate=\"%d\" risk=\"%s\"%s%s%s>",
                ex( cfg.safeDeleteSym ).c_str(), symTag( lead.kind ), ex( sdPathRel( lead.fileId ) ).c_str(), lead.line,
                defs.size(), callerIds.size(), ambiguousCallers, reach.size(), sites.size(), testedSelf ? 1 : 0,
                radiusTested, radiusUntested, deadCodeCandidate ? 1 : 0, risk,
                pageDisclosure( cab, sizeof( cab ), cw.end - cw.begin, callerIds.size(), cw.end, cfg.pageLimit, cfg.pageOffset, true ),
                rw::graphCountFloorAttrXml( g ).c_str(), sdRootAttr.c_str() );
    for( std::size_t i = cw.begin; i < cw.end; ++i )
    {
        const NodeId  callerId = callerIds[i];
        const Symbol& cs       = ing.symbols[ callerId ];
        std::printf( "<c n=\"%s\" p=\"%s:%u\"", ex( cs.name ).c_str(), ex( sdPathRel( cs.fileId ) ).c_str(), cs.line );
        if( callerId < g.ambOut.size() && g.ambOut[ callerId ] > 0 )
        {
            std::printf( " amb=\"%u\"", g.ambOut[ callerId ] );   // M15: the same COUNT a map row's amb= prints — one meaning, one unit
        }
        std::printf( "/>" );
    }
    std::printf( "</safe-delete>" );
    return 0;
}

// ── lane/paper-slice: --slice=SYM[:VAR] — statement-level def-use rows as a queryable primitive ─────────
//
// MOTIVATION: ARISE (arXiv:2605.03117) measured statement-level definition-use edges exposed as a
// queryable agent primitive at +17pp Function Recall@1 on SWE-bench Lite; this is the bounded v1
// (NAME-BASED, intra-procedural, one uniquely-resolved definition — src/slice.h owns the contract and
// its stated limits).
//
// SPEC GRAMMAR — two-phase, deterministic: the WHOLE spec is tried as a symbol selector first (bare
// --slice=SYM inventory; this is also what lets a canonical id containing "::" through unsplit), and
// only when that matches nothing is the tail after the LAST ':' read as VAR with the head as the
// selector (--slice=SYM:VAR / --slice=file:SYM:VAR). The refusal for a total miss names BOTH readings,
// because either half can be the fault.
//
// §A6a like --edit-check: a selector matching more than ONE definition is REFUSED with the spellings
// that pick one — a slice of "some overload" is an answer about a body the caller may never have meant,
// worse than no answer. editCheckGroups supplies the spellings so the two verbs cannot drift.
// ── the at flag: FILE:LINE → the enclosing-definition chain (ARISE get_enclosing_scopes parity) ────────
//
// The report half of the line-seeded addressing pair (graph.h::resolveAtSeed): bare `at` answers "what
// definitions enclose this location", and the SAME seed spelled `@FILE:LINE` in any SYM selector position
// resolves to the chain's innermost row. Everything this prints is a fact off the index plus one file read;
// a seed no indexed definition spans is REFUSED with the shared diagnosis (selectorrefuse.h), never
// answered with an empty chain — an empty success and a refusal are different claims.
std::optional<int> runAt( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;

    if( cfg.atSpec.empty() )
    {
        return std::nullopt;
    }

    const AtSeed seed = resolveAtSeed( ing, cfg.atSpec );
    if( seed.fault != AtFault::None )
    {
        std::fprintf( stderr, "ripwire: the at flag's seed '%s' named no location%s\n",
                      std::string( cfg.atSpec ).c_str(), atSeedFaultClause( ing, seed ).c_str() );
        return 1;
    }

    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    const bool         atSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  atRootPrefix = atSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    const std::string_view seedPath = atSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ seed.fileId ], atRootPrefix )
                                                   : std::string_view( ing.files[ seed.fileId ] );
    // 1-based line holding byte b: the last lineStarts entry at or before b
    const auto lineOfByte = [ & ]( std::uint32_t b ) -> std::uint32_t
    {
        const auto it = std::upper_bound( seed.lineStarts.begin(), seed.lineStarts.end(), b );
        return std::uint32_t( it - seed.lineStarts.begin() );
    };

    std::printf( "<!-- ripwire at: the ENCLOSING-DEFINITION CHAIN at one FILE:LINE seed. p= the resolved file, "
                 "l= the 1-based seed line, sym= the innermost enclosing definition's name (what the same seed "
                 "resolves to in a selector position), chain= the row count. Rows are INDEXED definitions only, "
                 "outermost first, innermost last: n= the definition's name, t= its kind tag, l= its own start "
                 "line, el= its end line (1-based, inclusive). A namespace or any construct the index does not "
                 "carry is NOT a row, so an outer scope can be absent rather than misnamed; a seed line inside no "
                 "indexed definition is refused, never served as an empty chain. The same seed composes into any "
                 "SYM selector as @FILE:LINE (callers, callees, impact, around, expand, uses, edit-check, slice, "
                 "safe-delete, path, connect) and resolves to the innermost row. -->"
                 "%s", rootRelPathsLegend( atSingleRoot ) );
    std::printf( "<at p=\"%s\" l=\"%u\" sym=\"%s\" chain=\"%zu\"",
                 ex( seedPath ).c_str(), seed.line, ex( ing.symbols[ seed.chain.back() ].name ).c_str(), seed.chain.size() );
    if( atSingleRoot )
    {
        std::printf( " root=\"%s\"", ex( cfg.roots[0] ).c_str() );
    }
    std::printf( ">" );
    for( const NodeId id : seed.chain )
    {
        const Symbol& s = ing.symbols[ id ];
        std::printf( "<s n=\"%s\" t=\"%s\" l=\"%u\" el=\"%u\"/>",
                     ex( s.name ).c_str(), symTag( s.kind ), s.line, lineOfByte( s.endByte > 0 ? s.endByte - 1 : 0 ) );
    }
    std::printf( "</at>\n" );
    return 0;
}

// The --at seed's effect on --slice's resolution (lane/tc-sliceat), in one place so runSlice reads as its
// phases. Mutates the resolution triple in place; returns the exit code when the seed REFUSES the run
// (fault, or seed-vs-spec disagreement), std::nullopt to proceed. Three cases, in order:
//   fault      → the shared at-diagnosis (selectorrefuse.h), exit 1;
//   spec is a plain identifier naming no symbol → the ARISE VARIABLE half: slice it inside the seed's
//                innermost enclosing definition (an unknown identifier still lands in the locals-listing
//                refusal downstream, never a silent inventory);
//   spec matched definitions → the seed NARROWS them to the definition(s) enclosing the seed line, the
//                innermost winning; a seed enclosed by none of them is a DISAGREEMENT, refused naming both
//                sides — a slice of a body the caller may not have meant is worse than no answer (§A6a).
inline std::optional<int> sliceApplyAtSeed( const rw::IngestResult& ing, const rw::Config& cfg, const rw::AtSeed& seed,
                                            std::vector<rw::NodeId>& matches, std::string_view& selector,
                                            std::string_view& varName )
{
    using namespace rw;

    if( seed.fault != AtFault::None )
    {
        std::fprintf( stderr, "ripwire: --slice: the at seed '%s' named no location%s\n",
                      std::string( cfg.atSpec ).c_str(), atSeedFaultClause( ing, seed ).c_str() );
        return 1;
    }

    if( matches.empty() && cfg.sliceSpec.find( ':' ) == std::string_view::npos )
    {
        matches  = { seed.chain.back() };
        varName  = cfg.sliceSpec;
        selector = std::string_view( ing.symbols[ seed.chain.back() ].name );
        return std::nullopt;
    }

    if( !matches.empty() )
    {
        NodeId narrowed = kNoNode;
        for( const NodeId chainId : seed.chain )   // outermost→innermost: the last hit is the innermost
        {
            if( std::find( matches.begin(), matches.end(), chainId ) != matches.end() )
            {
                narrowed = chainId;
            }
        }
        if( narrowed == kNoNode )
        {
            const Symbol& innermost = ing.symbols[ seed.chain.back() ];
            std::fprintf( stderr, "ripwire: --slice: the --at seed %s is inside '%s' (%s:%u), which is not among the %zu "
                                  "definition(s) '--slice=%s' matches — the seed and the spec disagree; drop one of them\n",
                          std::string( cfg.atSpec ).c_str(), innermost.name.c_str(), ing.files[ innermost.fileId ].c_str(),
                          innermost.line, matches.size(), std::string( cfg.sliceSpec ).c_str() );
            return 1;
        }
        matches = { narrowed };
    }
    return std::nullopt;
}

// ── card A4: --since=REV beside --slice — the DEPENDENCE diff against a committed tree ───────────────
//
// Lifted out of runSlice for the same reason sliceApplyAtSeed was: the verb's body is a RESOLUTION
// LADDER, and a second concern spliced into the middle of it is how that ladder stops being readable.
// Returns a value ONLY to refuse; nullopt means "nothing to do" (no --since) or "rendered, see the two
// out-parameters". src/slicediff.h owns every rule about what the diff means.
inline std::optional<int> sliceSincePrepare( const MainDispatch& d, std::string_view selector, std::string_view varName,
                                             const std::string& path, const rw::Symbol& sym, rw::slicev::SliceFam fam,
                                             const ::TSLanguage* grammar, const rw::slicev::SliceScan& scan, const std::string& src,
                                             std::string& legendOut, std::string& bodyOut, rw::slicev::SliceEmitOpts& emit )
{
    const rw::Config& cfg = d.cfg;
    if( cfg.since.empty() )
    {
        return std::nullopt;
    }
    // The diff is of the SEED VARIABLE's own statement rows, so it needs one: a bare --slice=SYM inventory
    // has no variable to have a def-use history. Refused, never silently ignored — the emptyvaluerefusecheck
    // ruling that a flag doing nothing on a run is a bug, not a no-op.
    if( varName.empty() )
    {
        std::fprintf( stderr, "ripwire: --since=%.*s beside --slice diffs ONE variable's def-use slice, and --slice=%s named no "
                              "variable — bare --slice=%s lists the sliceable locals; pick one and re-run as --slice=%s:VAR "
                              "--since=%.*s\n",
                      int( cfg.since.size() ), cfg.since.data(), std::string( selector ).c_str(),
                      std::string( selector ).c_str(), std::string( selector ).c_str(),
                      int( cfg.since.size() ), cfg.since.data() );
        return 1;
    }
    const std::string relPath = std::string( rw::sarif::rootRelativeUri( path, rw::sarif::rootPrefixOf( d.root ) ) );
    rw::slicediff::Out sd = rw::slicediff::compute( d.root, std::string( cfg.since ), relPath, sym, fam, grammar, varName,
                                                    scan, src, d.redactPtr, cfg.maxFileBytes, d.valueUses,
                                                    emit.compactLegend );
    if( !sd.ok )
    {
        std::fprintf( stderr, "%s\n", sd.err.c_str() );
        return 1;
    }
    legendOut       = std::move( sd.legend );
    bodyOut         = std::move( sd.body );
    emit.sinceLegend = &legendOut;   // the two out-parameters OWN the bytes; the emitter only borrows them
    emit.sinceBody   = &bodyOut;
    return std::nullopt;
}

std::optional<int> runSlice( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;

    if( cfg.sliceSpec.empty() )
    {
        return std::nullopt;
    }
    if( d.multiRoot )
    {
        std::fprintf( stderr, "ripwire: --slice is single-root only (it re-parses the definition's on-disk file, which a merged "
                              "multi-root graph cannot address unambiguously) — run it per root\n" );
        return 1;
    }

    // ── the two-phase spec split ───────────────────────────────────────────────────────────────────────
    std::string_view    selector = cfg.sliceSpec;
    std::string_view    varName;
    std::vector<NodeId> matches  = resolveAllByNameQualified( ing, selector );
    if( matches.empty() )
    {
        const std::size_t lastColon = cfg.sliceSpec.rfind( ':' );
        if( lastColon != std::string_view::npos && lastColon > 0 && lastColon + 1 < cfg.sliceSpec.size() )
        {
            selector = cfg.sliceSpec.substr( 0, lastColon );
            varName  = cfg.sliceSpec.substr( lastColon + 1 );
            matches  = resolveAllByNameQualified( ing, selector );
        }
    }

    // ── the line seed (lane/tc-sliceat): --at=FILE:LINE beside --slice is this verb's SEED, never a
    //    dropped competing verb (scanReportVerbPrecedence excludes the pair) — ARISE's own slicer is
    //    seeded at (file, line[, variable]), and the at machinery already owns the resolution. The
    //    @FILE:LINE selector spelling is the SAME seed in the spec position, so both carry the same
    //    disclosure; carrying BOTH spellings is two seeds and refuses (never a silent pick).
    const bool selectorAtLed = !selector.empty() && selector.front() == '@';
    const bool atSeeded      = !cfg.atSpec.empty();
    if( atSeeded && selectorAtLed )
    {
        std::fprintf( stderr, "ripwire: --slice=%s already carries an @FILE:LINE seed — one seed per run: drop --at=%s or "
                              "spell the seed once\n",
                      std::string( cfg.sliceSpec ).c_str(), std::string( cfg.atSpec ).c_str() );
        return 1;
    }

    AtSeed seed{};
    if( atSeeded )
    {
        seed = resolveAtSeed( ing, cfg.atSpec );
        if( std::optional<int> refused = sliceApplyAtSeed( ing, cfg, seed, matches, selector, varName ) )
        {
            return *refused;
        }
    }

    if( matches.empty() )
    {
        // both readings missed — refuse in the --expand compose shape, naming the grammar so the caller
        // knows the VAR half was tried too (the shared clause diagnoses the selector's own fault line)
        std::fprintf( stderr, "ripwire: --slice=%s matched no symbol (tried the whole spec as a selector, then HEAD:VAR)%s\n",
                      std::string( cfg.sliceSpec ).c_str(), rw::selectorFaultClause( ing, selector, "--slice=" ).c_str() );
        return 1;
    }

    // ── §A6a ambiguity refusal ─────────────────────────────────────────────────────────────────────────
    if( matches.size() > 1 )
    {
        const std::vector<EditCheckGroup> groups = editCheckGroups( ing, d.g, matches );
        std::string spellings;
        const std::size_t shownCount = std::min<std::size_t>( groups.size(), kEditCheckSpellingsShown );
        for( std::size_t groupIndex = 0; groupIndex < shownCount; ++groupIndex )
        {
            spellings += ( groupIndex ? ", " : "" ) + groups[ groupIndex ].spelling;
        }
        if( groups.size() > shownCount )
        {
            spellings += " (+" + std::to_string( groups.size() - shownCount ) + " more)";
        }
        const std::string varSuffix = varName.empty() ? std::string() : ( ":" + std::string( varName ) );
        std::fprintf( stderr, "ripwire: --slice: '%s' matches %zu definitions — a slice reads exactly ONE body, so an ambiguous "
                              "selector is refused, never silently narrowed. Qualify one: %s — e.g. --slice=%s%s%s\n",
                      std::string( selector ).c_str(), matches.size(), spellings.c_str(), groups[0].spelling.c_str(), varSuffix.c_str(),
                      groups.size() == 1 ? " (same-spelling overloads cannot be separated yet)" : "" );
        return 1;
    }

    const NodeId  focus = matches[0];
    const Symbol& sym   = ing.symbols[ focus ];

    // ── served-language gate — an honest refusal, never an empty success ───────────────────────────────
    const slicev::SliceFam fam = slicev::sliceFamilyOf( sym.lang );
    if( fam == slicev::SliceFam::None )
    {
        std::fprintf( stderr, "ripwire: --slice: slice not served for %s yet (served: %s) — the def-use classification is a "
                              "verified per-grammar parent-kind read, and %s's has not been built\n",
                      langTag( sym.lang ), slicev::kSliceServedList, langTag( sym.lang ) );
        return 1;
    }

    // ── read + re-parse the ONE file holding the definition ────────────────────────────────────────────
    const std::string& path = diskPath( ing, sym.fileId );
    std::string        src;
    if( std::FILE* in = std::fopen( path.c_str(), "rb" ) )
    {
        char        buf[ 4096 ];
        std::size_t n = 0;
        while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
        {
            src.append( buf, n );
        }
        std::fclose( in );
    }
    else
    {
        DEGRADED_PATH_ALERT( "slice: definition file unreadable" );
        std::fprintf( stderr, "ripwire: --slice: cannot read %s — the slice re-parses the definition's file and has nothing to walk\n", path.c_str() );
        return 1;
    }

    const ::TSLanguage* grammar = sliceGrammarForFile( path );
    slicev::SliceScan   scan    = slicev::sliceScanDefinition( src, sym, fam, grammar, varName );   // re-scanned below on a seed pre-pick
    if( !scan.parseOk )
    {
        DEGRADED_PATH_ALERT( "slice: definition re-parse failed" );
        std::fprintf( stderr, "ripwire: --slice: could not re-parse %s (grammar missing, or the indexed span no longer fits the "
                              "file — a stale index; re-run without --no-reindex or check --doctor)\n", path.c_str() );
        return 1;
    }

    // ── unknown-var refusal, offering the sliceable locals ─────────────────────────────────────────────
    if( !varName.empty() && scan.occ.empty() )
    {
        std::string locals;
        std::vector<slicev::SliceLocal> ordered = scan.locals;
        std::sort( ordered.begin(), ordered.end(), []( const slicev::SliceLocal& a, const slicev::SliceLocal& b )
                   { return a.line != b.line ? a.line < b.line : a.name < b.name; } );
        for( std::size_t localIndex = 0; localIndex < ordered.size(); ++localIndex )
        {
            locals += ( localIndex ? ", " : "" ) + ordered[ localIndex ].name;
        }
        std::fprintf( stderr, "ripwire: --slice: no occurrence of '%s' in %s — sliceable locals: %s (bare --slice=%s lists them "
                              "with first-def lines)\n",
                      std::string( varName ).c_str(), sym.name.c_str(), locals.empty() ? "(none found)" : locals.c_str(),
                      std::string( selector ).c_str() );
        return 1;
    }

    // ── the seed's variable half (lane/tc-sliceat): pre-pick, or mark the candidates ───────────────────
    // A seeded run with no VAR reads the seed LINE: exactly one sliceable local named there is the
    // paper's (file, line, variable) seed completed — pre-picked and DISCLOSED (var_from="seed"); zero
    // or several serve the inventory with the candidates marked (seed_vars= / per-row seed="1"), never a
    // guess. The disclosure record rides every seeded run, both spellings.
    slicev::SliceSeedInfo seedInfo;
    bool                  seededRun = false;
    std::string           pickedVar;                       // owns the pre-picked name (varName is a view)
    std::uint32_t         seedLine  = 0;
    if( atSeeded )
    {
        seedLine      = seed.line;
        seedInfo.spec = std::string( cfg.atSpec );
        seededRun     = true;
    }
    else if( selectorAtLed )
    {
        const AtSeed selSeed = resolveAtSeed( ing, selector.substr( 1 ) );   // the resolver already accepted this spelling
        if( selSeed.fault == AtFault::None )
        {
            seedLine      = selSeed.line;
            seedInfo.spec = std::string( selector.substr( 1 ) );
            seededRun     = true;
        }
    }
    if( seededRun && varName.empty() )
    {
        seedInfo.seedVars     = slicev::sliceSeedLineLocals( scan, seedLine );
        seedInfo.seedVarCount = seedInfo.seedVars.size();
        if( seedInfo.seedVarCount == 1 )
        {
            pickedVar            = seedInfo.seedVars.front();
            varName              = pickedVar;
            seedInfo.varFromSeed = true;
            scan                 = slicev::sliceScanDefinition( src, sym, fam, grammar, varName );   // the same scan a :VAR spec runs
        }
    }

    // ── rung 2 (lane/or-arise): the transitive cross-statement flow, when --slice-flow asks for it ─────
    // validateConfig already vetted the direction value and the flag pairings; what only THIS point can
    // know is whether the spec carried a seed VAR — the flow's one hard prerequisite.
    const bool flowActive = !cfg.sliceFlow.empty();
    if( flowActive && varName.empty() )
    {
        std::fprintf( stderr, "ripwire: --slice-flow needs a seed variable — bare --slice=%s lists the sliceable locals; pick one "
                              "and re-run as --slice=%s:VAR --slice-flow=%s\n",
                      std::string( selector ).c_str(), std::string( selector ).c_str(), std::string( cfg.sliceFlow ).c_str() );
        return 1;
    }

    slicev::SliceFlowOut  flowOut;
    slicev::SliceFlowSpec flowSpec;
    flowSpec.dir   = cfg.sliceFlow == "back" ? slicev::SliceFlowDir::Back
                   : cfg.sliceFlow == "fwd"  ? slicev::SliceFlowDir::Fwd
                                             : slicev::SliceFlowDir::Both;
    flowSpec.bound = cfg.sliceDepth > 0 ? std::uint32_t( cfg.sliceDepth ) : slicev::kSliceFlowDefaultDepth;
    if( flowActive )
    {
        flowOut      = slicev::sliceFlowCompute( scan, varName, flowSpec.dir, flowSpec.bound );
        flowSpec.out = &flowOut;
    }

    slicev::SliceEmitOpts emit;
    emit.flow          = flowActive ? &flowSpec : nullptr;
    emit.seed          = seededRun ? &seedInfo : nullptr;
    emit.compactLegend = cfg.legend == "compact";   // the ripwire.slice/v1 dialect: legend only, rows byte-identical

    std::string sinceLegend, sinceBody;             // card A4: owned here, pointed at by emit on success
    if( std::optional<int> refused = sliceSincePrepare( d, selector, varName, path, sym, fam, grammar, scan, src,
                                                        sinceLegend, sinceBody, emit ) )
    {
        return *refused;
    }
    const std::string xml = slicev::sliceBundleText( ing, d.root, focus, varName, scan, src, d.redactPtr, emit );
    std::fwrite( xml.data(), 1, xml.size(), stdout );
    return 0;
}

// ── G4 VERIFY-A-CLAIM: --verify="CLAIM" — one structured claim, a three-valued verdict, evidence inline ──
//
// The claim grammar and the verdict/limit vocabularies live in src/verify.h; test/verifycheck.sh pins the
// whole contract. This handler REUSES the sibling machinery verb-for-verb — shortestPathAny (--path),
// collectUseSites (--uses), grepCollect/grepEnrich (--grep), transitiveCallers (--impact) — because the gap
// the usage mine measured was never the data: it was that verification took a multi-call chain plus manual
// reading. The honesty split is the heart: a witness CONFIRMS; only a complete literal scan (or a printed
// witness against an absence-claim) REFUTES; every model-bounded absence is NOT-ESTABLISHED with limit=
// naming the bound. complete= is computed from the scan's own honesty bits (T1) and never co-occurs with
// counts_floor= — a false completeness claim is the worst bug this tool can ship.
std::optional<int> runVerify( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    const Graph&        g   = d.g;
    const std::string   vfFloor = rw::graphCountFloorAttrXml( g );   // M15: gauge + marker, one string for every openRoot shape (a temporary's c_str() would dangle in the honesty ternary)

    if( cfg.verifyClaim.empty() )
    {
        return std::nullopt;
    }

    const verify::Claim claim = verify::parseClaim( cfg.verifyClaim );
    if( !claim.ok )
    {
        std::fprintf( stderr, "%s\n", claim.err.c_str() );
        return 1;
    }

    // bounded evidence SAMPLE — verdicts are always computed on the FULL sets, only the printed rows
    // window; the root's disclosure pair says so per the truncation vocabulary (src/pageview.h rules 1-3).
    constexpr int kEvidenceCap = 20;

    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    // M12: --verify was the one path-emitting verb with NO root= at all — every p= below printed
    // ing.files[...] verbatim, "./src/main.cpp:986" on a relative root, while every sibling verb
    // (--callers/--uses/--path/--graph-query) strips the same leading "./" via rootRelativeUri and
    // discloses root= on its own element. Same single-root condition every other verb's root= uses.
    const bool         verSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  verRootPrefix = verSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    const std::string  verRootAttr   = verSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();
    const auto          verPathRel   = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return verSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ fileId ], verRootPrefix ) : std::string_view( ing.files[ fileId ] );
    };

    // the sibling verbs' own row grammar for symbol evidence (--path/--graph-query rows)
    const auto emitSymRow = [ & ]( NodeId n )
    {
        const Symbol& s = ing.symbols[n];
        std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( verPathRel( s.fileId ) ).c_str(), s.line );
    };

    // the FILE argument: a path substring over the indexed tree (filePathContains — the file: qualifier's
    // own rule). A claim about a file the index never saw REFUSES: no verdict about it could be a
    // measurement, and the skipped verb is where "why is it not indexed" lives.
    std::vector<char> fileFlags;
    const auto        matchFiles = [ & ]( std::string_view filePat ) -> bool
    {
        fileFlags.assign( ing.files.size(), 0 );
        bool any = false;
        for( std::size_t fileIndex = 0; fileIndex < ing.files.size(); ++fileIndex )
        {
            if( filePathContains( ing.files[ fileIndex ], filePat ) )
            {
                fileFlags[ fileIndex ] = 1;
                any = true;
            }
        }
        return any;
    };
    const auto refuseFile = [ & ]( std::string_view filePat ) -> int
    {
        std::fprintf( stderr, "ripwire: --verify file matched nothing indexed: %.*s — FILE is a path substring over the indexed tree; "
                              "files the ingest skipped are not searchable (the --skipped verb lists exactly which, with reasons)\n",
                      int( filePat.size() ), filePat.data() );
        return 1;
    };

    // the root opener, shared by every shape so the attribute ORDER is fixed: claim, shape, verdict,
    // shape-specific facts, root= (M12), limit=, then the honesty attribute (complete= XOR counts_floor=),
    // then the disclosure pair. `honesty` is exactly one of kGraphCountFloorAttrXml / " complete=\"1\"" / "".
    const auto openRoot = [ & ]( const char* verdict, const std::string& facts, const char* limit, const char* honesty, const char* pageTail )
    {
        VERIFY( std::size_t( claim.shape ) < std::size( verify::kShapeTags ) );   // the parser is the only producer, every value in range
        std::printf( "%s%s<verify claim=\"%s\" shape=\"%s\" verdict=\"%s\"%s%s", verify::kVerifyLegend,
                     rw::rootRelPathsLegend( verSingleRoot ),
                     ex( cfg.verifyClaim ).c_str(), verify::kShapeTags[ std::size_t( claim.shape ) ], verdict, facts.c_str(),
                     verRootAttr.c_str() );
        if( limit[0] != '\0' )
        {
            std::printf( " limit=\"%s\"", limit );
        }
        std::printf( "%s%s>", honesty, pageTail );
    };

    char              pab[ kPageDisclosureCap ];
    const auto        pageTailOf = [ & ]( std::size_t shownRows, std::size_t total, std::size_t windowEnd ) -> const char*
    { return pageDisclosure( pab, sizeof( pab ), shownRows, total, windowEnd, 0, 0, true ); };

    // ── calls( A , B ) — does A transitively call B (directed, name-based call graph) ────────────────
    if( claim.shape == verify::ClaimShape::Calls )
    {
        const std::vector<NodeId> srcDefs = resolveAllByNameQualified( ing, claim.arg1 );
        const std::vector<NodeId> dstDefs = resolveAllByNameQualified( ing, claim.arg2 );
        if( srcDefs.empty() || dstDefs.empty() )
        {
            const std::string_view missing = srcDefs.empty() ? claim.arg1 : claim.arg2;
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --verify symbol not found: ", missing, "--verify=" ).c_str() );
            return 1;
        }
        const std::vector<NodeId> path = rw::shortestPathAny( g, srcDefs, dstDefs );
        const std::string         facts = " from_defs=\"" + std::to_string( srcDefs.size() ) + "\" to_defs=\"" + std::to_string( dstDefs.size() ) + "\""
                                        + ( path.empty() ? std::string{} : " hops=\"" + std::to_string( path.size() - 1 ) + "\"" );
        if( !path.empty() )
        {
            openRoot( "confirmed", facts, "", vfFloor.c_str(), pageTailOf( path.size(), path.size(), path.size() ) );
            for( NodeId n : path )
            {
                emitSymRow( n );
            }
        }
        else
        {
            openRoot( "not-established", facts, verify::kLimitCallGraphFloor, vfFloor.c_str(), pageTailOf( 0, 0, 0 ) );
        }
        std::printf( "</verify>" );
        return 0;
    }

    // ── uses( SYM ) / unused( SYM ) — rides the --uses reference index (a FLOOR, and the verdicts obey it) ─
    if( claim.shape == verify::ClaimShape::Uses || claim.shape == verify::ClaimShape::Unused )
    {
        const std::string_view    sym  = claim.arg1;
        const std::vector<NodeId> defs = resolveAllByNameQualified( ing, sym );
        const UsesSelector        sel  = resolveUsesSelector( ing, sym, defs.size() );
        const std::vector<char>   isChosenCaller = sel.fileQualified ? usesChosenCallers( ing, g, defs ) : std::vector<char>{};
        const auto [ sites, callSitesOfName ]    = collectUseSites( ing, sel, isChosenCaller,
                                                                     verSingleRoot ? std::string_view( cfg.roots[0] ) : std::string_view{} );
        (void) callSitesOfName;
        if( defs.empty() && sites.empty() )
        {
            std::fprintf( stderr, "%s\n", withDidYouMean( ing, sel.suggestName,
                          "ripwire: --verify symbol not found: " + std::string( sym ) ).c_str() );
            return 1;
        }
        const bool        external = defs.empty() && sel.defsOfName == 0;
        const std::size_t total    = sites.size();
        const PageWindow  w        = pageWindow( total, kEvidenceCap, 0 );
        const std::string facts    = " defs=\"" + std::to_string( defs.size() ) + "\" external=\"" + ( external ? "1" : "0" )
                                   + "\" count=\"" + std::to_string( total ) + "\"";
        const bool        anySites = total > 0;
        const char*       verdict  = claim.shape == verify::ClaimShape::Uses ? ( anySites ? "confirmed" : "not-established" )
                                                                        : ( anySites ? "refuted"   : "not-established" );
        openRoot( verdict, facts, anySites ? "" : verify::kLimitReferenceFloor, vfFloor.c_str(),
                  pageTailOf( w.end - w.begin, total, w.end ) );
        for( std::size_t siteIndex = w.begin; siteIndex < w.end; ++siteIndex )
        {
            const UseSite& u = sites[ siteIndex ];
            std::printf( "<u role=\"%s\" p=\"%s:%u\"", refRoleTag( u.role ), ex( verPathRel( u.fileId ) ).c_str(), u.line );
            if( !u.in.empty() )
            {
                std::printf( " in_id=\"%s\"", ex( u.in ).c_str() );
            }
            std::printf( "/>" );
        }
        std::printf( "</verify>" );
        return 0;
    }

    // ── contains( FILE , "LIT" ) — the literal-scan shape, and the one that can serve a TRUE complete no ─
    if( claim.shape == verify::ClaimShape::Contains )
    {
        if( !matchFiles( claim.arg1 ) )
        {
            return refuseFile( claim.arg1 );
        }
        const GrepCollection    found = grepCollect( ing, std::string( claim.arg2 ) );
        std::vector<GrepRawHit> inFile;
        for( const GrepRawHit& r : found.raw )
        {
            if( fileFlags[ r.fileId ] )
            {
                inFile.push_back( r );
            }
        }
        const std::size_t total       = inFile.size();
        const bool        clean       = found.cleanScan();
        const PageWindow  w           = pageWindow( total, kEvidenceCap, 0 );
        const bool        windowWhole = w.begin == 0 && w.end == total;
        const bool        complete    = clean && windowWhole;   // T1: the scan's own honesty bits decide, never the verdict
        const char*       verdict     = total > 0 ? "confirmed" : ( clean ? "refuted" : "not-established" );
        const char*       limit       = ( total == 0 && !clean ) ? ( found.isBudgetReached ? verify::kLimitCollectionCeiling : verify::kLimitScanDegraded ) : "";
        const char*       honesty     = complete ? " complete=\"1\"" : ( !clean ? vfFloor.c_str() : "" );
        openRoot( verdict, " hits=\"" + std::to_string( total ) + "\"", limit, honesty, pageTailOf( w.end - w.begin, total, w.end ) );
        const std::vector<GrepHit> hits = grepEnrich( ing, std::span<const GrepRawHit>( inFile ).subspan( w.begin, w.end - w.begin ) );
        for( const GrepHit& h : hits )
        {
            std::printf( "<hit p=\"%s:%u\" in=\"%s\"><m><![CDATA[", ex( verPathRel( h.fileId ) ).c_str(), h.line, ex( h.enclosing ).c_str() );
            std::string safe;
            appendCdataSafe( h.text, safe );
            std::fwrite( safe.data(), 1, safe.size(), stdout );
            std::printf( "]]></m></hit>" );
        }
        std::printf( "</verify>" );
        return 0;
    }

    // ── defines( FILE , SYM ) — symbol-table witness first, then the literal check that can refute ────
    if( claim.shape == verify::ClaimShape::Defines )
    {
        if( !matchFiles( claim.arg1 ) )
        {
            return refuseFile( claim.arg1 );
        }
        // deliberately NO unknown-symbol refusal here: the claim is about the FILE, and "no file defines
        // this name anywhere" is a legitimate answer an agent asks for — the legend says so.
        const std::vector<NodeId> defsOfName = resolveAllByName( ing, claim.arg2 );
        std::vector<NodeId>       defsInFile;
        for( NodeId n : defsOfName )
        {
            if( fileFlags[ ing.symbols[n].fileId ] )
            {
                defsInFile.push_back( n );
            }
        }
        if( !defsInFile.empty() )
        {
            const PageWindow  w     = pageWindow( defsInFile.size(), kEvidenceCap, 0 );
            const std::string facts = " defs=\"" + std::to_string( defsInFile.size() ) + "\" defs_of_name=\"" + std::to_string( defsOfName.size() ) + "\"";
            openRoot( "confirmed", facts, "", vfFloor.c_str(), pageTailOf( w.end - w.begin, defsInFile.size(), w.end ) );
            for( std::size_t defIndex = w.begin; defIndex < w.end; ++defIndex )
            {
                emitSymRow( defsInFile[ defIndex ] );
            }
            std::printf( "</verify>" );
            return 0;
        }
        // no extracted definition — the literal check: does the name token occur in the file's bytes at
        // all? Absent under a clean scan ⇒ a COMPLETE no (the file cannot define what it never spells;
        // preprocessor token-pasting is outside the claim, like every literal claim is index-scoped).
        // Present ⇒ the extraction floor, never a refutation.
        const GrepCollection    found = grepCollect( ing, std::string( claim.arg2 ) );
        std::vector<GrepRawHit> inFile;
        for( const GrepRawHit& r : found.raw )
        {
            if( fileFlags[ r.fileId ] )
            {
                inFile.push_back( r );
            }
        }
        const std::size_t occ   = inFile.size();
        const bool        clean = found.cleanScan();
        const std::string facts = " defs=\"0\" defs_of_name=\"" + std::to_string( defsOfName.size() ) + "\" occurrences=\"" + std::to_string( occ ) + "\"";
        if( occ > 0 )
        {
            const PageWindow w = pageWindow( occ, kEvidenceCap, 0 );
            openRoot( "not-established", facts, verify::kLimitExtractionFloor, vfFloor.c_str(), pageTailOf( w.end - w.begin, occ, w.end ) );
            const std::vector<GrepHit> hits = grepEnrich( ing, std::span<const GrepRawHit>( inFile ).subspan( w.begin, w.end - w.begin ) );
            for( const GrepHit& h : hits )
            {
                std::printf( "<hit p=\"%s:%u\" in=\"%s\"><m><![CDATA[", ex( verPathRel( h.fileId ) ).c_str(), h.line, ex( h.enclosing ).c_str() );
                std::string safe;
                appendCdataSafe( h.text, safe );
                std::fwrite( safe.data(), 1, safe.size(), stdout );
                std::printf( "]]></m></hit>" );
            }
        }
        else if( clean )
        {
            openRoot( "refuted", facts, "", " complete=\"1\"", pageTailOf( 0, 0, 0 ) );
        }
        else
        {
            openRoot( "not-established", facts, found.isBudgetReached ? verify::kLimitCollectionCeiling : verify::kLimitScanDegraded,
                      vfFloor.c_str(), pageTailOf( 0, 0, 0 ) );
        }
        std::printf( "</verify>" );
        return 0;
    }

    // ── reaches( SYM , "FILE" | LAYER ) — does code there transitively CALL the target (impact-based) ─
    VERIFY( claim.shape == verify::ClaimShape::Reaches );
    const std::vector<NodeId> targetDefs = resolveAllByNameQualified( ing, claim.arg1 );
    if( targetDefs.empty() )
    {
        std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --verify symbol not found: ", claim.arg1, "--verify=" ).c_str() );
        return 1;
    }
    if( claim.arg2Quoted )
    {
        if( !matchFiles( claim.arg2 ) )
        {
            return refuseFile( claim.arg2 );
        }
    }
    else if( !query::isKnownLayerWord( claim.arg2 ) )
    {
        std::fprintf( stderr, "ripwire: --verify reaches: '%.*s' is not a built-in layer (%.*s) — quote it (\"%.*s\") to mean a FILE path substring\n",
                      int( claim.arg2.size() ), claim.arg2.data(),
                      int( std::string_view( query::kLayerVocabulary ).size() ), std::string_view( query::kLayerVocabulary ).data(),
                      int( claim.arg2.size() ), claim.arg2.data() );
        return 1;
    }
    const std::vector<NodeId> reach = rw::transitiveCallers( g, targetDefs );
    std::vector<NodeId>       witnesses;
    for( NodeId n : reach )
    {
        const std::uint32_t fileId = ing.symbols[n].fileId;
        if( claim.arg2Quoted ? bool( fileFlags[ fileId ] ) : ( builtinLayer( ing.files[ fileId ] ) != nullptr && claim.arg2 == builtinLayer( ing.files[ fileId ] ) ) )
        {
            witnesses.push_back( n );
        }
    }
    const std::string facts = " target_defs=\"" + std::to_string( targetDefs.size() ) + "\" witnesses=\"" + std::to_string( witnesses.size() ) + "\"";
    if( !witnesses.empty() )
    {
        const std::vector<NodeId> path = rw::shortestPathAny( g, witnesses, targetDefs );
        openRoot( "confirmed", facts + ( path.empty() ? std::string{} : " hops=\"" + std::to_string( path.size() - 1 ) + "\"" ),
                  "", vfFloor.c_str(), pageTailOf( path.size(), path.size(), path.size() ) );
        for( NodeId n : path )
        {
            emitSymRow( n );
        }
    }
    else
    {
        openRoot( "not-established", facts, verify::kLimitCallGraphFloor, vfFloor.c_str(), pageTailOf( 0, 0, 0 ) );
    }
    std::printf( "</verify>" );
    return 0;
}

// §P11.9: --external-surface's accumulation + row-building, pulled out of runExternalSurface so the extra
// per-REFERENCING-LANGUAGE bookkeeping (a name called from several languages, e.g. `printf` — C's stdio
// call AND Bash's builtin, used to merge into one row, summing unrelated surfaces and burying the smaller
// one) lands as a function CALL in the verb body, not another decision point inside it. Slot array indexed
// by the Lang enum (model.h; 16 values, small and POD) rather than a hashable composite key or nested map.
struct ExtSurfaceAcc  { std::uint32_t refs = 0; std::uint32_t calls = 0; };
struct ExtSurfaceName { std::string name; rw::Lang lang; std::uint32_t refs; std::uint32_t calls; };
constexpr std::size_t kExtSurfaceLangSlots = 16;   // cardinality of enum class rw::Lang (model.h)

inline rw::HashMap<std::string, std::array<ExtSurfaceAcc, kExtSurfaceLangSlots>>
accumulateExternalSurface( const rw::IngestResult& ing, const rw::HashMap<std::string, char>& defined )
{
    using namespace rw;
    // count references to names that have NO in-corpus def. We count only CALL / IMPORT / EXTENDS sites: an
    // undefined name we INVOKE / #include / derive-from is a genuine external dependency, whereas a bare
    // read/write of an undefined identifier is overwhelmingly a LOCAL variable (no symbol node), which would
    // otherwise swamp the surface with single-letter noise. `calls` is the call subset of `refs`.
    rw::HashMap<std::string, std::array<ExtSurfaceAcc, kExtSurfaceLangSlots>> ext;
    for( const Reference& r : ing.references )
    {
        if( r.isCompose || r.isDocLink )
        {
            continue; // type edge / doc mention — not a code reference
        }
        if( r.lang == Lang::Markdown )
        {
            continue; // markdown link — not a code reference
        }
        if( r.calleeName.empty() )
        {
            continue;
        }
        if( r.role == RefRole::Read || r.role == RefRole::Write )
        {
            continue; // a bare read/write ⇒ a local, not a dependency
        }
        if( defined.contains( r.calleeName ) )
        {
            continue; // DEFINED in-corpus → not external (set-difference)
        }
        const std::size_t langSlot = std::size_t( r.lang ) < kExtSurfaceLangSlots ? std::size_t( r.lang ) : 0;
        ExtSurfaceAcc& e = ext[ r.calleeName ][ langSlot ];
        ++e.refs;
        if( r.role == RefRole::Call )
        {
            ++e.calls;
        }
    }
    return ext;
}

inline std::vector<ExtSurfaceName>
buildExternalSurfaceRows( const rw::HashMap<std::string, std::array<ExtSurfaceAcc, kExtSurfaceLangSlots>>& ext )
{
    std::vector<ExtSurfaceName> names;
    names.reserve( ext.size() );
    for( const auto& [ nm, slots ] : ext )
    {
        for( std::size_t li = 0; li < kExtSurfaceLangSlots; ++li )
        {
            if( slots[li].refs )
            {
                names.push_back( { nm, rw::Lang( li ), slots[li].refs, slots[li].calls } );
            }
        }
    }
    std::sort( names.begin(), names.end(), []( const ExtSurfaceName& a, const ExtSurfaceName& b )
               {
                   if( a.refs != b.refs )
                   {
                       return a.refs > b.refs; // most-leaned-on first
                   }
                   if( a.name != b.name )
                   {
                       return a.name < b.name; // then name asc
                   }
                   return a.lang < b.lang;                          // then lang (deterministic tie-break for a split name)
               } );
    return names;
}

std::optional<int> runExternalSurface( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;

    // --external-surface (ABS-3): the set-difference DEPENDENCY SURFACE — names REFERENCED in the corpus but
    // never DEFINED in it (the stdlib / third-party the code leans on). Counts only real use-sites (call/read/
    // write/import/extends), excludes doc-mentions/compose/markdown. Deterministic: sorted by (refCount desc,
    // name asc). Every in-corpus-defined name is, by construction, excluded (that is the set-difference).
    if( cfg.externalSurface )
    {
        // in-corpus definition names (final segment), for the set-difference membership test.
        HashMap<std::string, char> defined;
        defined.reserve( ing.symbols.size() );
        for( const Symbol& s : ing.symbols )
        {
            if( s.kind != SymKind::Section )
            { // markdown headings are doc structure, not code defs
                defined.emplace( s.name, char( 1 ) );
            }
        }

        const auto ext   = accumulateExternalSurface( ing, defined );
        const auto names = buildExternalSurfaceRows( ext );

        // §P15/§P16: names is deterministically sorted (refs desc, name asc, lang asc — buildExternalSurfaceRows
        // above). --pack-top-n was the only cap and had no --offset partner; --limit now overrides it exactly
        // like --deps' packTopN/pageLimit composition (src/serialize.h::packDeps), and --offset finally pages.
        const int         histCap = cfg.packTopN > 0 ? cfg.packTopN : int( names.size() );
        const PageWindow  extPw   = pageWindow( names.size(), effectiveRowCap( cfg.pageLimit, histCap ), cfg.pageOffset );
        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        std::printf( "<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed "
                     "tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls) -->" );
        // P2.1: --pack-top-n caps the listing; names= is the true total, shown=/capped= the printed slice.
        const std::size_t extShown = extPw.end - extPw.begin;
        char              extAb[ kPageDisclosureCap ];
        std::printf( "<external-surface names=\"%zu\"%s>", names.size(),
                     pageDisclosure( extAb, sizeof( extAb ), extShown, names.size(), extPw.end,
                                     cfg.pageLimit, cfg.pageOffset, true ) );
        for( std::size_t i = extPw.begin; i < extPw.end; ++i )
        {
            std::printf( "<x n=\"%s\" lang=\"%s\" refs=\"%u\" calls=\"%u\"/>",
                         ex( names[i].name ).c_str(), langTag( names[i].lang ), names[i].refs, names[i].calls );
        }
        std::printf( "</external-surface>" );
        return 0;
    }
    return std::nullopt;
}

std::optional<int> runPath( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         pthSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  pthRootPrefix = pthSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  pthRootEsc;
    const std::string  pthRootAttr   = pthSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], pthRootEsc ) ) + "\"" ) : std::string();

    // --path=SRC,DST: shortest directed call-path (how does SRC reach DST through calls?)
    if( !cfg.pathSpec.empty() )
    {
        const std::string_view spec  = cfg.pathSpec;
        const std::size_t       comma = spec.find( ',' );
        // §B8.2: the bare-arg-count refusal goes through the same helper as every other value refusal —
        // it used to answer `--path=zzq` with a bare "needs SRC,DST", naming neither what it got nor what
        // to type, while the flag's own kViewFlags row already carries both for the EMPTY case.
        if( comma == std::string_view::npos )
        { rw::refuseFlagValue( "--path", "two symbol names, FROM,TO", spec, "--path=main,rankGraph" );  return 1; }
        const std::string_view srcN = spec.substr( 0, comma ), dstN = spec.substr( comma + 1 );
        // F10: an EMPTY endpoint used to be RESOLVED — and the near-miss suggester, asked for the closest
        // name to "", answered with the shortest symbol in the corpus ("endpoint not found:  (did you mean
        // 'A'?)"). An empty item is not a selector; say which one is empty before anything is resolved.
        if( srcN.empty() || dstN.empty() )
        {
            std::fprintf( stderr, "%s\n", rw::emptyListItemMessage( "--path", srcN.empty() ? 1 : 2, "--path=main,rankGraph" ).c_str() );
            return 1;
        }

        // r27-emitters T4: resolve EVERY def of each endpoint, not just the lowest-id one. `--path=main,X` used
        // to bind `main` to whichever def happened to hold the lowest NodeId (a bench script, a CMake stub, a
        // fixture) and then report reachable="0" for a path that plainly exists from the real `main` — a WRONG
        // answer with no way to see why. The search below is one multi-source BFS over all src defs, so the
        // cost is unchanged (a single O(E) pass, not one BFS per def pair). `file:name` still disambiguates,
        // exactly as on --around/--lego/--callers, and the resolved endpoints are now echoed so the ambiguity
        // that remains is VISIBLE.
        const std::vector<NodeId> srcDefs = resolveAllByNameQualified( ing, srcN );
        const std::vector<NodeId> dstDefs = resolveAllByNameQualified( ing, dstN );
        if( srcDefs.empty() || dstDefs.empty() )
        {
            // §M7 (W3FIX): both endpoints resolve through resolveAllByNameQualified, i.e. the shared file:name
            // grammar, so the endpoint that missed gets the shared diagnosis (unindexed path vs wrong file half
            // vs unknown name) instead of a near-miss on the name half alone.
            const std::string_view missing = srcDefs.empty() ? srcN : dstN;
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --path endpoint not found: ",
                                                                  missing, "--path=" ).c_str() );
            return 1;
        }

        const std::vector<NodeId> path    = rw::shortestPathAny( g, srcDefs, dstDefs );   // ONE BFS over every def pair
        const NodeId              srcUsed = path.empty() ? srcDefs.front() : path.front();
        const NodeId              dstUsed = path.empty() ? dstDefs.front() : path.back();

        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        const auto        loc = [ & ]( NodeId n ) -> std::string
        { const Symbol& s = ing.symbols[n];
          const std::string_view rp = pthSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], pthRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
          return ex( rp ) + ":" + std::to_string( s.line ); };

        // from_p/to_p = the def this run actually bound the name to; from_defs/to_defs = how many it could have
        // bound it to (>1 ⇒ qualify with file:name if this is not the one you meant).
        // R-E fix (2026-08-19): --path ships no legend of its own, so the shared root-relative clause IS its
        // whole first-screen legend here — root= would otherwise be the one attribute on this document with
        // nothing anywhere saying what it means. Same text, same helper, as every other verb's.
        // H5 (capture-audit 2026-09-04): reachable="0" hops="0" is a zero read off the name-based graph — the
        // same question --verify=calls(A,B) answers `not-established` + counts_floor="1" for. Same marker,
        // same brief sentence, on both transports (mcpverbs.h path_between mirrors this line).
        std::printf( "<!-- ripwire path: one DIRECTED call path from= to to= (each <s> a hop); reachable= is 0 and hops= 0 when the "
                     "graph holds none. %s-->%s", rw::kGraphCountFloorBriefLegend, rw::rootRelPathsLegend( pthSingleRoot ) );
        std::printf( "<path from=\"%s\" to=\"%s\" from_p=\"%s\" to_p=\"%s\" from_defs=\"%zu\" to_defs=\"%zu\" reachable=\"%d\" hops=\"%zu\"%s%s",
                     ex( srcN ).c_str(), ex( dstN ).c_str(), loc( srcUsed ).c_str(), loc( dstUsed ).c_str(),
                     srcDefs.size(), dstDefs.size(),
                     path.empty() ? 0 : 1, path.empty() ? std::size_t( 0 ) : path.size() - 1, pthRootAttr.c_str(),
                     rw::graphCountFloorAttrXml( g ).c_str() );
        // P2.10: a dead end is exactly the moment to name the next verb. --path is DIRECTED; --connect searches
        // undirected and finds the shared-caller join a directed walk can never see.
        if( path.empty() )
        {
            std::printf( " hint=\"no directed call path — try --connect=%s,%s (undirected: finds a shared caller), or --uses/--impact for non-call references%s\"",
                         ex( srcN ).c_str(), ex( dstN ).c_str(),
                         ( srcDefs.size() > 1 || dstDefs.size() > 1 ) ? "; several defs share these names — qualify as file:name to pick one" : "" );
        }
        std::printf( ">" );
        for( NodeId n : path )
        {
            const Symbol&           s  = ing.symbols[n];
            const std::string_view  rp = pthSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], pthRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
        }
        std::printf( "</path>" );
        return 0;
    }
    return std::nullopt;
}

std::optional<int> runConnect( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             cnSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view cnRootArg    = cnSingleRoot ? cfg.roots[0] : std::string_view();

    // --connect=A,B,C: the minimal connecting subgraph over 2..16 task symbols — how do they RELATE, and
    // which intermediaries join them? Search is UNDIRECTED (finds the shared-caller join a directed --path
    // can't), every reported edge keeps its true caller→callee direction. packConnect (mcp.h) is the ONE
    // shared emitter, so this and the MCP `connect` verb write identical bytes.
    if( !cfg.connectSpec.empty() )
    {
        std::vector<std::string_view> specs;
        {
            std::string_view s = cfg.connectSpec;
            for( std::size_t position = 1; ; ++position )
            {
                const std::size_t comma = s.find( ',' );
                const std::string_view tok = s.substr( 0, comma );
                // F14: an empty token used to be DROPPED, so `--connect=A,B,` ran as a 2-terminal connect at
                // exit 0 — a trailing comma, or a shell variable that expanded to nothing, silently changed
                // the question. Same ruling and same sentence as --path's empty endpoint.
                if( tok.empty() )
                {
                    std::fprintf( stderr, "%s\n",
                                  rw::emptyListItemMessage( "--connect", position, "--connect=parseArgs,serialize,rankGraph" ).c_str() );
                    return 1;
                }
                specs.push_back( tok );
                if( comma == std::string_view::npos )
                {
                    break;
                }
                s.remove_prefix( comma + 1 );
            }
        }
        if( specs.size() < 2 || specs.size() > rw::connectcfg::kMaxTerminals )
        {
            std::fprintf( stderr, "ripwire: --connect needs 2..%zu comma-separated symbols (got %zu) — for a broader ranked set use --for\n",
                          rw::connectcfg::kMaxTerminals, specs.size() );
            return 1;
        }
        std::vector<NodeId> terminals;
        for( const std::string_view spec : specs )
        {
            const NodeId id = resolveFocus( ing, spec );                 // "name" or "file:name" — exactly --around/--lego
            if( id == kNoNode )
            {
                // §M7 (W3FIX): resolveFocus is the SAME file:name resolver --around/--lego use, so this arm
                // gets the same shared diagnosis rather than a bare near-miss about the name half.
                std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --connect symbol not found: ",
                                                                       spec, "--connect=" ).c_str() );
                return 1;
            }
            terminals.push_back( id );
        }
        // §B8.1: the parser now REFUSES a radius outside the band instead of letting the core clamp it
        // silently, so cli.h's domain ceiling and connectcfg's clamp band must be the same number. This is
        // the one seam where both headers are visible — the core keeps clamping (the MCP `connect` verb and
        // any other caller still hand it an unvalidated radius; a core that VERIFYs on hostile input is a
        // crash, not a guard).
        static_assert( rw::kConnectRadiusMax == int( rw::connectcfg::kMaxRadius ),
                       "--connect-radius' refusal band drifted from the core's clamp band — the refusal would name a range the core does not honor" );
        const rw::ConnectResult res = rw::connectSubgraph( g, terminals, std::uint32_t( cfg.connectRadius ) );
        rw::packConnect( stdout, ing, g, res, d.redactPtr, cfg.maxTokens, cnRootArg );
        return 0;
    }
    return std::nullopt;
}

// §P10.3 / §P8 G1 — why --impact's 40-row cap is now a DEFAULT and not a ceiling. The verb answers "is it
// safe to change X?", and it answered it with a fixed 40 rows of a radius that is routinely 100+, while
// accepting --limit/--offset and ignoring both: the one question in the tool where a silent 3%-of-the-truth
// answer is most expensive was also the one with no flag to widen it. effectiveRowCap( --limit, 40 ) keeps
// the no-flag output byte-identical and makes --limit=200 finally emit up to 200 of reaches=.
// ── LB-H (r10 §5) — --impact's THREE DIALECT EMITTERS, split out of runImpact ────────────────────────────
// One verb, three serializations. They were three inline branches inside runImpact, so the function's
// complexity and length rose every time the verb learned a fact — the import tier was the third such
// round, and --quality-delta named it. ImpactView is the ALREADY-COMPUTED answer: resolution, ranking,
// the page window and the import tier all happen ONCE in runImpact, so each emitter is a pure rendering
// of one measurement and no two of them can disagree about what was measured.
struct ImpactView
{
    const rw::IngestResult&        ing;
    std::string_view               sym;
    std::size_t                    defs;
    std::size_t                    reaches;
    const std::vector<rw::NodeId>& show;
    rw::PageWindow                 page;
    const rw::ImportTier&          imports;
    std::span<const std::uint32_t> importPage;
    std::span<const char>          importLazyPage;   // kParserVer 72: parallel to importPage
    rw::RankDisclosure             prD;
    bool                           singleRoot;
    std::string_view               rootPrefix;
    std::string_view               rootAttr;    // pre-escaped ` root="…"`, empty on a multi-root run
    std::string_view               rootRaw;     // the unescaped root, for the JSON dialect's own quoting
    int                            pageLimit;
    int                            pageOffset;
    const std::vector<char>*       testReach;      // A6: testSymbolForwardReach — never null (runImpact always computes it)
    std::size_t                    radiusTested;    // A6: |reach ∩ tested|, over the FULL (un-windowed) reach set
    std::size_t                    radiusUntested;  // A6: reaches - radiusTested
    const rw::Graph&               g;               // M15: the gauge pair (graphCountFloorAttrXml) reads ambOut/unresolvedOut
};

// --format=columnar (RESEARCH lever 1): same page window, path-table + parallel arrays.
// V1-1: a fixed 160-byte buffer truncated mid-attribute on long escaped symbol names (invalid XML, the
// F6 class), and this branch hand-rolled shown=/capped= without the paging half — the one
// pageDisclosure() sibling the §A4c rollout missed. std::string kills the truncation class outright.
// LB-H: this form has ONE row shape (the symbol arrays), so the import tier is present as its COUNT
// only — never silently absent, and the legend says which shape the reader holds. Its shown_/capped
// pair is omitted with the rows it would describe: pageview.h rule 3 pairs them, and a disclosure of a
// listing that was not emitted is noise, not honesty.
int emitImpactColumnar( const ImpactView& v )
{
    using namespace rw;
    std::vector<char>       esc;
    char                    ipab[ kPageDisclosureCap ];
    const std::size_t       shownRows = v.page.end - v.page.begin;
    std::vector<NodeId>     rows( v.show.begin() + v.page.begin, v.show.begin() + v.page.end );
    const std::string       attr = "of=\"" + std::string( escapeXml( v.sym, esc ) ) + "\" defs=\"" + std::to_string( v.defs )
                                 + "\" reaches=\"" + std::to_string( v.reaches ) + "\""
                                 + " importers=\"" + std::to_string( v.imports.files.size() ) + "\""
                                 + " radius_tested=\"" + std::to_string( v.radiusTested )       // A6
                                 + "\" radius_untested=\"" + std::to_string( v.radiusUntested ) + "\""
                                 + std::string( v.rootAttr )
                                 + pageDisclosure( ipab, sizeof( ipab ), shownRows, v.show.size(), v.page.end,
                                                   v.pageLimit, v.pageOffset, true )
                                 + rw::graphCountFloorAttrXml( v.g )                              // §H4 §3.4
                                 + rw::renderDisclosure( v.prD, rw::DiscloseAs::XmlAttrs );  // W2-F
    emitColumnarSymbolRows( stdout, v.ing, "impact", attr.c_str(), rows, v.rootPrefix, v.testReach );
    return 0;
}

// L2: --json — same set, keys mirror the XML attr names (of/defs/reaches/shown/capped/t/n/p).
// §A4c: shown/capped came from a hand-rolled pair that never grew the paging half, so a JSON caller
// walking --offset had no has_more/next_offset to terminate on. The JSON row of pageDisclosure()'s syntax
// table emits the same seven fields the XML tag emits (discloseCap=true — this verb DOES have a 40-row
// display cap of its own). LB-H rides it as booleans where the XML says 0/1, the dialect rule this
// element already follows for capped=/counts_floor=, and import_reach is a SECOND array rather than rows
// folded into "impact": the JSON consumer sees the same two-tier shape and cannot sum them by accident.
int emitImpactJson( const ImpactView& v )
{
    using namespace rw;
    char ipab[ kPageDisclosureCap ];
    const std::size_t shownRows = v.page.end - v.page.begin;
    std::printf( "{\"of\":\"%s\",\"defs\":%zu,\"reaches\":%zu", jsonStr( v.sym ).c_str(), v.defs, v.reaches );
    std::printf( ",\"importers\":%zu,\"shown_importers\":%zu,\"importers_capped\":%s",
                 v.imports.files.size(), v.imports.shown, v.imports.capped ? "true" : "false" );
    std::printf( ",\"radius_tested\":%zu,\"radius_untested\":%zu", v.radiusTested, v.radiusUntested );   // A6
    if( v.singleRoot ) { std::printf( ",\"root\":\"%s\"", jsonStr( v.rootRaw ).c_str() ); }   // R-E
    std::printf( "%s%s%s,\"impact\":[",
                 pageDisclosure( ipab, sizeof( ipab ), shownRows, v.show.size(), v.page.end,
                                 v.pageLimit, v.pageOffset, true, kJsonPageSyntax ),
                 rw::graphCountFloorAttrJson( v.g ).c_str(),                                                // §H4 §3.4
                 rw::renderDisclosure( v.prD, rw::DiscloseAs::JsonKeys ).c_str() );           // W2-F: ONE keyset
    printJsonSymbolRows( v.ing, v.show, v.page.begin, v.page.end, v.rootPrefix, v.testReach );
    std::printf( "],\"import_reach\":[" );
    rw::emitImportRowsJson( stdout, v.ing, v.importPage, v.rootPrefix, v.importLazyPage );
    std::printf( "]}" );
    return 0;
}

// The default XML form. reaches= is the un-windowed reach-set size — the blast radius the INDEXED graph
// can see, which counts_floor= discloses is a floor (V3 L-4). LB-H: the import tier follows the symbol
// rows under its OWN tag, because it is a different unit — an <s> is a symbol that provably names SYM, an
// <f> is a file that names SYM's FILE — and a reader (or a parser) counting <s> rows must not pick it up.
int emitImpactXml( const ImpactView& v )
{
    using namespace rw;
    std::vector<char> esc;
    const auto        ex        = [ & ]( std::string_view t ) -> std::string { return std::string( escapeXml( t, esc ) ); };
    char              ipab[ kPageDisclosureCap ];
    const std::size_t shownRows = v.page.end - v.page.begin;
    std::printf( "<impact of=\"%s\" defs=\"%zu\" reaches=\"%zu\"%s radius_tested=\"%zu\" radius_untested=\"%zu\"%s%s%s%s>",
                 ex( v.sym ).c_str(), v.defs, v.reaches, v.imports.xmlAttrs.c_str(), v.radiusTested, v.radiusUntested,
                 std::string( v.rootAttr ).c_str(),
                 pageDisclosure( ipab, sizeof( ipab ), shownRows, v.show.size(), v.page.end,
                                 v.pageLimit, v.pageOffset, true ),
                 rw::graphCountFloorAttrXml( v.g ).c_str(), rw::renderDisclosure( v.prD, rw::DiscloseAs::XmlAttrs ).c_str() );
    for( std::size_t i = v.page.begin; i < v.page.end; ++i )
    {
        const Symbol&          s  = v.ing.symbols[ v.show[i] ];
        const std::string_view rp = v.singleRoot ? rw::sarif::rootRelativeUri( v.ing.files[ s.fileId ], v.rootPrefix )
                                                 : std::string_view( v.ing.files[ s.fileId ] );
        // A6: tested="1" only (never a literal 0) — see kTestedRowLegend.
        std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"%s/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line,
                     rw::isTestedByReach( v.ing, *v.testReach, v.show[i] ) ? " tested=\"1\"" : "" );
    }
    rw::emitImportRowsXml( stdout, v.ing, v.importPage, v.rootPrefix, v.importLazyPage );
    std::printf( "</impact>" );
    return 0;
}

std::optional<int> runImpact( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         imSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  imRootPrefix = imSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  imEsc;
    const std::string  imRootAttr   = imSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], imEsc ) ) + "\"" ) : std::string();

    // --impact=SYM: transitive blast radius — every symbol that (transitively) reaches SYM via calls
    if( !cfg.impactSym.empty() )
    {
        // X9(b): "file:name" disambiguates here too (same rule as --around/--lego/--edit-check).
        const std::vector<NodeId> seeds = resolveAllByNameQualified( ing, cfg.impactSym );
        if( seeds.empty() )
        {
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --impact symbol not found: ",
                                                                   cfg.impactSym, "--impact=" ).c_str() );   // §B4.2
            return 1;
        }
        const std::vector<NodeId> reach = rw::transitiveCallers( g, seeds );
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure  prD{ prIters, prConverged, true };   // W2-F: the listing is PageRank-ordered
        std::vector<NodeId>       show  = reach;
        std::sort( show.begin(), show.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );

        // A6 (survey card A6, agent-lsp): tested/untested partition of the blast radius, over the FULL
        // un-windowed reach set (not just the shown page) — the same isTestSymbol-seeded lens --safe-delete's
        // radius_tested=/radius_untested= already name (README:1025), never re-derived.
        const std::vector<char> imTestReach     = rw::testSymbolForwardReach( ing, g );
        const std::size_t       imRadiusTested   = rw::countTestedIn( ing, imTestReach, reach );
        const std::size_t       imRadiusUntested = reach.size() - imRadiusTested;
        // ── LB-H (r10 §5): the IMPORT tier — every file that directly imports a file defining SYM. ONE
        // measurement (graph.h::impactImportTier) feeds all three dialects AND the MCP twin, so the two
        // surfaces cannot drift. The two reaches stay separate all the way to the bytes: a separate count
        // (importers=), a separate truncation pair (shown_importers=/importers_capped=, pageview.h rule 6)
        // and a separate row tag.
        const rw::ImportTier imports        = rw::impactImportTier( ing, seeds );
        const auto           importPage     = std::span<const std::uint32_t>( imports.files ).first( imports.shown );
        const auto           importLazyPage = std::span<const char>( imports.lazy ).first( imports.shown );

        if( !cfg.json )
        { // L2: JSON has no comment-node analogue; the XML-only leading doc comment
            // §B12.4 in-band (W3FIX): the paging clause comes from pageview.h::kPageRaiseCapClause, which
            // carries the limit="0" definition too — rule 7 existed only in --help and that header before.
            // §H4 §3.4: opener + the shared floor/counting-unit tail, both from src/graphlegend.h so the MCP
            // twin cannot drift from this wording (the §B4 echo-site class).
            // LB-H: the import-tier clause is the columnar variant under --format=columnar, because that
            // form carries the count without the rows and a reader must be told which shape they hold.
            std::printf( "%s%s. %s%s%s%s%s%s-->", rw::kImpactLegendOpen, rw::kPageRaiseCapClause,
                         cfg.columnar ? rw::kImpactImportTierColumnarLegend : rw::kImpactImportTierLegend,
                         rw::kTestedRowLegend, rw::kImpactTestedPartitionLegend,   // A6
                         rw::kTestedLensBlindSpotLegend,                           // F-02: rides with the partition
                         rw::graphCountDisclosure().c_str(), rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str() );
        }
        // P2.1 + §P8 G1: the rank-ordered listing's 40 is a DEFAULT now, not a ceiling — see the §P10.3 note
        // above runImpact; pageDisclosure emits the ` shown= capped=` bytes this verb used to hand-roll
        // (src/pageview.h, THE TRUNCATION VOCABULARY, rules 1-3). LB-G: the same NAMED constant
        // --callers/--callees use, so the family's default lives in one place instead of three literals.
        const ImpactView view{ ing, cfg.impactSym, seeds.size(), reach.size(), show,
                               pageWindow( show.size(), effectiveRowCap( cfg.pageLimit, rw::kCallHierarchyRowCap ), cfg.pageOffset ),
                               imports, importPage, importLazyPage, prD, imSingleRoot, imRootPrefix, imRootAttr,
                               imSingleRoot ? cfg.roots[0] : std::string_view(), cfg.pageLimit, cfg.pageOffset,
                               &imTestReach, imRadiusTested, imRadiusUntested, g };

        if( cfg.columnar ) { return emitImpactColumnar( view ); }
        if( cfg.json     ) { return emitImpactJson( view ); }
        return emitImpactXml( view );
    }
    return std::nullopt;
}

// §A8.4: collapseMentionsToFileRows moved to src/mention.h — the MCP `mentions` verb shares it now
// (the same section-vs-file overcount lived there; two collapses would be the §A4c clone class).

std::optional<int> runMentions( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         mnSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  mnRootPrefix = mnSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();

    // --mentions=SYM: which DOCS (markdown plans/designs) name this code symbol in a `backtick` — the doc↔code
    // link (the reverse of "what code a doc touches"). From g.mentions, built OUT of the call graph so a doc
    // mentioning a symbol never inflated its PageRank/blast-radius. Rows now collapse to one per FILE (see
    // collapseMentionsToFileRows, above): mentions= is that file's own section-mention count, l= its first
    // (lowest-line) mention; the root's docs= names the row count (distinct files), sections= the old
    // pre-collapse tally, so nothing measured is lost, just renamed honestly.
    if( !cfg.mentionsSym.empty() )
    {
        // §B11.1 — the --owners twin, same defect, same fix: the shared file:name grammar and the shared
        // refusal that names which half is at fault. A qualified spelling now NARROWS the mention scan to the
        // definitions in that file instead of being refused as an unknown symbol.
        const std::vector<NodeId> defs = resolveAllByNameQualified( ing, cfg.mentionsSym );
        if( defs.empty() )
        {
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --mentions symbol not found: ",
                                                                   cfg.mentionsSym, "--mentions=" ).c_str() );
            return 1;
        }
        std::vector<NodeId> docs;
        for( NodeId d : defs )
        {
            if( d < g.mentions.size() )
            {
                for( NodeId dn : g.mentions[d] )
                {
                    docs.push_back( dn );
                }
            }
        }
        std::sort( docs.begin(), docs.end() );  docs.erase( std::unique( docs.begin(), docs.end() ), docs.end() );
        const std::size_t           sectionCount = docs.size();
        std::vector<MentionFileRow> fileRows     = collapseMentionsToFileRows( ing, docs );

        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        std::printf( "<!-- ripwire mentions: markdown FILES that name this symbol in a `backtick` (doc<->code; NOT a call edge). "
                     "docs= is the row count (distinct files); sections= counts the underlying markdown-section mentions "
                     "before file-collapse (docs <= sections). Each row's mentions= is its own section-mention count. "
                     "An @FILE:LINE seed rebinds to the innermost definition enclosing that line — sym= names it, of= echoes the seed as typed. "
                     "No line locator: the doc edge is stored at file granularity — a fabricated always-1 l= was removed; absent beats fake -->%s", rw::rootRelPathsLegend( mnSingleRoot ) );
        // §P15/§P16: fileRows is deterministic (file path order) and printed unconditionally, no historic
        // display cap — pageWindow directly on cfg.pageLimit/cfg.pageOffset, discloseCap=false so the
        // un-paginated tag stays byte-identical.
        const PageWindow  mentionsPw = pageWindow( fileRows.size(), cfg.pageLimit, cfg.pageOffset );
        char              mentionsAb[ kPageDisclosureCap ];
        const std::string mnRootAttr = mnSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();
        // @-seed rebind disclosure: the resolver's @-tier returned the seed's ONE enclosing definition,
        // so defs[0] IS the rebound target — sym= names it while of= keeps echoing the seed as typed.
        const std::string mnSymAttr  = ( !cfg.mentionsSym.empty() && cfg.mentionsSym.front() == '@' )
                                     ? " sym=\"" + ex( ing.symbols[ defs[0] ].name ) + "\""
                                     : std::string();
        std::printf( "<mentions of=\"%s\"%s defs=\"%zu\" docs=\"%zu\" sections=\"%zu\"%s%s>", ex( cfg.mentionsSym ).c_str(), mnSymAttr.c_str(), defs.size(),
                     fileRows.size(), sectionCount,
                     pageDisclosure( mentionsAb, sizeof( mentionsAb ), mentionsPw.end - mentionsPw.begin, fileRows.size(), mentionsPw.end,
                                     cfg.pageLimit, cfg.pageOffset, false ),
                     mnRootAttr.c_str() );
        for( std::size_t rowIndex = mentionsPw.begin; rowIndex < mentionsPw.end; ++rowIndex )
        {
            const MentionFileRow&  row = fileRows[ rowIndex ];
            const std::string_view rp  = mnSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ row.fileId ], mnRootPrefix ) : std::string_view( ing.files[ row.fileId ] );
            std::printf( "<doc p=\"%s\" mentions=\"%zu\"/>", ex( rp ).c_str(), row.mentions );
        }
        std::printf( "</mentions>" );
        return 0;
    }
    return std::nullopt;
}

std::optional<int> runAround( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::vector<std::uint32_t>* fanInPtr     = d.fanInPtr;
    const std::vector<std::uint32_t>* cboPtr       = d.cboPtr;
    const std::vector<std::uint8_t>*  testedPtr    = d.testedPtr;
    const std::vector<std::uint32_t>* lcom4Ptr     = d.lcom4Ptr;
    const std::vector<std::uint32_t>* ampPtr       = d.ampPtr;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses.
    const bool             aroundSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view aroundRootArg    = aroundSingleRoot ? cfg.roots[0] : std::string_view();

    // --around=SYMBOL: emit a focused ego-graph pack (bounded k-hop neighbourhood) instead of the
    // whole-repo map — "give me the context centered on THIS symbol".
    if( !cfg.around.empty() )
    {
        const NodeId focus = resolveFocus( ing, cfg.around );
        if( focus == kNoNode )
        {
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --around symbol not found: ",
                                                                   cfg.around, "--around=" ).c_str() );   // §B4.2
            return 1;
        }
        const EgoGraph eg = egoGraph( g, focus, cfg.aroundDepth, cfg.aroundFanout );
        std::vector<float> rank( ing.symbols.size(), 0.f );
        for( std::size_t i = 0; i < eg.nodes.size(); ++i )
        {
            rank[ eg.nodes[i] ] = 1.0f / ( 1.0f + float( eg.hopDist[i] ) );   // focus + closest neighbours lead
        }
        // §F1 — the two sibling blocks --around appends after its map, RENDERED AND CHARGED before the map's
        // header states est_tokens. They were emitted straight to stdout afterwards, so this verb reported the
        // map only: MEASURED on src/, `--around=Config` = 804 B at est_tokens="262" (3.07 B/tok, outside the
        // 2.36-2.59 markup band) because a 157-byte <compose> block rode in free. Same funnel as the default
        // map's four sections and the --for lens's two, at the same rates.
        //
        // S5-E HAS-A: compose view for the ego-graph neighbourhood.
        // B6.3: HTTP-route cross-service view for the same neighbourhood.
        rw::ChargedSection aroundCompose, aroundRoutes;
        if( !g.composeEdges.empty() )
        {
            aroundCompose = rw::chargeSection( [ & ]( std::FILE* f ) { packCompose( f, ing, g.composeEdges, eg.nodes ); },
                                                rw::kBytesPerTokenDefault );
        }
        if( !g.routeEdges.empty() )
        {
            aroundRoutes = rw::chargeSection( [ & ]( std::FILE* f ) { packRoutes( f, ing, g.routeEdges, eg.nodes ); },
                                               rw::kBytesPerTokenDefault );
        }

        // §B4b — G4: serialize() owns <r>…</r> and CLOSES it, so these two sibling blocks were a SECOND
        // top-level element (`--around=buildRecall` tailed `…</r><compose>…</compose>`, xmllint rejected it,
        // ripwire exited 0). See rw::aroundNeedsCtxWrap above for the full finding and the wrapper rule.
        // Trap #8 ("a disclosure has BYTES"): the 11 wrapper bytes are charged at the markup rate, like the
        // sections they enclose.
        const rw::CtxWrap wrap = rw::ctxWrapFor( aroundCompose, !g.composeEdges.empty(),
                                                   aroundRoutes,  !g.routeEdges.empty() );

        if( wrap.isNeeded )
        {
            std::fputs( "<ctx>", stdout );
        }

        // M20: --around renders through the shared map serializer, so its root used to be the PLAIN map
        // root — no of=, no depth=, no fanout=. The seed and the two bounds that decide what the
        // neighbourhood contains now ride on it (serialize.h::MapAnnotations::SeedDisclosure).
        rw::MapAnnotations aroundAnn;
        aroundAnn.seed = { ing.symbols[ focus ].name, cfg.aroundDepth, cfg.aroundFanout, definitionCountOfName( ing, focus ) };

        serialize( stdout, ing, rank, g.outOff, g.outTargets, int( eg.nodes.size() ), cfg.mostImportantLast, cfg.metrics, fanInPtr, &g.ambOut, false, g.outProv.empty() ? nullptr : &g.outProv, cboPtr, testedPtr, lcom4Ptr, ampPtr, &g.unresolvedOut, g.bindLabel.empty() ? nullptr : &g.bindLabel, /*autoOrder=*/false, /*outEstTokens=*/nullptr, aroundCompose.tokens + aroundRoutes.tokens + wrap.tokens, aroundAnn, /*statsFirstScreen=*/false, aroundRootArg, &g.locPinOut, g.externalCalls );

        if( !g.composeEdges.empty() )
        {
            rw::emitChargedSection( stdout, aroundCompose, [ & ]{ packCompose( stdout, ing, g.composeEdges, eg.nodes ); } );
        }
        if( !g.routeEdges.empty() )
        {
            rw::emitChargedSection( stdout, aroundRoutes, [ & ]{ packRoutes( stdout, ing, g.routeEdges, eg.nodes ); } );
        }

        if( wrap.isNeeded )
        {
            std::fputs( "</ctx>", stdout );
        }
        return 0;
    }
    return std::nullopt;
}

}   // namespace — verbs_navigate.h section of main.cpp
