#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_astquery.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_astquery.h — the narrow-parse query services, moved VERBATIM from ingest.cpp in the
// 2026-08-29 split: the --match/--lint shared AST-query pass (capture text + predicate evaluation,
// the per-file newline-offset index, grouped query compilation, the did-you-mean node-kind hints,
// astQueryGrouped/astQuery and the grammar-applicability disclosure), the pattern surface's grammar
// census (supportedPatternGrammars/eligiblePatternFiles), the R-H span tiers (spanTiersOfFiles),
// the unreachable-code walk behind the built-in lint rule, and collectGatedLocalNames. These are
// rw-level services other TUs reach through ingest.h — they sat AFTER ingest() outside the unnamed
// namespace, so unlike the other sections this one reopens `namespace rw` alone and is included at
// the very END of ingest.cpp, exactly where its content sat. Same RIPWIRE_INGEST_TU guard: any
// includer other than ingest.cpp is a compile error.

namespace rw
{

// text of a capture (first node with this index) in a match; false if absent / out of range.
inline bool captureText( const TSQueryMatch& m, std::uint32_t capIndex, std::string_view src, std::string& out )
{
    for( std::uint16_t i = 0; i < m.capture_count; ++i )
    {
        if( m.captures[i].index == capIndex )
        {
            const TSNode n = m.captures[i].node;
            const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
            if( a <= b && b <= src.size() ) { out = std::string( src.substr( a, b - a ) ); return true; }
            return false;
        }
    }
    return false;
}

// evaluate a pattern's query predicates against a match — #eq? / #not-eq? (string/capture equality) and
// #match? / #not-match? (ECMAScript regex). ts_query never applies these itself; without this, #eq? is a no-op.
inline bool passesPredicates( const TSQuery* q, const TSQueryMatch& m, std::string_view src )
{
    std::uint32_t pc = 0;
    const TSQueryPredicateStep* steps = ts_query_predicates_for_pattern( q, m.pattern_index, &pc );
    const auto argText = [ & ]( const TSQueryPredicateStep& s, std::string& out ) -> bool
    {
        if( s.type == TSQueryPredicateStepTypeCapture )
        {
            return captureText( m, s.value_id, src, out );
        }
        if( s.type == TSQueryPredicateStepTypeString )
        {
            std::uint32_t l = 0;
            const char* v = ts_query_string_value_for_id( q, s.value_id, &l );
            out.assign( v, l );
            return true;
        }
        return false;
    };
    for( std::uint32_t i = 0; i < pc; )
    {
        std::vector<TSQueryPredicateStep> pr;
        for( ; i < pc && steps[i].type != TSQueryPredicateStepTypeDone; ++i )
        {
            pr.push_back( steps[i] );
        }
        ++i;                                                            // skip the Done step
        if( pr.size() < 3 || pr[0].type != TSQueryPredicateStepTypeString )
        {
            continue;
        }
        // TWO statements, deliberately. Written as ONE — `string_view( f( …, &nl ), nl )` — the length
        // argument `nl` and the call that WRITES it are two arguments of the SAME call, and the order in
        // which a call's arguments are evaluated is UNSPECIFIED. GCC on x86-64 evaluates them right-to-left,
        // so it read `nl` while it was still 0: `op` came out EMPTY, matched none of the operator names
        // below, and every #eq?/#not-eq?/#match?/#not-match? predicate was silently skipped (`ok` stays
        // true ⇒ nothing filtered). GCC on aarch64 and Clang everywhere evaluate left-to-right and happened
        // to get it right, which is why this only ever reddened on x86-64 Linux/gcc — measured 2026-08-02:
        // g++-13 -O0 AND -O2 on x86-64 print len=0, the same g++-13 on aarch64 and clang-18 on x86-64 print
        // len=6. Sequencing the write before the read IS the fix; do not re-inline these two lines.
        std::uint32_t nl     = 0;
        const char*   opText = ts_query_string_value_for_id( q, pr[0].value_id, &nl );
        if( opText == nullptr )
        {
            continue; // no operator name ⇒ can't evaluate ⇒ don't filter
        }
        const std::string_view op( opText, nl );
        std::string lhs, rhs;
        if( !argText( pr[1], lhs ) || !argText( pr[2], rhs ) )
        {
            continue; // can't evaluate → don't filter
        }
        bool ok = true;
        if( op == "eq?" )
        {
            ok = ( lhs == rhs );
        }
        else if( op == "not-eq?" )
        {
            ok = ( lhs != rhs );
        }
        else if( op == "match?" || op == "not-match?" )
        { try { const bool mm = std::regex_search( lhs, std::regex( rhs ) ); ok = ( op == "match?" ) ? mm : !mm; } catch( ... ) { ok = true; } }
        if( !ok )
        {
            return false;
        }
    }
    return true;
}

// ---- per-file newline-offset index → O(log n) 1-based line lookup (A4 perf) ----
// Replaces the per-capture "scan [0,startByte) counting '\n'" (byte-0 rescan, O(startByte) EACH match)
// with one O(fileBytes) pass + a binary search per capture. Byte-identical result:
//   line(b) = 1 + (# of '\n' at offset < b) = 1 + lower_bound(offsets, b) position.
// The pass itself rides rw::findByte (src/infra/fixedStr.h) — a NEON/SSE2 find-'\n' kernel that is EXACT, so the
// offsets are bit-identical to the byte-at-a-time loop this replaced and determinism is untouched. '\r' is
// not a line break here and never was. bench/bench_newline_ab.cpp races the two against libc memchr and
// asserts all three agree byte-for-byte before it reports a number; the kernel won at ~1.4x over memchr.
inline std::vector<std::uint32_t> buildNewlineOffsets( std::string_view src )
{
PROFILE_SCOPE_DESCRIBE( "strings: buildNewlineOffsets (byte scan for newline)" );
    std::vector<std::uint32_t> off;
    const char* const          begin = src.data();
    const char*                first = begin;
    const char* const          last  = begin + src.size();
    while( first < last )
    {
        first = rw::findByte( first, last, '\n' );   // NEON/SSE2 kernel, exact — same answer as the byte loop it replaced
        if( first == last )
        {
            break;
        }
        off.push_back( std::uint32_t( first - begin ) );
        ++first;
    }
    return off;
}
inline std::uint32_t lineAtByte( const std::vector<std::uint32_t>& nlOffsets, std::uint32_t bytePos ) noexcept
{
    return std::uint32_t( 1 + ( std::lower_bound( nlOffsets.begin(), nlOffsets.end(), bytePos ) - nlOffsets.begin() ) );
}

// One AstMatch row from one [startByte,endByte) span of one file. THE single place a match's snippet is
// cut: the 120-byte cap, the UTF-8 continuation-byte back-off that stops the cut splitting a codepoint,
// and the whitespace scrub that keeps the row on one line. Shared by the query walk's capture emitter and
// by the pattern walk — two callers producing byte-different snippets for the same span would be a
// difference no reader could explain, and a second copy of this is exactly the new-clone-of-reused-helper
// shape --quality-delta flags.
inline AstMatch makeAstMatch( std::uint32_t fileId, std::string_view bytes, const std::vector<std::uint32_t>& nlOffsets,
                              std::uint32_t a, std::uint32_t b, std::string tag )
{
    PROFILE_SCOPE_DESCRIBE( "strings: capture text substr + whitespace scrub" );
    std::size_t cutLen = std::min<std::size_t>( b - a, 120u );
    if( cutLen < b - a )
    {
        while( cutLen > 0 && ( static_cast<unsigned char>( bytes[a + cutLen] ) & 0xC0 ) == 0x80 )
        {
            --cutLen;
        }
    }
    std::string text( bytes.substr( a, cutLen ) );
    for( char& ch : text )
    {
        if( ch == '\n' || ch == '\r' || ch == '\t' )
        {
            ch = ' ';
        }
    }
    return AstMatch{ fileId, a, b, lineAtByte( nlOffsets, a ), std::move( tag ), std::move( text ) };
}

// ---- shared AST-query pass (--match / --lint) ----
// One compiled query, plus the group it answers for. Grouping is a property of the QUERY, not of the walk:
// a worker executes every query a file's grammar has and files the captures into that query's own bucket.
struct GroupedQuery
{
    TSQuery*      query = nullptr;
    std::string   tag;
    std::uint32_t groupIndex = 0;
};

// Every query one grammar has to answer, in BOTH shapes. `perSpec` is one compiled query per spec, the
// literal thing each spec asked for. `combined` is all of those specs' patterns compiled into ONE query.
//
// The difference is the number of TREE WALKS. ts_query_cursor_exec walks the subtree once per query, so
// forty-odd single-pattern queries walked every C++ file forty-odd times to ask forty-odd independent
// questions of the same nodes -- and the profile put 87% of --lint's whole cost inside that loop. A query
// holding forty patterns walks once and runs them off one shared automaton; each match's `pattern_index`
// says which spec answered, so nothing about the RESULT changes.
//
// Both shapes are kept: `combined` is what the workers run, `perSpec` is the fallback if the concatenated
// source does not compile (or does not report the pattern count its parts add up to), and it also owns the
// tag and group each pattern belongs to.
struct GrammarQueries
{
    std::vector<GroupedQuery>  perSpec;
    TSQuery*                   combined = nullptr;   // nullptr = degraded to one tree walk per spec
    std::vector<std::uint32_t> patternOwner;         // combined pattern index -> index into perSpec
};

// Compile every group's specs for ONE grammar, in both shapes GrammarQueries holds. Called once per
// grammar the corpus can reach, from its own thread: the language tables it reads are immutable and each
// call touches nothing but its own result.
GrammarQueries compileGrammarQueries( const TSLanguage* g, const std::vector<AstQueryGroup>& groups )
{
    GrammarQueries gqs;
    std::string    combinedSrc;
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        if( groups[groupIndex].specs == nullptr )
        {
            continue;
        }
        for( const AstQuerySpec& spec : *groups[groupIndex].specs )
        {
            std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
            TSQuery*      q   = ts_query_new( g, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err );
            if( q == nullptr )
            {
                continue;   // this spec is not valid for this grammar -- a C++ query simply does not fire on Python
            }
            const std::uint32_t patterns = ts_query_pattern_count( q );
            for( std::uint32_t patternIndex = 0; patternIndex < patterns; ++patternIndex )
            {
                gqs.patternOwner.push_back( static_cast<std::uint32_t>( gqs.perSpec.size() ) );
            }
            gqs.perSpec.push_back( { q, spec.tag, static_cast<std::uint32_t>( groupIndex ) } );
            combinedSrc.append( spec.query );
            combinedSrc.push_back( '\n' );   // a spec may end in a `;` line comment; never let it swallow the next
        }
    }
    if( !gqs.perSpec.empty() )
    {
        std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
        TSQuery*      comb = ts_query_new( g, combinedSrc.data(), static_cast<std::uint32_t>( combinedSrc.size() ), &off, &err );
        if( comb != nullptr && ts_query_pattern_count( comb ) == static_cast<std::uint32_t>( gqs.patternOwner.size() ) )
        {
            gqs.combined = comb;
        }
        else
        {
            // Patterns that each compile alone are not GUARANTEED to compile together, and a pattern count that
            // does not add up would misattribute every tag. Either way the per-spec walks are still correct --
            // only slower -- so this degrades rather than fails.
            if( comb != nullptr )
            {
                ts_query_delete( comb );
            }
            DEGRADED_PATH_ALERT( "astQuery: combined per-grammar query did not compile - falling back to one tree walk per spec" );
        }
    }
    return gqs;
}

// octocode F3: the "compiled for no grammar" refusal (below) used to hand back the query verbatim and
// nothing else, so `(call_expresion)` — one deleted 's' away from the real `call_expression` — got no
// nearer a fix than staring at the S-expression. This is the hint: pull every token that LOOKS like a
// node-kind reference out of the failed query text, edit-distance each against the UNION of every linked
// grammar's own node-kind vocabulary (ts_language_symbol_count/name — the grammar's own runtime-exposed
// truth, never a hand-maintained list this tree would have to keep in sync), and report the closest.
//
// Candidate extraction is a plain text scan, not a second ts_query_new attempt: the query already failed to
// compile against EVERY linked grammar, so there is no successful parse to introspect. A node-kind token is
// an identifier immediately after `(` — `(call_expression ...)`, `(binary_expression left: (identifier))` —
// outside a quoted anonymous-token literal (`"+"`) and outside a `;` line comment; the bare wildcard `_`
// ("any node") is excluded, and predicates (`#eq?`) / field negation (`!decorator`) never start with an
// identifier char so they are excluded by construction, not by a special case. A FIELD name (`left:`) is
// never captured either — it precedes a `:`, never a `(`.
//
// Vocabulary: TSSymbolTypeRegular and TSSymbolTypeSupertype only — the two symbol kinds a query ever names
// bare. TSSymbolTypeAnonymous is a literal token (written as a quoted string, never a bare identifier) and
// TSSymbolTypeAuxiliary is grammar-internal machinery; suggesting either as "the kind you meant" would be
// a hint the reader could not type back into a query. Several extensions share one grammar object
// (.cpp/.cc/.cxx -> tree_sitter_cpp); each distinct TSLanguage* is walked once. When more than one grammar
// defines the same kind name, kLangTable's fixed row order decides which grammar the hint names — a pure
// function of the table, independent of HashMap iteration order.
//
// Deterministic across candidate tokens too: smaller edit distance wins, a tie breaks on the lexicographically
// smaller resulting KIND NAME — never on which candidate token or which grammar was tried first. Bandwidth
// cutoff matches didyoumean.h's own kMaxEditDistance (3): beyond that a "hint" is noise, not help, and the
// hint stays empty (the same honest "no plausible near-miss" contract as didYouMean()).
struct NodeKindHint { std::string kind; std::string grammar; };   // both empty ⇒ no candidate was close enough

static std::vector<std::string> extractCandidateNodeKinds( std::string_view query )
{
    std::vector<std::string> out;
    bool inString = false;
    for( std::size_t i = 0; i < query.size(); ++i )
    {
        const char c = query[i];
        if( inString )
        {
            if( c == '\\' ) { ++i; continue; }   // escape: skip the escaped byte, same rule astQueryShape uses
            if( c == '"' ) { inString = false; }
            continue;
        }
        if( c == '"' ) { inString = true; continue; }
        if( c == ';' )   // line comment: everything to end-of-line is inert
        {
            while( i + 1 < query.size() && query[i + 1] != '\n' ) { ++i; }
            continue;
        }
        if( c != '(' )
        {
            continue;
        }
        std::size_t j = i + 1;
        while( j < query.size() && std::isspace( static_cast<unsigned char>( query[j] ) ) )
        {
            ++j;
        }
        if( j >= query.size() || !( std::isalpha( static_cast<unsigned char>( query[j] ) ) || query[j] == '_' ) )
        {
            continue;   // "(#eq?" / "(!decorator" / "(\"literal\"" — none of these is a node-kind token
        }
        const std::size_t start = j;
        while( j < query.size() && ( std::isalnum( static_cast<unsigned char>( query[j] ) ) || query[j] == '_' ) )
        {
            ++j;
        }
        std::string tok( query.substr( start, j - start ) );
        if( tok != "_" && std::find( out.begin(), out.end(), tok ) == out.end() )
        {
            out.push_back( std::move( tok ) );
        }
    }
    return out;
}

static NodeKindHint nearestNodeKindHint( std::string_view query )
{
    NodeKindHint hint;
    const std::vector<std::string> candidates = extractCandidateNodeKinds( query );
    if( candidates.empty() )
    {
        return hint;   // nothing that even looks like a node-kind token (e.g. a bare syntax error)
    }

    // The union of every linked grammar's own vocabulary, first-grammar-in-table-order wins per name.
    HashMap<std::string_view, std::string_view> kindGrammar;   // node-kind name -> owning grammar's display name
    kindGrammar.reserve( 8192 );
    std::vector<const TSLanguage*> tried;
    for( const LangEntry& le : kLangTable )
    {
        if( le.grammar == nullptr || le.querySub.empty() )
        {
            continue;   // no grammar (markdown) or nothing to attribute a --match hit against
        }
        const TSLanguage* g = le.grammar();
        if( std::find( tried.begin(), tried.end(), g ) != tried.end() )
        {
            continue;   // several extensions share one grammar object
        }
        tried.push_back( g );
        const std::uint32_t symCount = ts_language_symbol_count( g );
        for( std::uint32_t s = 0; s < symCount; ++s )
        {
            const TSSymbolType ty = ts_language_symbol_type( g, static_cast<TSSymbol>( s ) );
            if( ty != TSSymbolTypeRegular && ty != TSSymbolTypeSupertype )
            {
                continue;
            }
            const char* nm = ts_language_symbol_name( g, static_cast<TSSymbol>( s ) );
            if( nm == nullptr || *nm == '\0' )
            {
                continue;
            }
            kindGrammar.try_emplace( std::string_view( nm ), le.querySub );   // first grammar in table order wins
        }
    }
    if( kindGrammar.empty() )
    {
        return hint;
    }

    constexpr int kMaxEditDistance = 3;   // same bandwidth as didYouMean()'s symbol-name cutoff
    int           bestDist = kMaxEditDistance + 1;
    for( const std::string& cand : candidates )
    {
        const std::string_view nearest = rw::nearestNameByEditDistance( kindGrammar.begin(), kindGrammar.end(), cand, kMaxEditDistance,
                                                                         []( const auto& kv ) -> std::string_view { return kv.first; } );
        if( nearest.empty() )
        {
            continue;
        }
        const int  dist   = rw::boundedEditDistance( nearest, cand, kMaxEditDistance );
        const bool better = hint.kind.empty() || dist < bestDist || ( dist == bestDist && std::string( nearest ) < hint.kind );
        if( better )
        {
            bestDist    = dist;
            hint.kind    = std::string( nearest );
            hint.grammar = std::string( kindGrammar.at( nearest ) );
        }
    }
    return hint;
}

// octocode F3: the refusal loop's own trailer, extracted so that loop's own branch count doesn't grow — a
// caller that asked for neither field pays one pointer-compare and returns, same as before this existed.
static void recordNodeKindHint( const AstQueryGroup& group, const std::string& query )
{
    if( group.nearestKindOut == nullptr && group.nearestGrammarOut == nullptr )
    {
        return;
    }
    const NodeKindHint hint = nearestNodeKindHint( query );
    if( group.nearestKindOut != nullptr )
    {
        group.nearestKindOut->push_back( hint.kind );
    }
    if( group.nearestGrammarOut != nullptr )
    {
        group.nearestGrammarOut->push_back( hint.grammar );
    }
}

// Defined further down this file, next to the rest of the unreachable-code check's helpers, and
// forward-declared here so the shared file walk can drive it — the same split as
// ingest()/astQueryGrouped() already use above.
inline void ur_walkTree( TSNode root, std::uint32_t fileId, std::string_view src, const std::vector<std::uint32_t>& nlOffsets, std::vector<AstMatch>& hits );

// Drive every BUILT-IN WALK group over one already-parsed file, each into its own bucket. Called from the
// shared worker loop with the tree and newline index the query groups are about to use, which is the whole
// point: a walk group exists so a non-query check can stop re-reading and re-parsing the corpus for itself.
// R2: one file's worth of pattern matching, kept out of runWalkGroups' dispatch body for the same reason
// ur_walkTree is — the dispatcher stays a two-line switch over walk kinds, and each walk's own logic (and
// its own reasons to grow) lives next to itself.
inline void pat_walkTree( const pattern::PatternProgramSet* set, TSNode root, std::uint32_t fileId, std::string_view bytes,
                          const std::vector<std::uint32_t>& nlOffsets, const TSLanguage* grammar, std::vector<AstMatch>& hits,
                          std::atomic<std::uint64_t>* ellipsisCappedOut )
{
    if( set == nullptr )
    {
        return;   // a Pattern group with no programs is a caller bug, but never a crash
    }
    const pattern::PatternProgram* prog = set->forGrammar( grammar );
    if( prog == nullptr )
    {
        return;   // this file's grammar is one the pattern did not resolve for — unresolved_in= says so
    }
    std::vector<std::pair<std::uint32_t, std::uint32_t>> spans;
    pattern::MatchStats                                  stats;
    pattern::findMatches( *prog, root, bytes, spans, pattern::kMaxHits, stats );
    if( ellipsisCappedOut != nullptr && stats.ellipsisCappedCount != 0 )
    {
        // Relaxed is right: nothing else is published alongside it and the only reader runs after the pool
        // has joined. Addition is associative, so the total does not depend on which worker got here first.
        ellipsisCappedOut->fetch_add( stats.ellipsisCappedCount, std::memory_order_relaxed );
    }
    for( const auto& [a, b] : spans )
    {
        if( a < b && b <= bytes.size() )
        {
            hits.push_back( makeAstMatch( fileId, bytes, nlOffsets, a, b, std::string() ) );
        }
    }
}

// `grammar` is the language THIS file was parsed with: the pattern walk needs it because one --pattern
// string compiles to a different node shape per grammar, and the wrong program against the right tree
// would silently match nothing. The unreachable-code walk ignores it (its rule is kind-name based).
inline void runWalkGroups( const std::vector<AstQueryGroup>& groups, TSNode root, std::uint32_t fileId, std::string_view bytes,
                           const std::vector<std::uint32_t>& nlOffsets, const TSLanguage* grammar, std::vector<std::vector<AstMatch>>& perGroupHits )
{
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        if( groups[groupIndex].walk == AstWalk::UnreachableCode )
        {
            ur_walkTree( root, fileId, bytes, nlOffsets, perGroupHits[groupIndex] );
        }
        else if( groups[groupIndex].walk == AstWalk::Pattern )
        {
            pat_walkTree( groups[groupIndex].patternPrograms, root, fileId, bytes, nlOffsets, grammar, perGroupHits[groupIndex],
                          groups[groupIndex].ellipsisCappedOut );
        }
    }
}

// §L3: grammar-applicability disclosure for AstQueryGroup::grammarsOut / eligibleFilesOut (see ingest.h for
// the field docs). A SEPARATE probe over the full kLangTable rather than a read of astQueryGrouped's own
// byGrammar table, because byGrammar only ever holds grammars the CORPUS is present for — exactly the
// information this exists to supply when the honest answer is "none of them" (a query that compiles fine
// for java/csharp/typescript but the corpus is Python-only). Cost is bounded by kLangTable's size (~37
// rows) per requesting group's specs, paid only when a caller asks — every existing --lint / --lint-rules
// call site leaves both fields null, so this is a no-op for them.
static void computeGrammarDisclosure( const IngestResult& ing, const std::vector<AstQueryGroup>& groups )
{
    for( const AstQueryGroup& grp : groups )
    {
        if( grp.grammarsOut == nullptr && grp.eligibleFilesOut == nullptr )
        {
            continue;
        }
        if( grp.specs == nullptr )
        {
            continue;   // a walk-only group has no query to probe grammars for
        }
        std::vector<const TSLanguage*> triedGrammars;   // dedup tracker: several extensions share one grammar
        std::vector<const TSLanguage*> okGrammars;       // grammars at least one spec in this group compiled against
        std::vector<std::string>       okNames;          // grammarsOut dedup: TWO distinct grammar OBJECTS can
                                                          // share one display NAME (tree_sitter_typescript and
                                                          // tree_sitter_tsx are both querySub "typescript"; the
                                                          // CUDA grammar reuses "cpp") — okGrammars stays one
                                                          // entry per compiling OBJECT (eligible_files needs
                                                          // every one of them), grammarsOut stays one per NAME.
        for( const LangEntry& le : kLangTable )
        {
            if( le.grammar == nullptr || le.querySub.empty() )
            {
                continue;   // no grammar (markdown) or no tags.scm surface to compile a --match query against
            }
            const TSLanguage* g = le.grammar();
            if( std::find( triedGrammars.begin(), triedGrammars.end(), g ) != triedGrammars.end() )
            {
                continue;
            }
            triedGrammars.push_back( g );
            bool compiledAny = false;
            for( const AstQuerySpec& spec : *grp.specs )
            {
                std::uint32_t off = 0; TSQueryError err = TSQueryErrorNone;
                if( TSQuery* probe = ts_query_new( g, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err ) )
                {
                    ts_query_delete( probe );
                    compiledAny = true;
                    break;
                }
            }
            if( compiledAny )
            {
                okGrammars.push_back( g );
                if( grp.grammarsOut != nullptr )
                {
                    const std::string name( le.querySub );
                    if( std::find( okNames.begin(), okNames.end(), name ) == okNames.end() )
                    {
                        okNames.push_back( name );
                        grp.grammarsOut->push_back( name );
                    }
                }
            }
        }
        if( grp.eligibleFilesOut != nullptr )
        {
            std::size_t eligible = 0;
            for( std::size_t fileId = 0; fileId < ing.files.size(); ++fileId )
            {
                const std::string ext = lowerExtensionOf( diskPath( ing, std::uint32_t( fileId ) ) );
                const LangEntry*  fle = lookupLang( ext );
                if( fle == nullptr || fle->grammar == nullptr )
                {
                    continue;
                }
                if( std::find( okGrammars.begin(), okGrammars.end(), fle->grammar() ) != okGrammars.end() )
                {
                    ++eligible;
                }
            }
            *grp.eligibleFilesOut = eligible;
        }
    }
}

std::vector<std::vector<AstMatch>> astQueryGrouped( const IngestResult& ing, const std::vector<AstQueryGroup>& groups,
                                                    std::vector<std::string>* keptBytesOut )
{
    std::vector<std::vector<AstMatch>> out( groups.size() );
    if( keptBytesOut != nullptr )
    {
        keptBytesOut->assign( ing.files.size(), std::string() );   // sized BEFORE the pool starts: workers only ever write distinct slots
    }
    bool                               anySpecs = false;
    bool                               anyWalk  = false;
    for( const AstQueryGroup& group : groups )
    {
        anySpecs = anySpecs || ( group.specs != nullptr && !group.specs->empty() );
        anyWalk  = anyWalk  || ( group.walk != AstWalk::None );
    }
    // A walk group is work even with no spec anywhere: it needs the parse, not a compiled query.
    if( ( !anySpecs && !anyWalk ) || ing.files.empty() )
    {
        return out;
    }

    // The grammars this CORPUS can actually reach. ts_query_new is not cheap -- compiling every spec
    // against every one of the sixteen linked grammars was the single largest serial cost of a `--lint`
    // run, and on a corpus holding one language fifteen sixteenths of it answered a question no file
    // could ask. A grammar with no file to run on contributes no match, so not compiling for it changes
    // nothing a caller can see -- except the "did not compile for ANY grammar" disclosure below, which is
    // a statement about the QUERY and not about the corpus, and is therefore still decided over the full
    // table.
    // The `.h` remap is deliberately conservative: whether a header is ObjC is a fact about its BYTES,
    // read per file inside the walk, so any `.h` at all admits the ObjC grammar here.
    std::vector<const TSLanguage*> presentGrammars;
    {
        bool anyCHeader = false;
        for( std::size_t fileId = 0; fileId < ing.files.size(); ++fileId )
        {
            const std::string ext = lowerExtensionOf( diskPath( ing, std::uint32_t( fileId ) ) );
            anyCHeader = anyCHeader || ext == ".h";
            const LangEntry* le = lookupLang( ext );
            if( le == nullptr || le->grammar == nullptr )
            {
                continue;
            }
            const TSLanguage* g = le->grammar();
            if( std::find( presentGrammars.begin(), presentGrammars.end(), g ) == presentGrammars.end() )
            {
                presentGrammars.push_back( g );
            }
        }
        const LangEntry* objcLe = anyCHeader ? lookupLang( ".m" ) : nullptr;
        if( objcLe != nullptr && objcLe->grammar != nullptr
            && std::find( presentGrammars.begin(), presentGrammars.end(), objcLe->grammar() ) == presentGrammars.end() )
        {
            presentGrammars.push_back( objcLe->grammar() );
        }
    }

    // Compile each spec against every DISTINCT grammar it is valid for (up front, single-threaded). Queries
    // are immutable after creation → shared read-only across workers; only the cursor is per-thread.
    // ONE GRAMMAR PER THREAD. Compiling is per-grammar independent work over read-only language tables --
    // the same assumption the ingest prewarm already makes when it launches ts_query_new off-thread -- and
    // it was the longest SERIAL stretch of a --lint run: the file walk that follows is fully parallel, so
    // a single-threaded compile set the floor on the whole verb. Results land in a vector indexed by the
    // deterministic presentGrammars order and are installed in that order afterwards, so no thread's
    // arrival time reaches the map, let alone the output.
    HashMap<const TSLanguage*, GrammarQueries> byGrammar;
    {
    PROFILE_SCOPE_DESCRIBE( "astQuery: compile queries per grammar" );
    std::vector<GrammarQueries> compiledPerGrammar( presentGrammars.size() );
    {
        unsigned compileHw = std::thread::hardware_concurrency();
        if( compileHw == 0 )
        {
            compileHw = 1;
        }
        const unsigned           compileThreads = static_cast<unsigned>( std::min<std::size_t>( compileHw, std::max<std::size_t>( presentGrammars.size(), std::size_t( 1 ) ) ) );
        std::atomic<std::size_t> nextGrammar{ 0 };
        std::vector<std::thread> compilers;  compilers.reserve( compileThreads );
        for( unsigned worker = 0; worker < compileThreads; ++worker )
        {
            compilers.emplace_back( [ & ]()
            {
                for( ;; )
                {
                    const std::size_t grammarIndex = nextGrammar.fetch_add( 1, std::memory_order_relaxed );
                    if( grammarIndex >= presentGrammars.size() )
                    {
                        break;
                    }
                    compiledPerGrammar[grammarIndex] = compileGrammarQueries( presentGrammars[grammarIndex], groups );
                }
            } );
        }
        for( std::thread& th : compilers )
        {
            th.join();
        }
    }
    for( std::size_t grammarIndex = 0; grammarIndex < presentGrammars.size(); ++grammarIndex )
    {
        if( !compiledPerGrammar[grammarIndex].perSpec.empty() )
        {
            byGrammar.emplace( presentGrammars[grammarIndex], std::move( compiledPerGrammar[grammarIndex] ) );
        }
    }
    }
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )   // warn once if a spec compiled for NO grammar (malformed query)
    {
        if( groups[groupIndex].specs == nullptr )
        {
            continue;
        }
        for( const AstQuerySpec& spec : *groups[groupIndex].specs )
        {
            bool any = false;
            for( const auto& [g, qs] : byGrammar )
            {
                for( const GroupedQuery& gq : qs.perSpec )
                {
                    if( gq.groupIndex == groupIndex && gq.tag == spec.tag )
                    {
                        any = true;
                        break;
                    }
                }
                if( any )
                {
                    break;
                }
            }
                // Nothing in the corpus could run it — but "did not compile for ANY grammar" is a claim about
                // the QUERY (§P0.1: a malformed query's zero must never be presented as a measurement), so it
                // is settled against the grammars this corpus does NOT hold before it is made. First success
                // wins; a C++ query on a Python-only tree is valid and stays silent, exactly as when every
                // grammar was compiled up front.
                for( const LangEntry& absent : kLangTable )
                {
                    if( any )
                    {
                        break;
                    }
                    if( absent.grammar == nullptr )
                    {
                        continue;
                    }
                    const TSLanguage* ag = absent.grammar();
                    if( byGrammar.find( ag ) != byGrammar.end() )
                    {
                        continue;   // already tried above, and it did not compile
                    }
                    std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
                    if( TSQuery* probe = ts_query_new( ag, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err ) )
                    {
                        ts_query_delete( probe );
                        any = true;
                    }
                }
                if( !any )
                {
                    std::fprintf( stderr, "ripwire: AST query did not compile for any grammar: %.*s\n", int( spec.query.size() ), spec.query.data() );
                    if( groups[groupIndex].uncompiledOut )
                    {
                        groups[groupIndex].uncompiledOut->push_back( spec.query );
                    }
                    recordNodeKindHint( groups[groupIndex], spec.query );   // octocode F3: opt-in, see above
                }
        }
    }

    // §L3: grammar-applicability disclosure, opt-in per group (grammarsOut / eligibleFilesOut) — a standalone
    // pass so the existing groups[] loops above stay exactly as complex as they were for every caller that
    // doesn't ask for this (--lint, --lint-rules leave both null; zero cost, zero shape change for them).
    computeGrammarDisclosure( ing, groups );

    const std::size_t nfiles = ing.files.size();
    unsigned hw = std::thread::hardware_concurrency();
    if( hw == 0 )
    {
        hw = 1;
    }
    const unsigned nthreads = static_cast<unsigned>( std::min<std::size_t>( hw, nfiles ) );

    // NO mid-flight global cap: a shared match counter raced by workers makes WHICH matches survive the
    // cap scheduling-dependent (nondeterministic --lint/--match on repos past maxMatches). Collect every
    // file's matches fully (per-file counts are naturally bounded and short-lived), sort deterministically,
    // THEN truncate to maxMatches — cap membership becomes a pure function of the input.
    std::vector<std::vector<std::vector<AstMatch>>> tHits( nthreads, std::vector<std::vector<AstMatch>>( groups.size() ) );
    std::atomic<std::size_t>                        nextSlot{ 0 };
    std::vector<std::thread>                        pool;  pool.reserve( nthreads );

    // BIGGEST FILE FIRST (longest-processing-time-first) -- the same work order, for the same reason, that
    // the ingest parse pool builds before it fans out. Handing files out in crawl order leaves the corpus's
    // largest translation unit (ripwire's own src/main.cpp: 653 KB, 40x the median) to be picked up near the
    // END of the queue, where it runs alone against an otherwise idle pool and sets the wall time by itself.
    // Sorting the queue by descending on-disk size puts the stragglers first and lets the small files fill in
    // behind them. WHICH thread parses WHICH file was never part of the output -- captures are bucketed per
    // group and sorted on a total key after the join -- so this changes scheduling and nothing else.
    std::vector<std::uint32_t> walkOrder( nfiles );
    std::iota( walkOrder.begin(), walkOrder.end(), std::uint32_t( 0 ) );
    {
        std::vector<std::uintmax_t> fileByteSize( nfiles, 0 );
        std::error_code             ec;
        for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
        {
            ec.clear();
            fileByteSize[fileId] = fs::file_size( diskPath( ing, std::uint32_t( fileId ) ), ec );
            if( ec )
            {
                fileByteSize[fileId] = 0;
            }
        }
        std::stable_sort( walkOrder.begin(), walkOrder.end(),
                          [ & ]( std::uint32_t a, std::uint32_t b ) noexcept
                          {
                              if( fileByteSize[a] != fileByteSize[b] )
                              {
                                  return fileByteSize[a] > fileByteSize[b];
                              }
                              return a < b;
                          } );
    }

    for( unsigned t = 0; t < nthreads; ++t )
    {
        pool.emplace_back( [ &, t ]()
        {
            ParserGuard pg;
            if( pg.p == nullptr )
            {
                return;
            }
            TSQueryCursor* cur = ts_query_cursor_new();
            std::string    readBuf;   // worker-local scratch, reused across files unless the read is retained below
            for( ;; )
            {
                const std::size_t slot = nextSlot.fetch_add( 1, std::memory_order_relaxed );
                if( slot >= nfiles )
                {
                    break;
                }
                const std::size_t fileId = walkOrder[slot];
                try
                {
                    const std::string& path = diskPath( ing, std::uint32_t( fileId ) );   // multi-root: labeled ing.files → on-disk path
                    const std::string ext = lowerExtensionOf( path );
                    const LangEntry* le = lookupLang( ext );
                    if( le == nullptr )
                    {
                        continue;
                    }
                    if( !readFile( path, readBuf ) )
                    {
                        continue;
                    }
                    if( looksBinary( readBuf ) )
                    {
                        continue;
                    }
                    if( ext == ".h" && looksObjC( readBuf ) )
                    {
                        if( const LangEntry* objcLe = lookupLang( ".m" ) )
                        {
                            le = objcLe;
                        }
                    }

                    if( le->grammar == nullptr )
                    {
                        continue; // markdown — no grammar (would deref a null fn ptr)
                    }
                    const TSLanguage* g          = le->grammar();
                    const auto        it         = byGrammar.find( g );
                    const bool        hasQueries = ( it != byGrammar.end() && !it->second.perSpec.empty() );
                    if( !hasQueries && !anyWalk )
                    {
                        continue; // no spec applies to this grammar, and no built-in walk wants the tree either
                    }

                    // THE retention point, and the reason it is here rather than at any of the exits below:
                    // handing the read over BEFORE the tree is built means every path that follows works from
                    // the retained slot, so no exit can forget to keep it and no branch can keep it twice. When
                    // nothing is retaining, `bytes` binds the worker's own scratch and the loop reuses one
                    // buffer exactly as it always did. Markdown is already gone by here — a file with no
                    // grammar has no symbol a later pass could ask about.
                    std::string& bytes = ( keptBytesOut != nullptr ) ? ( ( *keptBytesOut )[fileId] = std::move( readBuf ) ) : readBuf;

                    if( !ts_parser_set_language( pg.p, g ) || !grammarAbiOk( g ) )
                    {
                        continue;
                    }
                    TSTree* tree = nullptr;
                    {
                    PROFILE_SCOPE_DESCRIBE( "astQuery/worker: tree-sitter parse" );
                    tree = ts_parser_parse_string( pg.p, nullptr, bytes.data(), static_cast<std::uint32_t>( bytes.size() ) );
                    }
                    if( !tree )
                    {
                        continue;
                    }
                    const TSNode root = ts_tree_root_node( tree );
                    const std::vector<std::uint32_t> nlOffsets = buildNewlineOffsets( bytes );   // one pass, then binary-search per capture

                    // Built-in walk groups first: they read the SAME tree and the SAME newline index the
                    // query groups below use, into their own per-group bucket, so nothing crosses over.
                    if( anyWalk )
                    {
                        PROFILE_SCOPE_DESCRIBE( "astQuery/worker: built-in tree walk" );
                        runWalkGroups( groups, root, std::uint32_t( fileId ), bytes, nlOffsets, g, tHits[t] );
                    }
                    if( !hasQueries )
                    {
                        ts_tree_delete( tree );
                        continue;   // walk-only file — no compiled spec for this grammar
                    }

                    PROFILE_SCOPE_DESCRIBE( "astQuery/worker: cursor exec + captures" );
                    // Every capture of one match, filed under the spec that owns the pattern. Shared by both
                    // execution shapes below so the ONE walk and the fallback walks cannot drift apart.
                    const auto emitCaptures = [ & ]( const TSQueryMatch& m, const GroupedQuery& owner )
                    {
                        for( std::uint16_t c = 0; c < m.capture_count; ++c )
                        {
                            const TSNode        n = m.captures[c].node;
                            const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
                            if( a >= b || b > bytes.size() )
                            {
                                continue;
                            }
                            // The snippet cut (120 bytes, UTF-8-safe, whitespace-scrubbed) lives in
                            // makeAstMatch — the pattern walk emits rows through the same helper.
                            tHits[t][owner.groupIndex].push_back( makeAstMatch( std::uint32_t( fileId ), bytes, nlOffsets, a, b, owner.tag ) );
                        }
                    };

                    if( it->second.combined != nullptr )
                    {
                        TSQuery* const q = it->second.combined;   // ONE walk for every spec this grammar has
                        ts_query_cursor_exec( cur, q, root );
                        TSQueryMatch m;
                        while( ts_query_cursor_next_match( cur, &m ) )
                        {
                            if( !passesPredicates( q, m, bytes ) )
                            {
                                continue; // honour #eq? / #match? etc. — predicates are per PATTERN, so this reads the right ones
                            }
                            if( m.pattern_index >= it->second.patternOwner.size() )
                            {
                                continue;   // unreachable: patternOwner was verified against ts_query_pattern_count
                            }
                            emitCaptures( m, it->second.perSpec[ it->second.patternOwner[ m.pattern_index ] ] );
                        }
                    }
                    else
                    {
                        for( const GroupedQuery& gq : it->second.perSpec )
                        {
                            ts_query_cursor_exec( cur, gq.query, root );
                            TSQueryMatch m;
                            while( ts_query_cursor_next_match( cur, &m ) )
                            {
                                if( !passesPredicates( gq.query, m, bytes ) )
                                {
                                    continue; // honour #eq? / #match? etc.
                                }
                                emitCaptures( m, gq );
                            }
                        }
                    }
                    ts_tree_delete( tree );
                }
                catch( ... ) { /* per-file degrade — never abort the pass */ }
            }
            ts_query_cursor_delete( cur );
        } );
    }
    for( std::thread& th : pool )
    {
        th.join();
    }

    for( auto& [g, qs] : byGrammar )
    {
        for( GroupedQuery& gq : qs.perSpec )
        {
            ts_query_delete( gq.query );
        }
        if( qs.combined != nullptr )
        {
            ts_query_delete( qs.combined );
        }
    }

    // Per group, exactly what a standalone pass produced: merge the per-thread buckets in thread order,
    // sort on the total key, then spend each tag's own budget. Nothing crosses a group boundary.
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        const bool hasSpecs = ( groups[groupIndex].specs != nullptr && !groups[groupIndex].specs->empty() );
        if( !hasSpecs && groups[groupIndex].walk == AstWalk::None )
        {
            continue;   // a caller may pass an inert slot to keep its group indices stable
        }
        std::vector<AstMatch> merged;
        std::size_t           tot = 0;
        for( const auto& perGroup : tHits )
        {
            tot += perGroup[groupIndex].size();
        }
        merged.reserve( tot );
        for( auto& perGroup : tHits )
        {
            for( auto& m : perGroup[groupIndex] )
            {
                merged.push_back( std::move( m ) );
            }
        }
        std::sort( merged.begin(), merged.end(), [ & ]( const AstMatch& x, const AstMatch& y ) // deterministic order
                   {
                       if( ing.files[x.fileId] != ing.files[y.fileId] )
                       {
                           return ing.files[x.fileId] < ing.files[y.fileId];
                       }
                       if( x.startByte != y.startByte )
                       {
                           return x.startByte < y.startByte;
                       }
                       if( x.endByte != y.endByte )
                       {
                           return x.endByte < y.endByte; // nested same-start captures (outer+inner call at one byte) need this or std::sort leaks thread arrival order
                       }
                       return x.tag < y.tag;                                                // equal keys ⇒ identical records (text derives from [start,end)) — order among them can't affect output
                   } );

        // A built-in walk group has no spec table to budget against, and emits ONE tag — so the per-tag
        // cap below degenerates to a single truncation of the sorted list, which is byte-for-byte the tail
        // the standalone spelling ran (collect all, sort on the same total key, resize to maxMatches).
        if( !hasSpecs )
        {
            if( merged.size() > groups[groupIndex].maxMatches )
            {
                merged.resize( groups[groupIndex].maxMatches );
            }
            out[groupIndex] = std::move( merged );
            continue;
        }

        // ── deterministic PER-SPEC cap (§P0.2), applied AFTER the sort so the survivors are a pure function of
        // the input. One POOLED budget let the noisiest query eat it: `(number_literal)` alone filled 5000, the
        // pool was path-sorted then cut, and every other rule was starved of the tail of the tree — `--lint`
        // reported goto=1 on a tree with two and do-while=0 on a tree with one. Each tag now spends its OWN
        // budget, which is exactly what a separate pass per spec would have produced (same collected set, same
        // (file, startByte) order within a tag) at the cost of ONE tree walk instead of N.
        const std::vector<AstQuerySpec>&    specs = *groups[groupIndex].specs;
        HashMap<std::string, std::uint32_t> tagSlot;   tagSlot.reserve( specs.size() * 2 );
        for( const AstQuerySpec& spec : specs )
        {
            const std::uint32_t nextSlot = static_cast<std::uint32_t>( tagSlot.size() );
            tagSlot.emplace( spec.tag, nextSlot );                          // duplicate tags share one budget, by design
        }

        std::vector<std::size_t> keptPerTag( tagSlot.size(), 0 );
        std::vector<AstMatch>    keep;   keep.reserve( merged.size() );
        for( AstMatch& m : merged )
        {
            const auto slotIt = tagSlot.find( m.tag );
            VERIFY( slotIt != tagSlot.end() );                              // every emitted tag came from a spec
            std::size_t& keptCount = keptPerTag[ slotIt->second ];
            if( keptCount >= groups[groupIndex].maxMatches )
            {
                continue; // this spec's own budget is spent — never another's
            }
            ++keptCount;
            keep.push_back( std::move( m ) );
        }
        out[groupIndex] = std::move( keep );
    }
    return out;
}

// R2: the grammars the pattern surface serves, derived from kLangTable so it can never disagree with the
// crawler about which extension is which language. One row per distinct grammar OBJECT — .ts and .tsx are
// two objects sharing the name "typescript", and .cu's CUDA grammar shares "cpp", and BOTH need their own
// compiled program even though the disclosure prints one name. Membership is decided by pattern.h's
// template table: a family with no wrap templates is a family this verb does not serve, stated in exactly
// one place. kLangTable order makes the result deterministic without a sort.
// The DISCLOSURE label for one grammar object, given the labels already handed out. querySub is the
// TEMPLATE key and is deliberately shared by dialects — the C++ tags.scm and the C++ pattern templates are
// what compile against tree_sitter_cuda, and tree_sitter_tsx borrows "typescript" the same way — but a
// shared disclosure NAME is how V-3 happened: `grammars="cpp"` asserted the C++ grammar resolved on a run
// where only the CUDA object had, while eligible_files=, keyed on the object, counted the .cpp file as
// unscanned. The first object to claim a querySub keeps it verbatim (so every single-dialect language's
// output is unchanged); a later object under the same key is qualified by the extension that introduced
// it — "cpp/cu", "typescript/tsx". DERIVED, not enumerated, so a dialect grammar added tomorrow cannot
// silently re-collide by being forgotten in a table.
static std::string patternGrammarLabel( std::string_view querySub, std::string_view ext, const std::vector<pattern::GrammarRow>& taken )
{
    bool claimed = false;
    for( const pattern::GrammarRow& r : taken )
    {
        claimed = claimed || ( r.label == querySub );
    }
    if( !claimed )
    {
        return std::string( querySub );
    }
    const std::string_view bare = ( !ext.empty() && ext.front() == '.' ) ? ext.substr( 1 ) : ext;
    return std::string( querySub ) + "/" + std::string( bare );
}

// --slice (lane/paper-slice): path -> grammar object, through the ONE crawl rule (lowerExtensionOf +
// kLangTable) -- see the ingest.h declaration for why this lives here and not in slice.h.
const ::TSLanguage* sliceGrammarForFile( std::string_view path )
{
    const LangEntry* le = lookupLang( lowerExtensionOf( path ) );
    if( le == nullptr || le->grammar == nullptr )
    {
        return nullptr;
    }
    return le->grammar();
}

std::vector<pattern::GrammarRow> supportedPatternGrammars()
{
    std::vector<pattern::GrammarRow> rows;
    rows.reserve( kLangTable.size() );
    for( const LangEntry& le : kLangTable )
    {
        if( le.grammar == nullptr || le.querySub.empty() || pattern::templatesFor( le.querySub ) == nullptr )
        {
            continue;
        }
        const TSLanguage* g = le.grammar();
        bool              seen = false;
        for( const pattern::GrammarRow& r : rows )
        {
            seen = seen || ( r.grammar == g );
        }
        if( !seen )
        {
            rows.push_back( { g, le.querySub, patternGrammarLabel( le.querySub, le.ext, rows ) } );
        }
    }
    return rows;
}

PatternFileCensus eligiblePatternFiles( const IngestResult& ing, const pattern::PatternProgramSet& set )
{
    const std::vector<pattern::GrammarRow> served = supportedPatternGrammars();
    PatternFileCensus                      census;
    for( std::size_t fileId = 0; fileId < ing.files.size(); ++fileId )
    {
        const std::string ext = lowerExtensionOf( diskPath( ing, std::uint32_t( fileId ) ) );
        const LangEntry*  le  = lookupLang( ext );
        if( le == nullptr || le->grammar == nullptr )
        {
            continue;
        }
        const TSLanguage* g = le->grammar();
        if( set.forGrammar( g ) != nullptr )
        {
            ++census.eligibleCount;
            continue;
        }
        // Not resolved for. It only counts as SKIPPED if this verb serves the grammar at all — a .rb or a
        // .json file is not "skipped", it is out of scope, and unsupported= already says so.
        for( const pattern::GrammarRow& r : served )
        {
            if( r.grammar == g )
            {
                ++census.skippedCount;
                break;
            }
        }
    }
    return census;
}

// The single-group spelling every standalone caller uses. One walk, one group — byte-identical to the
// hand-written pass this replaced, and there is exactly ONE file-walk implementation to keep correct.
std::vector<AstMatch> astQuery( const IngestResult& ing, const std::vector<AstQuerySpec>& specs, std::size_t maxMatches,
                                std::vector<std::string>* uncompiledOut )
{
    const std::vector<AstQueryGroup>   one{ { &specs, maxMatches, uncompiledOut } };
    std::vector<std::vector<AstMatch>> got = astQueryGrouped( ing, one );
    return std::move( got[0] );
}

// ---- R-H span tiers: the narrow single-file parse entry (declared in ingest.h — read its header first) --
//
// Node-type classification is a rule over the type NAME, not a per-grammar table, and that is deliberate:
// twelve grammars spell the same two concepts a dozen ways (comment / line_comment / block_comment /
// multiline_comment / documentation_comment / html_comment; string / string_literal / raw_string_literal /
// interpreted_string_literal / verbatim_string_literal / template_string / string_content), and a hand-kept
// per-grammar table is exactly the surface that goes stale the next time a grammar is vendored in. The two
// substring rules below cover every one of those spellings by construction; the exact-match table carries
// only the spellings that DON'T contain either word.
//
// Substring, not prefix/suffix: `raw_string_literal` and `documentation_comment` both need it. The exact
// table must stay exact — a substring rule for "str" would classify `struct_specifier` as a string.
inline constexpr std::string_view kSpanTierExactStringTypes[] = {
    "char_literal",         // C/C++/Rust
    "character_literal",    // Java/C#
    "line_str_text",        // Swift — the TEXT inside a "…" literal
    "raw_str_part",         // Swift raw strings
    "heredoc_body",         // Bash/Ruby
    "heredoc_content",      // Bash
};

// Code (the default) unless the node's own type says otherwise.
inline SpanTier spanTierOfNodeType( const char* type ) noexcept
{
    if( type == nullptr )
    {
        return SpanTier::Code;
    }
    if( std::strstr( type, "comment" ) != nullptr )
    {
        return SpanTier::Comment;
    }
    if( std::strstr( type, "string" ) != nullptr )
    {
        return SpanTier::String;
    }
    for( const std::string_view exact : kSpanTierExactStringTypes )
    {
        if( exact.compare( type ) == 0 )
        {
            return SpanTier::String;
        }
    }
    return SpanTier::Code;
}

// Collect one tree's OUTERMOST comment/string spans. Explicit stack, not recursion: a generated file can
// nest thousands of nodes deep (the YAML grammar's own 254-level indent bug is the standing reminder), and
// a query-time pass may not be the thing that overflows the stack. A classified node is recorded and NOT
// descended into, so `string_content` inside `string_literal` cannot produce a second, overlapping span.
static void collectSpanTiers( TSNode root, std::uint32_t byteCount, SpanTierMap& out )
{
    std::vector<TSNode> stack;
    stack.push_back( root );
    while( !stack.empty() )
    {
        const TSNode n = stack.back();
        stack.pop_back();
        const SpanTier    tier = spanTierOfNodeType( ts_node_type( n ) );
        const std::uint32_t a  = ts_node_start_byte( n ), b = ts_node_end_byte( n );
        if( tier != SpanTier::Code )
        {
            if( a < b && b <= byteCount )
            {
                out.startByte.push_back( a );
                out.endByte.push_back( b );
                out.tier.push_back( std::uint8_t( tier ) );
            }
            continue;   // do not descend: the span is already claimed, whole
        }
        // ALL children, not just the named ones — a comment is an `extra` in most grammars and several
        // spell it as an anonymous node, so a named-only walk silently misses exactly the tier this
        // function exists to find.
        const std::uint32_t childCount = ts_node_child_count( n );
        for( std::uint32_t c = childCount; c > 0; --c )
        {
            stack.push_back( ts_node_child( n, c - 1 ) );
        }
    }
    // The stack walk emits in DFS pop order, which is not byte order once a subtree is skipped; the
    // classify path binary-searches, so sort here once rather than making every lookup linear.
    std::vector<std::uint32_t> order( out.startByte.size() );
    std::iota( order.begin(), order.end(), std::uint32_t( 0 ) );
    std::stable_sort( order.begin(), order.end(), [ & ]( std::uint32_t x, std::uint32_t y ) noexcept
                      { return out.startByte[x] < out.startByte[y]; } );
    SpanTierMap sorted;
    sorted.startByte.reserve( order.size() );
    sorted.endByte.reserve( order.size() );
    sorted.tier.reserve( order.size() );
    for( const std::uint32_t index : order )
    {
        sorted.startByte.push_back( out.startByte[index] );
        sorted.endByte.push_back( out.endByte[index] );
        sorted.tier.push_back( out.tier[index] );
    }
    out.startByte = std::move( sorted.startByte );
    out.endByte   = std::move( sorted.endByte );
    out.tier      = std::move( sorted.tier );
}

SpanTierBatch spanTiersOfFiles( std::span<const std::string> diskPaths )
{
    SpanTierBatch batch;
    batch.perFile.resize( diskPaths.size() );
    if( diskPaths.empty() )
    {
        return batch;
    }

    // BIGGEST FILE FIRST, the same longest-processing-time-first order (and the same reason) as
    // astQueryGrouped's pool: hand the corpus's largest translation unit out first so it cannot strand an
    // otherwise-idle pool at the tail. E5 design condition 2 — this is the pattern it named, scoped to the
    // caller's file list instead of ing.files.
    const std::size_t          fileCount = diskPaths.size();
    std::vector<std::uint32_t> walkOrder( fileCount );
    std::iota( walkOrder.begin(), walkOrder.end(), std::uint32_t( 0 ) );
    {
        std::vector<std::uintmax_t> fileByteSize( fileCount, 0 );
        std::error_code             ec;
        for( std::size_t fileIndex = 0; fileIndex < fileCount; ++fileIndex )
        {
            ec.clear();
            fileByteSize[fileIndex] = fs::file_size( diskPaths[fileIndex], ec );
            if( ec )
            {
                fileByteSize[fileIndex] = 0;
            }
        }
        std::stable_sort( walkOrder.begin(), walkOrder.end(), [ & ]( std::uint32_t a, std::uint32_t b ) noexcept
                          {
                              if( fileByteSize[a] != fileByteSize[b] )
                              {
                                  return fileByteSize[a] > fileByteSize[b];
                              }
                              return a < b;
                          } );
    }

    unsigned hw = std::thread::hardware_concurrency();
    if( hw == 0 )
    {
        hw = 1;
    }
    const unsigned            threadCount = static_cast<unsigned>( std::min<std::size_t>( hw, fileCount ) );
    std::atomic<std::size_t>  nextSlot{ 0 };
    std::atomic<std::uint64_t> bytesParsed{ 0 };
    const auto                worker = [ & ]()
    {
        ParserGuard pg;
        if( pg.p == nullptr )
        {
            DEGRADED_PATH_ALERT( "span tiers: no tree-sitter parser — hits stay unclassified (never suppressed)" );
            return;
        }
        std::string bytes;
        try
        {
            for( ;; )
            {
                const std::size_t slot = nextSlot.fetch_add( 1, std::memory_order_relaxed );
                if( slot >= fileCount )
                {
                    break;
                }
                const std::size_t  fileIndex = walkOrder[slot];
                const std::string& path      = diskPaths[fileIndex];
                const std::string  ext       = lowerExtensionOf( path );
                const LangEntry*   le        = lookupLang( ext );
                if( le == nullptr || le->grammar == nullptr )
                {
                    continue;   // markdown and every unsupported extension: unclassifiable, and it stays that way
                }
                bytes.clear();
                if( !readFile( path, bytes ) || looksBinary( bytes ) )
                {
                    continue;
                }
                if( ext == ".h" && looksObjC( bytes ) )
                {
                    if( const LangEntry* objcLe = lookupLang( ".m" ) )
                    {
                        le = objcLe;   // the SAME reroute the crawl and the AST walk both apply
                    }
                }
                const TSLanguage* g = le->grammar();
                if( g == nullptr || !ts_parser_set_language( pg.p, g ) || !grammarAbiOk( g ) )
                {
                    continue;
                }
                TSTree* tree = nullptr;
                {
                    PROFILE_SCOPE_DESCRIBE( "spanTiers/worker: tree-sitter parse" );
                    tree = ts_parser_parse_string( pg.p, nullptr, bytes.data(), static_cast<std::uint32_t>( bytes.size() ) );
                }
                if( tree == nullptr )
                {
                    continue;
                }
                collectSpanTiers( ts_tree_root_node( tree ), std::uint32_t( bytes.size() ), batch.perFile[fileIndex] );
                batch.perFile[fileIndex].isParsed = true;   // slot owned by this worker alone
                ts_tree_delete( tree );
                bytesParsed.fetch_add( bytes.size(), std::memory_order_relaxed );
            }
        }
        catch( ... )   // a throw escaping a worker thread is std::terminate — degrade to unclassified instead
        {
            DEGRADED_PATH_ALERT( "span tiers: parse worker degraded (exception swallowed) — files left unclassified" );
        }
    };
    if( threadCount <= 1 )
    {
        worker();
    }
    else
    {
        // symmetric bare scope: the workers live exactly as long as the parse batch
        std::vector<std::thread> pool;
        pool.reserve( threadCount );
        for( unsigned t = 0; t < threadCount; ++t )
        {
            pool.emplace_back( worker );
        }
        for( std::thread& w : pool )
        {
            w.join();
        }
    }

    batch.bytesParsed = bytesParsed.load( std::memory_order_relaxed );
    for( const SpanTierMap& m : batch.perFile )
    {
        if( m.isParsed )
        {
            ++batch.parsedFileCount;
        }
        else
        {
            ++batch.unparsedFileCount;
        }
    }
    return batch;
}

// ---- unreachable-code detection (built-in --lint rule "unreachable-code") ----
//
// A GENUINE block node — a brace-delimited statement list whose direct children are the block's
// statements (NOT a switch body's case list, NOT a case body). Only these are scanned: within one,
// a statement's straight-line successor is a plain sibling, so "code after an unconditional exit is
// dead" holds syntactically. Case bodies (children of case_statement) are deliberately NOT blocks
// here, so `break; x();` inside a case is never flagged (conservative — no false positives).
inline bool ur_isBlockNode( const char* t ) noexcept
{
    return    std::strcmp( t, "compound_statement" ) == 0    // C / C++ / ObjC
           || std::strcmp( t, "block" ) == 0                 // Python / Java (and other {…} blocks)
           || std::strcmp( t, "statement_block" ) == 0;      // JS / TS
}

// An UNCONDITIONAL terminator statement: once seen at a block level, control cannot fall through to
// the next sibling. `goto` is intentionally EXCLUDED — a following statement can be a label target,
// so flagging it would be a false positive (the #1 trap this check must avoid). `return_statement`
// covers C-family + Python; `raise_statement` is Python's throw.
inline bool ur_isTerminator( const char* t ) noexcept
{
    return    std::strcmp( t, "return_statement" ) == 0
           || std::strcmp( t, "break_statement" ) == 0
           || std::strcmp( t, "continue_statement" ) == 0
           || std::strcmp( t, "throw_statement" ) == 0       // C++ / ObjC / Java / JS
           || std::strcmp( t, "raise_statement" ) == 0;      // Python
}

// A node that is NOT a real statement for reachability purposes — skip it when looking for the next
// sibling after a terminator (comments, and the block's own braces/colon punctuation). tree-sitter
// exposes comments as named siblings inside a block; a comment after `return` is not dead CODE.
inline bool ur_isSkippableSibling( TSNode n ) noexcept
{
    if( !ts_node_is_named( n ) )
    {
        return true; // '{', '}', ';', ':' punctuation tokens
    }
    const char* t = ts_node_type( n );
    return std::strcmp( t, "comment" ) == 0;
}

// A jump TARGET sibling: a label or a case makes the following statements reachable out-of-line, so
// the moment one appears after a terminator we STOP scanning this block (never flag past it). This
// is the second false-positive guard (belt-and-braces with excluding goto and not scanning case
// bodies): even a stray label inside a plain block halts the dead-code claim.
inline bool ur_isJumpTarget( const char* t ) noexcept
{
    return    std::strcmp( t, "labeled_statement" ) == 0     // C-family `lbl:` (goto/switch fallthrough target)
           || std::strcmp( t, "case_statement" ) == 0        // C-family switch case/default
           || std::strcmp( t, "case" ) == 0                  // grammar variants
           || std::strcmp( t, "default" ) == 0;
}

// Walk one file's AST (iterative frame-stack DFS — the cc_walk shape, NO recursion). For every block
// node, scan its direct children left-to-right; the FIRST non-skippable statement after a terminator
// (with no intervening jump target) is unreachable → one finding at that statement's start byte.
inline void ur_walkTree( TSNode root, std::uint32_t fileId, std::string_view src, const std::vector<std::uint32_t>& nlOffsets, std::vector<AstMatch>& hits )   // A4-F25: NOT noexcept — allocates (see cc_walk)
{
    struct UrFrame { TSNode node; std::uint16_t depth; };
    std::vector<UrFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, 0 } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );

    while( !stack.empty() )
    {
        const UrFrame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 512 )
        {
            continue; // pathological-AST guard (file capped at 1 MB)
        }
        const TSNode        n          = frame.node;
        const std::uint16_t childDepth = static_cast<std::uint16_t>( frame.depth + 1 );
        const char*         t          = ts_node_type( n );
        collectChildren( n, cursor.cur, kids );              // one collection serves the block scan AND the descent

        // If this is a genuine block, scan its statement siblings for a post-terminator statement.
        if( ur_isBlockNode( t ) )
        {
            bool sawTerminator = false;
            for( const TSNode c : kids )
            {
                const char* ct = ts_node_type( c );

                if( sawTerminator )
                {
                    if( ur_isSkippableSibling( c ) )
                    {
                        continue; // comment / punctuation → not code, keep looking
                    }
                    if( ur_isJumpTarget( ct ) )
                    {
                        break; // label/case → reachable out-of-line → stop, no flag
                    }
                    // First real statement after an unconditional exit in this block → UNREACHABLE.
                    const std::uint32_t a = ts_node_start_byte( c ), b = ts_node_end_byte( c );
                    if( a < b && b <= src.size() )
                    {
                        const std::uint32_t line = lineAtByte( nlOffsets, a );
                        std::size_t cutLen = std::min<std::size_t>( b - a, 120u );
                        if( cutLen < b - a )
                        { // UTF-8-safe truncation (serialize.h/astQuery pattern)
                            while( cutLen > 0 && ( static_cast<unsigned char>( src[a + cutLen] ) & 0xC0 ) == 0x80 )
                            {
                                --cutLen;
                            }
                        }
                        std::string text( src.substr( a, cutLen ) );
                        for( char& ch : text )
                        {
                            if( ch == '\n' || ch == '\r' || ch == '\t' )
                            {
                                ch = ' ';
                            }
                        }
                        hits.push_back( { fileId, a, b, line, std::string( "unreachable-code" ), std::move( text ) } );
                    }
                    break;   // one finding per block — the first dead statement; the rest are consequential noise
                }
                else if( ur_isSkippableSibling( c ) )
                {
                    continue;                                       // comments/punctuation don't set the terminator flag
                }
                else if( ur_isTerminator( ct ) )
                {
                    sawTerminator = true;                           // arm: the NEXT real sibling is unreachable
                }
                // else: an ordinary statement — reachable; a terminator inside it (nested block/branch)
                //       is handled when we descend into that child's own block, never at THIS level.
            }
        }

        // Descend into every child (blocks nest — a function body holds inner blocks, and non-block
        // statements like if/for CONTAIN blocks we must still reach). Push in reverse for L-to-R order.
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[ i - 1 ], childDepth } );
        }
    }
}

// local-variable-indexing plan, Phase 2 (PLAN.md 2026-08-06 evening) — see ingest.h's own comment for the
// full contract. Definition lives HERE (outside the anonymous namespace above) purely for LINKAGE — it
// must be externally callable to satisfy ingest.h's declaration — while every helper it calls
// (ln_extractDeclaratorIdentifiers / ln_declaratorIdentifiers / ln_declDepth / ln_collectLocalDecls) stays
// anonymous-namespace-scoped next to cc_walk/complexityOf, which they mirror.
std::vector<LocalNameFact> collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )
{
    std::vector<LocalNameFact> out;
    if( !localsCountedLang( lang ) || defBytes.empty() )
    {
        return out;   // MVP scope (model.h::localsCountedLang) — degrade to empty, never assert on a caller mistake
    }
    const TSLanguage* grammar = ( lang == Lang::C ) ? tree_sitter_c() : tree_sitter_cpp();
    TSParser* parser = ts_parser_new();
    if( parser == nullptr )
    {
        return out;
    }
    ts_parser_set_language( parser, grammar );
    TSTree* tree = ts_parser_parse_string( parser, nullptr, defBytes.data(), std::uint32_t( defBytes.size() ) );
    if( tree == nullptr )
    {
        ts_parser_delete( parser );
        return out;
    }
    const TSNode root = ts_tree_root_node( tree );
    // the def parses as a single top-level function_definition inside a translation_unit — descend into
    // the translation_unit's children (bounded: one file-worth of def text, already size-capped upstream).
    const std::uint32_t n = ts_node_child_count( root );
    for( std::uint32_t i = 0; i < n; ++i )
    {
        ln_collectLocalDecls( ts_node_child( root, i ), ts_node_child( root, i ), 512, out, defStartLine, defBytes );
    }
    ts_tree_delete( tree );
    ts_parser_delete( parser );
    return out;
}

}   // namespace rw — ingest_astquery.h section of ingest.cpp
