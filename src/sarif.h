#pragma once

// sarif.h — W1-SARIF (board Track A P0-7): serialize --lint's findings as SARIF 2.1.0
// (github.com/oasis-tcs/sarif-spec) instead of the native XML <lint> block, so they land in
// GitHub's code-scanning UI (github/codeql-action/upload-sarif). PURE RE-SERIALIZATION: the
// caller (main.cpp's runLint) hands this the exact same sorted/deduped finding list it already
// built for the XML path — no new analysis, no re-ranking, no re-filtering. Findings emitted here
// must be byte-for-byte the same SET the XML path would have printed for the same run.
//
// MINIMUM VIABLE for GitHub code scanning: version, $schema, runs[0].tool.driver{name,rules[{id,
// shortDescription}]}, results[{ruleId,level,message.text,locations[0].physicalLocation{
// artifactLocation.uri,region.startLine}}].
//
// HONESTY (the project's non-negotiable #3: no surface quietly omits). Two things the XML <lint>
// carries that have no SARIF-standard field:
//   - a rule's per-run "spent its whole capture budget" floor (XML: <rule name=".." capped="1"/>)
//   - a finding's enclosing symbol NAME (XML: <f ... in="..">)
// Both ride in `properties` rather than being dropped. The raw ripwire severity string (empty for
// a built-in fact, else info|warn|error) also rides there, alongside the SARIF `level` it was
// mapped from — level is a lossy 4-way bucket, the raw string is not.
//
// SEVERITY MAPPING. Built-in findings are DESCRIPTIVE FACTS, never gates (see runLint's own XML
// comment: "[AST]-only checks (descriptive facts, not gates)") — they carry no severity of their
// own, so they map to SARIF's lowest/informational level, "note", same tier as a user rule's
// declared "info". User rules carry a validated severity (src/lintrules.h's kLintSeverities:
// info|warn|error) that maps 1:1 onto SARIF's own three non-"none" levels.
//
// RULE CATALOGUE. runs[0].tool.driver.rules lists every rule NAME (built-in + user, in the same
// declaration order the XML per-rule tally uses), not only the ones with >=1 finding this run —
// that is SARIF's own semantic for `rules[]` (the tool's reportable catalogue) and mirrors the XML
// tally, which also lists a rule with count="0". Each rule's shortDescription.text is the rule id
// itself: no per-rule prose exists anywhere in the source to draw from, and inventing any here
// would not be re-serialization.
//
// TWO MORE FACTS THE XML CARRIES AND THIS DOCUMENT USED TO DROP — both of them the difference
// between "ran and found nothing" and "never ran here at all", which is the honesty contract's
// central distinction, so neither may be inferred from a bare absence:
//   - SELECTION (--lint-select= / --lint-ignore=). The XML omits a deselected rule's row entirely and
//     states selected="K of N" + the raw select=/ignore= on its root. Dropping the row is not open to
//     SARIF, whose rules[] is the tool's CATALOGUE rather than this run's worklist; the standard field
//     for "catalogued but not enabled this run" is `defaultConfiguration.enabled`, so a deselected rule
//     carries it as false. A kept rule omits it and inherits SARIF's own default of true — the same
//     absent-means-nothing-happened convention the XML root uses for inert_rules=/findings_capped=.
//     `properties.selected`/`select`/`ignore` on the RUN mirror the XML root, and only when a selection
//     was actually given: an unfiltered run says nothing, exactly as the XML does.
//   - APPLICABILITY (the XML's applicable="0"): NONE of a rule's registered languages (lintcatalog.h)
//     exist in this corpus, so its zero is structural inertness and not a measurement. Carried as
//     `properties.applicable`, and — unlike the XML, whose row can drop the attribute because its
//     legend defines the absence — it is emitted for EVERY rule, true and false alike. A SARIF document
//     has no legend travelling with it, so an absent property there would be read as "true" by whoever
//     consumes it, which is the guess this field exists to remove.
//
// DETERMINISM. No timestamp, no run id, no host path — none of SARIF's optional non-deterministic
// fields are emitted. Ordering is entirely inherited from the caller's already-sorted vectors.

#include "model.h"
#include "infra/jsonesc.h"

#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace sarif
{

// One entry in runs[0].tool.driver.rules — the rule CATALOGUE, independent of whether it fired.
struct SarifRuleDecl
{
    std::string id;                  // built-in tag ("c-style-cast", ...) or user rule id
    bool        isUserRule = false;
    bool        capped     = false;  // this rule's raw capture stream spent its whole per-rule budget
                                      // (XML twin: <rule name=".." capped="1"/> — its count is a FLOOR)
    bool        selected   = true;   // kept by --lint-select=/--lint-ignore= (XML twin: the row exists at all)
    bool        applicable = true;   // at least one of its registered languages is in this corpus
                                      // (XML twin: the ABSENCE of applicable="0" on the row)
};

// Everything runs[0].properties says about the RUN rather than about one rule or one finding — the JSON
// twin of the XML <lint> root's own attribute set. One struct rather than one parameter per fact: these
// grow together (findings_capped= and selected= arrived in different rounds and the next one will arrive
// the same way), and a serializer whose signature grows a bool per disclosure is a signature nobody can
// call correctly. `selectionActive` false ⇒ neither --lint-select= nor --lint-ignore= was given and the
// three selection fields are NOT emitted — absent means no selection, never "a selection that kept
// everything".
struct SarifRunProperties
{
    bool        anyRuleCapped   = false;  // XML twin: findings_capped="1" — at least one count is a floor
    bool        selectionActive = false;
    std::size_t selectedCount   = 0;
    std::size_t totalCount      = 0;
    std::string select;   // the raw --lint-select= argument, "" when the flag was absent
    std::string ignore;   // the raw --lint-ignore= argument, "" when the flag was absent
};

// One result — the SAME shape as main.cpp's file-scope LintOut, plus the enclosing-symbol name
// runLint resolves via its own `enclosing()` lambda (sarif.h has no symbol-table dependency of its
// own on purpose: it is a pure serializer over data the caller already computed).
struct SarifFinding
{
    std::string   rule;        // built-in tag or user rule id
    std::string   sev;         // "" (built-in fact) | "info" | "warn" | "error" (validated user set)
    std::string   file;        // ing.files[fileId] — root-relative, e.g. "./src/main.cpp"
    std::uint32_t line = 0;
    std::string   enclosing;   // enclosing symbol name, or "" (no enclosing def found)
    std::string   text;        // finding message
};

// severity string -> SARIF result level. See the file header for why an empty (built-in) sev maps
// to "note" rather than a silent default toward "warning".
inline const char* sarifLevel( std::string_view sev )
{
    if( sev == "error" ) { return "error"; }
    if( sev == "warn" )  { return "warning"; }
    return "note";   // "" (built-in fact) or "info" — both non-gating, both SARIF's lowest tier
}

// ing.files stores each path exactly as derived from the run's OWN root argument: "./bad.cpp" for a
// relative root ("." / "test/lintfix"), but a full absolute path when the root itself was absolute —
// the native XML <lint p="…"> carries the identical inconsistency (see e.g. ccjson.h's writeCcJson,
// which strips the same way for the same reason). SARIF wants a plain root-relative URI regardless of
// which spelling the caller used, so this normalizes BOTH shapes against `rootPrefix` (the run's root,
// trailing '/' already stripped — see rootPrefixOf below) rather than assuming a leading "./".
inline std::string_view rootRelativeUri( std::string_view file, std::string_view rootPrefix )
{
    if( file.rfind( "./", 0 ) == 0 )
    {
        return file.substr( 2 );
    }
    if( !rootPrefix.empty() && file.size() > rootPrefix.size() + 1
        && file.compare( 0, rootPrefix.size(), rootPrefix ) == 0 && file[ rootPrefix.size() ] == '/' )
    {
        return file.substr( rootPrefix.size() + 1 );
    }
    return file;
}

// Normalize a scan root for rootRelativeUri above: drop trailing '/' so the prefix strips cleanly
// (same normalization ccjson.h's writeCcJson performs on the same input for the same reason).
inline std::string rootPrefixOf( std::string_view root )
{
    std::string prefix( root );
    while( prefix.size() > 1 && prefix.back() == '/' )
    {
        prefix.pop_back();
    }
    return prefix;
}

// Escape + quote `s` as a JSON string literal onto `out`. Reuses the same validating core mcp.h's
// stdio JSON-RPC uses (no <>& hardening — this document is never re-embedded in HTML/markup, same
// posture as the MCP wire format) rather than hand-rolling a fourth near-clone escaper.
inline void jsonQuoted( std::FILE* out, std::string_view s )
{
    const std::string esc = rw::jsonesc::escapeMcp( s );
    std::fputc( '"', out );
    std::fwrite( esc.data(), 1, esc.size(), out );
    std::fputc( '"', out );
}

// One entry of runs[0].tool.driver.rules. `defaultConfiguration` is written ONLY for a deselected rule
// (see the SELECTION note in the file header); `properties.applicable` is written always (see APPLICABILITY).
inline void writeSarifRuleDecl( std::FILE* out, const SarifRuleDecl& r )
{
    std::fputs( "{\"id\":", out );
    jsonQuoted( out, r.id );
    std::fputs( ",\"shortDescription\":{\"text\":", out );
    jsonQuoted( out, r.id );
    std::fputs( "},", out );   // close shortDescription
    if( !r.selected )
    {
        std::fputs( "\"defaultConfiguration\":{\"enabled\":false},", out );
    }
    std::fprintf( out, "\"properties\":{\"builtin\":%s,\"capped\":%s,\"applicable\":%s}}",
                  r.isUserRule ? "false" : "true", r.capped ? "true" : "false",
                  r.applicable ? "true" : "false" );
}

// One entry of runs[0].results. `rootPrefix` is rootPrefixOf(root), hoisted by the caller so the whole
// finding list pays for it once.
inline void writeSarifResult( std::FILE* out, const SarifFinding& f, std::string_view rootPrefix )
{
    std::fputs( "{\"ruleId\":", out );
    jsonQuoted( out, f.rule );
    std::fprintf( out, ",\"level\":\"%s\",\"message\":{\"text\":", sarifLevel( f.sev ) );
    jsonQuoted( out, f.text );
    std::fputs( "},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":", out );
    jsonQuoted( out, rootRelativeUri( f.file, rootPrefix ) );
    std::fprintf( out, "},\"region\":{\"startLine\":%u}}}]", f.line );
    std::fputs( ",\"properties\":{\"enclosingSymbol\":", out );
    jsonQuoted( out, f.enclosing );
    std::fputs( ",\"sev\":", out );
    jsonQuoted( out, f.sev );
    std::fputs( "}}", out );
}

// runs[0].properties — the XML lint root's own attributes. The selection triple rides only under a real
// selection, so a consumer can never read "no selection" as "a selection that kept everything".
inline void writeSarifRunProperties( std::FILE* out, const SarifRunProperties& props )
{
    std::fprintf( out, "\"properties\":{\"findingsCapped\":%s", props.anyRuleCapped ? "true" : "false" );
    if( props.selectionActive )
    {
        std::fputs( ",\"selected\":", out );
        jsonQuoted( out, std::to_string( props.selectedCount ) + " of " + std::to_string( props.totalCount ) );
        if( !props.select.empty() )
        {
            std::fputs( ",\"select\":", out );
            jsonQuoted( out, props.select );
        }
        if( !props.ignore.empty() )
        {
            std::fputs( ",\"ignore\":", out );
            jsonQuoted( out, props.ignore );
        }
    }
    std::fputc( '}', out );
}

// Emit the whole SARIF 2.1.0 document to `out`. `rules` and `findings` are caller-owned, already in
// their final deterministic order (the caller's existing sort — see main.cpp's sortLintRows /
// dedupeLintFindings and the allRuleNames declaration order); this function performs no reordering.
inline void emitLintSarif( std::FILE* out, const std::vector<SarifRuleDecl>& rules,
                            const std::vector<SarifFinding>& findings, const SarifRunProperties& props,
                            std::string_view root )
{
    const std::string rootPrefix = rootPrefixOf( root );
    std::fputs( "{\"version\":\"2.1.0\",\"$schema\":"
                "\"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json\","
                "\"runs\":[{\"tool\":{\"driver\":{\"name\":\"ripwire\",\"rules\":[", out );
    for( std::size_t ruleIndex = 0; ruleIndex < rules.size(); ++ruleIndex )
    {
        if( ruleIndex )
        {
            std::fputc( ',', out );
        }
        writeSarifRuleDecl( out, rules[ ruleIndex ] );
    }
    std::fputs( "]}},\"results\":[", out );
    for( std::size_t findingIndex = 0; findingIndex < findings.size(); ++findingIndex )
    {
        if( findingIndex )
        {
            std::fputc( ',', out );
        }
        writeSarifResult( out, findings[ findingIndex ], rootPrefix );
    }
    std::fputs( "],", out );
    writeSarifRunProperties( out, props );
    std::fputs( "}]}", out );
}

}   // namespace sarif
}   // namespace rw
