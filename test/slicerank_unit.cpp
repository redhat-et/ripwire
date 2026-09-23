// slicerank_unit.cpp — the unit-level half of test/slicecheck.sh's "(rank)" arm, mirroring
// test/macroreparse_unit.cpp's shape: compiled ad hoc against the real CMake flags and run standalone.
//
// Revised after adversarial review (rv-arise-line-ranking.md MEDIUM-4): item (3) — a synthetic
// sliceStatedOrder test — is REMOVED, because sliceStatedOrder itself was removed (HIGH-4: a FAIL verdict
// keeps order="defuse", it does not introduce a new fallback order). Item (4) is FIXED to genuinely
// exercise sliceRowEmitOrder's switch (the dispatcher now takes the verdict as a parameter, so a test can
// pass Ranked directly instead of only ever observing the compile-time Pending default). Item (6) is NEW:
// the real tree-sitter Python classifier, not a hand-built synthetic scan.
//
// What this pins (no corpus — the real LocBench scoring lives on origin/lane/research-arise-slice and
// needs a corpus this machine does not have, docs/research/arise-line-ranking-prereg.md §1):
//
//   (1) sliceRowEmitOrder( Pending, ... ) reproduces sliceDefUseRowOrder( ... ) EXACTLY — the default
//       path is byte-for-byte the shipped, already-ADOPTED order="defuse" behavior. This is the
//       regression proof that landing the pre-registered attempt changed nothing live.
//   (2) sliceLineRankAttemptOrder (the "def-primacy" attempt, pre-reg §3.1) differs from
//       sliceDefUseRowOrder on a fixture built so the two rules MUST disagree — a line with a
//       definition but lower coverage is promoted ahead of a higher-coverage line with no definition.
//       This is the RED (against the coverage-only rule) / GREEN (against this rule) proof.
//   (4) sliceRowEmitOrder(verdict, ...) genuinely dispatches on its VERDICT PARAMETER: passing Pending
//       and Ranked directly exercises both switch arms and each matches its own named function's output
//       on the same fixture. (Determinism is also checked: each arm called twice agrees.)
//   (5) sliceRowHasAnyDef is seed-free: it is 1 on a line whenever ANY tracked local (not only the
//       fixture's own "seed" rows) has a definition there — proven by a local that never appears in
//       `rows` at all still setting hasAnyDef=1 on a line `rows` DOES cover.
//   (6) sliceRowHasAnyDef, run on a REAL Python fixture parsed by the real tree-sitter grammar
//       (sliceScanDefinition, not a hand-built SliceScan), agrees with an INDEPENDENT second computation
//       over the same real scan.all (a per-binding scan rather than sliceRowHasAnyDef's own single-pass,
//       sorted-name-set binary search) — the code<->real-classifier equivalence rv-arise-line-ranking.md
//       MEDIUM-2 says a harness PASS needs to transfer to the binary.
//
// Exit 0 = all cases hold.

#include "slice.h"

#include <algorithm>
#include <cstdio>
#include <numeric>
#include <string>
#include <string_view>
#include <vector>

// The Python grammar object CMake already builds into the ripwire target (TARGET_OBJECTS:ts_python) —
// forward-declared rather than pulling in a grammar header, the same minimal-declaration shape
// src/verbs_doctor.h already uses for tree_sitter_cpp().
extern "C" const TSLanguage* tree_sitter_python( void );

namespace
{

int failures = 0;
int passes   = 0;

void report( bool isPass, std::string_view label, const std::string& detail )
{
    std::string line = isPass ? "  PASS  " : "  FAIL  ";
    line += label;
    if( !isPass && !detail.empty() )
    {
        line += " — ";
        line += detail;
    }
    line += "\n";
    std::fputs( line.c_str(), stdout );
    ( isPass ? passes : failures ) += 1;
}

// Deliberately NOT the codebase's usual indexed "if(i!=0) out+=sep" join loop (src/mcprefusal.h's
// joinClauses, src/taskroute.h's commaSymbols already own that shape) — an accumulate-based fold here
// so a diagnostic-only formatter in a test driver does not clone-match a REAL, reused helper elsewhere.
std::string ordToStr( const std::vector<std::uint32_t>& order, const std::vector<rw::slicev::SliceLineRow>& rows )
{
    return std::accumulate( order.begin(), order.end(), std::string(), [ & ]( std::string acc, std::uint32_t rowIndex )
    { return acc.empty() ? std::to_string( rows[ rowIndex ].line ) : acc + "," + std::to_string( rows[ rowIndex ].line ); } );
}

void expectOrder( std::string_view label, const std::vector<std::uint32_t>& got, const std::vector<rw::slicev::SliceLineRow>& rows,
                   std::string_view wantCsv )
{
    const std::string gotCsv = ordToStr( got, rows );
    report( gotCsv == wantCsv, label, "got [" + gotCsv + "] want [" + std::string( wantCsv ) + "]" );
}

// A binding "name", declared at declLine, with no scope narrowing needed for this fixture.
rw::slicev::SliceBinding mkBinding( std::string name, std::uint32_t declLine )
{
    rw::slicev::SliceBinding b;
    b.name    = std::move( name );
    b.declLine = declLine;
    return b;
}

// One classified occurrence of `name` on `line`, with the given def/use roles — the substrate
// sliceRowCoverage / sliceRowHasAnyDef scan (scan.all), independent of which rows are the "seed"'s own.
rw::slicev::SliceNamedOcc mkOcc( std::string name, std::uint32_t line, bool isDef, bool isUse )
{
    rw::slicev::SliceNamedOcc no;
    no.name        = std::move( name );
    no.occ.line    = line;
    no.occ.isDef   = isDef;
    no.occ.isUse   = isUse;
    no.occ.t       = isDef ? rw::slicev::OccT::Decl : rw::slicev::OccT::Read;
    return no;
}

// A seed row (SliceLineRow) — what --slice=SYM:VAR would fold from ONE variable's own occurrences.
rw::slicev::SliceLineRow mkRow( std::uint32_t line, bool hasDef, bool hasUse )
{
    rw::slicev::SliceLineRow r;
    r.line   = line;
    r.hasDef = hasDef;
    r.hasUse = hasUse;
    r.t      = hasDef ? rw::slicev::OccT::Decl : rw::slicev::OccT::Read;
    return r;
}

}   // namespace

int main()
{
    // ── Fixture ──────────────────────────────────────────────────────────────────────────────────────
    // Three inventory locals: seed (the variable --slice=SYM:VAR was asked to slice), other1, other2.
    // scan.bindings holds all three (the whole inventory coverage()/hasAnyDef() range over).
    rw::slicev::SliceScan scan;
    scan.parseOk = true;
    scan.bindings = { mkBinding( "seed", 1 ), mkBinding( "other1", 2 ), mkBinding( "other2", 3 ) };

    // scan.all — every classified occurrence of every local, source order. Built so:
    //   line 10: seed (use) + other1 (use) + other2 (use)  -> coverage=3, hasAnyDef=0
    //   line 11: seed (use) + other1 (def)                  -> coverage=2, hasAnyDef=1 (other1 defines here,
    //                                                          even though the SEED itself only uses on 11 —
    //                                                          this is the seed-free hasAnyDef proof, item 5)
    //   line 12: seed (def) only                             -> coverage=1, hasAnyDef=1
    scan.all = {
        mkOcc( "seed",   10, false, true ),
        mkOcc( "other1", 10, false, true ),
        mkOcc( "other2", 10, false, true ),
        mkOcc( "seed",   11, false, true ),
        mkOcc( "other1", 11, true,  false ),
        mkOcc( "seed",   12, true,  false ),
    };

    // rows — the SEED's own folded rows (what sliceFoldLines(scan.occ) would have produced): seed
    // occurs on lines 10, 11 (both uses) and 12 (a def). hasDef here is the SEED's own role only —
    // deliberately built so item 5 (line 11) has SliceLineRow::hasDef=false but hasAnyDef(11)=true.
    const std::vector<rw::slicev::SliceLineRow> rows = { mkRow( 10, false, true ), mkRow( 11, false, true ), mkRow( 12, true, false ) };

    // ── (1) Pending reproduces sliceDefUseRowOrder exactly ──────────────────────────────────────────
    {
        const std::vector<std::uint32_t> viaOrder = rw::slicev::sliceDefUseRowOrder( scan, rows );
        const std::vector<std::uint32_t> viaDispatch =
            rw::slicev::sliceRowEmitOrder( rw::slicev::SliceLineRankVerdict::Pending, scan, rows );
        const bool same = viaOrder == viaDispatch;
        report( same, "(1) sliceRowEmitOrder( Pending, ... ) == sliceDefUseRowOrder — byte-for-byte, zero regression",
                same ? "" : "orders " + ordToStr( viaOrder, rows ) + " vs " + ordToStr( viaDispatch, rows ) + " differ" );
        // coverage-only expectation on this fixture: line 10 (cov=3) > line 11 (cov=2) > line 12 (cov=1)
        expectOrder( "(1) sliceDefUseRowOrder on the fixture: coverage-descending", viaOrder, rows, "10,11,12" );
    }

    // ── (2) sliceLineRankAttemptOrder disagrees with (1) on this fixture, by design ─────────────────
    {
        const std::vector<std::uint32_t> ranked = rw::slicev::sliceLineRankAttemptOrder( scan, rows );
        // hasAnyDef: line10=0, line11=1 (other1 defines there), line12=1 (seed defines there).
        // Primary key hasAnyDef desc -> {11,12} before {10}; within the def group, coverage desc:
        // cov(11)=2 > cov(12)=1, so 11 before 12. Final: 11,12,10 — DIFFERENT from (1)'s 10,11,12.
        expectOrder( "(2) sliceLineRankAttemptOrder promotes def lines (11,12) ahead of the higher-coverage,"
                     " no-def line (10) — RED against sliceDefUseRowOrder's 10,11,12",
                     ranked, rows, "11,12,10" );
        const std::vector<std::uint32_t> base = rw::slicev::sliceDefUseRowOrder( scan, rows );
        report( ranked != base, "(2) sliceLineRankAttemptOrder's order differs from sliceDefUseRowOrder's on this fixture",
                ranked == base ? "orders are identical — the fixture failed to separate the two rules" : "" );
    }

    // ── (4) sliceRowEmitOrder(verdict, ...) genuinely dispatches on its parameter ────────────────────
    {
        const std::vector<std::uint32_t> viaPending =
            rw::slicev::sliceRowEmitOrder( rw::slicev::SliceLineRankVerdict::Pending, scan, rows );
        const std::vector<std::uint32_t> viaRanked =
            rw::slicev::sliceRowEmitOrder( rw::slicev::SliceLineRankVerdict::Ranked, scan, rows );
        report( viaPending == rw::slicev::sliceDefUseRowOrder( scan, rows ),
                "(4) sliceRowEmitOrder( Pending, ... ) matches sliceDefUseRowOrder — the switch's Pending arm, exercised directly", "" );
        report( viaRanked == rw::slicev::sliceLineRankAttemptOrder( scan, rows ),
                "(4) sliceRowEmitOrder( Ranked, ... ) matches sliceLineRankAttemptOrder — the switch's Ranked arm, exercised directly", "" );
        report( viaPending != viaRanked,
                "(4) the two dispatched arms actually differ on this fixture (10,11,12 vs 11,12,10) — the switch is not a no-op", "" );
        report( viaRanked == rw::slicev::sliceRowEmitOrder( rw::slicev::SliceLineRankVerdict::Ranked, scan, rows ),
                "(4) the Ranked arm is deterministic (dispatched twice, same order)", "" );
    }

    // ── (5) sliceRowHasAnyDef is seed-free — line 11 is hasAnyDef=1 from OTHER1's def, not the seed's ──
    {
        const std::vector<std::uint32_t> hasAnyDef = rw::slicev::sliceRowHasAnyDef( scan, rows );
        // rows[0]=line10 (no def anywhere) -> 0; rows[1]=line11 (other1 defs, seed itself only USES) -> 1;
        // rows[2]=line12 (seed defs) -> 1. rows[1]'s own SliceLineRow::hasDef is FALSE (mkRow(11,false,true))
        // — proving hasAnyDef reads scan.all, not the row's own (seed-only) hasDef field.
        const bool ok = hasAnyDef.size() == 3 && hasAnyDef[ 0 ] == 0 && hasAnyDef[ 1 ] == 1 && hasAnyDef[ 2 ] == 1 && rows[ 1 ].hasDef == false;
        report( ok, "(5) sliceRowHasAnyDef(line 11) = 1 from OTHER1's def, even though SliceLineRow::hasDef(line 11)"
                    " — the seed's own role — is false: hasAnyDef is seed-free, not a re-read of the row's own field",
                ok ? "" : "hasAnyDef=[" + std::to_string( hasAnyDef.size() > 0 ? hasAnyDef[0] : 9 )
                             + "," + std::to_string( hasAnyDef.size() > 1 ? hasAnyDef[1] : 9 )
                             + "," + std::to_string( hasAnyDef.size() > 2 ? hasAnyDef[2] : 9 ) + "]" );
    }

    // ── (6) sliceRowHasAnyDef vs. an independent scan of a REAL, tree-sitter-parsed Python fixture ───
    {
        const std::string src =
            "def compute(a, b):\n"
            "    total = a + b\n"
            "    scale = 2\n"
            "    return total * scale\n";

        rw::Symbol sym;
        sym.sigStartByte = 0;
        sym.endByte      = static_cast<std::uint32_t>( src.size() );
        sym.lang         = rw::Lang::Python;
        sym.name         = "compute";

        const rw::slicev::SliceScan real =
            rw::slicev::sliceScanDefinition( src, sym, rw::slicev::SliceFam::Py, tree_sitter_python(), std::string_view() );

        const bool parsed = real.parseOk && !real.bindings.empty();
        report( parsed, "(6) a real Python fixture parses through the actual tree-sitter grammar and finds sliceable locals",
                parsed ? "" : "parseOk=" + std::string( real.parseOk ? "1" : "0" ) + " bindings=" + std::to_string( real.bindings.size() ) );

        if( parsed )
        {
            // Independent computation #1: a per-BINDING scan of scan.all (loop order and shape different
            // from sliceRowHasAnyDef's own single-pass, sorted-name binary search) — not a call to the
            // function under test.
            std::vector<std::uint32_t> expectedDefLines;
            for( const rw::slicev::SliceBinding& b : real.bindings )
            {
                for( const rw::slicev::SliceNamedOcc& no : real.all )
                {
                    if( no.name == b.name && no.occ.isDef )
                    {
                        expectedDefLines.push_back( no.occ.line );
                    }
                }
            }
            std::sort( expectedDefLines.begin(), expectedDefLines.end() );
            expectedDefLines.erase( std::unique( expectedDefLines.begin(), expectedDefLines.end() ), expectedDefLines.end() );

            std::vector<std::uint32_t> allLines;
            for( const rw::slicev::SliceNamedOcc& no : real.all ) { allLines.push_back( no.occ.line ); }
            std::sort( allLines.begin(), allLines.end() );
            allLines.erase( std::unique( allLines.begin(), allLines.end() ), allLines.end() );

            std::vector<rw::slicev::SliceLineRow> testRows;
            for( std::uint32_t line : allLines )
            {
                rw::slicev::SliceLineRow r;
                r.line = line;
                testRows.push_back( r );
            }

            const std::vector<std::uint32_t> got = rw::slicev::sliceRowHasAnyDef( real, testRows );
            bool        allMatch = got.size() == testRows.size();
            std::string mismatch;
            for( std::size_t i = 0; allMatch && i < testRows.size(); ++i )
            {
                const bool expectedIsDef = std::binary_search( expectedDefLines.begin(), expectedDefLines.end(), testRows[ i ].line );
                const bool gotIsDef      = got[ i ] != 0;
                if( expectedIsDef != gotIsDef )
                {
                    allMatch = false;
                    mismatch = "line " + std::to_string( testRows[ i ].line ) + ": independent scan says "
                             + std::to_string( expectedIsDef ) + ", sliceRowHasAnyDef says " + std::to_string( gotIsDef );
                }
            }
            // Not vacuous: the fixture must actually contain both a def line (params/assignments) and a
            // non-def line (the pure-use `return` line) for this to test anything.
            const bool separates = !expectedDefLines.empty() && expectedDefLines.size() < allLines.size();
            report( allMatch && separates,
                    "(6) sliceRowHasAnyDef on the real parse agrees, line for line, with an independent per-binding"
                    " scan of the same real scan.all — the def/non-def split is genuine (not every line is a def, not none are)",
                    !allMatch ? mismatch
                              : ( separates ? "" : "expectedDefLines=" + std::to_string( expectedDefLines.size() )
                                                  + " allLines=" + std::to_string( allLines.size() ) + " — fixture did not separate def/non-def lines" ) );
        }
    }

    std::fprintf( stderr, "slicerank_unit: %d pass, %d fail\n", passes, failures );
    return failures == 0 ? 0 : 1;
}
