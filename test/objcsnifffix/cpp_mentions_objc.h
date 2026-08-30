#pragma once
// cpp_mentions_objc.h — the objcsniffcheck VICTIM fixture: a plain C++ header whose COMMENTS (and
// string literals) mention the three Objective-C declaration keywords the .h language sniff tests
// for. Pre-kParserVer-74, looksObjC's raw substring search saw "@interface" below and rerouted this
// whole file to the objc grammar, which cannot parse namespaces/lambdas — every C++ symbol here was
// shredded at extraction with no --skipped row (measured live on src/ingest_model.h, whose
// collapseObjCDeclDefs doc comment mentions the @interface decl / @implementation def pairing and a
// lone @protocol method). This fixture pins the exact class of symbol that went missing there: a
// STRUCT METHOD inside an ANONYMOUS NAMESPACE in a HEADER.
namespace rw
{

namespace
{

struct SniffVictim
{
    int  cursorState = 1'000'000;   // digit separators — a naive char-literal scan would swallow from here

    int sniffVictimMethod( int x )
    {
        return x + cursorState;     // objcsniffcheck greps this line and asserts its in= enclosing symbol
    }
};

// string-literal and raw-string mentions must be masked too, not just comments:
inline const char* kSniffLiteral    = "@implementation InsideAString";
inline const char* kSniffRawLiteral = R"fix(@protocol InsideARawString)fix";

}   // namespace

}   // namespace rw
