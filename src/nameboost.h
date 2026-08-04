#pragma once

// nameboost.h — r5 EXPERIMENT (pre-registered: bench/locbench/results/r5_nameboost/PREREG.md, incl. the
// 2026-08-04 pre-run amendments): query-noun-in-name lift under the CONCEPTUAL (subtoken+body) route.
// INERT unless RIPWIRE_NAMEBOOST="<minTokLen>,<maxLifted>" parses to values in range — the default binary
// is byte-identical with the env unset (gate: test/nameboostcheck.sh; verified against a reference build).
//
// The r3-headroom loss shape this attacks (q07/q08): a MIXED conceptual query that embeds a name or name
// fragment ("…where the match object is produced"; "form.is_valid()"). The subtoken route dilutes the
// name evidence into common tokens, so the symbol carrying the query's own noun ranks ~100th or drops
// out of the pruned pool entirely. The name-exact router already wins when the query IS a name; this is
// the in-between shape.
//
// Mechanism (why this is NOT the rejected r4 shape): a symbol FIRES on DIRECT NAME EVIDENCE — a raw query
// token (maximal [A-Za-z0-9_]+ run, lowercased) of length >= minTokLen whose camel/snake subtoken sequence
// is a CONTIGUOUS run of the symbol's own name subtokens ("match" → ResolverMatch; "is_valid" → is_valid)
// — not on adjacency to a scored neighbor (r4's chooser guessed; this one reads the task text). The
// anti-noise guard is the PREREG's "positive body/doc score": the symbol's doc-comment+body postings row
// must contain >= 1 query subtoken that is NOT one of the symbol's own name subtokens — name-only
// evidence never lifts. (Two vacuity traps make the exclusion necessary: a name hit alone always yields
// positive TOTAL BM25 score via the name field, and the body span starts at sigStartByte, so the row
// itself contains the signature's name-echo. Evidence-beyond-the-name is the only non-vacuous reading of
// the registered guard, and test/nameboostcheck.sh (iii) pins it.)
//
// Placement is the mention boost's slot ladder, BELOW the mention band: fired symbols are walked by
// (current score desc, id asc); one already sitting at-or-above the next slot target is SKIPPED WITHOUT
// consuming a slot (max() placement would no-op — the already-visible strong hits must not eat the
// ladder); the first maxLifted below-slot symbols land at top*(1 - kMentionTopGapStep*(kMentionMaxFiles
// + 1 + j)), j = 0.. — strictly below #1 and below every mention-band slot. #1 is never displaced.
//
// Amortization (PREREG amendment 3): the pass touches ONLY in-memory symbol names plus the persisted
// doc/body postings rows the rich cache already carries — no file read, no per-query corpus rescan (the
// r3 deviation this amendment exists to not repeat). Requires lex stats (hasLexStats): on the rare
// stat-less ingests (lean verbs, multi-root merges, stubs) the boost stays inert — the guard cannot be
// evaluated without the rows, and scanning bodies to build it per query is exactly the forbidden rescan.
//
// RIPWIRE_NAMEBOOST_AUDIT=1 (with the boost active) prints every FIRED symbol to STDERR — the amendment-2
// targeting audit re-verifies its Python trigger mirror against this exact production predicate. stderr
// only; the stdout XML is untouched (G4).

#include "model.h"
#include "lexindex.h"   // forEachLexSubtoken (the ONE subtoken state machine) + lexSubtokenHash
#include "mention.h"    // kMentionTopGapStep / kMentionMaxFiles — the ONE slot-ladder vocabulary
#include "envpair.h"    // the ONE "<a>,<b>" experiment-env parser (shared with r4 siblift)
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

inline constexpr std::size_t kNameboostMinTokFloor = 2;    // env values outside the range mean OFF, never a clamp-and-guess
inline constexpr std::size_t kNameboostMinTokCeil  = 16;
inline constexpr std::size_t kNameboostMaxLifted   = 8;

// parse "<minTokLen>,<maxLifted>" — returns (0,0) = off for anything malformed or out of range.
inline std::pair<std::size_t, std::size_t> nameboostParams()
{
    return parseEnvSizePair( "RIPWIRE_NAMEBOOST", kNameboostMinTokFloor, kNameboostMinTokCeil, 1, kNameboostMaxLifted );
}

namespace nameboost_detail
{

// lowercase-compare a raw name-subtoken span against an already-lowercase query subtoken. The state
// machine guarantees only the span's FIRST byte can be uppercase (lexindex.h), so one head fold suffices.
inline bool spanEqualsLower( std::string_view text, std::size_t start, std::size_t end, const std::string& q ) noexcept
{
    const std::size_t len = end - start;
    if( q.size() != len || len == 0 )
    {
        return false;
    }
    const unsigned char head = static_cast<unsigned char>( text[start] );
    const char          low  = ( head >= 'A' && head <= 'Z' ) ? char( head - 'A' + 'a' ) : char( head );
    if( low != q[0] )
    {
        return false;
    }
    for( std::size_t k = 1; k < len; ++k )
    {
        if( text[ start + k ] != q[k] )
        {
            return false; // later bytes of a subtoken are already lowercase/digit on both sides
        }
    }
    return true;
}

// does one qualifying query token (as its >= 1 subtokens, in order) appear as a CONTIGUOUS run of the
// name's subtoken spans? "match" → [resolver][match] yes; "is_valid" ([is][valid]) → [is][valid] yes.
inline bool tokenFiresOnName( std::string_view name, const std::vector<std::vector<std::string>>& qTokSubs )
{
    // the name's subtoken spans (>= 2 bytes, mirroring subtokens()/scanField) — small fixed-shape scratch
    std::vector<std::pair<std::size_t, std::size_t>> spans;
    forEachLexSubtoken( name, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte )
    {
        if( tokEndByte - tokStartByte >= 2 )
        {
            spans.emplace_back( tokStartByte, tokEndByte );
        }
    } );
    if( spans.empty() )
    {
        return false;
    }
    for( const std::vector<std::string>& subs : qTokSubs )
    {
        if( subs.empty() || subs.size() > spans.size() )
        {
            continue;
        }
        for( std::size_t at = 0; at + subs.size() <= spans.size(); ++at )
        {
            bool all = true;
            for( std::size_t k = 0; k < subs.size() && all; ++k )
            {
                all = spanEqualsLower( name, spans[ at + k ].first, spans[ at + k ].second, subs[k] );
            }
            if( all )
            {
                return true;
            }
        }
    }
    return false;
}

} // namespace nameboost_detail

// Apply the lift to lensRank (size == ing.symbols.size()). CALLER contract: routed, conceptual
// (subtoken+body) route only, and the same lensRank every other slot-ladder boost reads. Returns true if
// anything moved.
inline bool applyNameBoost( const IngestResult& ing, std::string_view task, std::vector<float>& lensRank,
                            std::size_t minTokLen, std::size_t maxLifted )
{
    using namespace nameboost_detail;
    const std::size_t S = ing.symbols.size();
    if( minTokLen == 0 || maxLifted == 0 || lensRank.size() != S || lensRank.empty() )
    {
        return false;
    }
    // the body/doc-evidence guard reads the persisted doc+body postings rows; without them (lean ingest,
    // multi-root merge, stub) the boost stays inert — see the header's amortization note.
    if( !ing.hasLexStats || ing.lexTokenRowOffsets.size() != S + 1 )
    {
        return false;
    }

    // qualifying RAW query tokens: maximal [A-Za-z0-9_]+ byte runs, lowercased, raw length >= minTokLen,
    // deduped, each expanded to its subtoken sequence (>= 2-byte subtokens; empty expansions drop out)
    std::vector<std::string>              qTokens;
    std::vector<std::vector<std::string>> qTokSubs;
    {
        const auto isIdent = []( unsigned char c ) noexcept
        { return ( c >= 'A' && c <= 'Z' ) || ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' ) || c == '_'; };
        std::size_t runStart = std::string_view::npos;
        for( std::size_t k = 0; k <= task.size(); ++k )
        {
            const bool in = k < task.size() && isIdent( static_cast<unsigned char>( task[k] ) );
            if( in && runStart == std::string_view::npos )
            {
                runStart = k;
            }
            if( !in && runStart != std::string_view::npos )
            {
                if( k - runStart >= minTokLen )
                {
                    std::string low( task.substr( runStart, k - runStart ) );
                    for( char& c : low )
                    {
                        if( c >= 'A' && c <= 'Z' ) { c = char( c - 'A' + 'a' ); }
                    }
                    if( std::find( qTokens.begin(), qTokens.end(), low ) == qTokens.end() )
                    {
                        std::vector<std::string> subs;
                        forEachLexSubtoken( low, [ & ]( std::size_t a, std::size_t b )
                        {
                            if( b - a >= 2 ) { subs.emplace_back( low.substr( a, b - a ) ); }
                        } );
                        if( !subs.empty() )
                        {
                            qTokens.push_back( std::move( low ) );
                            qTokSubs.push_back( std::move( subs ) );
                        }
                    }
                }
                runStart = std::string_view::npos;
            }
        }
    }
    if( qTokSubs.empty() )
    {
        return false;
    }

    // the WHOLE query's unique subtoken hashes — the body/doc-evidence guard's probe set (the same
    // vocabulary BM25 scores with, not just the qualifying tokens)
    std::vector<std::uint64_t> qSubHashes;
    forEachLexSubtokenHashed( task, [ & ]( std::size_t a, std::size_t b, std::uint64_t h )
    {
        if( b - a >= 2 )
        {
            qSubHashes.push_back( h );
        }
    } );
    std::sort( qSubHashes.begin(), qSubHashes.end() );
    qSubHashes.erase( std::unique( qSubHashes.begin(), qSubHashes.end() ), qSubHashes.end() );
    if( qSubHashes.empty() )
    {
        return false;
    }

    // fired set: positive current score (a pruned-to-zero score cannot be ordered — the caller disables
    // MaxScore pruning while the boost is active), direct name evidence, positive body/doc evidence
    std::vector<NodeId> fired;
    for( std::size_t i = 0; i < S; ++i )
    {
        if( !( lensRank[i] > 0.f ) || !tokenFiresOnName( ing.symbols[i].name, qTokSubs ) )
        {
            continue;
        }
        const std::uint64_t* rowBegin = ing.lexTokenHashes.data() + ing.lexTokenRowOffsets[i];
        const std::uint64_t* rowEnd   = ing.lexTokenHashes.data() + ing.lexTokenRowOffsets[ i + 1 ];
        // the symbol's own name subtokens are EXCLUDED from the evidence probe: the body span starts at
        // sigStartByte, so the row always echoes the signature's name — see the guard note in the header
        std::vector<std::uint64_t> nameHashes;
        forEachLexSubtokenHashed( ing.symbols[i].name, [ & ]( std::size_t a, std::size_t b, std::uint64_t h )
        {
            if( b - a >= 2 )
            {
                nameHashes.push_back( h );
            }
        } );
        bool evidence = false;
        for( const std::uint64_t h : qSubHashes )
        {
            if( std::find( nameHashes.begin(), nameHashes.end(), h ) != nameHashes.end() )
            {
                continue; // name-echo — not body/doc evidence
            }
            const std::uint64_t* it = std::lower_bound( rowBegin, rowEnd, h );
            if( it != rowEnd && *it == h )
            {
                evidence = true;
                break;
            }
        }
        if( evidence )
        {
            fired.push_back( NodeId( i ) );
        }
    }
    if( fired.empty() )
    {
        return false;
    }
    std::sort( fired.begin(), fired.end(), [ & ]( const NodeId a, const NodeId b ) noexcept
               { return lensRank[a] != lensRank[b] ? lensRank[a] > lensRank[b] : a < b; } );

    if( std::getenv( "RIPWIRE_NAMEBOOST_AUDIT" ) )
    {
        for( const NodeId id : fired )
        {
            const Symbol& s = ing.symbols[id];
            std::fprintf( stderr, "nameboost-audit:\t%s\t%s\n",
                          s.fileId < ing.files.size() ? ing.files[ s.fileId ].c_str() : "?", s.name.c_str() );
        }
    }

    float topScore = 0.0f;
    for( const float s : lensRank )
    {
        topScore = std::max( topScore, s );
    }
    if( !( topScore > 0.0f ) )
    {
        return false;
    }

    // slot ladder BELOW the mention band: slot j lands at top*(1 - step*(kMentionMaxFiles + 1 + j)).
    // Walk score-desc; an already-at-or-above-slot symbol is skipped WITHOUT consuming a slot.
    bool        moved  = false;
    std::size_t placed = 0;
    for( const NodeId id : fired )
    {
        if( placed >= maxLifted )
        {
            break;
        }
        const float slot = topScore * ( 1.0f - kMentionTopGapStep * float( kMentionMaxFiles + 1 + placed ) );
        if( !( slot > 0.0f ) )
        {
            break; // ladder ran below zero — nothing below here can be placed honestly
        }
        if( lensRank[id] >= slot )
        {
            continue; // already visible at/above this slot — do not spend the ladder on a no-op
        }
        lensRank[id] = slot;
        moved        = true;
        ++placed;
    }
    return moved;
}

} // namespace rw
