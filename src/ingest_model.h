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
            case SymKind::Field:     return 1;   // never collides with Var in practice: the static/non-static gates are complementary
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

// 4) attribute each reference to its enclosing definition (innermost span containing it).
//    Per file: the enclosing def is the one with the latest startByte <= ref.startByte
//    whose endByte > ref.startByte. We index defs by file via a sorted view.
struct DefSpan
{
    std::uint32_t startByte;
    std::uint32_t endByte;
    NodeId        id;
};

// group def spans by fileId in one flat array (rawDefs aligned 1:1 with result.symbols after the
// assignSymbols sort). The previous vector<vector<...>> shape allocated twice per file; offsets keep the
// same per-file ranges with contiguous storage, which matters on C++ repos with many small headers.
struct DefSpanIndex
{
    std::vector<std::size_t> fileSpanStart;   // per-fileId [begin,end) offsets into spans — size nfiles+1
    std::vector<DefSpan>     spans;           // grouped by fileId, start-sorted within each file's range
};

inline DefSpanIndex buildDefSpanIndex( const IngestResult& result, const std::vector<RawDef>& rawDefs )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/build-model: def-span index" );

    DefSpanIndex index;
    index.fileSpanStart.assign( result.files.size() + 1, 0 );
    for( const RawDef& d : rawDefs )
    {
        ++index.fileSpanStart[ d.fileId + 1 ];
    }
    for( std::size_t fileId = 1; fileId < index.fileSpanStart.size(); ++fileId )
    {
        index.fileSpanStart[ fileId ] += index.fileSpanStart[ fileId - 1 ];
    }

    index.spans.resize( rawDefs.size() );
    std::vector<std::size_t> fileSpanWrite = index.fileSpanStart;
    for( std::uint32_t i = 0; i < rawDefs.size(); ++i )
    {
        const std::size_t spanIndex = fileSpanWrite[ rawDefs[ i ].fileId ]++;
        // member-variable round (card A3): a FIELD never encloses anything. Its declaration sits inside the
        // owner's body, so a real span here would make the field the innermost definition around the S5-E
        // HAS-A type ref captured on that very line (fromSymbol used to be the CLASS, and buildFieldNarrowTables,
        // composeEdges and the --lego view all key on that) and around a default initializer's own reads.
        // A zero-width span contains no byte, so every reference attributes exactly as it did before fields
        // were symbols — byte-identical fromSymbol corpus-wide. The field's own [start, end) stays on the
        // Symbol (--expand reads it there), only this containment index is blind to it.
        const bool isField = rawDefs[ i ].kind == SymKind::Field;
        index.spans[ spanIndex ] = { rawDefs[ i ].startByte, isField ? rawDefs[ i ].startByte : rawDefs[ i ].endByte, result.symbols[ i ].id };
    }

    for( std::size_t fileId = 0; fileId < result.files.size(); ++fileId )
    {
        const std::size_t begin = index.fileSpanStart[ fileId ];
        const std::size_t end   = index.fileSpanStart[ fileId + 1 ];
        // A4-F23a: startByte alone is not a total order — equal-start spans (a markdown file node and its
        // first-line heading both at byte 0) would get stdlib-dependent innermost attribution. Tie-break on
        // endByte DESCENDING (wider container first, so the sweep opens it before the nested span), then id
        // for totality → cross-platform byte-identical output.
        std::sort( index.spans.begin() + begin, index.spans.begin() + end,
                   []( const DefSpan& a, const DefSpan& b ) noexcept
                   {
                       if( a.startByte != b.startByte )
                       {
                           return a.startByte < b.startByte;
                       }
                       if( a.endByte != b.endByte )
                       {
                           return a.endByte > b.endByte;
                       }
                       return a.id < b.id;
                   } );
    }
    return index;
}

// innermost enclosing def of a byte position: the container span with the LARGEST start ≤ pos whose end
// is past pos (spans are start-sorted per file). Refs/bindings are consumed in deterministic
// (fileId,startByte,...) order, so a single per-file sweep replaces one binary search per fact. The active
// stack's back is the latest-start span still open, which is exactly the previous lookup's chosen container.
struct DefSweep
{
    const std::vector<DefSpan>&    spans;
    const std::vector<std::size_t>& fileStart;
    std::uint32_t                  currentFileId = std::numeric_limits<std::uint32_t>::max();
    std::size_t                    nextSpanIndex = 0;
    std::size_t                    endSpanIndex  = 0;
    std::vector<std::size_t>       activeSpanIndices;

    NodeId find( std::uint32_t fileId, std::uint32_t pos )
    {
        if( fileId != currentFileId )
        {
            currentFileId = fileId;
            nextSpanIndex = fileStart[ fileId ];
            endSpanIndex  = fileStart[ fileId + 1 ];
            activeSpanIndices.clear();
        }

        while( nextSpanIndex < endSpanIndex && spans[ nextSpanIndex ].startByte <= pos )
        {
            activeSpanIndices.push_back( nextSpanIndex++ );
        }
        while( !activeSpanIndices.empty() && spans[ activeSpanIndices.back() ].endByte <= pos )
        {
            activeSpanIndices.pop_back();
        }

        return activeSpanIndices.empty() ? kNoNode : spans[ activeSpanIndices.back() ].id;
    }
};

// references: emit in deterministic (fileId, startByte, name) order. A RawRef is FAT (5 std::strings ≈
// 160 B), so we order a uint32 INDEX permutation instead of the objects themselves. Bucket by file first,
// radix-sort each file's indices by the numeric startByte, then comparison-sort only equal-byte name ties.
// Same ordering contract as the old comparator, but it moves the hot path onto byte histograms.
inline std::vector<std::uint32_t> orderReferences( const std::vector<RawRef>& rawRefs, std::size_t fileCount )
{
    std::vector<std::uint32_t> refOrder( rawRefs.size() );
    PROFILE_SCOPE_DESCRIBE( "ingest/build-model: sort ref index" );

    std::vector<std::size_t> refStartByFile( fileCount + 1, 0 );
    for( const RawRef& r : rawRefs )
    {
        ++refStartByFile[ r.fileId + 1 ];
    }
    for( std::size_t fileId = 1; fileId < refStartByFile.size(); ++fileId )
    {
        refStartByFile[ fileId ] += refStartByFile[ fileId - 1 ];
    }

    std::vector<std::size_t> refWriteByFile = refStartByFile;
    for( std::uint32_t i = 0; i < rawRefs.size(); ++i )
    {
        refOrder[ refWriteByFile[ rawRefs[ i ].fileId ]++ ] = i;
    }

    std::vector<std::uint32_t> refScratch( rawRefs.size() );
    // A4-F23b: (startByte,name) is NOT a total order — Python `class A(Foo)` captures `Foo` twice at one
    // byte with different roles (Extends + Read), so the stdlib sort's residual order was implementation-
    // dependent. Extend the key with role then isInherit for a total, cross-platform-stable ordering.
    const auto lessRefResidual = [ &rawRefs ]( const RawRef& a, const RawRef& b ) noexcept
    {
        if( a.name != b.name )
        {
            return a.name < b.name;
        }
        if( a.role != b.role )
        {
            return static_cast<std::uint8_t>( a.role ) < static_cast<std::uint8_t>( b.role );
        }
        return static_cast<int>( a.isInherit ) < static_cast<int>( b.isInherit );
    };
    const auto lessRefByByteName = [ &rawRefs, &lessRefResidual ]( std::uint32_t ia, std::uint32_t ib ) noexcept
    {
        const RawRef& a = rawRefs[ ia ];
        const RawRef& b = rawRefs[ ib ];
        if( a.startByte != b.startByte )
        {
            return a.startByte < b.startByte;
        }
        return lessRefResidual( a, b );
    };
    const auto lessRefByName = [ &rawRefs, &lessRefResidual ]( std::uint32_t ia, std::uint32_t ib ) noexcept
    {
        return lessRefResidual( rawRefs[ ia ], rawRefs[ ib ] );
    };
    const auto radixSortRefSegment = [ & ]( std::size_t begin, std::size_t end )
    {
        constexpr std::size_t kRadixThreshold = 64;
        const std::size_t count = end - begin;
        if( count < kRadixThreshold )
        {
            std::sort( refOrder.begin() + begin, refOrder.begin() + end, lessRefByByteName );
            return;
        }

        bool isAlreadySorted = true;
        for( std::size_t i = begin + 1; i < end; ++i )
        {
            if( lessRefByByteName( refOrder[ i ], refOrder[ i - 1 ] ) )
            {
                isAlreadySorted = false;
                break;
            }
        }
        if( isAlreadySorted )
        {
            return;
        }

        std::uint32_t* src = refOrder.data() + begin;
        std::uint32_t* dst = refScratch.data() + begin;
        bool inScratch = false;

        for( unsigned shift = 0; shift < 32; shift += 8 )
        {
            std::uint32_t hist[ 256 ] = {};
            for( std::size_t i = 0; i < count; ++i )
            {
                ++hist[ ( rawRefs[ src[ i ] ].startByte >> shift ) & 0xffu ];
            }

            bool singleBucket = false;
            for( std::uint32_t h : hist )
            {
                if( h == count ) { singleBucket = true; break; }
            }
            if( singleBucket )
            {
                continue;
            }

            std::uint32_t offsets[ 256 ];
            std::uint32_t sum = 0;
            for( std::size_t i = 0; i < 256; ++i )
            {
                offsets[ i ] = sum;
                sum += hist[ i ];
            }
            for( std::size_t i = 0; i < count; ++i )
            {
                const std::uint32_t idx = src[ i ];
                const std::uint32_t bin = ( rawRefs[ idx ].startByte >> shift ) & 0xffu;
                dst[ offsets[ bin ]++ ] = idx;
            }
            std::swap( src, dst );
            inScratch = !inScratch;
        }

        if( inScratch )
        {
            std::copy( src, src + count, refOrder.data() + begin );
        }

        std::size_t tieBegin = begin;
        while( tieBegin < end )
        {
            std::size_t tieEnd = tieBegin + 1;
            const std::uint32_t byte = rawRefs[ refOrder[ tieBegin ] ].startByte;
            while( tieEnd < end && rawRefs[ refOrder[ tieEnd ] ].startByte == byte )
            {
                ++tieEnd;
            }
            if( tieEnd - tieBegin > 1 )
            {
                std::sort( refOrder.begin() + tieBegin, refOrder.begin() + tieEnd, lessRefByName );
            }
            tieBegin = tieEnd;
        }
    };

    for( std::size_t fileId = 0; fileId < fileCount; ++fileId )
    {
        const std::size_t begin = refStartByFile[ fileId ];
        const std::size_t end   = refStartByFile[ fileId + 1 ];
        radixSortRefSegment( begin, end );
    }
    return refOrder;
}

// rawRefs is consumed here (never read again) → MOVE its 5 strings into each Reference instead of copying.
inline void emitReferences( IngestResult& result, std::vector<RawRef>& rawRefs, const std::vector<std::uint32_t>& refOrder, const DefSpanIndex& spanIndex )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/build-model: emit refs" );

    result.references.resize( rawRefs.size() );
    DefSweep refSweep{ spanIndex.spans, spanIndex.fileSpanStart };
    std::size_t outRefIndex = 0;
    for( std::uint32_t idx : refOrder )
    {
        RawRef& r = rawRefs[ idx ];
        Reference& ref = result.references[ outRefIndex++ ];
        ref.fileId      = r.fileId;
        ref.line        = r.line;        // ABS-3: 1-based use-site line for --uses p="file:line"
        ref.lang        = r.lang;
        ref.calleeName  = std::move( r.name );
        ref.qualifier   = std::move( r.qualifier );
        ref.role        = r.role;        // ABS-3 use-site role (call/read/write/import/extends)
        ref.isInherit   = r.isInherit;
        ref.isDocLink   = r.isDocLink;
        ref.isCompose   = r.isCompose;   // S5-E: HAS-A member-variable type edge — NEVER enters call graph
        ref.recv        = r.recv;        // P2-D receiver shape (this/self/var) for one-hop narrowing
        ref.recvVar     = std::move( r.recvVar );
        ref.argCount    = r.argCount;        // B2.2: call-site positional arg count (when countable)
        ref.argCountKnown = r.argCountKnown; // B2.2: whether argCount is reliable (no spread/splat)
        ref.fieldName   = std::move( r.fieldName );   // S5-E: the member variable name (e.g. "m_pool")
        ref.composeRel  = std::move( r.composeRel );  // S5-E: "creates" or "uses"
        ref.startByte   = r.startByte;                // shadow fix round: for the block-span containment test
        ref.fromSymbol  = refSweep.find( r.fileId, r.startByte );
    }
}

// member-variable round (card A3): a Python field is DEFINED by its first `self.x = …` assignment, and that very
// identifier is what the value-use visitor captured as a role="write" ref — the definition's own name is not a
// use of it (usescheck.sh 3c pins the same rule for C++ locals). rawDefs is aligned 1:1 with result.symbols
// (assignSymbols), so a Field def's (fileId, nameByte) is the exact site to drop. C/C++ fields never reach here
// (a field_identifier in a declarator is not a value use), so the pass is a no-op there; every other ref keeps
// its position and order.
inline void dropFieldDefinitionSites( IngestResult& result, const std::vector<RawDef>& rawDefs )
{
    HashMap<std::uint64_t, char> defSite;
    for( const RawDef& d : rawDefs )
    {
        if( d.kind == SymKind::Field )
        {
            defSite.try_emplace( ( std::uint64_t( d.fileId ) << 32 ) | d.nameByte, 1 );
        }
    }
    if( defSite.empty() )
    {
        return;
    }
    std::erase_if( result.references, [ & ]( const Reference& r )
                   {
                       return ( r.role == RefRole::Read || r.role == RefRole::Write )
                           && defSite.find( ( std::uint64_t( r.fileId ) << 32 ) | r.startByte ) != defSite.end();
                   } );
}

// P2-D Rule 2: attribute each local var→type binding to its enclosing def (same containment scan as refs),
// in deterministic (file, byte, var) order. A binding whose position is file-scope (kNoNode) is kept too —
// buildGraph keys on (fromSymbol, var), so a file-scope binding only ever matches a file-scope recvVar call.
inline void emitBindings( IngestResult& result, std::vector<RawBind>& rawBinds, const DefSpanIndex& spanIndex )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/build-model: sort+emit binds" );

    std::sort( rawBinds.begin(), rawBinds.end(),
               []( const RawBind& a, const RawBind& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.startByte != b.startByte )
                   {
                       return a.startByte < b.startByte;
                   }
                   if( a.var != b.var )
                   {
                       return a.var < b.var;
                   }
                   // L3: a decl can emit BOTH a Rule-2 type record and a fn record at one (file, byte, var) —
                   // kind+typeName make the order strict, so the merged-across-threads sort is a total order.
                   if( a.kind != b.kind )
                   {
                       return a.kind < b.kind;
                   }
                   return a.typeName < b.typeName;
               } );
    result.bindings.resize( rawBinds.size() );
    DefSweep bindSweep{ spanIndex.spans, spanIndex.fileSpanStart };
    std::size_t outBindIndex = 0;
    for( RawBind& rb : rawBinds )   // rawBinds consumed here → move its 2 strings into the Binding
    {
        Binding& b = result.bindings[ outBindIndex++ ];
        b.fileId     = rb.fileId;
        b.kind       = rb.kind;
        b.spanStart  = rb.spanStart;   // shadow fix round: the declaring block's span rides through
        b.spanEnd    = rb.spanEnd;
        b.var        = std::move( rb.var );
        b.typeName   = std::move( rb.typeName );
        b.fromSymbol = bindSweep.find( rb.fileId, rb.startByte );
    }
}

// A4-R5: FFI binding aliases in a deterministic total order (fileId, kind, aliasName, targetScope,
// targetName) so buildGraph's alias tables are built identically warm-vs-cold, run-to-run.
inline void emitBindingAliases( IngestResult& result, std::vector<BindingAlias>& rawFfis )
{
    std::sort( rawFfis.begin(), rawFfis.end(),
               []( const BindingAlias& a, const BindingAlias& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.kind != b.kind )
                   {
                       return a.kind < b.kind;
                   }
                   if( a.aliasName != b.aliasName )
                   {
                       return a.aliasName < b.aliasName;
                   }
                   if( a.targetScope != b.targetScope )
                   {
                       return a.targetScope < b.targetScope;
                   }
                   return a.targetName < b.targetName;
               } );
    result.bindingAliases = std::move( rawFfis );
}

// B6.3: HTTP-route DEFs need no byte-span attribution (their handler is resolved by NAME, in the
// DEF's own file, by buildGraph) — just a deterministic total order.
inline void emitRouteDefs( IngestResult& result, std::vector<RouteDef>& rawRouteDefs )
{
    std::sort( rawRouteDefs.begin(), rawRouteDefs.end(),
               []( const RouteDef& a, const RouteDef& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.line != b.line )
                   {
                       return a.line < b.line;
                   }
                   if( a.method != b.method )
                   {
                       return a.method < b.method;
                   }
                   return a.path < b.path;
               } );
    result.routeDefs = std::move( rawRouteDefs );
}

// B6.3: HTTP-route USEs attribute fromSymbol the same way refs/binds do above — byte-span containment
// over the SAME DefSpanIndex (a fresh DefSweep cursor; the previous ones are per-file stateful and
// already exhausted).
inline void emitRouteUses( IngestResult& result, std::vector<RawRouteUse>& rawRouteUses, const DefSpanIndex& spanIndex )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/build-model: sort+emit route uses" );

    std::sort( rawRouteUses.begin(), rawRouteUses.end(),
               []( const RawRouteUse& a, const RawRouteUse& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.startByte != b.startByte )
                   {
                       return a.startByte < b.startByte;
                   }
                   return a.path < b.path;
               } );
    result.routeUses.resize( rawRouteUses.size() );
    DefSweep routeSweep{ spanIndex.spans, spanIndex.fileSpanStart };
    std::size_t outRouteIndex = 0;
    for( RawRouteUse& ru : rawRouteUses )   // rawRouteUses consumed here → move its string into the RouteUse
    {
        RouteUse& out = result.routeUses[ outRouteIndex++ ];
        out.fileId     = ru.fileId;
        out.line       = ru.line;
        out.method     = ru.method;
        out.path       = std::move( ru.path );
        out.fromSymbol = routeSweep.find( ru.fileId, ru.startByte );
    }
}

}   // namespace

}   // namespace rw
