// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  test/selfcheckfix/disclose_contract.cpp
//
//  The compile-time contract of DISCLOSE( sink, why[, "msg"] ) and Diagnostics::answerUnchanged (src/infra/Diagnostics.h
//  §4b), stated as code. Nothing links this file. test/selfcheckcheck.sh arm (K) compiles it -fsyntax-only:
//    - as is, in the plain and the NDEBUG flavour: every static_assert holds and every DISCLOSE below compiles;
//    - once per RW_NEG_* switch, in both flavours: each must FAIL to compile, and the diagnostic must name the defect.
//  It lives in a *fix directory, like every gate fixture: nothing calls it, and --quality-delta's dead-code kind exempts
//  fixture paths. The plain compile is each negative's contrast: the same file, one line different, compiles, so a
//  negative that fails for an unrelated reason (a missing include, a typo in this file) cannot pass as a refusal.
//
#include "infra/Diagnostics.h"

#include <cstdint>

namespace disclosecontract
{

// A model sink: the reasons it can record are a closed scoped enum it owns; disclose() sets the field an emitter reads.
struct Model
{
    enum class DisclosureWhy : std::uint8_t
    {
        Truncated,
        Unreadable,
    };
    std::uint32_t truncatedCount  = 0;
    std::uint32_t unreadableCount = 0;

    // One counter per reason, indexed by the reason itself — deliberately not the switch a src/ sink uses (a sink there
    // sets the field its emitter reads; this one only has to be observable by arm (S)).
    void disclose( DisclosureWhy why ) noexcept
    {
        std::uint32_t* const counters[] = { &truncatedCount, &unreadableCount };
        ++*counters[ static_cast<std::uint8_t>( why ) ];
    }
};

// Shapes that must NOT model the contract, one defect each.
struct NoWhy
{
    void disclose( int ) noexcept {}
};
struct UnscopedWhy
{
    enum DisclosureWhy { A };                                  // promotes to int: a bare integer would be accepted
    void disclose( DisclosureWhy ) noexcept {}
};
struct NotNoexcept
{
    enum class DisclosureWhy { A };
    void disclose( DisclosureWhy ) {}                          // a disclosure that can throw can lose the disclosure
};
struct ReturnsStatus
{
    enum class DisclosureWhy { A };
    bool disclose( DisclosureWhy ) noexcept { return true; }   // a result nobody reads is a result that gets ignored
};
struct OtherSink
{
    enum class DisclosureWhy { A };
    void disclose( DisclosureWhy ) noexcept {}
};

static_assert( Diagnostics::DisclosureSink<Model> );
static_assert( Diagnostics::DisclosureSink<Model&> );
static_assert( Diagnostics::DisclosureSink<OtherSink> );
static_assert( Diagnostics::DisclosureSink<const Diagnostics::AnswerUnchanged> );
static_assert( Diagnostics::DisclosureSink<const Diagnostics::AnswerRefused> );
static_assert( !Diagnostics::DisclosureSink<const Model> );     // disclose() records: a const sink cannot
static_assert( !Diagnostics::DisclosureSink<int> );
static_assert( !Diagnostics::DisclosureSink<NoWhy> );
static_assert( !Diagnostics::DisclosureSink<UnscopedWhy> );
static_assert( !Diagnostics::DisclosureSink<NotNoexcept> );
static_assert( !Diagnostics::DisclosureSink<ReturnsStatus> );

// The four spellings a degrade site may use, and the defects that must not compile.
inline void sites( Model& model, const char* runtimeText, Model::DisclosureWhy runtimeWhy, int notASink )
{
    DISCLOSE( model, Model::DisclosureWhy::Truncated );
    DISCLOSE( model, Model::DisclosureWhy::Unreadable, "contract: one file could not be read — its rows are absent from the answer" );
    DISCLOSE( Diagnostics::answerUnchanged, "contract: the cache write failed — this answer is already computed, only the next run is cold" );
    DISCLOSE( Diagnostics::answerRefused, "contract: the verb exits 1 naming the unreadable file; no answer is printed" );
    DISCLOSE( "contract: the one-argument trace still compiles (and still ships nothing)" );

#if defined( RW_NEG_NOT_A_SINK )
    DISCLOSE( notASink, Model::DisclosureWhy::Truncated );
#elif defined( RW_NEG_NOT_NOEXCEPT )
    NotNoexcept throwing;
    DISCLOSE( throwing, NotNoexcept::DisclosureWhy::A );
#elif defined( RW_NEG_RUNTIME_WHY )
    DISCLOSE( model, runtimeWhy );
#elif defined( RW_NEG_WRONG_WHY_TYPE )
    DISCLOSE( model, OtherSink::DisclosureWhy::A );
#elif defined( RW_NEG_EMPTY_REASON )
    DISCLOSE( Diagnostics::answerUnchanged, "" );
#elif defined( RW_NEG_RUNTIME_REASON )
    DISCLOSE( Diagnostics::answerUnchanged, runtimeText );
#elif defined( RW_NEG_NONLITERAL_MSG )
    DISCLOSE( model, Model::DisclosureWhy::Truncated, runtimeText );
#elif defined( RW_NEG_NO_ARGS )
    DISCLOSE();
#endif

    static_cast<void>( runtimeText );
    static_cast<void>( runtimeWhy );
    static_cast<void>( notASink );
}

} // namespace disclosecontract

#if defined( RW_RUN_SINKS )
// test/selfcheckcheck.sh arm (S) builds THIS translation unit as a program, optimised, in the NDEBUG flavour a user runs
// (and in the plain one): the sink form must RECORD in both — the whole point of it is that the release binary still
// discloses after the trace is compiled out. Exit 0 and one line "truncated=1 unreadable=1" only when both reasons landed.
#include <cstdio>
#include <string>
int main()
{
    disclosecontract::Model model;
    disclosecontract::sites( model, "run-time text", disclosecontract::Model::DisclosureWhy::Truncated, 0 );
    const std::string line = "truncated=" + std::to_string( model.truncatedCount ) + " unreadable=" + std::to_string( model.unreadableCount ) + "\n";
    std::fputs( line.c_str(), stdout );
    return ( model.truncatedCount == 1 && model.unreadableCount == 1 ) ? 0 : 1;
}
#endif
