#pragma once

// mcprefusal.h — THE MCP REFUSAL VOCABULARY: one statement of what a refusal says, for both dispatch arms.
//
// WHY THIS FILE EXISTS. The MCP surface dispatches TWICE — the live server's `tools/call` chain (mcp.h) and
// the `batch` verb's sub-query chain (mcpverbs.h's runBatchSub) — and every refusal was written out twice,
// independently, so the same condition arrived in three different wordings across the tool:
//
//     condition                     CLI                          live arm                    batch arm
//     ------------------------------------------------------------------------------------------------
//     empty required value          flag + problem + EXAMPLE     "missing required field: X" "missing X"
//     symbol does not resolve       noun + ECHO + did-you-mean   "symbol not found"          "symbol not found"
//     name is not a verb            —                            "unknown tool or missing args" (conflated)
//
// §B6 M7/M8/M9 fix all three by making the wording a TABLE plus three renderers, which both arms call. The
// house rule this follows is the one cli.h's refuseEmptyValue already established for the 16 value-taking
// flags: a new verb inherits the refusal by filling in table columns, not by remembering to copy a
// paragraph — and a fix lands on both arms because there is only one place to land.
//
// The `flags` verb (mcp.h's flip branch) already echoed the spelling AND offered near-misses before this
// file existed; it is the proof the shape is cheap, and it is the shape generalized here.

#include "model.h"
#include "didyoumean.h"    // §B6 M8: the ONE near-miss suggester (lifted out of main.cpp so this is reachable)
#include "degradedscan.h"  // degradedTextHit — the ONE degraded-parse text scan (selectorrefuse.h words the same facts for the CLI)
#include "selectorrefuse.h" // the @FILE:LINE at-diagnosis (atSeedFaultClause) — ONE set of fault sentences for both surfaces
#include "mcpjson.h"       // §H3: mcpdetail::FrameShape — the framing verdict this file words (mcpjson is upstream of everything MCP; no cycle)

#include <algorithm>       // std::find — the declared-field membership tests (M4)
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw::mcprefuse
{

// ─── M7: the verb → required-field table ─────────────────────────────────────────────────────────────────
//
// `Required` rows must ALL be present. `AnyOf` rows of one verb are satisfied by ANY one of them (exemplar's
// kind-or-task). `needs` is the CLI's middle clause ("what this field is"), `example` its last one ("what to
// type") — the two halves neither MCP arm carried. Both are written in the ARGUMENT spelling an MCP caller
// actually types, not the CLI flag spelling, because that is what the reader has to fix.
// `Optional` rows are never reported missing — they are in the table for their OTHER two columns (the
// not-found hint, and the one wording of what the field is), which a verb whose field is optional needs
// just as much as a verb whose field is required (verifier N7: `owners`' symbol is optional and its
// not-found clause was hand-written twice, once per arm).
enum class FieldRule : std::uint8_t { Required, AnyOf, Optional };

struct McpFieldSpec
{
    const char* verb;                          // MCP tool name ("" = the universal row, checked by the caller)
    const char* field;                         // the argument key
    const char* needs;                         // "a literal string to search for"
    const char* example;                       // "pattern=\"parseArgs\""
    FieldRule   rule = FieldRule::Required;
    // §B6 M8 / verifier N7: the verb's own trailing "and here is what to do instead" clause on a NOT-FOUND.
    // It lived at the LIVE arm's call sites only, so the batch arm served three of these sentences with the
    // guidance half chopped off — one condition, two lengths. It belongs on the row that already owns this
    // field's wording, so both arms read the FULL sentence from one place.
    const char* notFoundHint = nullptr;
};

inline constexpr McpFieldSpec kMcpRequiredFields[] = {
    // ── the universal row: every index-backed verb needs a tree to answer about ──
    // F-LOW-3 (wave-2 verifier): this row said `2..16` while the schema row for the same field says
    // `an ARRAY of 1..16` (kMcpValueFields below) and the enforcement is mcpArrayArg( …, 1, 16 ) in mcp.h.
    // Measured before changing it — `paths:[ONE_ROOT]` ANSWERS, `paths:[]` and 17 roots refuse — so it is
    // the REFUSAL's lower bound that was wrong, not the schema's, and M12's "the two say the same words
    // because they read the same bytes" was true of every field except this one.
    { "",                        "path",      "a directory to answer about (or a `paths` array of 1..16 workspace roots)", "path=\".\"" },

    // ── read verbs ──
    { "find_symbol",             "symbol",    "a symbol name (the final name segment; add scope to disambiguate) or @FILE:LINE (a 1-based line-seed: the innermost definition enclosing that line)", "symbol=\"parseArgs\"",
      FieldRule::Required, "pass the final name segment; add scope to disambiguate — or @FILE:LINE when you hold a location" },
    { "find_referencing_symbols","symbol",    "a symbol name (the final name segment; add scope to disambiguate) or @FILE:LINE (a 1-based line-seed: the innermost definition enclosing that line)", "symbol=\"parseArgs\"",
      FieldRule::Required, "pass the final name segment; add scope to disambiguate — or @FILE:LINE when you hold a location" },
    { "grep",                    "pattern",   "a literal string to search for",                                    "pattern=\"parseArgs\"" },
    // R-H span tiers: the MCP spelling of the CLI's --grep-in. Optional, and the hatch has to exist on THIS
    // surface too — an MCP-only agent that sees suppressed_comment= has no CLI to re-ask from.
    { "grep",                    "in",        "which span tier to serve: code (default) or any",                    "in=\"any\"", FieldRule::Optional },
    { "cochange",                "file",      "a file path (a path SUFFIX is enough)",                              "file=\"src/main.cpp\"" },
    { "memory_recall",           "task",      "the task in plain words",                                           "task=\"how does the cache key work\"" },
    { "mentions",                "symbol",    "a code symbol name to find in doc backticks",                        "symbol=\"parseArgs\"",
      FieldRule::Required, "mentions answers about a CODE symbol named in doc backticks" },
    { "owners",                  "symbol",    "an OPTIONAL symbol name — restricts the report to the file that defines it", "symbol=\"parseArgs\"",
      FieldRule::Optional, "or this tree has no git history (owners is mined from git)" },
    { "for",                     "task",      "the task in plain words",                                           "task=\"add a since filter\"" },
    { "lego",                    "type",      "an interface or base-type name (file:name disambiguates; @FILE:LINE line-seeds resolve)", "type=\"Shape\"" },
    { "fetch_body",              "handle",    "a `handle` string taken from a read verb's result (@FILE:LINE line-seeds resolve too)",   "handle=\"src/cli.h::rw::parseArgs\"" },
    { "batch",                   "queries",   "an array of {verb, ...args} sub-query objects",                      "queries=[{\"verb\":\"grep\",\"pattern\":\"x\"}]" },

    // ── flagship-reflex verbs ──
    { "exemplar",                "kind",      "a kind token (fn|method|class|struct|iface|var)",                    "kind=\"fn\"",  FieldRule::AnyOf },
    { "exemplar",                "task",      "a task string whose top match donates its kind",                     "task=\"a JSON writer\"", FieldRule::AnyOf },
    { "impact",                  "symbol",    "a symbol name to take the blast radius of (file:name disambiguates; @FILE:LINE line-seeds resolve)", "symbol=\"parseArgs\"" },
    { "uses",                    "symbol",    "a symbol name to find the resolvable use-sites of (an @FILE:LINE line-seed serves the enclosing definition's name)", "symbol=\"parseArgs\"" },
    { "path_between",            "from",      "the SOURCE symbol name (or @FILE:LINE)",                             "from=\"main\"" },
    { "path_between",            "to",        "the DESTINATION symbol name (or @FILE:LINE)",                        "to=\"parseArgs\"" },
    { "connect",                 "symbols",   "an array (or comma-string) of 2..16 symbol names (@FILE:LINE entries resolve)", "symbols=[\"main\",\"parseArgs\"]" },
    { "explore",                 "task",      "the task in plain words",                                            "task=\"add a since filter\"" },
    { "pack_task",               "task",      "the task in plain words",                                            "task=\"add a since filter\"" },
    { "from_trace",              "trace",     "the raw trace TEXT, pasted (not paraphrased into a query)",           "trace=\"Traceback (most recent call last): ...\"" },
    { "edit_check",              "symbol",    "the def name you just edited (file:name disambiguates; @FILE:LINE = the def at that line)", "symbol=\"parseArgs\"",
      FieldRule::Required, "pass the def name you just edited; file:name disambiguates, @FILE:LINE addresses by location" },
    // card A1 — the PRE-APPLY preview, mirrored from the CLI's --edit-check --edit-payload --dry-run. OPTIONAL
    // and read-only: passing it does not write, it asks the same contract question about bytes that have not
    // been written. The field NAME is deliberately `new_body`, the one replace_symbol_body already uses, so a
    // caller previewing an edit and then making it types one key, not two spellings of one idea.
    { "edit_check",              "new_body",  "OPTIONAL — the replacement definition to PREVIEW rather than apply: the answer then describes the contract AFTER these bytes would be spliced over the symbol, and nothing is written", "new_body=\"int f( int x ) { return x; }\"",
      FieldRule::Optional },
    { "whereis",                 "symbol",    "the symbol name to look for across every ref",                       "symbol=\"parseArgs\"" },
    { "slice",                   "symbol",    "the definition to slice: a symbol name, SYM:VAR, file:name[:VAR], or @FILE:LINE[:VAR] (a 1-based line-seed: the innermost definition enclosing that line)", "symbol=\"parseArgs\"",
      FieldRule::Required, "pass the definition to slice — a name, SYM:VAR, or @FILE:LINE to seed by location" },

    // ── edit verbs ──
    { "replace_symbol_body",     "symbol",    "the def name to replace",                                            "symbol=\"parseArgs\"" },
    { "replace_symbol_body",     "new_body",  "the complete, well-formed replacement definition",                   "new_body=\"int f() { return 0; }\"" },
    { "insert_before_symbol",    "symbol",    "the def name to insert before",                                      "symbol=\"parseArgs\"" },
    { "insert_before_symbol",    "text",      "the text to insert",                                                 "text=\"// note\\n\"" },
    { "insert_after_symbol",     "symbol",    "the def name to insert after",                                       "symbol=\"parseArgs\"" },
    { "insert_after_symbol",     "text",      "the text to insert",                                                 "text=\"// note\\n\"" },
};

// join a list of clauses with `sep`, no trailing separator (the three renderers below all need this once).
inline std::string joinClauses( const std::vector<std::string_view>& parts, std::string_view sep )
{
    std::string out;
    for( std::size_t i = 0; i < parts.size(); ++i )
    {
        if( i )
        {
            out += sep;
        }
        out += parts[i];
    }
    return out;
}

// M7 — the missing-required-field refusal for `verb`, or "" when nothing required is missing. `isPresent`
// answers "did the request carry this argument?" and is the ONLY thing the two arms supply differently (the
// live arm reads its parsed locals, the batch arm reads its sub-query object), which is precisely why the
// WORDING can live here and the lookup at the call sites.
//
// The message KEEPS the "missing required field: X" prefix both arms and every gate already grep for, and
// adds the two clauses the CLI has always carried and neither MCP arm did: what the field is, and what to
// type. Several missing Required fields of one verb are reported together (path_between's from+to), which is
// the D3 behaviour, not a new one.
template<class PresentFn>
inline std::string missingFieldRefusal( std::string_view verb, PresentFn isPresent )
{
    std::vector<std::string_view> names, needs, examples;
    std::vector<std::string_view> anyNames, anyNeeds;
    std::string_view              anyExample;
    bool                          hasAnyOf = false, anyOfSatisfied = false;

    for( const McpFieldSpec& row : kMcpRequiredFields )
    {
        if( verb != row.verb )
        {
            continue;
        }
        if( row.rule == FieldRule::Optional )
        {
            continue; // in the table for its hint/needs columns, never required
        }
        if( row.rule == FieldRule::AnyOf )
        {
            hasAnyOf = true;
            anyNames.push_back( row.field );
            anyNeeds.push_back( row.needs );
            if( anyExample.empty() )
            {
                anyExample = row.example;
            }
            if( isPresent( row.field ) )
            {
                anyOfSatisfied = true;
            }
            continue;
        }
        if( isPresent( row.field ) )
        {
            continue;
        }
        names.push_back( row.field );
        needs.push_back( row.needs );
        examples.push_back( row.example );
    }

    // a verb whose AnyOf group is entirely absent reports the group, not one arbitrary member of it.
    if( hasAnyOf && !anyOfSatisfied && names.empty() )
    {
        return "missing required field: " + joinClauses( anyNames, " or " ) + " — " + std::string( verb )
             + " needs " + joinClauses( anyNeeds, " or " ) + ", e.g. " + std::string( anyExample );
    }

    if( names.empty() )
    {
        return {};
    }

    return std::string( "missing required field" ) + ( names.size() > 1 ? "s" : "" ) + ": "
         + joinClauses( names, ", " ) + " — " + std::string( verb ) + " needs " + joinClauses( needs, " and " )
         + ", e.g. " + joinClauses( examples, " " );
}

// The refusal a verb+field pair renders when NOTHING was given at all — used where the caller has already
// established that the field is absent (connect with no parseable names, batch with no sub-query objects)
// and only needs the table's sentence for it. Verifier N6: those two kept bespoke pre-M7 wordings on the
// live arm ("connect requires a 'symbols' array…") while every other verb had moved to the table.
inline std::string missingFieldRefusal( std::string_view verb )
{
    return missingFieldRefusal( verb, []( std::string_view ) { return false; } );
}

// M8 / N7: the verb's trailing not-found guidance clause, from the row that owns the field's wording.
// Empty when the row has none — notFound() then omits the clause rather than inventing a generic one.
inline std::string_view notFoundHintFor( std::string_view verb, std::string_view field )
{
    for( const McpFieldSpec& row : kMcpRequiredFields )
    {
        if( verb == row.verb && field == row.field && row.notFoundHint )
        {
            return row.notFoundHint;
        }
    }
    return {};
}

// ─── verifier N2/N3/N11: the bad-VALUE refusal table ─────────────────────────────────────────────────────
//
// M7's table answers "you gave me NOTHING for this field". Its twin question — "you gave me something this
// field cannot mean" — had no answer at all on either MCP arm: `limit:0`, `limit:-1`, `limit:"abc"`,
// `offset:-2` were accepted and ignored, `limit:3.9` was truncated to 3, `radius:2^40` wrapped through a
// uint32 cast to radius="1" (a DIFFERENT question, answered confidently), and a `files` array on
// situational_awareness read as absent so the verb described `git diff` instead. Every one of those is a
// loud refusal on the CLI (§A10.2's refusePageValue / §B8.2's refuseFlagValue: name the flag, state the
// DOMAIN, echo what was GOT, show something RUNNABLE) — this is that same sentence in argument spelling.
//
// The columns ARE the refusal, exactly as cli.h's kIntFlags rows are: a new value-taking argument inherits
// the wording by filling in a row, not by remembering to hand-write a fourth dialect.
struct McpValueSpec
{
    const char* field;     // the argument key
    const char* needs;     // the DOMAIN, in the refusal's voice
    const char* example;   // runnable, and inside that domain
    // §B6 M2/M4/M12: the JSON-SCHEMA type this field is advertised as in tools/list. It lives here, beside
    // `needs`, because `needs` is the same fact in the refusal's voice ("a STRING literal to search for" /
    // "an integer in 1..12") and two spellings of one fact in two files is how the wire contract and the
    // refusal came to disagree. tools/list now RENDERS from this column instead of hand-spelling it a
    // second time — see inputSchemaFor below.
    const char* jsonType = "string";
    // Item type for an ARRAY field ("string" / "object"); ignored otherwise.
    const char* itemType = "string";
};

// W3FIX H5/M8/M5: the table now covers EVERY value-taking argument the two arms read, not just the four
// numeric ones N2/N3/N11 happened to name. The rows below are grouped the way the failures group:
//
//   • NUMERIC — the N2/N3 set plus the three the verifier found still coercing silently: `partition` wrapped
//     modulo 2^32 exactly as `radius` did before N3 (partition:4294967299 ran as 3), `top_k:"1e3"` and
//     `budget_tokens:"1e3"` both coerced to 1 (findInt stopped at the first non-digit), and `top_k:2^40`
//     clamped silently to the ceiling. Every one of them now names its DOMAIN here.
//   • STRING — thirteen fields the inputSchemas declare as strings and both arms read through the bare
//     findString path, so a present-but-wrong-shaped value read as ABSENT and the verb served its default:
//     `situational_awareness diff:["a","b"]` answered about the working tree and reported it clean with full
//     confidence (the N11 class, one field over), and `kind`/`symbol` on five verbs silently dropped a
//     non-string filter. `path`/`file`/`handle`/`new_body`/`text`/… are here for the same reason.
//   • ARRAY — the three schema-typed arrays. A wrong SHAPE (`connect symbols:5`, `analyze paths:5`,
//     `batch queries:5`) reported "missing required field", i.e. exactly the absent-vs-wrong-shape collapse
//     findRawValue exists to separate, and `connect symbols:["main"]` got a bespoke fourth-dialect sentence
//     ("connect needs 2..16 symbols (got 1)") instead of the domain clause and a runnable example.
inline constexpr McpValueSpec kMcpValueFields[] = {
    // ── numeric ──
    { "limit",         "a positive integer (omit it for the verb's own default window)",             "limit=40", "integer" },
    { "offset",        "a non-negative integer (omit it to start at the first row)",                  "offset=0", "integer" },
    { "radius",        "an integer in 1..12 (omit it for the default 6)",                             "radius=6", "integer" },
    { "partition",     "an integer in 2..16 (omit it for one un-split bundle; 1 IS the un-split one)", "partition=4", "integer" },
    { "top_k",         "an integer in 1..1000 (omit it for the verb's own default)",                  "top_k=4", "integer" },
    { "budget_tokens", "a positive integer token budget (omit it for the verb's own default)",        "budget_tokens=6000", "integer" },
    { "start_line",    "a positive integer, 1-based and body-relative (omit it to start at line 1)",  "start_line=1", "integer" },
    { "end_line",      "a positive integer, 1-based and body-relative (omit it to read to the end)",  "end_line=40", "integer" },
    { "depth",         "an integer in 1..32 (the slice flow's BFS bound; omit it for the disclosed default 8; needs flow)", "depth=4", "integer" },
    // ── string ──
    { "path",          "a STRING directory path",                                                     "path=\".\"" },
    { "files",         "a STRING of comma-separated paths, not an array",                             "files=\"src/a.cpp,src/b.h\"" },
    { "diff",          "a STRING of unified-diff TEXT (omit it to use the working-tree git diff)",     "diff=\"diff --git a/x b/x\"" },
    { "symbol",        "a STRING symbol name (the final name segment; add scope to disambiguate)",     "symbol=\"parseArgs\"" },
    { "kind",          "a STRING (a name-substring filter, or exemplar's kind token)",                 "kind=\"fn\"" },
    { "pattern",       "a STRING literal to search for",                                              "pattern=\"parseArgs\"" },
    { "task",          "a STRING: the task in plain words",                                           "task=\"add a since filter\"" },
    { "type",          "a STRING interface or base-type name (file:name disambiguates)",               "type=\"Shape\"" },
    { "file",          "a STRING file path (a path SUFFIX is enough)",                                "file=\"src/main.cpp\"" },
    { "handle",        "a STRING handle taken from a read verb's result",                             "handle=\"src/cli.h::rw::parseArgs\"" },
    { "from",          "a STRING: the SOURCE symbol name",                                            "from=\"main\"" },
    { "to",            "a STRING: the DESTINATION symbol name",                                       "to=\"parseArgs\"" },
    { "trace",         "a STRING: the raw trace TEXT, pasted",                                        "trace=\"Traceback (most recent call last): ...\"" },
    { "new_body",      "a STRING: the complete, well-formed replacement definition",                  "new_body=\"int f() { return 0; }\"" },
    { "text",          "a STRING: the text to insert",                                                "text=\"// note\\n\"" },
    { "verb",          "a STRING naming one read sub-verb",                                           "verb=\"grep\"" },
    // R-H span tiers + wave-3 verifier P6-2: a CLOSED value set, so the sentence names the set. The CLI
    // twin refuses an unknown --grep-in= value and says why (a typo would read as "code" and quietly
    // suppress the very rows the caller asked to see); both MCP dialects now refuse through this row.
    { "in",            "a STRING span tier: code (the default) or any",                               "in=\"any\"" },
    // lane/tc-sliceat: slice's own knobs — var picks the variable (omit it for the inventory, or to let an
    // @FILE:LINE seed line pre-pick), flow is a CLOSED direction set so the sentence names it.
    { "var",           "a STRING variable name inside the resolved definition (omit it to list the sliceable locals)", "var=\"out\"" },
    { "flow",          "a STRING flow direction: back, fwd or both (omit it for the flat per-line rows)", "flow=\"back\"" },
    // ── the ENVELOPE, outside `params` (§B6 M6/M7) ──
    // These four were read through the bare findString/findObject path, which collapses "absent" onto
    // "present but not the shape I read" — so `"method":5` became `-32700 "parse error"` (a JSON that parsed
    // fine), `"name":5` became "missing required field: name" for a field that WAS sent, and a wrong-typed
    // `params`/`arguments` was SILENTLY IGNORED: the argument scope fell back one level, the caller's `path`
    // vanished, and the verb answered about the DEFAULT root with total confidence. Same columns, same
    // renderer, one level up the request.
    { "method",        "a STRING naming a JSON-RPC method (initialize / tools/list / tools/call / ping)", "method=\"tools/list\"" },
    // §B6 M11: the handshake's own field. A wrong-TYPED value used to read as ABSENT (findString returns ""
    // for a non-string), so the server silently negotiated its latest version for a client whose request it
    // could not parse — the absent-vs-wrong-shape collapse, on the one field the handshake reads.
    { "protocolVersion", "a STRING protocol date (an unsupported one negotiates the server's latest)",     "protocolVersion=\"2025-11-25\"" },
    { "params",        "a JSON OBJECT of the method's parameters (omit it when the method takes none)", "params={\"name\":\"analyze\",\"arguments\":{\"path\":\".\"}}", "object" },
    { "name",          "a STRING naming one of the advertised tools (call tools/list for them)",      "name=\"analyze\"" },
    { "arguments",     "a JSON OBJECT of the tool's arguments — not a string of JSON, which drops every argument in it", "arguments={\"path\":\".\"}", "object" },
    // ── array ──
    { "symbols",       "an ARRAY (or comma-string) of 2..16 symbol names",                            "symbols=[\"main\",\"parseArgs\"]", "array", "string" },
    { "queries",       "an ARRAY of {verb, ...args} sub-query objects",                               "queries=[{\"verb\":\"grep\",\"pattern\":\"x\"}]", "array", "object" },
    { "paths",         "an ARRAY of 1..16 workspace root directories",                                "paths=[\"svc\",\"web\"]", "array", "string" },
};

// W3FIX NIT: the got-ECHO is CAPPED. The echo exists so a caller can see which of their values was rejected,
// and 160 bytes shows that; without a cap a 4 MB argument minted a 4 MB refusal frame — the server turning a
// hostile request into an amplified response, on the exact path a hostile request takes. The trim backs off to
// a UTF-8 codepoint boundary so the echo cannot end in a half character (jsonEscape would scrub it to U+FFFD,
// which is a second, quieter kind of wrong bytes).
inline constexpr std::size_t kMcpEchoMaxBytes = 160;

inline std::string cappedEcho( std::string_view got )
{
    if( got.size() <= kMcpEchoMaxBytes )
    {
        return std::string( got );
    }

    std::size_t cut = kMcpEchoMaxBytes;
    while( cut > 0 && ( static_cast<unsigned char>( got[cut] ) & 0xC0 ) == 0x80 )
    {
        --cut; // mid-sequence continuation byte
    }
    return std::string( got.substr( 0, cut ) ) + "…";
}

// ─── G5: an edit verb's PAYLOAD field, and the noun a refusal calls it by ────────────────────────────────
//
// Both are read from kMcpRequiredFields, the table that already decides which fields each edit verb requires.
// The call site used to spell the field with a ternary (`name == "replace_symbol_body" ? new_body : text`) and
// the clause below used to hardcode the noun "definition" — so `insert_before_symbol` / `insert_after_symbol`
// were refused with "and no definition" about a field whose own row in this table contracts it as "the text to
// insert". Wrong noun, and a second list of the same fact: the round's meta-pattern twice in six lines.
//
// The payload row is derived, not re-listed: each edit verb has exactly two rows here, `symbol` (which
// addresses the def) and the payload (which supplies the bytes), so the payload IS the non-`symbol` row. The
// consteval block below fails the BUILD if that ever stops being true — a fourth edit verb, or a third
// required field on an existing one, is a compile error here rather than a silently wrong noun on the wire.
inline constexpr std::string_view editPayloadField( std::string_view verb )
{
    for( const McpFieldSpec& row : kMcpRequiredFields )
    {
        if( verb == std::string_view( row.verb ) && std::string_view( row.field ) != "symbol" )
        {
            return row.field;
        }
    }
    return {};
}

// The noun the blank-payload clause calls the field by — short, and in the field's own vocabulary. Kept as a
// table beside the clause rather than as a sixth column on McpFieldSpec: `needs` is a full sentence fragment
// ("the complete, well-formed replacement definition") and reads wrong in the "and no ___" slot.
struct McpPayloadNoun { const char* field; const char* noun; };

inline constexpr McpPayloadNoun kMcpPayloadNouns[] = {
    { "new_body", "definition"     },
    { "text",     "text to insert" },
};

inline constexpr std::string_view payloadNoun( std::string_view field )
{
    for( const McpPayloadNoun& row : kMcpPayloadNouns )
    {
        if( field == std::string_view( row.field ) )
        {
            return row.noun;
        }
    }
    return "content";   // a field with no row still gets a true sentence, just a generic noun
}

// Build-time floor: the three edit verbs each resolve to exactly one payload field, and each payload field has
// a noun. If a fourth edit verb lands without its rows, or a row is renamed, this fails to COMPILE — which is
// the failure mode wave 1 chose for isMcpEditVerb's group tag, for the same reason (a safety-adjacent list
// that drifts silently is the defect; a build break is the fix that cannot be forgotten).
consteval bool mcpPayloadTablesAreComplete()
{
    for( std::string_view verb : { "replace_symbol_body", "insert_before_symbol", "insert_after_symbol" } )
    {
        const std::string_view field = editPayloadField( verb );
        if( field.empty() )
        {
            return false;
        }
        if( payloadNoun( field ) == "content" )
        {
            return false; // no noun row ⇒ the generic fallback ⇒ incomplete
        }

        // exactly ONE non-`symbol` required row per edit verb (else the ternary's replacement is ambiguous)
        int payloadRows = 0;
        for( const McpFieldSpec& row : kMcpRequiredFields )
        {
            if( verb == std::string_view( row.verb ) && std::string_view( row.field ) != "symbol" )
            {
                ++payloadRows;
            }
        }
        if( payloadRows != 1 )
        {
            return false;
        }
    }
    return true;
}
static_assert( mcpPayloadTablesAreComplete(),
               "every edit verb needs exactly one non-`symbol` required row in kMcpRequiredFields and a "
               "matching row in kMcpPayloadNouns — a new edit verb must add both" );

// F2 — the clause a PRESENT-but-blank edit payload appends to its missing-field sentence. The PREFIX is
// unchanged on purpose ("missing required field: new_body — …", the one wording both MCP arms and every gate
// read), because the caller's mistake is still the same mistake; what the bare sentence could not say is that
// they DID send a value. `spelling` arrives already rendered as `U+200E`-style code points — see mcp.h's
// blankPayloadSpelling for why this is a spelling and never an echo. Empty `spelling` ⇒ no clause, which is
// how the §H2-ruled equivalence of an omitted payload and `new_body:""` stays byte-identical.
inline std::string blankPayloadClause( std::size_t codePointCount, std::string_view spelling, std::string_view field )
{
    if( spelling.empty() || codePointCount == 0 )
    {
        return {};
    }

    // "invisible code point(s)" rather than a relative clause, so the sentence needs no verb agreement — one
    // wording that reads correctly at 1 and at 4000, instead of two spellings and a plural bug.
    return " — got " + std::to_string( codePointCount )
         + ( codePointCount == 1 ? " invisible code point" : " invisible code points" )
         + " and no " + std::string( payloadNoun( field ) ) + ": " + std::string( spelling );
}

// The rendered sentence for `field` given the value as TYPED. A field with no row degrades to the same
// sentence minus the two clauses it has no source for — a missing row is a call-site omission, and a
// refusal that names the field and echoes the value is still strictly better than silence.
inline std::string badValueRefusal( std::string_view field, std::string_view got )
{
    const std::string echo = cappedEcho( got );
    std::string       msg  = "invalid value for field: " + std::string( field );
    for( const McpValueSpec& row : kMcpValueFields )
    {
        if( field == row.field )
        {
            msg += std::string( " — needs " ) + row.needs;
            msg += " — got '" + echo + "', e.g. " + row.example;
            return msg;
        }
    }
    msg += " — got '" + echo + "'";
    return msg;
}

// The universal `path` row, rendered — the live arm checks it before the per-verb table because an absent
// path fails every verb identically and naming the verb's own field first would send the caller to the
// wrong fix.
inline std::string missingPathRefusal()
{
    const McpFieldSpec& row = kMcpRequiredFields[0];   // the "" (universal) row, by construction the first
    return std::string( "missing required field: " ) + row.field + " — every index-backed verb needs "
         + row.needs + ", e.g. " + row.example;
}

// The ENVELOPE's own required key, rendered from the SAME row badValueRefusal reads for it — so "you sent
// `method` in the wrong shape" and "you sent no `method` at all" are two sentences about one field written
// once. There is no verb to name here (the envelope is what selects the verb), so the clause names the
// request instead.
inline std::string missingEnvelopeField( std::string_view field )
{
    for( const McpValueSpec& row : kMcpValueFields )
    {
        if( field == row.field )
        {
            return "missing required field: " + std::string( field ) + " — a JSON-RPC request needs "
                 + row.needs + ", e.g. " + row.example;
        }
    }
    return "missing required field: " + std::string( field );
}

// ─── §H3 / §B6 M6 / §B6 M8: the FRAMING refusal table ────────────────────────────────────────────────────
//
// `-32700 "parse error"` was the catch-all for FOUR unrelated inputs, naming no field, no problem, nothing
// got and nothing to type — the one refusal on this surface that failed the standing rule outright:
//
//   truncated frame     a frame cut off mid-write was DISPATCHED (an edit verb rewrote the file); when it did
//                       refuse, it refused with a FALSE cause about a field whose value was in the bytes
//   batch array         a SPEC-LEGAL top-level `[…]` (mandatory in both advertised protocol versions) got ONE
//                       response for N requests and called the input unparseable — it parses perfectly
//   two frames in one   the second object was silently DROPPED, no disclosure at all
//   real garbage        the only input the sentence was ever right about
//
// Split here, one row per fault, each carrying the code that fits it (-32700 = the bytes are not valid JSON;
// -32600 = valid JSON, invalid request) plus what is wrong and what to send instead. The CODES matter to a
// client: a -32700 says "my writer is broken", a -32600 says "my request shape is wrong", and collapsing them
// told every caller the first thing.
struct McpFrameSpec
{
    mcpdetail::FrameShape shape;
    int                   code;      // -32700 invalid JSON · -32600 valid JSON, invalid request
    const char*           problem;   // what is wrong with this frame
    const char*           fix;       // what to send instead
};

inline constexpr McpFrameSpec kMcpFrameFaults[] = {
    { mcpdetail::FrameShape::Blank,      -32700,
      "parse error: the request carries no JSON at all",
      "send one complete JSON-RPC request object, e.g. {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" },
    { mcpdetail::FrameShape::Incomplete, -32700,
      "INCOMPLETE JSON-RPC frame: it ends inside an unclosed object, array or string, so it cannot be a whole "
      "request — NOTHING was dispatched and no file was touched",
      "send the WHOLE request before the newline (this transport is newline-delimited: a frame split across "
      "writes must be reassembled first), e.g. {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" },
    { mcpdetail::FrameShape::Mismatched, -32700,
      "parse error: a closing brace/bracket does not match the container it closes",
      "send well-formed JSON, e.g. {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" },
    { mcpdetail::FrameShape::BatchArray, -32600,
      "batched requests are not supported: this server answers exactly ONE request object per frame, and a "
      "top-level array asks for N responses — it would have been answered with one, silently",
      "send each request as its own frame (its own line over stdio, its own POST over HTTP), e.g. "
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" },
    { mcpdetail::FrameShape::NotObject,  -32700,
      "parse error: a JSON-RPC request must be a JSON OBJECT",
      "e.g. {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" },
    { mcpdetail::FrameShape::Trailing,   -32600,
      "one JSON-RPC request per frame: bytes follow the first complete object, and only the first would ever "
      "have been answered",
      "put the second request in its own frame (separate the two with a newline over stdio, or POST them "
      "separately)" },
};

struct McpFrameRefusal
{
    int         code = 0;
    std::string message;
};

// The rendered framing refusal. FrameShape::Object is not a fault and yields code 0 — a caller that asks
// about it has a bug, and answering "" is louder than inventing a message for a well-formed frame.
inline McpFrameRefusal frameRefusal( mcpdetail::FrameShape shape, std::string_view got )
{
    for( const McpFrameSpec& row : kMcpFrameFaults )
    {
        if( row.shape != shape )
        {
            continue;
        }
        std::string msg = row.problem;
        if( !got.empty() )
        {
            msg += " — got '" + cappedEcho( got ) + "'";
        }
        msg += " — ";
        msg += row.fix;
        return { row.code, std::move( msg ) };
    }
    return {};
}

// ─── §B6 M3: the ROOT-path refusal — the false-zero class ─────────────────────────────────────────────────
//
// A nonexistent `path`, and a FILE passed as `path`, both produced all-zero SUCCESS reports (`files=0`,
// `total=0`, `0 relevant of 0 documents`) carrying the SAME `_index` hash — so "this tree is empty", "there
// is no such tree" and "that is a file, not a tree" were indistinguishable to a caller, on six verbs, while
// the CLI exits 1 on the first of them ("root path does not exist", main.cpp). Zero is not a measurement
// here: nothing was measured.
//
// An EMPTY-but-real directory is deliberately NOT a fault — it is the CLI's own rule ("nothing there" and
// "no such place" are different answers) and a valid empty result.
enum class RootFault : std::uint8_t { Missing, NotADirectory };

inline std::string rootRefusal( RootFault fault, std::string_view spelling )
{
    const McpFieldSpec& row = kMcpRequiredFields[0];   // the universal `path` row — one wording for one field
    std::string         msg = ( fault == RootFault::Missing )
        ? "path does not exist: '" + cappedEcho( spelling ) + "' — nothing was measured, so a zero here would be a false zero"
        : "path is a FILE, not a directory: '" + cappedEcho( spelling ) + "' — every verb answers about a TREE (to reach inside one file, pass its directory and use `file`/`pattern`)";
    msg += std::string( " — needs " ) + row.needs + ", e.g. " + row.example;
    return msg;
}

// ─── the SINGLE-ROOT refusal seam (§B6 M9 today; §B6 M1's whole verb list next) ───────────────────────────
//
// A verb that can only answer about ONE tree, handed a multi-root `paths` workspace, had no way to say so:
// `quality_baseline` rendered the raw \x1f-separated workspace REGISTRY KEY into a client-facing message
// under `-32603` with the cause "unwritable directory?" — three lies in one sentence (an internal key as a
// path, an internal-error code for a usage error, and a filesystem cause for a shape problem).
//
// This renderer is the seam: it names the verb, states that it is single-root, says WHY in the verb's own
// terms, and tells the caller what to send — WITHOUT ever rendering the key. §B6 M1 (the other single-root
// verbs, which today answer with false causes of their own) is a separate item and joins by adding call
// sites here, not by writing a second sentence.
inline std::string singleRootRefusal( std::string_view verb, std::string_view because )
{
    return std::string( verb ) + " is single-root: " + std::string( because )
         + " — pass `path` naming ONE root instead of a `paths` array, e.g. path=\".\"";
}

// ─── §B6 M1: WHICH verbs are single-root, as a table — the MCP twin of the CLI's enumeration ─────────────
//
// Wave 1 built singleRootRefusal and wired it to exactly ONE verb (quality_baseline). Every other
// single-root verb kept answering a multi-root `paths` request with a refusal of its own, naming a cause
// that is FALSE on two real git repos:
//
//   whereis / stray_content -> "not a git repository (or no HEAD commit) — no refs to search"   (both are)
//   quality_delta           -> "no .ripwire_quality_baseline and no git HEAD to auto-compare against"
//   edit_check              -> "symbol not found: 'X'"   for a symbol find_symbol RETURNS on the same paths
//   owners                  -> "no git history for this tree (not a repo, or no commits)"        (it has)
//   situational_awareness   -> "no changed files given and no git diff"
//
// Each of those sentences sends the caller to fix a repo that is not broken. The cause is always the same
// one thing — the verb reads git/HEAD through a path that is a multi-root workspace REGISTRY KEY, not a
// directory — so it is named once, here, and the reason column says why THAT verb cannot merge roots.
//
// The set is not invented: the first four are exactly the verbs the CLI refuses for the same reason
// (main.cpp's multi-root refusal block, plus the per-verb --whereis/--stray-content refusals), verified
// verb-for-verb on a two-root fixture. `owners` and `situational_awareness` are the INVERTED pair — the CLI
// ANSWERS them multi-root and the MCP arm cannot, because their MCP path has no per-root git plumbing. They
// are listed so their refusal states the true cause and an actionable fix; closing the inversion for real
// means porting the CLI's per-root iteration into the MCP arm, which is a feature, not a disclosure fix.
//
// `batch` is deliberately ABSENT even though the CLI refuses `--batch` multi-root: the MCP batch verb runs
// its sub-queries against the MERGED index like every other read verb, and demonstrably answers correctly,
// so refusing it here would delete working behaviour to match a CLI restriction that looks like the
// questionable side of that divergence.
// The shape EVERY "this verb cannot answer here, and here is why" rule table shares: the verb, and the
// clause its refusal (or its omission note) renders as the reason. Named once because the tables below are
// not two kinds of thing — they are two answers to the same question about different conditions — and so
// one build-time floor (mcpRuleVerbsAreKnown) can guard all of them instead of one hand-copied floor each.
struct McpVerbRule
{
    const char* verb;
    const char* because;
};
using McpSingleRootVerb = McpVerbRule;   // §B6 M1's rows: the reason clause after "<verb> is single-root: "
using McpGitOnlyVerb    = McpVerbRule;   // V3/F4's rows: the reason clause inside the omission note

inline constexpr McpSingleRootVerb kMcpSingleRootVerbs[] = {
    { "quality_baseline",      "it pins ONE tree's floor into ONE .ripwire_quality_baseline sidecar, and a "
                               "workspace of N roots has no single place to put it" },
    { "quality_delta",         "its baseline is keyed to ONE repo's git HEAD (or that repo's sidecar), and N "
                               "roots have N HEADs; run it per root" },
    { "edit_check",            "its contract comparison is against ONE repo's git HEAD snapshot, and N roots "
                               "have N HEADs; run it per root" },
    { "whereis",               "it enumerates ONE repo's refs (one repo = one ref namespace); run it per root" },
    { "stray_content",         "it compares ONE repo's refs against their merge-base (one repo = one ref "
                               "namespace); run it per root" },
    { "owners",                "its author weights are mined from ONE repo's git log; run it per root" },
    { "situational_awareness", "its diff, blast radius and tests_to_run are all keyed to ONE repo's working "
                               "tree; run it per root" },
    { "slice",                 "it re-parses the ONE on-disk file holding the definition, which a merged "
                               "multi-root graph cannot address unambiguously; run it per root" },
};

// The reason `verb` is single-root, or "" when it is not (the caller then dispatches normally).
//
// No alias resolution here, deliberately: kMcpVerbAliases is declared further down this header, and the one
// alias it holds (`pack_task` -> `explore`) names a verb that is not single-root, so resolving would change
// no answer. The consteval floor below is what keeps that true rather than my saying so — it fails the BUILD
// if any row here ever names a verb that is not an advertised tool, which is the way this table would rot.
inline std::string_view singleRootReason( std::string_view verb )
{
    for( const McpSingleRootVerb& row : kMcpSingleRootVerbs )
    {
        if( verb == std::string_view( row.verb ) )
        {
            return row.because;
        }
    }
    return {};
}

// ─── V3/F4: WHICH verbs cannot answer at all without git — the tools/list omission set ────────────────────
//
// The octocode recon's F4: their server calls remove_route for every capability it does not have, so
// tools/list only ever contains tools that can succeed; ripwire's PINNED listener advertised all 30
// regardless, and a non-git workspace paid ~9.1K est-tokens of schema per turn for verbs that could only
// refuse. This table is the "can it succeed here" half of that fix; mcp.h owns the omission itself.
//
// THE MEMBERSHIP RULE, and why it is only three. A verb belongs here iff a non-git root makes it refuse
// UNCONDITIONALLY — no argument, no sidecar, no fallback reaches an answer. The recon named five; probing
// each against a non-git pinned root (test/mcptoolprunecheck.sh arm (E) is that probe, kept as a gate)
// found only these three. The other four git-TOUCHING verbs answer, and are deliberately absent:
//   cochange              answers with commits:0 / at:null — the disclosure IS the git-less answer
//   situational_awareness answers when `files` names the changed files instead of a git diff
//   quality_delta         answers against a quality_baseline SIDECAR (head_sha "(none — not a git repo)")
//   edit_check            answers (every symbol reads as new-symbol against an absent HEAD)
// Omitting one of those would advertise LESS than the server can do, which is the same class of dishonesty
// as advertising more — so the rule is "provably cannot", never "probably will not".
//
// `because` is the clause the disclosure sentence renders, so the omission explains itself in the verb's
// own terms rather than as one generic line for all three.
inline constexpr McpGitOnlyVerb kMcpGitOnlyVerbs[] = {
    { "owners",        "its author weights are mined from git log" },
    { "whereis",       "it enumerates the repo's refs" },
    { "stray_content", "it compares refs against their merge-base" },
};
inline constexpr std::size_t kMcpGitOnlyCount = std::size( kMcpGitOnlyVerbs );

// The disclosure sentence appended to the server's `instructions` when the omission is in force. An
// omission a client cannot see is indistinguishable from a build that never had those verbs, so the
// absence has to describe itself: what was dropped, and the one condition that would bring it back.
// Derived from the table — the names are never restated, which is how the two would drift apart.
//
// The three renderers below all take the SAME `omitted` flag and answer "" when it is false, so their call
// sites in the tools/list assembly are plain concatenations. That is not decoration: the alternative is one
// conditional per site inside dispatchMcpLine, a function already carrying enough branches that a
// --quality-delta run gates on it. The predicate is decided once; these say what it means.
// `isGitDir` disambiguates WHICH of the two git-only causes this is (finding #7, the adversarial verifier's
// 2026-08-15 harvest): "no .git at all" and ".git present but no HEAD commit" both make pinnedRootHasGit
// false, but only the first is actually "not a git repository" — a `git init` with zero commits IS one, it
// just has no HEAD to read history from. Saying "is not a git repository" about the second case is a FALSE
// CAUSE of exactly the kind mcpverbs.h:224 warns against, and it is avoidable: every git-only verb's own
// per-request refusal already carries the qualifier ("not a git repository (or no HEAD commit)" — see
// mcp.h:1261/1268), so this disclosure now renders the same two-cause sentence instead of asserting the
// narrower one unconditionally.
inline std::string gitOnlyOmissionNote( bool omitted, bool isGitDir )
{
    if( !omitted )
    {
        return {};
    }
    std::string note = isGitDir
                      ? std::string( " NOTE: this server's workspace is a git repository with no HEAD commit"
                                      " (nothing committed yet), so its git-backed verbs are OMITTED from tools/list —" )
                      : std::string( " NOTE: this server's workspace is not a git repository (or has no HEAD commit),"
                                      " so its git-backed verbs are OMITTED from tools/list —" );
    for( std::size_t i = 0; i < kMcpGitOnlyCount; ++i )
    {
        note += ( i == 0 ? " " : ", " );
        note += kMcpGitOnlyVerbs[i].verb;
        note += " (";
        note += kMcpGitOnlyVerbs[i].because;
        note += ")";
    }
    note += ". They are absent because they could only refuse here, not because this build lacks them;"
            " point a server at a git checkout to get them back.";
    return note;
}

// The stanza, or nothing at all — the omission itself, as a filter over the one place tools/list writes
// its verbs rather than as a second, prunable copy of the catalog (octocode's remove_route posture).
inline std::string gitOnlyStanza( bool omitted, std::string stanza )
{
    return omitted ? std::string{} : std::move( stanza );
}

// The two git-only names inside `batch`'s cross-branch exclusion prose. Batch says, in words, which
// ADVERTISED verbs it will not serve; when two of them are not advertised at all, listing them sends a
// caller looking for tools this server does not offer. Spelled here beside the table those names come
// from, so the prose and the omission cannot drift apart in the way §B6 M14's hand-written count did.
inline std::string batchGitOnlyExcludedNames( bool omitted )
{
    return omitted ? std::string{} : std::string( "whereis, stray_content, " );
}

// ─── V3/RN1: the omitted-`path` clause on an unresolvable fetch_body handle ───────────────────────────────
//
// A handle is PATH-QUALIFIED for an unscoped definition (a free function's stable id is only unique within
// its file), so a handle minted by a read verb on tree A does not resolve in tree B. When the request
// omitted `path`, the tree that answered is the one the SERVER supplied — the pinned/startup root, or the
// R2a launch cwd — and blaming a rename for that miss sends the caller to re-read a symbol that is fine.
// The lightrag recon (RN1) measured the cost at two dead-end round trips.
//
// So the sentence forks on PROVENANCE, not on a guess about the handle: named the tree yourself and an
// unresolvable handle really does mean renamed/removed; did not, and the recoverable cause is the argument
// you left out. We cannot invert the hash to say WHICH tree would have worked — so this names the argument
// and the root that actually answered, and says nothing it cannot support.
//
// Takes the base message and returns it UNCHANGED unless the clause applies, for the same reason the three
// omission renderers above answer "": the fork belongs beside the sentence it decides, not as one more
// branch in the dispatch chain.
inline std::string withHandleRootProvenance( std::string message, bool clauseApplies, std::string_view rootThatAnswered )
{
    if( !clauseApplies )
    {
        return message;
    }
    return message + " — but this request did not name a tree, so it was answered against '" + std::string( rootThatAnswered )
         + "', the root this server supplied for the omitted `path`. A handle is only valid in the tree the read"
           " verb that minted it answered about: pass that tree as `path` before concluding the symbol is gone.";
}

// ─── M8: the not-found refusal ───────────────────────────────────────────────────────────────────────────
//
// Name the noun, ECHO the spelling the caller typed, offer the near-miss when one exists. All three halves
// were missing on both MCP arms across seven verbs, so a typo and a genuinely absent symbol produced the
// same four words ("symbol not found") with nothing to act on — while the CLI's twin has carried the echo
// and the suggestion since A3-F16a, and the `flags` verb next door carries both today.
//
// `retryHint` is the verb's own "and here is what to do instead" clause, when it has one; omitted otherwise
// rather than filled with a generic sentence that would be wrong for half the callers.
//
// DEGRADED-PARSE routing (mcpdegradedhintcheck, 2026-08-30 — the MCP port of selectorrefuse.h's CLI
// clause). When the not-found name occurs as a WHOLE WORD in a parse-degraded file's bytes, the refusal
// says so instead of answering blind: over a shredded parse "not found" is not proof of a rename, and an
// MCP-only agent has no --skipped habit to fall back on. The FACTS come from degradedscan.h's one shared
// scan (never a second copy of it); the wording and the retry are this surface's own — the retry names
// the grep VERB in argument spelling, whose file rows carry parse_degraded="1" for exactly these files.
// Appended by notFound itself so every verb on BOTH dispatch arms inherits it from the one seam, the
// same way the near-miss does. Precise, not blanket: an ordinary typo occurs in no file, so a
// nowhere-name refusal stays plain.
inline std::string degradedParseNote( const IngestResult& ing, std::string_view spelling )
{
    const DegradedTextHit hit = degradedTextHit( ing, spelling );
    if( !hit.found )
    {
        return {};
    }
    return " — note: the name occurs textually in " + ing.files[ hit.fileIndex ] + ", whose parse is DEGRADED (err_ratio="
         + hit.errRatio + "): symbols there may be unextracted, so this miss is not proof of a rename; "
           "grep pattern=\"" + cappedEcho( spelling ) + "\" shows the textual hits and marks such file rows parse_degraded=\"1\"";
}

// The @FILE:LINE half: a spelling that is a line-seed gets the SAME fault diagnosis the CLI's selector
// clause speaks (selectorrefuse.h::atSeedFaultClause — one sentence per AtFault value, shared verbatim so
// the same fault is never described two ways across surfaces). "" for a non-@ spelling, and "" for a seed
// that RESOLVES (fault None) — a resolvable seed reaching a not-found is the caller's own story to tell.
inline std::string atSeedClause( const IngestResult& ing, std::string_view spelling )
{
    if( spelling.empty() || spelling.front() != '@' )
    {
        return {};
    }
    return atSeedFaultClause( ing, resolveAtSeed( ing, spelling.substr( 1 ) ) );
}

inline std::string notFound( const IngestResult& ing, std::string_view noun, std::string_view spelling,
                             std::string_view retryHint = {} )
{
    std::string msg = std::string( noun ) + " not found: '" + cappedEcho( spelling ) + "'";
    if( !spelling.empty() && spelling.front() == '@' )
    { // a line-seed: the at-diagnosis is the actionable half; a symbol-name near-miss for '@f.cpp:12' is noise
        return msg + atSeedClause( ing, spelling );
    }
    const std::string near = didYouMean( ing, spelling );
    if( !near.empty() && near != spelling )
    {
        msg += " (did you mean '" + near + "'?)";
    }
    if( !retryHint.empty() ) { msg += " — "; msg += retryHint; }
    msg += degradedParseNote( ing, spelling );
    return msg;
}

// The FILE-spelling variant (`cochange`, `situational_awareness`). didYouMean's pool is symbol names, which
// can only ever suggest nonsense for a path, so the candidate search runs over the indexed file paths —
// didyoumean.h::nearestIndexedFile, which the CLI FILE-list selectors now call too (H6/F11): this refusal
// was the ONE surface that had the suggestion, and a second copy on the CLI side would be a second tuning.
inline std::string fileNotFound( const IngestResult& ing, std::string_view spelling )
{
    const std::string_view best = nearestIndexedFile( ing, spelling );

    std::string msg = "file not found: '" + cappedEcho( spelling ) + "'";
    if( !best.empty() && best != spelling )
    {
        msg += " (did you mean '" + std::string( best ) + "'?)";
    }
    msg += " — a path SUFFIX is enough";
    return msg;
}

// ─── M9: the unknown-verb refusal ────────────────────────────────────────────────────────────────────────
//
// "unknown tool or missing args" conflated two failures with entirely different fixes — a typo'd tool name
// and a known tool called with an incomplete argument set — and named neither the verb nor a near-miss,
// with the whole verb registry in-process. Split here, and the typo half gets the same near-miss treatment
// the not-found refusals get. `known` is the caller's registry (mcp.h passes kMcpVerbTable's names, the
// batch arm its own served set), so this renderer never hard-codes a verb list that could drift from one.
inline std::string nearestName( std::span<const std::string_view> known, std::string_view typed )
{
    constexpr int    kMaxEditDistance = 3;
    std::string_view best;
    int              bestDist = kMaxEditDistance + 1;
    for( std::string_view candidate : known )
    {
        const int dist = boundedEditDistance( candidate, typed, kMaxEditDistance );
        if( dist > kMaxEditDistance )
        {
            continue;
        }
        if( dist < bestDist || ( dist == bestDist && ( best.empty() || candidate < best ) ) )
        { bestDist = dist; best = candidate; }
    }
    return std::string( best );
}

// ─── W3FIX M4: the verb → DECLARED-ARGUMENT table, and the unknown-field refusal ─────────────────────────
//
// The class this closes is the quiet one. `explore` honors `budget_tokens`; `token_budget` and `max_tokens` —
// the two names an agent actually reaches for — were read by nothing and DROPPED, so the bundle came back at
// the default 6000 with nothing in it saying the budget had been ignored. Neither MCP arm ever refused an
// unknown argument field, on a surface whose entire contract is "it is in inputSchema or it does not exist",
// with didyoumean.h in-process one call away.
//
// Adding the two aliases would have bought silence until the fourth name. Refusing what the schema does not
// declare, with a near-miss against the verb's OWN field set, closes the family instead.
//
// *** KEEP IN SYNC WITH tools/list *** — one row per advertised tool, fields in the stanza's own order.
// test/mcpw3fixcheck.sh enforces it by ENUMERATION (it parses the live tools/list inputSchemas and diffs the
// property names against these rows), not by restating the list — the M14 lesson: a gate that restates the
// table cannot catch the table.
struct McpVerbFields
{
    const char* verb;
    const char* fields;   // space-separated, in inputSchema order
    enum class Effect : std::uint8_t { ReadOnly, Writes, Destructive };
    Effect      effect = Effect::ReadOnly;
};

inline constexpr McpVerbFields kMcpVerbFields[] = {
    // ── read verbs ──
    { "analyze",                  "path paths" },
    // M13: limit/offset are DECLARED because these two now HONOR them (symbolQueryJson takes an
    // McpPageArgs) — their CLI twins --callees/--callers are both in cli.h's honorsPaging set, and a verb
    // that pages on one surface and is pinned to page 1 on the other is the parity gap this closed.
    { "find_symbol",              "path paths symbol limit offset" },
    { "find_referencing_symbols", "path paths symbol limit offset" },
    { "grep",                     "path paths pattern in limit offset" },
    // M13 (capture-audit 2026-09-04): every verb whose CLI twin sits in cli.h's honorsPaging set now
    // declares limit+offset here, and every verb whose CLI twin honors --token-budget declares
    // budget_tokens. Before this, only grep/impact/uses/whereis paged over MCP while their CLI twins all
    // did — the refusal was loud, but "loud" is not the same as "answerable", and an MCP-only agent had no
    // page 2 for cochange/owners/doc_drift/stray_content/mentions/find_*. Gate: mcpcontractcheck.sh's
    // paging arm, which derives the CLI set from kPagingHonoringVerbs rather than trusting this table.
    // --cochange is in that set, so its twin declares the same window.
    { "cochange",                 "path file limit offset" },
    { "memory_recall",            "path task top_k budget_tokens" },
    { "situational_awareness",    "path diff files" },
    { "mentions",                 "path paths symbol limit offset" },
    { "for",                      "path paths task budget_tokens" },
    { "lego",                     "path paths type" },
    { "owners",                   "path symbol limit offset" },
    { "fetch_body",               "path handle start_line end_line" },
    { "batch",                    "path queries" },
    // ── flagship-reflex verbs ──
    { "exemplar",                 "path paths kind task" },
    { "quality_delta",            "path" },
    { "quality_baseline",         "path", McpVerbFields::Effect::Writes },
    { "impact",                   "path paths symbol limit offset" },
    // LB-G (r10 GitNexus round): limit/offset are DECLARED here because the verb now HONORS them
    // (mcpPageArgs -> pageWindow), exactly as `impact` one row up. `uses` grew a default site cap in the
    // same round, so a caller that wants the whole footprint needs the hatch the CLI --uses already had.
    { "uses",                     "path paths symbol limit offset" },
    { "path_between",             "path paths from to" },
    { "connect",                  "path paths symbols radius" },
    { "explore",                  "path paths task budget_tokens partition" },
    { "from_trace",               "path paths trace budget_tokens" },
    { "edit_check",               "path paths symbol new_body" },
    { "whereis",                  "path symbol kind limit offset" },
    { "stray_content",            "path kind limit offset" },
    { "flags",                    "path kind symbol" },
    { "doc_drift",                "path kind limit offset" },
    // lane/tc-sliceat: the ARISE def-use slice — var/flow/depth mirror the CLI's :VAR / --slice-flow /
    // --slice-depth knobs; single-root by kMcpSingleRootVerbs (a per-definition on-disk re-parse).
    { "slice",                    "path symbol var flow depth" },
    // ── edit verbs ──
    { "replace_symbol_body",      "path paths symbol file new_body", McpVerbFields::Effect::Destructive },
    { "insert_before_symbol",     "path paths symbol file text", McpVerbFields::Effect::Writes },
    { "insert_after_symbol",      "path paths symbol file text", McpVerbFields::Effect::Writes },
};

// Dispatch-only ALIASES of advertised tools: a name tools/call answers that gets no separate tools/list
// stanza (kMcpVerbCount tracks ADVERTISED tools). Declared here so the field lookup, the unknown-tool
// near-miss pool and the prose that advertises the alias all read ONE list. `pack_task` is long-standing
// behavior (it predates the `explore` rename) and is ADVERTISED in prose rather than refused — the explore
// and batch stanzas both name it.
struct McpVerbAlias { const char* alias; const char* target; };

inline constexpr McpVerbAlias kMcpVerbAliases[] = { { "pack_task", "explore" } };

// `paths` is accepted on EVERY verb even where the stanza omits it: the multi-root rebind is verb-agnostic
// code that runs before dispatch, so refusing it per-verb would refuse a form the server actually honors.
// The tolerated set is different — those are params-level PROTOCOL keys that only land in the argument scope
// when a client flattens `arguments` into `params` (a shape mcpObjectArg's scope selection still accepts;
// §B6 M7 deleted findArgsScope, which used to tolerate it by falling back SILENTLY on a wrong-shaped
// `arguments`), so they are accepted and deliberately NOT listed as arguments of the verb.
inline constexpr std::string_view kMcpUniversalFields[] = { "path", "paths" };
inline constexpr std::string_view kMcpToleratedFields[] = { "name", "arguments", "_meta" };

// The verb's declared fields (aliases resolved), plus the universal ones, deduped, in table order. Empty
// when `verb` names no advertised tool or alias — the caller then leaves the request to the unknown-TOOL
// refusal, which owns that failure and has the actionable message for it.
inline std::vector<std::string_view> declaredFieldsFor( std::string_view verb )
{
    for( const McpVerbAlias& alias : kMcpVerbAliases )
    {
        if( verb == alias.alias ) { verb = alias.target; break; }
    }

    std::vector<std::string_view> out;
    for( const McpVerbFields& row : kMcpVerbFields )
    {
        if( verb != row.verb )
        {
            continue;
        }
        const std::string_view all = row.fields;
        for( std::size_t start = 0; start < all.size(); )
        {
            const std::size_t space = all.find( ' ', start );
            out.push_back( all.substr( start, space == std::string_view::npos ? std::string_view::npos : space - start ) );
            if( space == std::string_view::npos )
            {
                break;
            }
            start = space + 1;
        }
        break;
    }
    if( out.empty() )
    {
        return out; // unknown tool — say nothing about its fields
    }

    for( const std::string_view universal : kMcpUniversalFields )
    {
        if( std::find( out.begin(), out.end(), universal ) == out.end() )
        {
            out.push_back( universal );
        }
    }
    return out;
}

// is `field` one this verb accepts (declared, universal or a tolerated protocol key)?
inline bool isFieldAccepted( std::span<const std::string_view> declared, std::string_view field )
{
    if( std::find( declared.begin(), declared.end(), field ) != declared.end() )
    {
        return true;
    }
    for( const std::string_view tolerated : kMcpToleratedFields )
    {
        if( field == tolerated )
        {
            return true;
        }
    }
    return false;
}

// The refusal itself — name the field, offer the near-miss from the verb's OWN declared set (which is what
// makes `token_budget` → `budget_tokens` land), then list that set so the caller does not have to go read
// tools/list to recover. Same three-part shape as unknownVerbRefusal below, one level down.
//
// The near-miss BAR is tighter here than for a verb name, on purpose: argument names are short, so the shared
// distance-3 cutoff "suggests" `task` for `path` — 3 edits out of 4 characters, which is noise wearing help's
// clothes. The distance must be under HALF the typed length; below that bar the refusal simply lists the set,
// which is the honest answer when nothing is close.
inline std::string unknownFieldRefusal( std::string_view verb, std::string_view field,
                                        std::span<const std::string_view> declared )
{
    constexpr int     kMaxEditDistance = 3;   // same bandwidth cutoff nearestName searches within
    std::string       msg  = "unknown field: '" + cappedEcho( field ) + "'";
    const std::string near = nearestName( declared, field );
    if( !near.empty() && 2u * unsigned( boundedEditDistance( near, field, kMaxEditDistance ) ) < field.size() )
    {
        msg += " (did you mean '" + near + "'?)";
    }
    msg += " — " + std::string( verb ) + " accepts: " + joinClauses(
               std::vector<std::string_view>( declared.begin(), declared.end() ), ", " );
    return msg;
}

// The batch verb's SUB-QUERY item schema (the `queries` items properties, verbatim from the batch stanza).
// A sub-query is judged against the ONE declared item schema, not against its sub-verb's own field set:
// tools/list says these keys are legal on any sub-query, and refusing a key the schema advertises would be
// stricter than what the server documents. `path` is deliberately absent — a batch's root is the batch's,
// and a per-sub-query `path` never took effect.
inline constexpr std::string_view kBatchSubQueryFields[] = {
    "verb", "symbol", "pattern", "task", "type", "file", "from", "to",
    "handle", "kind", "start_line", "end_line", "limit", "offset",
    // Wave-3 verifier P3-4/P6-1: `in` on the batch grep sub-query. R-H's own reason for putting the hatch
    // on the live MCP verb — an MCP-only agent that reads suppressed_comment= has no CLI to re-ask from —
    // applies verbatim here, and this was the surface that had NO fallback at all.
    "in",
};

// The build-time floor EVERY McpVerbRule table stands on: each row must name a verb kMcpVerbFields knows,
// so a renamed or deleted verb cannot leave a rule pointing at nothing. Placed here rather than beside the
// tables because kMcpVerbFields is declared between them.
//
// ONE function over a (rows, count) pair rather than one per table. §B6 M1's floor was written first, and
// V3/F4's arrived as a byte-for-byte copy of it with one identifier changed — which is the shape of thing
// this whole header exists to stop being written twice, and a --quality-delta pass named it as a 73-token
// clone the same afternoon. The tables share a row type (McpVerbRule) precisely so this can be one.
consteval bool mcpRuleVerbsAreKnown( const McpVerbRule* rows, std::size_t rowCount )
{
    for( std::size_t i = 0; i < rowCount; ++i )
    {
        bool found = false;
        for( const McpVerbFields& known : kMcpVerbFields )
        {
            if( std::string_view( rows[i].verb ) == std::string_view( known.verb ) ) { found = true; break; }
        }
        if( !found )
        {
            return false;
        }
    }
    return true;
}
// §B6 M1: a dangling row here would stop the single-root gate firing, and the false-cause refusals it was
// built to kill ("not a git repository" about two real git repos) would come back.
static_assert( mcpRuleVerbsAreKnown( kMcpSingleRootVerbs, std::size( kMcpSingleRootVerbs ) ),
               "a kMcpSingleRootVerbs row names a verb that is not in kMcpVerbFields — the single-root gate "
               "would never fire for it, and its multi-root refusal would go back to naming a false cause" );
// V3/F4 fails in a nastier direction: a dangling row here OMITS nothing while the disclosure sentence goes
// on promising the omission — a lie in the one place this feature exists to tell the truth.
static_assert( mcpRuleVerbsAreKnown( kMcpGitOnlyVerbs, kMcpGitOnlyCount ),
               "a kMcpGitOnlyVerbs row names a verb that is not in kMcpVerbFields — tools/list would omit "
               "nothing while the instructions still announced the omission" );

// ─── §B6 M2 / M4 / M12: tools/list's inputSchema, RENDERED from the tables that already decide it ────────
//
// This is the round's meta-pattern in its inverted form. The unknown-field guard has always enforced one
// list (kMcpVerbFields + kMcpUniversalFields, via declaredFieldsFor) and the required-field guard another
// (kMcpRequiredFields); the WIRE CONTRACT was a fifth, hand-written copy inside 30 string literals in
// mcp.h, and it disagreed with both:
//
//   M2 — `paths` is accepted and consumed on all 30 verbs (kMcpUniversalFields says so, and the comment
//        above it has said so in prose) and was DECLARED on 18. The 12 undeclared verbs answer a multi-root
//        request correctly, so a schema-driven client was the only party that could not discover the form.
//   M4 — every `required` omitted `path`, which under the DEFAULT shipped install (`ripwire wrap claude`
//        passes no startup root) is required on all 30. Not a constant: a server started as
//        `ripwire <root> --mcp`, or the remote transport with a pinned workspace, supplies the root itself
//        and `path` is genuinely optional there. So it is rendered per-server from the policy, and the
//        answer is true for the server that gave it rather than true on average.
//   M12 — 0 of 84 declared properties carried a `description`, on a surface where `kind` is an enum on one
//        verb and a substring filter on four others. The description is the `needs` column: the per-verb
//        row from kMcpRequiredFields when there is one (so `symbol` on edit_check reads "the def name you
//        just edited" and on mentions "a code symbol name to find in doc backticks"), else the generic
//        row from kMcpValueFields. The schema and the refusal now say the same words about a field because
//        they read the same bytes.
//
// `required` is the Required-rule rows of kMcpRequiredFields — which reproduces all 30 hand-written
// `required` arrays exactly, verified by the gate. AnyOf rows render as JSON Schema `anyOf` (exemplar's
// kind-or-task, M4's second half: expressible, and never expressed).

// A field's rendered `{"type":…}` fragment, from the McpValueSpec column.
inline std::string jsonTypeFragmentFor( std::string_view field )
{
    for( const McpValueSpec& row : kMcpValueFields )
    {
        if( field == std::string_view( row.field ) )
        {
            if( std::string_view( row.jsonType ) != "array" )
            {
                return std::string( "\"type\":\"" ) + row.jsonType + "\"";
            }

            // `queries` is the one array of OBJECTS, and its item schema is the sub-query field list —
            // kBatchSubQueryFields, the list runBatchSub actually validates against.
            if( std::string_view( row.itemType ) == "object" )
            {
                std::string items = "\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{";
                bool        first = true;
                for( const std::string_view sub : kBatchSubQueryFields )
                {
                    if( !first )
                    {
                        items += ",";
                    }
                    first = false;
                    items += "\"" + std::string( sub ) + "\":{" + jsonTypeFragmentFor( sub ) + "}";
                }
                return items + "},\"required\":[\"verb\"]}";
            }
            return "\"type\":\"array\",\"items\":{\"type\":\"string\"}";
        }
    }
    return "\"type\":\"string\"";   // a field with no row is a string by default — the historic shape
}

// The description for (verb, field): the verb's OWN row wins over the generic one, because that is where
// the meaning actually differs.
inline std::string_view fieldDescriptionFor( std::string_view verb, std::string_view field )
{
    for( const McpVerbAlias& alias : kMcpVerbAliases )
    {
        if( verb == alias.alias ) { verb = alias.target; break; }
    }

    for( const McpFieldSpec& row : kMcpRequiredFields )
    {
        if( verb == std::string_view( row.verb ) && field == std::string_view( row.field ) )
        {
            return row.needs;
        }
    }
    for( const McpValueSpec& row : kMcpValueFields )
    {
        if( field == std::string_view( row.field ) )
        {
            return row.needs;
        }
    }
    return {};
}

// JSON-escape for a description string (they carry quotes and backslashes). Local and minimal: this header
// is deliberately free of project includes beyond jsonesc.h, which owns the canonical escaper.
inline std::string schemaEscape( std::string_view s ) { return jsonesc::escapeMcp( s ); }

// The whole `"inputSchema":{...}` value for one verb. `pathIsRequired` comes from the live server's policy:
// true only when the server carries no startup/pinned root, i.e. when the caller really must send one.
inline std::string inputSchemaFor( std::string_view verb, bool pathIsRequired )
{
    const std::vector<std::string_view> fields = declaredFieldsFor( verb );

    std::string out   = "{\"type\":\"object\",\"properties\":{";
    bool        first = true;
    for( const std::string_view field : fields )
    {
        if( !first )
        {
            out += ",";
        }
        first = false;
        out += "\"" + std::string( field ) + "\":{" + jsonTypeFragmentFor( field );
        const std::string_view desc = fieldDescriptionFor( verb, field );
        if( !desc.empty() )
        {
            out += ",\"description\":\"" + schemaEscape( desc ) + "\"";
        }
        out += "}";
    }
    out += "},\"required\":[";

    bool firstReq = true;
    const auto req = [ & ]( std::string_view f )
    {
        if( !firstReq )
        {
            out += ",";
        }
        firstReq = false;
        out += "\"" + std::string( f ) + "\"";
    };
    // M4: `path` first when this server cannot supply one itself.
    if( pathIsRequired )
    {
        req( "path" );
    }

    std::string_view resolved = verb;
    for( const McpVerbAlias& alias : kMcpVerbAliases )
    {
        if( resolved == alias.alias ) { resolved = alias.target; break; }
    }

    std::vector<std::string_view> anyOf;
    for( const McpFieldSpec& row : kMcpRequiredFields )
    {
        if( resolved != std::string_view( row.verb ) )
        {
            continue;
        }
        if( row.rule == FieldRule::Required )
        {
            req( row.field );
        }
        else if( row.rule == FieldRule::AnyOf )
        {
            anyOf.push_back( row.field );
        }
    }
    out += "]";

    // M4's second half: exemplar's kind-or-task IS expressible, and was not expressed.
    if( !anyOf.empty() )
    {
        out += ",\"anyOf\":[";
        for( std::size_t i = 0; i < anyOf.size(); ++i )
        {
            if( i )
            {
                out += ",";
            }
            out += "{\"required\":[\"" + std::string( anyOf[i] ) + "\"]}";
        }
        out += "]";
    }
    return out + "}";
}

// The rest of a tools/list stanza after its human-facing description: the input schema and the MCP safety
// annotations Codex uses when selecting and approving tools. The effect lives on kMcpVerbFields so a new
// advertised verb cannot acquire a second, hand-maintained side-effect list. All ripwire tools are local to
// the caller's workspace: none reaches an external/open-world service.
inline std::string toolMetadataFor( std::string_view verb, bool pathIsRequired )
{
    McpVerbFields::Effect effect = McpVerbFields::Effect::ReadOnly;
    for( const McpVerbFields& row : kMcpVerbFields )
    {
        if( verb == row.verb )
        {
            effect = row.effect;
            break;
        }
    }

    const bool readOnly    = effect == McpVerbFields::Effect::ReadOnly;
    const bool destructive = effect == McpVerbFields::Effect::Destructive;
    return "\"inputSchema\":" + inputSchemaFor( verb, pathIsRequired )
         + ",\"annotations\":{\"readOnlyHint\":" + ( readOnly ? "true" : "false" )
         + ",\"destructiveHint\":" + ( destructive ? "true" : "false" )
         + ",\"openWorldHint\":false}";
}

// The two halves the old single message ran together. An EMPTY name is its own third case (the params
// carried no tool selector at all) — reported as a missing field, because that is what it is.
// `advertisedCount` is the number tools/list actually serves; 0 = "the same as `known`". W3FIX M4 split the
// two because the near-miss POOL now also carries the callable aliases (a `packtask` typo should land on
// `pack_task`), while the sentence's number must stay the count tools/list will hand back — a message that
// promises 31 tools from a list of 30 is a small lie in the one place a confused caller is reading.
inline std::string unknownVerbRefusal( std::span<const std::string_view> known, std::string_view typed,
                                       std::size_t advertisedCount = 0 )
{
    if( typed.empty() )
    {
        return "missing required field: name — tools/call params must name a tool, e.g. name=\"analyze\" "
               "(call tools/list for the available tools)";
    }

    std::string msg = "unknown tool: '" + cappedEcho( typed ) + "'";
    const std::string near = nearestName( known, typed );
    if( !near.empty() )
    {
        msg += " (did you mean '" + near + "'?)";
    }
    msg += " — call tools/list for the " + std::to_string( advertisedCount ? advertisedCount : known.size() )
         + " available tools";
    return msg;
}

}   // namespace rw::mcprefuse
