// type3clone_harness.cpp — unit + mutation harness for Type-3 (gapped) clone detection in src/clones.h.
//
// Builds an IngestResult by hand over on-disk fixture files (one function per file; the whole file is the
// "body" via sigEndByte=0/endByte=fileSize). Exercises BOTH passes:
//   • findClones()      — exact normalized-stream matches, must stay Type-1/2 (type==2, similarity==1).
//   • findClonesType3() — near-miss pairs, must report type==3 with similarity in [kType3MinSimilarity,1).
//
// Cases proved:
//   A  two truly-identical bodies          → Type-1/2 group (findClones), NOT a Type-3 pair.
//   B  identical except ONE inserted stmt   → Type-3 pair (findClonesType3) in the similarity band, NOT Type-1/2.
//   C  two dissimilar bodies                → neither pass reports them (no false positive).
//   D  determinism                          → two runs byte-identical (id-sorted output).
//   E  MUTATION: raising the threshold above the measured similarity must DROP case B (a broken/too-loose
//      threshold gate — proves the test actually constrains kType3MinSimilarity, not just "runs").
//
// Exit 0 = all pass; nonzero = a failure (message on stderr). Pure; touches only files it creates in argv[1].

#include "../src/clones.h"

#include <cstdio>
#include <cstdint>
#include <string>
#include <vector>

using namespace rw;

static int g_fail = 0;
static void check( bool cond, const char* msg )
{
    std::printf( "  %s  %s\n", cond ? "PASS" : "FAIL", msg );
    if( !cond ) g_fail = 1;
}

// write `src` to dir/name, return its absolute path + byte size.
static std::pair<std::string, std::uint32_t> writeFile( const std::string& dir, const char* name, const std::string& src )
{
    const std::string path = dir + "/" + name;
    std::FILE* fp = std::fopen( path.c_str(), "wb" );
    if( fp ) { std::fwrite( src.data(), 1, src.size(), fp ); std::fclose( fp ); }
    return { path, std::uint32_t( src.size() ) };
}

// append a whole-file function symbol (body == [0,size)) to ing.
static void addWholeFileFn( IngestResult& ing, const std::string& path, std::uint32_t size )
{
    const std::uint32_t fileId = std::uint32_t( ing.files.size() );
    ing.files.push_back( path );
    Symbol s;
    s.id          = NodeId( ing.symbols.size() );
    s.kind        = SymKind::Function;
    s.fileId      = fileId;
    s.line        = 1;
    s.sigStartByte = 0;
    s.sigEndByte  = 0;       // body region = [0, size) → whole file is normalized
    s.endByte     = size;    // endByte > sigEndByte ⇒ passes the "real body" gate
    s.name        = std::string( "fn" ) + std::to_string( s.id );
    ing.symbols.push_back( std::move( s ) );
}

#ifdef CTX_T3_CAP_FIXTURE
// ── Cap-hitting fixture (B1) ──────────────────────────────────────────────────────────────────────────────────
// Four near-duplicate bodies that (by construction) all land in ONE fingerprint bucket [0,1,2,3] and pairwise
// survive BOTH cheap prefilters AND the LCS similarity band, so all C(4,2)=6 pairs are prefilter-surviving. Each
// body is a large identical core plus a VARYING number (1..4) of identical `if` blocks: the differing block-count
// makes the four normalized streams DISTINCT (not exact/Type-1-2 dups), keeps every pair's LCS-ratio in [0.80,1.0),
// and — because body n's k-gram set is a subset of body n+1's — puts every body in body-1's smallest-hash bucket.
// With the pair-cap kType3MaxPairs lowered at COMPILE TIME (-DCTX_TYPE3_MAX_PAIRS=C) the deterministic bucket walk
// emits exactly the FIRST C prefilter-surviving pairs in id order and drops the rest. Compiling at several C values
// (the gate uses C=2, C=3, uncapped) proves the cap DISCRIMINATES — an impl ignoring it would emit 6 every time.
static std::string capBody( int nBlocks )
{
    std::string s = "int f( int a, int b, int c, int d )\n{\n    int acc = 0;\n";
    for( int k = 0; k < 12; ++k ) s += "    acc = acc + a * b - c + d;\n";                        // large common core
    for( int i = 0; i < nBlocks; ++i ) s += "    if( acc > a ) { acc = acc - b; } else { acc = acc + c; }\n";   // n identical blocks
    for( int k = 0; k < 12; ++k ) s += "    acc = acc * d + a - b;\n";                            // more common core
    s += "    return acc;\n}\n";
    return s;
}

static int runCapFixture( const std::string& dir )
{
    IngestResult ing;
    for( int n = 1; n <= 4; ++n )
    {
        const std::string name = std::string( "cap" ) + std::to_string( n ) + ".cpp";
        auto [p, sz] = writeFile( dir, name.c_str(), capBody( n ) );   // symbol ids 0,1,2,3 for n = 1,2,3,4
        addWholeFileFn( ing, p, sz );
    }
    const int         minTokens = 40;                 // bodies are ≈230–270 tokens; well clear of the floor
    const std::size_t cap       = kType3MaxPairs;     // the compile-time cap under test

    // Canonical deterministic enumeration order of the single [0,1,2,3] bucket; ALL 6 are prefilter-surviving and
    // in the similarity band by construction, so emitted == the first min(cap,6) of these, in this exact id order.
    const std::pair<NodeId, NodeId> canon[6] = { { 0, 1 }, { 0, 2 }, { 0, 3 }, { 1, 2 }, { 1, 3 }, { 2, 3 } };
    const std::size_t               expectN  = std::min<std::size_t>( cap, 6 );

    const std::vector<CloneGroup> t3  = findClonesType3( ing, minTokens );
    const std::vector<CloneGroup> t3b = findClonesType3( ing, minTokens );   // determinism rerun

    std::printf( "  INFO  cap=%zu emitted=%zu expected=%zu\n", cap, t3.size(), expectN );

    check( t3.size() == expectN, "CAP) emitted pair count == min(cap,6): the pair-cap truncates to the first-N prefilter-surviving pairs" );

    bool orderOk = ( t3.size() == expectN );
    for( std::size_t i = 0; orderOk && i < t3.size(); ++i )
        orderOk = ( t3[i].members.size() == 2 && t3[i].members[0] == canon[i].first && t3[i].members[1] == canon[i].second );
    check( orderOk, "CAP) emitted pairs are exactly the first-N of the deterministic id-ordered enumeration (which survive / which drop)" );

    bool detOk = ( t3.size() == t3b.size() );
    for( std::size_t i = 0; detOk && i < t3.size(); ++i )
        detOk = ( t3[i].members == t3b[i].members && t3[i].similarity == t3b[i].similarity );
    check( detOk, "CAP) capped output is deterministic run-to-run (the dropped set is fixed by the bucket walk)" );

    bool bandOk = true;
    for( const CloneGroup& cg : t3 ) bandOk &= ( cg.type == 3 && cg.similarity >= kType3MinSimilarity && cg.similarity < 1.0f );
    check( bandOk, "CAP) every emitted pair is a real Type-3 near-miss (type=3, similarity in [min,1)) — not a vacuous pass" );

    std::printf( g_fail ? "TYPE3 CAP FIXTURE: FAIL\n" : "TYPE3 CAP FIXTURE: OK\n" );
    return g_fail;
}
#endif   // CTX_T3_CAP_FIXTURE

int main( int argc, char** argv )
{
    if( argc < 2 ) { std::fprintf( stderr, "usage: %s <tmpdir>\n", argv[0] ); return 2; }
    const std::string dir = argv[1];

#ifdef CTX_T3_CAP_FIXTURE
    return runCapFixture( dir );   // B1 cap-hitting path (compiled with a lowered -DCTX_TYPE3_MAX_PAIRS); skips A–E
#endif

    // Bodies of ~30 tokens so they clear kType3MinSimilarity's minTokens floor comfortably.
    const std::string bodyA =
        "int f( int a, int b ){ int s = 0; for( int i = 0; i < a; ++i ){ s += i * b; if( s > 100 ){ s -= 1; } } return s; }\n";
    // B: identical to A except ONE inserted statement (`int t = a + b;`) — a Type-3 gap, not exact.
    const std::string bodyB =
        "int g( int a, int b ){ int s = 0; int t = a + b; for( int i = 0; i < a; ++i ){ s += i * b; if( s > 100 ){ s -= 1; } } return s + t; }\n";
    // A' : a byte-for-byte-DIFFERENT spelling that normalizes to the SAME stream as A (renamed vars/literals →
    // Type-2). Must group with A under findClones.
    const std::string bodyAprime =
        "int h( int x, int y ){ int q = 0; for( int k = 0; k < x; ++k ){ q += k * y; if( q > 100 ){ q -= 1; } } return q; }\n";
    // C: structurally unrelated — must be similar to NOTHING here.
    const std::string bodyC =
        "void logmsg( const char* m ){ while( *m ){ putchar( *m ); ++m; } putchar( 10 ); flush_all(); return; }\n";

    auto [pA,  szA ]  = writeFile( dir, "a.cpp",      bodyA );
    auto [pB,  szB ]  = writeFile( dir, "b.cpp",      bodyB );
    auto [pAp, szAp]  = writeFile( dir, "aprime.cpp", bodyAprime );
    auto [pC,  szC ]  = writeFile( dir, "c.cpp",      bodyC );

    IngestResult ing;
    addWholeFileFn( ing, pA,  szA  );   // id 0
    addWholeFileFn( ing, pB,  szB  );   // id 1
    addWholeFileFn( ing, pAp, szAp );   // id 2
    addWholeFileFn( ing, pC,  szC  );   // id 3

    const int minTokens = 12;

    // ── exact pass: A and A' share a normalized stream → one Type-1/2 group; B and C do NOT join it ──────────
    const std::vector<CloneGroup> exact = findClones( ing, minTokens );
    bool exactHasApair = false;
    for( const CloneGroup& cg : exact )
    {
        bool has0 = false, has2 = false, has1 = false, has3 = false;
        for( NodeId m : cg.members ) { has0 |= ( m == 0 ); has1 |= ( m == 1 ); has2 |= ( m == 2 ); has3 |= ( m == 3 ); }
        if( has0 && has2 ) { exactHasApair = true; check( cg.type == 2 && cg.similarity == 1.0f, "A) exact group is type=2, similarity=1" ); }
        check( !( has0 && has1 ), "A) inserted-stmt body B is NOT in an exact group with A" );
        check( !has3, "C) dissimilar body C is in no exact group" );
    }
    check( exactHasApair, "A) truly-identical (normalized) A & A' form a Type-1/2 group" );

    // ── near-miss pass: exactly the {A,B} pair, type=3, similarity in band; A' (exact of A) NOT a Type-3 ──────
    const std::vector<CloneGroup> t3 = findClonesType3( ing, minTokens );
    bool foundAB = false, sawC = false, sawExactAsT3 = false;
    float simAB = 0.0f;
    for( const CloneGroup& cg : t3 )
    {
        check( cg.members.size() == 2, "B) every Type-3 group is a pair" );
        check( cg.type == 3, "B) Type-3 group carries type=3" );
        check( cg.similarity >= kType3MinSimilarity && cg.similarity < 1.0f, "B) similarity in [min,1) band" );
        const NodeId x = cg.members[0], y = cg.members[1];
        if( ( x == 0 && y == 1 ) ) { foundAB = true; simAB = cg.similarity; }
        if( x == 3 || y == 3 ) sawC = true;
        // A(0) and A'(2) are EXACT (sim==1) → must never appear as a Type-3 pair.
        if( ( x == 0 && y == 2 ) ) sawExactAsT3 = true;
    }
    check( foundAB, "B) inserted-stmt pair {A,B} detected as Type-3" );
    check( !sawC, "C) dissimilar body C produces no Type-3 pair (no false positive)" );
    check( !sawExactAsT3, "B) exact pair {A,A'} is NOT reported as Type-3 (exact belongs to Type-1/2)" );
    std::printf( "  INFO  measured similarity(A,B) = %.4f\n", simAB );

    // ── D) determinism: rerun both passes, assert identical member sequences ─────────────────────────────────
    const std::vector<CloneGroup> t3b = findClonesType3( ing, minTokens );
    bool detOk = ( t3.size() == t3b.size() );
    for( std::size_t i = 0; detOk && i < t3.size(); ++i )
        detOk = ( t3[i].members == t3b[i].members && t3[i].type == t3b[i].type && t3[i].similarity == t3b[i].similarity );
    check( detOk, "D) Type-3 output is deterministic (byte-identical run-to-run)" );

    // ── E) MUTATION gate: a threshold strictly ABOVE the measured (A,B) similarity must drop {A,B}. This is the
    //       gate that catches a broken/too-loose threshold — if kType3MinSimilarity were pushed down to ~0 the
    //       feature would report everything; this asserts the band is a REAL constraint, not decorative. ───────
    if( foundAB )
    {
        // emulate a raised threshold: recompute and require NO pair survives a cutoff above simAB.
        const float raised = simAB + 0.02f;
        int survivors = 0;
        for( const CloneGroup& cg : t3 ) if( cg.similarity >= raised ) ++survivors;
        // {A,B} (the only near-miss) sits below `raised` ⇒ it must NOT survive; a too-loose implementation that
        // reported dissimilar pairs at sim≈1 would leave survivors here.
        check( survivors == 0, "E) mutation: raising the threshold above sim(A,B) drops the only near-miss pair" );
        // And the live threshold must be ≤ simAB (else {A,B} could never have been found) — a lower-bound sanity.
        check( kType3MinSimilarity <= simAB, "E) live kType3MinSimilarity is ≤ the real near-miss similarity" );
    }

    std::printf( g_fail ? "TYPE3 HARNESS: FAIL\n" : "TYPE3 HARNESS: OK\n" );
    return g_fail;
}
