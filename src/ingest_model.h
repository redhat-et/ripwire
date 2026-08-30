#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_model.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_model.h — the build-model tail of ingest(), moved VERBATIM out of the function body in the
// 2026-08-30 ingest() decomposition: everything after the doc post-pass that turns the merged raw
// fact lists into the deterministic IngestResult model — def dedup, the ObjC decl/def collapse,
// Symbol-id assignment (+ the B0 lex CSR flatten), the per-file def-span index with its sweep
// cursor, and the ordered emit of references/bindings/aliases/routes. Each phase is a named
// helper with the same body it had inline, so ingest() reads as the pipeline and each contract can
// be edited in isolation. Same contract as every ingest_*.h: reopens `namespace rw` and the unnamed
// namespace inside it — one TU, one unnamed namespace, internal linkage unchanged, zero new API
// surface — under the RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

// 3a) dedup definitions: some grammars' tags patterns overlap (Go: type_spec + the
//     struct/interface specializations both fire; Rust: a fn inside an impl matches both
//     the method and the function pattern). Two matches with the same (fileId, startByte,
//     name) are ONE definition. Collapse them, keeping the most specific kind so the
//     downstream graph sees one node per real symbol.
inline void dedupRawDefs( std::vector<RawDef>& rawDefs )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/build-model: dedup defs" );

    auto specificity = []( SymKind k ) noexcept -> int
    {
        // higher = more specific / preferred when two matches collide
        switch( k )
        {
            case SymKind::Method:    return 5;
            case SymKind::Interface: return 4;
            case SymKind::Struct:    return 3;
            case SymKind::Class:     return 3;
            case SymKind::Function:  return 2;
            case SymKind::Var:       return 1;
            default:                 return 0;   // Other
        }
    };

    // identity = the declared identifier itself: (fileId, name-token start byte). Two tags
    // patterns that both name the same identifier are the same symbol regardless of which
    // wrapper node each captured.
    std::sort( rawDefs.begin(), rawDefs.end(),
               [ &specificity ]( const RawDef& a, const RawDef& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.nameByte != b.nameByte )
                   {
                       return a.nameByte < b.nameByte;
                   }
                   // same identity: most-specific kind first so unique() keeps it
                   const int specificityA = specificity( a.kind ), specificityB = specificity( b.kind );
                   if( specificityA != specificityB )
                   {
                       return specificityA > specificityB;
                   }
                   // same identity AND same specificity with DIFFERENT spans (Go: `type Foo struct{}` fires
                   // two capture rows): finish the total order on span — startByte ascending, endByte
                   // DESCENDING (widest span first) — so the unique() survivor is input-order independent.
                   if( a.startByte != b.startByte )
                   {
                       return a.startByte < b.startByte;
                   }
                   return a.endByte > b.endByte;
               } );

    const auto sameIdentity = []( const RawDef& a, const RawDef& b ) noexcept
    {
        return a.fileId == b.fileId && a.nameByte == b.nameByte;
    };
    rawDefs.erase( std::unique( rawDefs.begin(), rawDefs.end(), sameIdentity ), rawDefs.end() );
}

// 3a-bis) same-FILE decl/def collapse (ObjC only) — the intra-file mirror of graph.h's cross-file byName
//     collapse. In C++ a header decl and its .cpp def live in DIFFERENT files, so (fileId, nameByte)
//     already keeps them as two legitimate nodes (one per file) and the graph.h byName pass merges them
//     only for resolution. ObjC breaks that symmetry: the @interface decl and the @implementation def sit
//     in the SAME .m/.mm file with different name-token bytes, so 3a leaves BOTH as nodes — every ObjC
//     method (and the class itself) lands twice, doubling <s> nodes AND call edges (token waste + rank
//     distortion in every ObjC file). Collapse it here, at the same "one node per real symbol" seam: within
//     a file, if a (name, scope, kind) group has ANY body-present definition (bodyByte > startByte — the
//     same predicate as graph.h's hasBody, made correct for ObjC by the body-child fallback above), drop
//     that group's bodyLESS declarations and keep the definition(s). A group with NO def anywhere in the
//     file (an @interface method with no @implementation, a protocol-only method) keeps its decls untouched
//     — the exact "no def anywhere keeps decls" escape hatch graph.h uses.
//
//     GATED to ObjC defs deliberately. (1) SCOPE: gate (d) requires C++/Python output to stay byte-for-byte
//     identical, and this bug is ObjC-only. (2) CORRECTNESS: the (fileId, name, scope, kind) key does NOT
//     distinguish C++ OVERLOADS — a header with `svector() = default;` (bodyLESS) + `svector(const&){...}`
//     (body) would wrongly drop the defaulted ctor as a "shadowed decl". ObjC selectors don't overload by
//     signature within a class, so for ObjC the key uniquely pairs exactly one decl with one def. A `.mm`'s
//     C++ functions carry Lang::ObjC too, but a C++ overload set inside a .mm is out of this fixture's scope
//     and the same key limitation applies — so we restrict to the observed ObjC node shapes by language and
//     rely on the byte-identical + langcheck gates. Never manufactures a symbol the tags query didn't capture.
inline void collapseObjCDeclDefs( std::vector<RawDef>& rawDefs )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/build-model: objc decl-def collapse" );

    const auto hasBody = []( const RawDef& d ) noexcept { return d.bodyByte > d.startByte; };

    // (fileId, name, scope, kind) → does the group contain at least one body-present ObjC def? one pass.
    // Only ObjC defs are keyed; non-ObjC defs are never grouped and always pass through unchanged.
    HashMap<std::string, bool> groupHasDef;
    groupHasDef.reserve( rawDefs.size() );
    std::string key;
    const auto makeKey = [ &key ]( const RawDef& d )
    {
        key.clear();
        key.append( std::to_string( d.fileId ) ).push_back( '\x1f' );
        key.append( d.name ).push_back( '\x1f' );
        key.append( d.scope ).push_back( '\x1f' );
        key.push_back( char( '0' + int( d.kind ) ) );
        return std::string_view( key );
    };
    for( const RawDef& d : rawDefs )
    {
        if( d.lang != Lang::ObjC )
        {
            continue; // C++/Python/… never participate (SCOPE + overload-safety)
        }
        const std::string_view k = makeKey( d );
        const auto [ it, inserted ] = groupHasDef.try_emplace( std::string( k ), hasBody( d ) );
        if( !inserted && hasBody( d ) )
        {
            it->second = true;
        }
    }

    // keep a def group's DEFS only; keep a decl-only group whole (escape hatch). Stable: preserves order.
    std::vector<RawDef> kept;
    kept.reserve( rawDefs.size() );
    for( RawDef& d : rawDefs )
    {
        if( d.lang == Lang::ObjC )                                // only ObjC symbols are eligible to be dropped
        {
            const auto it = groupHasDef.find( std::string( makeKey( d ) ) );
            const bool groupDef = ( it != groupHasDef.end() ) && it->second;
            if( groupDef && !hasBody( d ) )
            {
                continue; // a decl shadowed by a same-file ObjC def → drop
            }
        }
        kept.push_back( std::move( d ) );
    }
    rawDefs = std::move( kept );
}

// 3b) assign Symbol ids in (fileId, line, name) order — deterministic (model.h) — then, on rich
//     ingests, flatten the per-def lex stats into the per-symbol CSR. The two stay in ONE helper so
//     the "rawDefs is aligned 1:1 with result.symbols after the sort" invariant the CSR flatten
//     rides on is established and consumed in the same scope (and the profile nesting is unchanged).
inline void assignSymbols( IngestResult& result, std::vector<RawDef>& rawDefs, bool captureValueUses )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/build-model: assign symbols" );

    std::sort( rawDefs.begin(), rawDefs.end(),
               []( const RawDef& a, const RawDef& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.line != b.line )
                   {
                       return a.line < b.line;
                   }
                   if( a.name != b.name )
                   {
                       return a.name < b.name;
                   }
                   return a.startByte < b.startByte;   // stable last-resort tiebreak
               } );

    result.symbols.reserve( rawDefs.size() );
    for( std::uint32_t i = 0; i < rawDefs.size(); ++i )
    {
        const RawDef& d = rawDefs[ i ];
        Symbol s;
        s.id     = i;
        s.kind   = d.kind;
        s.lang   = d.lang;
        s.fileId = d.fileId;
        s.line   = d.line;
        s.sigStartByte = d.startByte;
        s.sigEndByte   = ( d.bodyByte > d.startByte ) ? d.bodyByte : d.endByte;
        s.endByte      = d.endByte;
        s.cx           = d.cx;
        s.ccx          = d.ccx;
        s.loc          = d.loc;      // Q4: physical line span
        s.locals       = d.locals;   // Phase 1: local-decl floor count (C/C++ only; model.h localsCountedLang)
        s.ppAlt        = d.ppAlt;    // ppalt disclosure: preproc alternative branches in the body (model.h)
        s.params       = d.params;   // Q4: parameter count (fns/methods)
        s.arityExact   = d.arityExact;   // B2.2: params is a fixed call-comparable arity
        s.testScope    = d.testScope;    // L8: an in-file test convention encloses this def
        s.maxNest      = d.maxNest;  // Q4: max control nesting (fns/methods)
        s.humps        = d.humps;   // nesting profile: regions reaching quality::kNestBar (model.h)
        s.deepLoc      = d.deepLoc; // nesting profile: lines inside them, a FLOOR (model.h)
        s.ev           = d.ev;      // essential complexity, a FLOOR (model.h; 0 outside evCountedLang)
        s.evWhy        = d.evWhy;   // per-tag contributing-jump counts (model.h kEvWhyTagTable order)
        s.name   = d.name;
        s.scope  = d.scope;
        result.symbols.push_back( std::move( s ) );
    }

    // B0.1/B0.2 (rich ingests only): flatten the per-def stats into the per-symbol CSR (rawDefs is
    // aligned 1:1 with result.symbols after the sort above) and derive the per-FILE pre-filter
    // signatures from the same hashes — the B0.1 Bloom is a pure function of the persisted postings,
    // so it costs the cache format nothing and can never disagree with the stats it gates.
    if( captureValueUses )
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: lex stats CSR + file signatures (B0)" );

        const std::size_t symbolCount = result.symbols.size();
        std::size_t       pairCount   = 0;
        for( const RawDef& d : rawDefs )
        {
            pairCount += d.lex.tokenHashes.size();
        }

        result.hasLexStats = true;
        result.lexDocBodyDl.resize( symbolCount );
        result.lexTokenRowOffsets.resize( symbolCount + 1 );
        result.lexTokenHashes.reserve( pairCount );
        result.lexTokenTfs.reserve( pairCount );
        result.lexFileSig.assign( result.files.size() * kLexFileSigWords, 0 );

        result.lexTokenRowOffsets[ 0 ] = 0;
        for( std::size_t i = 0; i < symbolCount; ++i )
        {
            const RawDefLex& lx = rawDefs[ i ].lex;
            result.lexDocBodyDl[ i ] = lx.dlWeighted;
            result.lexTokenHashes.insert( result.lexTokenHashes.end(), lx.tokenHashes.begin(), lx.tokenHashes.end() );
            result.lexTokenTfs.insert( result.lexTokenTfs.end(), lx.tokenTfs.begin(), lx.tokenTfs.end() );
            result.lexTokenRowOffsets[ i + 1 ] = std::uint32_t( result.lexTokenHashes.size() );

            const std::uint32_t fileId = rawDefs[ i ].fileId;
            if( fileId < result.files.size() )
            {
                std::uint64_t* const sig = result.lexFileSig.data() + std::size_t( fileId ) * kLexFileSigWords;
                for( const std::uint64_t hash : lx.tokenHashes )
                {
                    sig[lexSigWord( hash )] |= lexSigBit( hash );
                }
            }
        }
    }
}

}   // namespace

}   // namespace rw
