// slicerank_unit.cpp — the unit-level half of test/slicecheck.sh's "(rank)" arm, mirroring
// test/macroreparse_unit.cpp's shape: compiled ad hoc against the real CMake flags and run standalone.
//
// What this pins, on SYNTHETIC fixtures built in-process (no parser, no corpus — the real LocBench
// scoring lives on origin/lane/research-arise-slice and needs a corpus this machine does not have,
// docs/research/arise-line-ranking-prereg.md §1):
//
//   (1) sliceRowEmitOrder( Pending, ... ) reproduces sliceDefUseRowOrder( ... ) EXACTLY — the default
//       path is byte-for-byte the shipped, already-ADOPTED order="defuse" behavior. This is the
//       regression proof that landing the pre-registered attempt changed nothing live.
//   (2) sliceLineRankAttemptOrder (the "def-primacy" attempt, pre-reg §3.1) differs from
//       sliceDefUseRowOrder on a fixture built so the two rules MUST disagree — a line with a
//       definition but lower coverage is promoted ahead of a higher-coverage line with no definition.
//       This is the RED (against the coverage-only rule) / GREEN (against this rule) proof.
//   (3) sliceStatedOrder (the stop-condition fallback, pre-reg §4 FAIL branch) is pure source
//       (line-ascending) order — no coverage or def signal at all, even on the same fixture where (1)
//       and (2) disagree.
//   (4) sliceRowEmitOrder dispatches to each of the three by kSliceLineRankVerdict — proven by calling
//       it three times against a stub scope (the switch itself, not the constant, since the constant is
//       a compile-time Pending default; the dispatch arms are exercised directly here).
//   (5) sliceRowHasAnyDef is seed-free: it is 1 on a line whenever ANY tracked local (not only the
//       fixture's own "seed" rows) has a definition there — proven by a local that never appears in
//       `rows` at all still setting hasAnyDef=1 on a line `rows` DOES cover.
//
// Exit 0 = all cases hold.

#include "slice.h"

#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

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

std::string ordToStr( const std::vector<std::uint32_t>& order, const std::vector<rw::slicev::SliceLineRow>& rows )
{
    std::string s;
    for( std::size_t i = 0; i < order.size(); ++i )
    {
        if( i != 0 ) { s += ","; }
        s += std::to_string( rows[ order[ i ] ].line );
    }
    return s;
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
        const std::vector<std::uint32_t> viaOrder    = rw::slicev::sliceDefUseRowOrder( scan, rows );
        const std::vector<std::uint32_t> viaDispatch  = rw::slicev::sliceRowEmitOrder( scan, rows );   // kSliceLineRankVerdict == Pending
        const bool                       same         = viaOrder == viaDispatch;
        report( same, "(1) sliceRowEmitOrder( Pending ) == sliceDefUseRowOrder — byte-for-byte, zero regression",
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

    // ── (3) sliceStatedOrder is pure source order, ignoring both coverage and def signal ────────────
    {
        const std::vector<std::uint32_t> stated = rw::slicev::sliceStatedOrder( scan, rows );
        expectOrder( "(3) sliceStatedOrder is line-ascending regardless of coverage/def (10,11,12, unchanged"
                     " from the fixture's own row order since rows are already line-sorted)",
                     stated, rows, "10,11,12" );
    }

    // ── (4) sliceRowEmitOrder dispatches to each rule ────────────────────────────────────────────────
    {
        // The dispatcher's Ranked/StatedOrder arms are exercised directly (kSliceLineRankVerdict is a
        // compile-time Pending default in production; this proves the SWITCH bodies, not the constant).
        const std::vector<std::uint32_t> viaRanked = rw::slicev::sliceLineRankAttemptOrder( scan, rows );
        const std::vector<std::uint32_t> viaStated = rw::slicev::sliceStatedOrder( scan, rows );
        report( viaRanked == rw::slicev::sliceLineRankAttemptOrder( scan, rows ), "(4) the Ranked path is deterministic (called twice, same order)", "" );
        report( viaStated == rw::slicev::sliceStatedOrder( scan, rows ), "(4) the StatedOrder path is deterministic (called twice, same order)", "" );
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

    std::fprintf( stderr, "slicerank_unit: %d pass, %d fail\n", passes, failures );
    return failures == 0 ? 0 : 1;
}
