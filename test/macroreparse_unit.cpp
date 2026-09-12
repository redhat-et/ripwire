// macroreparse_unit.cpp — the scanner-level half of test/macroreparsecheck.sh. The shell arms prove the member-macro
// re-parse on real parses; this driver pins the three pure decisions it rests on, one case per boundary:
//   (1) WHICH bytes the scanner calls a semicolon-less member macro invocation (and every shape it must refuse),
//   (2) that blanking keeps every byte offset and every newline, so a re-parsed tree's spans index the ORIGINAL bytes,
//   (3) the adoption rule — strictly fewer error bytes, nothing else.
// A shape the fixtures do not reach is still a shape the next scanner edit can break, so it is pinned here.
// Exit 0 = all cases hold.

#include "macroreparse.h"

#include <cstdint>
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

struct Expected
{
    std::string_view name;
    std::uint32_t    line;
};

// Scan `src` and compare the invocations found against `want`, in source order: the name the span starts with, its
// 1-based line, and that the span ends exactly one past a `)`.
void expectInvocations( std::string_view label, std::string_view src, const std::vector<Expected>& want )
{
    std::vector<rw::macroreparse::BlankSpan> spans;
    rw::macroreparse::ScanScratch            scratch;
    rw::macroreparse::findMemberMacroInvocations( src, spans, scratch );
    std::string got;
    bool        isMatch = spans.size() == want.size();
    for( std::size_t i = 0; i < spans.size(); ++i )
    {
        const rw::macroreparse::BlankSpan& s = spans[ i ];
        const bool isWellFormed = s.startByte < s.nameEndByte && s.nameEndByte < s.endByte && s.endByte <= src.size() && src[ s.endByte - 1 ] == ')';
        const std::string_view name = isWellFormed ? src.substr( s.startByte, s.nameEndByte - s.startByte ) : std::string_view( "<malformed>" );
        got += std::string( name ) + "@" + std::to_string( s.line ) + " ";
        if( !isWellFormed || i >= want.size() || name != want[ i ].name || s.line != want[ i ].line )
        {
            isMatch = false;
        }
    }
    report( isMatch, label, "got [" + got + "]" );
}

void expectBlankKeepsOffsets( std::string_view label, std::string_view src )
{
    std::vector<rw::macroreparse::BlankSpan> spans;
    rw::macroreparse::ScanScratch            scratch;
    rw::macroreparse::findMemberMacroInvocations( src, spans, scratch );
    std::string out;
    rw::macroreparse::blankInvocations( src, spans, out );
    bool isKept = out.size() == src.size() && !spans.empty();
    for( std::size_t i = 0; isKept && i < src.size(); ++i )
    {
        bool isInside = false;
        for( const rw::macroreparse::BlankSpan& s : spans )
        {
            isInside = isInside || ( i >= s.startByte && i < s.endByte );
        }
        const char want = ( isInside && src[ i ] != '\n' ) ? ' ' : src[ i ];
        isKept = out[ i ] == want;
    }
    report( isKept, label, "blanked copy differs outside the spans, or kept a byte inside one" );
}

void expectAdopt( std::string_view label, std::uint32_t firstErrorBytes, std::uint32_t reparsedErrorBytes, bool want )
{
    const bool got = rw::macroreparse::adoptsReparse( firstErrorBytes, reparsedErrorBytes );
    report( got == want, label, "adoptsReparse(" + std::to_string( firstErrorBytes ) + ", " + std::to_string( reparsedErrorBytes ) + ") = " + ( got ? "true" : "false" ) );
}

}   // namespace

int main()
{
    using E = std::vector<Expected>;

    // ── (1a) shapes the scanner must find ───────────────────────────────────────────────────────────────────────
    expectInvocations( "last member, right before the closing brace", "struct A : public B {\n  using B::B;\n  NAME_OF(A)\n};\n", E{ { "NAME_OF", 3 } } );
    expectInvocations( "followed by another member", "struct A {\n  TAG(A)\n  int width;\n};\n", E{ { "TAG", 2 } } );
    expectInvocations( "trailing line comment", "struct A {\n  TAG(A)  // why\n};\n", E{ { "TAG", 2 } } );
    expectInvocations( "trailing block comment", "struct A {\n  TAG(A) /* why */\n};\n", E{ { "TAG", 2 } } );
    expectInvocations( "a run of invocations", "class C {\n  FIRST(C)\n  SECOND(C, 2)\n};\n", E{ { "FIRST", 2 }, { "SECOND", 3 } } );
    expectInvocations( "after an access specifier", "class D {\n public:\n  TAG(D)\n};\n", E{ { "TAG", 3 } } );
    expectInvocations( "nested parens and a string holding a paren", "struct E {\n  TAG(f(g), \"x)\")\n};\n", E{ { "TAG", 2 } } );
    expectInvocations( "union body", "union U {\n  int i;\n  TAG(U)\n};\n", E{ { "TAG", 3 } } );
    expectInvocations( "template struct, decltype in the base clause", "template <class T>\nstruct F : Base<decltype(sizeof(T))> {\n  TAG(F)\n};\n", E{ { "TAG", 3 } } );
    expectInvocations( "followed by a destructor", "struct G {\n  TAG(G)\n  ~G();\n};\n", E{ { "TAG", 2 } } );
    expectInvocations( "followed by an attribute", "struct H {\n  TAG(H)\n  [[nodiscard]] int size() const;\n};\n", E{ { "TAG", 2 } } );
    expectInvocations( "leading underscore and digits", "struct I {\n  _TAG2(I)\n};\n", E{ { "_TAG2", 2 } } );
    expectInvocations( "preprocessor lines around it", "struct J {\n#ifdef FEATURE\n  TAG(J)\n#endif\n};\n", E{ { "TAG", 3 } } );
    expectInvocations( "CRLF line endings", "struct K {\r\n  TAG(K)\r\n};\r\n", E{ { "TAG", 2 } } );
    expectInvocations( "nested class, then the outer class", "class Outer {\n  struct Inner {\n    TAG(Inner)\n  };\n  TAG(Outer)\n};\n", E{ { "TAG", 3 }, { "TAG", 5 } } );
    expectInvocations( "class inside a namespace", "namespace n {\nstruct L {\n  TAG(L)\n};\n}\n", E{ { "TAG", 3 } } );
    expectInvocations( "after an inline method body", "struct M {\n  int f() { return 1; }\n  TAG(M)\n};\n", E{ { "TAG", 3 } } );

    // ── (1b) shapes the scanner must refuse ─────────────────────────────────────────────────────────────────────
    expectInvocations( "refuse: lowercase name", "struct A {\n  tag_of(A)\n};\n", E{} );
    expectInvocations( "refuse: mixed-case name", "struct A {\n  TagOf(A)\n};\n", E{} );
    expectInvocations( "refuse: the semicolon is there", "struct A {\n  TAG(A);\n};\n", E{} );
    expectInvocations( "refuse: namespace scope", "namespace n {\nTAG(a)\nTAG(b)\n}\n", E{} );
    expectInvocations( "refuse: file scope", "TAG(a)\nint f();\n", E{} );
    expectInvocations( "refuse: function body", "void f() {\n  TAG(x)\n}\n", E{} );
    expectInvocations( "refuse: arguments span lines", "struct A {\n  TAG(a,\n      b)\n};\n", E{} );
    expectInvocations( "refuse: next token opens a body", "struct A {\n  CTOR(int x)\n  {}\n};\n", E{} );
    expectInvocations( "refuse: next token is noexcept", "struct A {\n  MAKE(int x)\n  noexcept;\n};\n", E{} );
    expectInvocations( "refuse: next token is override", "struct A {\n  MAKE(int x)\n  override;\n};\n", E{} );
    expectInvocations( "refuse: next token is =", "struct A {\n  MAKE(const A&)\n  = delete;\n};\n", E{} );
    expectInvocations( "refuse: next token is :", "struct A {\n  MAKE(int x)\n  : x_(x) {}\n};\n", E{} );
    expectInvocations( "refuse: next token is ->", "struct A {\n  MAKE(int x)\n  -> int;\n};\n", E{} );
    expectInvocations( "refuse: a token before it on the line", "struct A {\n  int TAG(a)\n};\n", E{} );
    expectInvocations( "refuse: a comment before it on the line", "struct A {\n  /* c */ TAG(a)\n};\n", E{} );
    expectInvocations( "refuse: a token after it on the line", "struct A {\n  TAG(a) int x;\n};\n", E{} );
    expectInvocations( "refuse: inside comments", "struct A {\n  // TAG(a)\n  /* TAG(b)\n  */\n};\n", E{} );
    expectInvocations( "refuse: inside a raw string", "struct A {\n  const char* s = R\"(\n  TAG(a)\n)\";\n};\n", E{} );
    expectInvocations( "refuse: inside a #define", "#define WRAP(x) \\\n  TAG(x)\nstruct A {};\n", E{} );
    expectInvocations( "refuse: previous token is not a member boundary", "struct A {\n  int a =\n  TAG(x)\n};\n", E{} );
    expectInvocations( "refuse: enum body", "enum E {\n  TAG(x)\n};\n", E{} );
    expectInvocations( "refuse: enum class body", "enum class E {\n  TAG(x)\n};\n", E{} );
    expectInvocations( "refuse: function returning a struct pointer", "struct S *make() {\n  TAG(x)\n}\n", E{} );
    expectInvocations( "refuse: aggregate initializer", "struct S s = {\n  TAG(x)\n};\n", E{} );
    expectInvocations( "refuse: unterminated class at end of file", "struct A {\n  TAG(x)", E{} );
    expectInvocations( "refuse: extern C block", "extern \"C\" {\n  TAG(x)\n}\n", E{} );
    expectInvocations( "refuse: lambda in a member initializer", "struct A {\n  std::function<void()> f = [] {\n    TAG(x)\n  };\n};\n", E{} );
    expectInvocations( "refuse: inside parentheses in a class body", "struct A {\n  int v = sum(\n  TAG(x)\n  );\n};\n", E{} );

    // ── (2) blanking keeps offsets and newlines ─────────────────────────────────────────────────────────────────
    expectBlankKeepsOffsets( "blank: one invocation, bytes and newlines outside it untouched", "struct A : public B {\n  using B::B;\n  NAME_OF(A)\n};\n" );
    expectBlankKeepsOffsets( "blank: a run, with a trailing comment kept", "class C {\n  FIRST(C)  // kept\n  SECOND(C, \"x)\")\n};\n" );
    expectBlankKeepsOffsets( "blank: CRLF", "struct K {\r\n  TAG(K)\r\n};\r\n" );

    // ── (3) the adoption rule: strictly fewer error bytes ───────────────────────────────────────────────────────
    expectAdopt( "adopt: fewer error bytes", 100, 99, true );
    expectAdopt( "adopt: error bytes gone", 5, 0, true );
    expectAdopt( "keep: equal error bytes", 100, 100, false );
    expectAdopt( "keep: more error bytes", 100, 101, false );
    expectAdopt( "keep: no error bytes before (a MISSING-only parse)", 0, 0, false );

    // ── the name shape and the language set ─────────────────────────────────────────────────────────────────────
    report( rw::macroreparse::isMacroShapedName( "NAME_OF" ) && rw::macroreparse::isMacroShapedName( "_TAG2" ) && rw::macroreparse::isMacroShapedName( "X" ),
            "name shape: NAME_OF, _TAG2, X are macro-shaped", "" );
    report( !rw::macroreparse::isMacroShapedName( "tag_of" ) && !rw::macroreparse::isMacroShapedName( "TagOf" ) && !rw::macroreparse::isMacroShapedName( "__" )
                && !rw::macroreparse::isMacroShapedName( "" ) && !rw::macroreparse::isMacroShapedName( "A_b" ),
            "name shape: tag_of, TagOf, __, empty, A_b are not", "" );
    report( rw::macroreparse::isMacroReparseLang( rw::Lang::Cpp ) && rw::macroreparse::isMacroReparseLang( rw::Lang::C ) && rw::macroreparse::isMacroReparseLang( rw::Lang::ObjC ),
            "languages: C++ (incl. CUDA/Metal), C, ObjC are in", "" );
    report( !rw::macroreparse::isMacroReparseLang( rw::Lang::Python ) && !rw::macroreparse::isMacroReparseLang( rw::Lang::Rust )
                && !rw::macroreparse::isMacroReparseLang( rw::Lang::Markdown ) && !rw::macroreparse::isMacroReparseLang( rw::Lang::Unknown ),
            "languages: Python, Rust, Markdown, Unknown are out", "" );

    std::fputs( failures == 0 ? "macroreparse_unit: ALL PASS\n" : "macroreparse_unit: FAILURES\n", stdout );
    return failures == 0 ? 0 : 1;
}
