// extentsuspect_unit.cpp — the rule-level half of test/extentcheck.sh. The shell arms prove the detector on
// real parses; this driver proves each RULE on synthetic extents, including the two (name, scope) that no
// input the current grammars accept can reach end to end. A rule no fixture reaches is still code the next
// span change can break, so it is pinned here rather than trusted.
//
// Every case builds ONE file's definitions in the order the ingest hands them over (startByte ascending,
// endByte descending) and asserts the exact bit set per definition. Exit 0 = all cases hold.

#include "extentsuspect.h"

#include <cstdint>
#include <cstdio>
#include <string_view>
#include <vector>

namespace
{

int failures = 0;

using rw::extent::ExtentDef;

ExtentDef def( std::uint32_t start, std::uint32_t sigEnd, std::uint32_t end, std::uint32_t name, rw::SymKind kind, rw::Lang lang,
               std::string_view nm, std::string_view scope = {}, std::uint8_t recovered = 0 )
{
    ExtentDef d;
    d.startByte  = start;
    d.sigEndByte = sigEnd;
    d.endByte    = end;
    d.nameByte   = name;
    d.kind       = kind;
    d.lang       = lang;
    d.recovered  = recovered;
    d.name       = nm;
    d.scope      = scope;
    return d;
}

void expectBits( std::string_view label, const std::vector<ExtentDef>& defs, const std::vector<std::uint8_t>& want )
{
    std::vector<std::uint8_t>  got( defs.size(), 0xFF );
    rw::extent::ExtentScratch  scratch;
    rw::extent::classifyFileExtents( defs, got, scratch );
    for( std::size_t i = 0; i < defs.size(); ++i )
    {
        if( got[ i ] != want[ i ] )
        {
            std::printf( "  FAIL  %.*s: def %zu (%.*s) bits=%u want=%u\n", int( label.size() ), label.data(), i,
                         int( defs[ i ].name.size() ), defs[ i ].name.data(), unsigned( got[ i ] ), unsigned( want[ i ] ) );
            ++failures;
            return;
        }
    }
    std::printf( "  PASS  %.*s\n", int( label.size() ), label.data() );
}

void expectText( std::uint8_t bits, std::string_view want )
{
    const std::string_view got = rw::extent::extentSuspectReasons( bits );
    if( got != want )
    {
        std::printf( "  FAIL  reasons(%u) = '%.*s', want '%.*s'\n", unsigned( bits ), int( got.size() ), got.data(),
                     int( want.size() ), want.data() );
        ++failures;
        return;
    }
    std::printf( "  PASS  reasons(%u) = '%.*s'\n", unsigned( bits ), int( want.size() ), want.data() );
}

}   // namespace

int main()
{
    using rw::Lang;
    using rw::SymKind;
    using namespace rw::extent;

    // ── R1 (name): a definition's own name lies inside its own signature span ─────────────────────────
    expectBits( "R1 name inside the signature is clean",
                { def( 100, 150, 200, 120, SymKind::Function, Lang::JavaScript, "f" ) }, { 0 } );
    expectBits( "R1 name inside the BODY is suspect (a span adopted from an encloser)",
                { def( 100, 150, 200, 160, SymKind::Function, Lang::JavaScript, "f" ) }, { kSuspectName } );
    expectBits( "R1 name before the definition starts is suspect",
                { def( 100, 150, 200, 90, SymKind::Function, Lang::Python, "f" ) }, { kSuspectName } );
    expectBits( "R1 bodyless definition: the whole extent is the signature",
                { def( 100, 200, 200, 199, SymKind::Function, Lang::Cpp, "f" ) }, { 0 } );
    expectBits( "R1 a section's name is an identity key, not a declarator (markdown file node names EOF)",
                { def( 0, 500, 500, 500, SymKind::Section, Lang::Markdown, "README" ) }, { 0 } );

    // ── R3 (head): a definition inside a BODIED definition's signature span, C family only ───────────
    expectBits( "R3 struct in a function's return type flags both and the whole component",
                { def( 0, 800, 1000, 790, SymKind::Function, Lang::Cpp, "swallower" ),
                  def( 0, 20, 700, 7, SymKind::Struct, Lang::Cpp, "Swallowed" ),
                  def( 100, 120, 200, 105, SymKind::Method, Lang::Cpp, "member", "Swallowed" ),
                  def( 1000, 1050, 1100, 1005, SymKind::Function, Lang::Cpp, "after" ) },
                { kSuspectHead, kSuspectHead, kSuspectHead, 0 } );
    expectBits( "R3 the same shape outside the C family is not judged",
                { def( 0, 800, 1000, 790, SymKind::Function, Lang::TypeScript, "f" ),
                  def( 0, 20, 700, 7, SymKind::Class, Lang::TypeScript, "C" ) },
                { 0, 0 } );
    expectBits( "R3 a bodyless container (typedef struct) holds its struct legitimately",
                { def( 0, 100, 100, 95, SymKind::Other, Lang::C, "Alias" ),
                  def( 8, 20, 90, 15, SymKind::Struct, Lang::C, "Tag" ) },
                { 0, 0 } );
    expectBits( "R3 identical extents are a duplicate capture, not a containment",
                { def( 0, 50, 100, 10, SymKind::Function, Lang::Cpp, "a" ),
                  def( 0, 50, 100, 12, SymKind::Function, Lang::Cpp, "b" ) },
                { 0, 0 } );
    expectBits( "R3 definitions in a signature AFTER the name are valid C++ (mem-initializer lambda: local struct, vexing-parse local)",
                { def( 0, 900, 1000, 10, SymKind::Method, Lang::Cpp, "Storage", "Storage" ),
                  def( 200, 230, 300, 207, SymKind::Class, Lang::Cpp, "LocalProtector", "LocalProtector" ),
                  def( 240, 260, 260, 245, SymKind::Method, Lang::Cpp, "clone", "LocalProtector" ),
                  def( 400, 450, 450, 420, SymKind::Function, Lang::Cpp, "queuedBatch" ) },
                { 0, 0, 0, 0 } );
    expectBits( "R3 a definition inside a body is clean",
                { def( 0, 20, 500, 7, SymKind::Class, Lang::Cpp, "Outer" ),
                  def( 30, 60, 120, 40, SymKind::Method, Lang::Cpp, "m", "Outer" ) },
                { 0, 0 } );

    // ── R2 (scope): filed under C:: yet physically inside a DIFFERENT class, C++ only ─────────────────
    expectBits( "R2 member filed under another same-file class is suspect; its honest sibling is not",
                { def( 0, 20, 500, 7, SymKind::Struct, Lang::Cpp, "Holder", "Holder" ),
                  def( 50, 80, 150, 60, SymKind::Method, Lang::Cpp, "misplaced", "Target" ),
                  def( 200, 230, 300, 210, SymKind::Method, Lang::Cpp, "fine", "Holder" ),
                  def( 320, 330, 380, 322, SymKind::Method, Lang::Cpp, "elsewhere", "NotInThisFile" ),
                  def( 390, 420, 420, 395, SymKind::Method, Lang::Cpp, "friendDecl", "Target" ),
                  def( 430, 440, 490, 436, SymKind::Struct, Lang::Cpp, "Inner", "Inner" ),
                  def( 600, 620, 700, 607, SymKind::Struct, Lang::Cpp, "Target", "Target" ) },
                { 0, kSuspectScope, 0, 0, 0, 0, 0 } );
    expectBits( "R2 is C++ only",
                { def( 0, 20, 500, 7, SymKind::Class, Lang::Python, "Holder", "Holder" ),
                  def( 50, 80, 150, 60, SymKind::Method, Lang::Python, "m", "Target" ),
                  def( 600, 620, 700, 607, SymKind::Class, Lang::Python, "Target", "Target" ) },
                { 0, 0, 0 } );
    // Same-file class names that PREFIX one another. Both the sort and the lookup then compare views of unequal
    // length that agree on the shorter one — the one comparison libstdc++'s string_view operator< answers by
    // subtracting the lengths in size_type. G1's integer sanitizer aborts on that wrap, so under the Linux ASan
    // flags extentcheck (U) builds this driver with, this case is the red arm for the default comparator
    // (CI run 34583440115: `8 - 13` from resetExtentScratch's std::sort). Under any flags it pins the answers.
    expectBits( "R2 class names that prefix one another (Tree, TreeGuard, TreeGuardScope) sort and resolve by bytes",
                { def( 0, 20, 500, 7, SymKind::Struct, Lang::Cpp, "TreeGuardScope", "TreeGuardScope" ),
                  def( 50, 80, 150, 60, SymKind::Method, Lang::Cpp, "misplaced", "Tree" ),
                  def( 200, 230, 300, 210, SymKind::Method, Lang::Cpp, "fine", "TreeGuardScope" ),
                  def( 320, 330, 380, 322, SymKind::Method, Lang::Cpp, "prefixOnly", "TreeGuar" ),
                  def( 600, 620, 700, 607, SymKind::Struct, Lang::Cpp, "TreeGuard", "TreeGuard" ),
                  def( 800, 820, 900, 807, SymKind::Class, Lang::Cpp, "Tree", "Tree" ) },
                { 0, kSuspectScope, 0, 0, 0, 0 } );

    // ── R4 (error): a recovered container, everything inside it, and scopeless recovered members ─────
    expectBits( "R4 a recovered container taints every definition inside it, nested classes included",
                { def( 0, 20, 900, 7, SymKind::Struct, Lang::Cpp, "Swallower", "Swallower", kRecoveredContainer ),
                  def( 100, 130, 200, 110, SymKind::Method, Lang::Cpp, "a", "Swallower" ),
                  def( 300, 320, 400, 307, SymKind::Class, Lang::Cpp, "Inner", "Inner" ),
                  def( 330, 350, 380, 335, SymKind::Method, Lang::Cpp, "b", "Inner" ),
                  def( 950, 960, 990, 952, SymKind::Function, Lang::Cpp, "outside" ),
                  def( 1000, 1030, 1100, 1010, SymKind::Method, Lang::Cpp, "orphan", "", kRecoveredOrphan ),
                  def( 1200, 1220, 1300, 1207, SymKind::Class, Lang::Cpp, "Clean", "Clean" ),
                  def( 1230, 1250, 1290, 1235, SymKind::Method, Lang::Cpp, "c", "Clean" ) },
                { kSuspectError, kSuspectError, kSuspectError, kSuspectError, 0, kSuspectError, 0, 0 } );

    // ── rules compose ───────────────────────────────────────────────────────────────────────────────────
    expectBits( "rules compose: a head violation inside a recovered container carries both reasons",
                { def( 0, 20, 2000, 7, SymKind::Struct, Lang::Cpp, "Rec", "Rec", kRecoveredContainer ),
                  def( 100, 900, 1000, 890, SymKind::Method, Lang::Cpp, "swallower", "Rec" ),
                  def( 100, 120, 800, 107, SymKind::Struct, Lang::Cpp, "Inner", "Inner", kRecoveredContainer ) },
                { kSuspectHead | kSuspectError, kSuspectHead | kSuspectError, kSuspectHead | kSuspectError } );

    // ── the reason vocabulary, fixed order ──────────────────────────────────────────────────────────────
    expectText( 0, "" );
    expectText( kSuspectError, "error" );
    expectText( kSuspectHead | kSuspectError, "head,error" );
    expectText( kSuspectName | kSuspectHead | kSuspectScope | kSuspectError, "name,head,scope,error" );

    std::printf( failures == 0 ? "extentsuspect_unit: ALL PASS\n" : "extentsuspect_unit: %d FAILED\n", failures );
    return failures == 0 ? 0 : 1;
}
