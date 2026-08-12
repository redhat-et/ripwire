// verpin.h — the kParserVer shape, verbatim: const-qualified NON-SCREAMING module constants at
// namespace scope. Every kMc* name here must be indexed t="var" post-fix (the census's 21.4%
// constant-shaped lookup family); the two Deferred* families at the bottom must stay absent.
#pragma once
#include <cstdint>

namespace mcfix
{
    // the literal ingest.cpp shape: namespace-scope constexpr, k-camel name
    constexpr std::uint32_t kMcNsConstexpr = 61;

    // the literal quality.h mirror shape: inline constexpr
    inline constexpr std::uint32_t kMcNsInlineConstexpr = 7;

    // plain const at namespace scope
    const double kMcNsPlainConst = 2.5;

    // constinit (mutable but const-initialized — the qualifier still marks a deliberate module binding)
    constinit int kMcNsConstinit = 9;
}

// class-static constants: the field_declaration family (no pattern at all pre-fix, even SCREAMING)
struct McConfig
{
    static constexpr int kMcClassConstexpr   = 3;
    static constexpr int MC_CLASS_SCREAM     = 4;
    static const int     kMcClassConstInt    = 5;

    // NEGATIVES — per-instance state, must stay unindexed:
    int       mcMemberDefaultInit = 0;   // default-member-initializer, not a constant
    const int mcMemberConstField  = 1;   // const but NON-static: per-instance, not a module constant
};

// DEFERRED family (pinned absent): enumerators are constants but blow up the corpus
// (>=5000 capture-cap hits on the the 2 377-file private validation tree probe, 2026-08-12) — deliberately not indexed.
enum class McColor { kMcEnumRed = 1, kMcEnumGreen = 2 };
enum McPlain { MC_ENUM_SCREAM = 1 };
