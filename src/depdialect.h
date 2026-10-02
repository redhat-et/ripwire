#pragma once

// depdialect.h — the DEPENDENCY DIALECT vocabulary, read by BOTH the lint side and the ingest side.
//
// WHY IT MOVED OUT OF lintrules.h (#358). DepDialect used to be declared inside lintrules.h, which only
// main.cpp's verb-family TUs include. The import-capture round needs it from the OTHER side: a specifier
// normaliser is chosen per dialect at CAPTURE time (src/ingest_importcap.h), and the ingest TU cannot
// include lintrules.h — that header pulls the YAML rule loader, the canonical whole-file read and
// docparse, none of which a parse worker wants to carry. The vocabulary is shared domain, not a lint
// detail, so it gets its own header and lintrules.h includes it back. One definition, two readers; the
// enum and its table are unchanged, and this file is the only place either is spelled.

#include <cstdint>

#include "model.h"   // Lang — the enum dependencyDialect maps

namespace rw
{

// The DEPENDENCY DIALECT a language's imports resolve in — the answer to "could an include edge from a
// file of language A to a file of language B exist AT ALL". Per-file capability is not enough to answer
// that: a Bash gate and the C++ translation unit it exercises are BOTH dependency-capable as of
// kParserVer 81, and no `source` can ever name a .cpp. Anything that asks "is the ABSENCE of a static
// dependency between these two informative?" (gitmine.h's `surprising=`) needs the pair form, or it
// re-manufactures exactly the §A9.3 false positive — measured here, on this repo, before the change
// landed: of 153 `dep_capable="0"` co-change rows in the top 400, a per-file-only flip would have turned
// 88 capable, and 75 of those 88 are cross-dialect (.h↔.sh, .cpp↔.sh, .py↔.sh, .js↔.sh) and would have
// rendered as "hidden architectural debt" that no include edge could ever have explained.
//
// One group per resolvable dialect; C-family is one group because a .c/.h/.cpp/.mm genuinely include one
// another, and TS+JS is one group because their specifiers resolve against one shared extension ladder
// (resolve.h::resolveTsImport). Every other language resolves only onto its own files (resolve.h's
// Step-A candidate lists are extension-closed), so each is its own group. Java/Go/Swift/C#/PHP keep a
// group despite being DEFERRED in the resolver: capability is about the language, not about how far this
// tool currently resolves it, and a deferred pair is honestly "could carry one, we found none". Kotlin
// joins Java's group rather than minting its own, for the SAME reason C-family is one group: a Kotlin
// file genuinely imports a Java class and vice versa in a mixed Android/JVM module (graph.h's
// langCompatible bridges the two for the same reason on the call-graph side) — a separate Kotlin dialect
// would report a real cross-language import pair as "not defined" instead of "found none".
enum class DepDialect : std::uint8_t { None = 0, CFamily, Web, Python, Rust, Go, Swift, Java, CSharp, Php, Bash, Ruby, Lua, Elixir };

/// Return the dependency dialect of a language, or DepDialect::None when it carries no file dependency.
inline DepDialect dependencyDialect( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::Cpp: case Lang::C: case Lang::ObjC:  return DepDialect::CFamily;
        case Lang::TypeScript: case Lang::JavaScript:   return DepDialect::Web;
        case Lang::Python:                              return DepDialect::Python;
        case Lang::Rust:                                return DepDialect::Rust;
        case Lang::Go:                                  return DepDialect::Go;
        case Lang::Swift:                               return DepDialect::Swift;
        case Lang::Java: case Lang::Kotlin:              return DepDialect::Java;
        case Lang::CSharp:                              return DepDialect::CSharp;
        case Lang::Php:                                 return DepDialect::Php;
        case Lang::Bash:                                return DepDialect::Bash;
        case Lang::Ruby:                                return DepDialect::Ruby;
        case Lang::Lua:                                 return DepDialect::Lua;
        case Lang::Elixir:                              return DepDialect::Elixir;
        case Lang::Dart:                                // not dependency-capable (dependencyCapable's DART paragraph)
        case Lang::GDScript:                            // not dependency-capable (the same paragraph)
        case Lang::Json: case Lang::Toml: case Lang::Yaml: case Lang::Markdown: case Lang::Unknown:
                                                        return DepDialect::None;
    }
    return DepDialect::None;   // a byte past the enum
}

}   // namespace rw
