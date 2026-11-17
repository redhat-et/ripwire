#pragma once
// forliteral.h — MF1-LIT: THE LITERAL ANCHOR of a --for answer whose task names a literal (an error string, an env var, a
// config key, an error code).
//
// WHY. A --for task such as `FZF_DEFAULT_COMMAND` or `"dependency cycle" error` names a STRING, not a symbol. The ranked answer
// reads it as words: name-exact finds no definition (`reason="no_candidates"`, empty <sigs>) or stops at the one variable spelled
// like it, and the place the literal is read, compared, built or raised is never printed. Measured before this code (ORCH
// reports/mf1-lit.md Stage 0): on the three MF1-DEV rows whose 12 missing items readout-40 files under LITERAL (fastify-02,
// fzf-05, textual-03) the default answer held none of the code that handles the literal, while a byte-exact scan finds it in
// one call (`--grep`).
//
// WHAT. <lit s= shape= hits= src= …> just before </ctx>, after every byte of the ordinary answer (RIPWIRE_NO_LITERAL_ANCHOR=1
// is the rest of it byte for byte): the grep verb's own byte-exact literal scan (search.h grepCollect + grepEnrich) over the
// index, then
//   * <ls> rows: the sites in SOURCE files (filter.h pathTierOf = Source, not a doc/shell/config file), each labelled by the
//     parse (ingest.h spanTierAt): k="string" inside a string literal, k="code" outside one (an identifier or key use),
//     k="?" a file past the classification budget or with no grammar (never dropped, never called code). One row per source
//     line; sites inside a function or method first, then string before code before unclassified, the scan's own path order
//     within each; in= the innermost definition holding the site and ink= its kind; a string site outside any function (an
//     error-code table entry) carries the kForLiteralContextLines lines after it (lines=), at most kForLiteralContextRows rows;
//   * counts beside them for what is NOT a handler: comment= (comment sites in source files, and a Python docstring: a triple-quoted
//     string that is the first statement of a module, class or def body; a string opening a call-argument line is a site),
//     test= (test or bench paths), doc= (docs, shell scripts, config files) — counted, never listed as rows here (the grep verb
//     lists them: next=);
//   * <b> the whole body of the function or method holding a shown site when it is kForLiteralWholeBodyLines lines or fewer
//     (at most kForLiteralBodies owners in row order), or <x> an excerpt of a longer one: its signature line plus one window
//     [site-1, site+5] per shown site (windows merged only where they touch; l= lists the ranges, an ellipsis line sits between
//     them; of= is the body's lines; next= names the whole body); EXCERPT-ARM: a window that leaves out the head of the match arm
//     or case holding its site starts at that head, kForLiteralArmLines up at most (arm="1"); a body this answer already printed
//     WHOLE in a <b> is not repeated (body="above" on its rows; a hop row, a fold skip or a truncated <b> is no body above);
//     an owner past the cap prints no body and its rows say body="held".
// Several sites are always listed with counts: the block never picks one. floor="1" when the scan stopped early (budget,
// unreadable files) or a source site was left unclassified (k="?": comment= cannot see it): every count is then a floor. No source site, nothing printed (a literal met only in tests, docs or comments
// anchors nothing; never a "the literal is unused" claim).
//
// WHEN. The default regime of the XML dialect, a single root: an explicit --token-budget, --json, --columnar and --candidates
// carry none. The literal is read from the task: the first "double-quoted" span of at least 6 bytes holding a letter and a space
// (a message fragment; a backticked span is code the ranked answer already reads as names, and measured as noise on S1), else the first CONST_SHAPED word (upper-case letters and digits joined by at least one underscore, 5 bytes or more,
// or 10 or more upper-case letters and digits). A task with neither carries no block. The block is not in est_tokens (the
// FOR-ROUTE-DECLINED precedent: the bytes are counted on the element instead, bytes=). MCP `for` is not changed.
//
// LITERAL-ANCHOR V1. Failing both, the same block for two more shapes read from the --for text itself (an agent's or a stored subject
// is bare: `files.autoSave afterDelay setting flow`, `Invalid user settings file notification`, no backticks survive into it):
//   * shape="dotted": a dotted key of 3+ segments, or 2 with a whole word setting/option/key/command/flag beside it. Identity is an
//     allowlist (forliteral.h dottedKeysOf): identifier segments only; never a file name or host (a leading dot, a file or host suffix,
//     the name of an indexed file), a `self.`/`this.` chain or a call; a capitalised first segment (Class.method) only with a cue.
//     Rows hold the key: a site inside a longer name or a child key is counted in longer=, never a row (a dotted prefix before it is
//     kept: `config.a.b`). Sites the quotes delimit rank above mentions, and kForLiteralRegistrationRows slots are kept for a quoted
//     site outside any function (a registration), whatever the reader count. A row cut at 200 bytes opens near the key.
//   * shape="message": 3+ words with a whole word error/notification/message: a backticked or single-quoted span (cue outside it),
//     else the task minus a leading or trailing cue, else the words before a cue inside the sentence. Tries: the whole text, then
//     fragments of the longest placeholder-free word run, down to 3 words (frag="1": s= is only part of the task's words); a
//     FRAGMENT with fewer than kForLiteralMessageContent words that are not function words is dropped, the whole text needs one and
//     must end in it (`must not be empty` passes, `the value of the` does not); the rest are ordered by that count.
//     Hits stand on word edges (a hit inside a longer word is counted in longer=; the letter of an escape, `\n`, or of a printf
//     verb, `%s`, right before the hit is no word byte). A code row (k=code) is never printed; a k=? row stays.
// Literals are tried in order (forLiteralCandidates: quoted span, CONST words, dotted keys, message), kForLiteralCandidates scans, until
// one has a source site; try="N" says it was the task's Nth. Literals past the cap are not scanned: when none of the scanned ones
// anchors, <lit_capped scanned= skipped= next=> says so (a task of five keys no longer reads as five misses).
//
// TABLE-CONST V2. Last of all, only when no earlier literal has a site, shape="table": the sites of the identifiers a task about a table
// or a registration names, the question a ranked answer cannot print because the table holds no edge (a Go map entry, a Rust macro row, a C
// X-macro line). Trigger (forTableCueOf), whole words: a registration, table or compile-time word; "add a new", the exemplar form, whose
// anchor is the named sibling; or default/handler, which print only when a table row exists. Anchors (forTableAnchorsOf): backticked
// spans first, then identifier-shaped words (snake_case, camelCase, Pascal with an inner capital, a::b, a.b), then a plain word after
// like/alongside/following; a backticked span stands as it is, any other word must be a symbol of the index (forTableAnchorKeeps). A backticked
// span or a word after like is firm: it prints its sites. A bare identifier-shaped word, or a span right after to/into in an add task (the thing
// changed), prints only beside a real table row (TableAnchor::firm). At most kForTableAnchors <lit> print and kForLiteralCandidates scans are made
// (an anchor with no site costs one); all of them under one byte cap (kForTableByteCap, cut on a row boundary, capped=1 and next=). An anchor past a
// cap, or with no room left, is counted by <lit_capped>, never dropped. A row whose line reads as a table row (lit_detail::tableRowOf) ranks first
// and carries tbl= (the line that opens the table, "item" at top level) and the lines after it: the members beside it. Inside a function body a
// call is a statement, never a row; every row needs an opener the allowlist proves (classifyOpener). Hits stand on word edges.
//
// REGISTRAR-2 (reports/registrar-2.md; ORCH Stage 0: 5 rows of 380 gain, 0 lose). A registration is a table with one row per call: the same block
// reads more of them, present-only, three ways. (1) Trigger: defined/declared (not after not/never: an error message), build/builds/built, handled,
// turned into and get(s) to are TableRowOnly cues (kForTableSiteCues), so they print only beside a table row. (2) A site no table holds is a row
// when it is an argument of a call that SAYS it registers (registrationCallOf; the name allowlist is regindex.h reg_detail::isRegistrationCallee: a
// register verb, or an adding verb before route/command/handler, or a decorator's noun): a Python decorator `@websocket_command({...: "get_states"})`,
// `component.async_register_entity_service(SERVICE_TURN_ON, None, "async_turn_on")` over several lines, `async_reg(hass, handle_get_states)` (a hit
// inside a longer name is a row only here); in a function body too; reg= (not tbl=: no table opener) is the callee's line up to its paren. Not a call:
// a declaration of the same name (a constructor, a method, a GNU-style definition), a member of a type, a member-initializer list, a closure body.
// The top-level Rust macro row and the macro-table brace row were rows already (T2, T5); the cue was what the Stage 0 rows lacked.
// (3) Rows of generated and JSON files rank after source rows of the same nearness (isGeneratedOrDataPath), and never hold the home table. A callee's
// name is no proof the call registers: the row quotes it. (4) A dotted name that finds no site is retried by its last part, which lists quoted-key
// rows and its definition only (keepTailKeyRows).
//
// G-STORED-B (ORCH reports/os5-g-stored-s0.md). A stored subject is bare (`new_boxed_executor for HashJoinNode`, `light.turn_on hue async_turn_on`): no
// cue word, so the walk above never ran. With no cue the same walk runs on the task's anchors (none: no scan), but lists STRONG rows only (TableCue::
// StrongRowOnly, lit_detail::isStrongRow): a registration call's argument (reg=), a top-level macro or call row (tbl="item"), a macro-table brace row
// (a `name! {` or `$macro! {` opener). Weak rows (a dict, list, __all__, #define or const-array table, a site that is no row) are counted in weak=,
// never listed; none strong, no block. The legend clause rides only on such an answer. The callee vocabulary narrowed with it (rv-reg2-delta D1):
// `use` is a hook prefix, an adding verb's noun is the name's last word, `reg` is a verb only last or before a noun. The table legend lost the bytes
// no attribute of the answer needs (D4): the vocabulary list and the rank sentence; the tail= sentence rides only beside a tail=.
//
// FLAG-SHAPE-LIT (ORCH reports/os6-flag-default-s0.md OS-6b). A task naming a `--flag` (`kubelet --max-pods`; flagNamesOf: a kebab `--a-b`, or
// `--name` before a flag/option word) scans the bare name, after the shapes above, as shape="flag": a site is the whole quoted name (flagHitAt:
// `"max-pods"`, `"--workers"`), any other hit a mention (mention=). On the first string row whose call has one, def= is the default argument
// (flagDefaultAt: default=/default_value=, else the argument after the name, two after for a pflag `...P(` shorthand form; a sentence is a
// usage text, no default). When def= names a field (`c.MaxPods`), the field's CONSTANT writes (isConstantWriteAt: `x.F = 110`, `F: 110`; never
// `out.F = in.F`) are ld rows, functions and files named for defaults first, at most kForFlagWriteRows, writes= counting all read.

#include "infra/namesplit.h" // isIdentChar
#include "infra/sortutil.h"  // svLess — AnchorSet::dirs sort and search in byte order, never through operator<
#include "filter.h"          // pathTierOf — source / test / doc, the reader's tier
#include "layout.h"          // layout::lineOf — a byte offset's line
#include "hopbody.h"         // renderBodyElement — the --expand body element, no callee rows; pythonDocstringQuote
#include "langfacts.h"       // langFacts(...).leadingDocstring — which languages have a docstring convention
#include "lintrules.h"       // kLintExtRows — the extensions of every indexed language
#include "model.h"
#include "nextverb.h"        // nextFlag / nextAttrXml
#include "receiverevidence.h"   // ReceiverEvidence::callableKind
#include "resolve.h"       // tsimport::isAssetSpecifier — an asset extension is no key segment
#include "redact.h"          // redactInPlace — raw source text is redacted before it is emitted
#include "regindex.h"        // reg_detail::isRegistrationCallee — the registrar family's callee vocabulary (REGISTRAR-2 rows)
#include "sarif.h"           // rootPrefixOf / rootRelativeUri
#include "search.h"          // grepCollect / grepEnrich / isBareWordCodePath
#include "serialize.h"       // escapeXml / appendCdataSafe / truncateUtf8WithEllipsis / lineBreaksOf
#include "taskroute.h"       // taskroute::identifierRunOf
#include "siblift.h"         // siblift_detail::dirOf — a path's directory
#include "forreadercallers.h"   // renderReaderCallers — READER-CALLERS: the callers of the shown rows' reader functions
#include "subjectanchor.h"   // subject_detail::sourceClassDef / isToolOrVendoredPath — the answer's source-class anchors

#include <algorithm>
#include <array>
#include <tuple>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iterator>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::size_t kForLiteralSiteRows      = 8;      // <ls> rows shown (a runaway guard: shown=/src= count, next= lists all)
inline constexpr std::size_t kForLiteralRankedRows    = 256;    // source sites ordered for the rows (past it: counted in src=, not ranked)
inline constexpr std::size_t kForLiteralContextRows   = 2;      // string sites outside any function served with the lines after them
inline constexpr std::uint32_t kForLiteralContextLines = 2;     // ...this many lines after the site
inline constexpr std::size_t kForLiteralBodies        = 3;      // owner bodies served, in row order
inline constexpr std::size_t kForLiteralBodyCapBytes  = 3000;   // a short body over this many bytes is still served as an excerpt <x>
inline constexpr std::uint32_t kForLiteralWholeBodyLines = 10;  // a body of at most this many lines is served whole; a longer one as an excerpt
inline constexpr std::uint32_t kForLiteralExcerptBefore = 1;    // lines before a site in its excerpt window
inline constexpr std::uint32_t kForLiteralExcerptAfter  = 5;    // lines after it: what the code does with a literal follows the read (+2/+3 drops fzf R2)
inline constexpr std::uint32_t kForLiteralArmLines      = 12;   // EXCERPT-ARM: a window widens up to the head of the match arm or case holding its site, at most this many lines up
inline constexpr std::size_t kForLiteralTierFiles     = 64;     // source hit files classified (k=); past it k="?"
inline constexpr std::size_t kForLiteralLineBytes     = 200;    // the matched line's text, cut on a UTF-8 boundary
inline constexpr std::size_t kForLiteralMinQuoted     = 6;
inline constexpr std::size_t kForLiteralMinConst      = 5;
inline constexpr std::size_t kForLiteralMinBareCaps   = 10;
inline constexpr std::size_t kForLiteralMinKeyBytes   = 6;      // a dotted key shorter than this is not a key (`a.b.c`)
inline constexpr std::size_t kForLiteralMessageWords  = 3;      // a message or a fragment of one has at least this many words
inline constexpr std::size_t kForLiteralMessageTries  = 8;      // whole-repo scans a message may cost (a runaway guard on a task's word count)
inline constexpr std::size_t kForLiteralMessageContent = 2;      // a message FRAGMENT holds at least this many words that are not function words
inline constexpr std::size_t kForLiteralWholeContent   = 1;      // the WHOLE text holds at least this many, and ends in one (`must not be empty`)
inline constexpr std::size_t kForLiteralCandidates    = 4;      // literals (quoted span, CONST words, dotted keys) a task may have scanned, in order, until one has a source site
inline constexpr std::size_t kForLiteralRegistrationRows = 2;   // shape=dotted: row slots kept for quoted sites outside any function (a registration) whatever the reader count
inline constexpr std::size_t kForLiteralFileMaxSegments = 4;    // a dotted word of this many segments or more is a key even when its last one is an extension (`envoy.filters.http.lua`)
inline constexpr std::size_t kForLiteralKeyLead       = 40;     // a cut row starts this many bytes before the key
inline constexpr std::size_t kForTableAnchors         = 3;      // shape=table: identifiers of a task scanned, in order, each with a site printing a <lit>
inline constexpr std::size_t kForTableRows            = 32;     // shape=table: <ls> rows per anchor (next= lists all)
inline constexpr std::size_t kForTableByteCap         = 40000;  // shape=table: all its <lit> elements together, cut on a row boundary (runaway guard: a 16 KB cap loses ld-nushell-07)
inline constexpr std::size_t kForTableElementBytes    = 800;    // shape=table: what an element's open tag and legend may add to its rows and bodies; an anchor is not tried with less than this left
inline constexpr std::size_t kForTableRankedRows      = 4096;   // shape=table: source sites read for a table row and ordered (a registry past the readers in path order must still rank first)
inline constexpr std::size_t kForTableContextRows     = 4;      // shape=table: table rows served with the lines after them
inline constexpr std::size_t kForTableSiblingLines    = 24;     // a sibling row of a table row is looked for this many lines away (an entry may span lines)
inline constexpr std::size_t kForTableOpenerLines     = 2000;   // the line that opens a table is looked for this many lines above a row
inline constexpr std::size_t kForTableOpenerBytes     = 80;     // tbl= text
inline constexpr std::size_t kForTableMinAnchor       = 3;      // a shorter word is no anchor
inline constexpr std::size_t kForTableMaxAnchor       = 60;     // a longer backticked span is no anchor
inline constexpr std::size_t kForRegCallLines         = 4;      // shape=table: a registration call's open paren is looked for this many lines above a site
inline constexpr std::size_t kForRegCallBytes         = 512;    // ...and this many bytes
inline constexpr std::size_t kForRegLineHits          = 8;      // shape=table: later hits on one line kept to try as a registration argument (the first is the site)
inline constexpr std::size_t kForFlagMinName          = 3;      // FLAG-SHAPE-LIT: a `--flag` name shorter than this is no flag; a name with no inner hyphen needs kForLiteralMinConst bytes and a flag/option word
inline constexpr std::size_t kForFlagDefaultMaxBytes     = 80;     // def= text
inline constexpr std::size_t kForFlagWriteRows        = 2;      // constant writes of the default's field listed (ld rows)
inline constexpr std::size_t kForFlagWriteHits        = 4096;   // the field's sites read for a constant write (past it: floor=1)
inline constexpr std::size_t kForFlagOwnerMaxLines       = 8;      // a constant write outside any function names the owner type within this many lines above it
inline constexpr std::size_t kForTableReaderRows      = 2;      // REG-READER: <lr> reads of a subscript row's table listed (readers= counts all)
inline constexpr std::size_t kForTableReaderFiles     = 16;     // REG-READER: caller files read for them, by path (past it: readers= is a floor)
inline constexpr std::size_t kForRegIdentBytes        = 128;    // shape=table: an identifier run longer than this around a hit is no argument name (a blob, not a name)

// the element's legend comment (X3: no double hyphen inside). The compact form is the default --legend=compact posture; the long
// text rides --legend=full. Both name every attribute the element prints.
inline constexpr std::string_view kForLiteralLegend =
    "<!-- ripwire for lit: a byte-exact index scan for the literal the task names (s=; shape= quoted span or CONST word), after "
    "the unchanged answer, not in est_tokens (bytes= is its size). ls = one source line holding it, in-function sites first: "
    "k=string in a string literal, code outside one, ? unclassified; in=/ink= the enclosing definition and kind; CDATA its line "
    "(lines=a-b: with the lines after it). hits= all matches, src= source lines (shown=, capped=1), comment= comments and "
    "docstrings, test= test paths, doc= docs, shell, config: counted, never rows. b = a shown site's whole function (10 lines or "
    "fewer), x = an excerpt of a longer one (l= its line ranges: the signature line and a window around each site, an ellipsis "
    "line between them; of= the body's lines; cut=1: a line over 200 bytes was cut; next= the whole body); body=above: printed "
    "above, held: its owner body is past the 3-body cap, not printed. floor=1: scan stopped early or a site "
    "was not classified (k=?), counts are floors; next= on lit lists every site. -->";
inline constexpr std::string_view kForCompactLiteralLegend =
    "<!-- ripwire for lit: byte-exact scan for the task's literal (s=, shape=), not in est_tokens (bytes=). ls: a source line with it "
    "(k=string|code|?; in=/ink= its def; lines=a-b adds the lines after). hits=/src= all/source lines (shown=; capped=1: more); "
    "comment= test= doc= counted, not rows; floor=1: floors. b whole fn, x excerpt (l= ranges, \xE2\x80\xA6 between; of= body lines; "
    "cut=1: lines cut; next= whole); body=above|held: printed above|past the 3-body cap. -->";
static_assert( kForLiteralLegend.find( "--", 4 ) == kForLiteralLegend.size() - 3 && kForCompactLiteralLegend.find( "--", 4 ) == kForCompactLiteralLegend.size() - 3,
               "the only double hyphen in a legend comment is its closing: one inside is not well-formed XML" );

// present only with shape=dotted|message, so the bytes of a quoted or const fire do not move; the name of the shape is the row's whole
// reading, the base legend above still defines every other attribute
inline constexpr std::string_view kForLiteralKeyLegend =
    "<!-- ripwire for lit: shape=dotted a dotted key in the task (3 or more segments, or 2 with a setting, option, key, command or flag "
    "word): rows hold the key (a dotted prefix may stand before it), quoted sites first, up to two row slots kept for a quoted string "
    "site outside any function (a registration or table the parse classified as a string; a C #define is not one); longer= source "
    "sites inside a longer name, child key or word, counted, never rows. shape=message the task's words as a "
    "message (3 or more, with an error, notification or message word): never a code row; frag=1: the whole text has no site, s= is "
    "the part that does. try=N: the task's Nth literal anchored; the ones before it had no source site or were not scanned. -->";
static_assert( kForLiteralKeyLegend.find( "--", 4 ) == kForLiteralKeyLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );
// the walk's cap, printed alone (no <lit>) when the task names more literals than kForLiteralCandidates scans and none of those anchored
inline constexpr std::string_view kForLiteralCapLegend =
    "<!-- ripwire for lit: lit_capped = the task names more literals than this answer prints; scanned= whole-repo scans made; skipped= literals not scanned (past "
    "the scan cap), scanned with no room left in the byte cap, or scanned with too many sites to read for a table row and none in those read, their sites not shown; "
    "next= scans the first of them; a scanned literal without a <lit> had no source site (shape=table: or no table row); this note is not in est_tokens. -->";
static_assert( kForLiteralCapLegend.find( "--", 4 ) == kForLiteralCapLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );

// present only with shape=table (the first of its elements), so the bytes of every other fire do not move
inline constexpr std::string_view kForLiteralTableLegend =
    "<!-- ripwire for lit: shape=table a task about a table, registration or new sibling: the identifier it names, one lit per identifier, "
    "after the other shapes found no site. Table rows first: tbl= the line that opens the table (item: a top level macro or call row), read from the text; no tbl= or "
    "reg= is no claim. reg= instead: the row is an argument of a call whose name says it registers (the name, not proof), also inside a longer name, and reg= is that "
    "call up to its paren, looked for 4 lines and 512 bytes above the site. lines=a-b with the lines after it. read=N: only the first N source sites of src= in path "
    "order were read for a table row. longer= source sites inside a longer word, counted, never rows. A cut on a row boundary says capped=1. -->";
static_assert( kForLiteralTableLegend.find( "--", 4 ) == kForLiteralTableLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );
static_assert( kForRegCallLines == 4 && kForRegCallBytes == 512, "the table legend says how far a registration call is looked for: 4 lines and 512 bytes" );
// G-STORED-B: present only when the task has no table, registration or handler word (TableCue::StrongRowOnly), with the first element
inline constexpr std::string_view kForLiteralStrongLegend =
    "<!-- ripwire for lit: the task has no table or registration word, so only strong rows are listed: a registration call's direct argument (reg=), a top level macro or "
    "call row (tbl=item), a macro table row (tbl= a name! opener). weak=N source sites read that are other table rows or no row, not listed. -->";
static_assert( kForLiteralStrongLegend.find( "--", 4 ) == kForLiteralStrongLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );
// FLAG-SHAPE-LIT: the clause of shape=flag (policy legend), present only on a flag fire
inline constexpr std::string_view kForLiteralFlagLegend =
    "<!-- ripwire for lit: shape=flag a flag the task names (s= without its leading dashes): rows are the sites where it is a whole quoted string (its "
    "definition among them, also an invocation or a lookup); mention= other source sites (usage text, a longer flag name), counted, never rows. def= on a "
    "row: the default of a flag-definition call (default= or the flag API's default slot), read from the text, no claim it is the value in effect. ld = a "
    "constant write (x.F = 110, F: 110) of the field def= names, in a function whose text or a literal's lines name the type of the receiver in def= (a "
    "name match, no type check), functions and files named for defaults first, at most 2; writes=N all such writes read; none is no claim. -->";
// the try=N sentence of the flag clause rides only beside a try= (the other shapes carry it in their own legend)
inline constexpr std::string_view kForLiteralFlagTryLegend =
    "<!-- ripwire for lit: try=N: the task's Nth literal anchored; the ones before it had no source site. -->";
static_assert( kForLiteralFlagTryLegend.find( "--", 4 ) == kForLiteralFlagTryLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );
static_assert( kForLiteralFlagLegend.find( "--", 4 ) == kForLiteralFlagLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );
static_assert( kForFlagWriteRows == 2, "the flag legend says at most 2 ld rows" );

// EXCERPT-ARM: present only with arm= on an <x> (the first element that prints it)
inline constexpr std::string_view kForLiteralArmLegend =
    "<!-- ripwire for lit: x arm=1: a window starts at the head of the match arm or case holding its site (12 lines up at most), not one line above it. -->";
static_assert( kForLiteralArmLegend.find( "--", 4 ) == kForLiteralArmLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );
static_assert( kForLiteralArmLines == 12, "the arm legend says how far up a window may widen: 12 lines" );
// rv-reg2-delta D4: present only with tail= (the first element that prints it)
inline constexpr std::string_view kForLiteralTailLegend =
    "<!-- ripwire for lit: tail=N: a dotted name found no site; its last part lists quoted keys and its definition, N sites not listed. -->";
static_assert( kForLiteralTailLegend.find( "--", 4 ) == kForLiteralTailLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );
// REG-READER: present only with a subscript reg= row (the first element that prints one)
inline constexpr std::string_view kForLiteralSubscriptLegend =
    "<!-- ripwire for lit: reg= ending in `] =`: the site is the key or value of a write into a table with a computed key, in a function named New*, new_*, "
    "Register* or register_* (the name, not proof); reg= is the table and key. lr = a read of that table (t[k] not assigned, t.get(), also a caller's local "
    "bound to that function's call) in the row's file or its callers' files, listed only when the answer above names the table; reads sharing a quoted part "
    "of the key first, at most 2; readers=N all reads found (floor=1 if a file was unread or callers past 16 files were not read). -->";
static_assert( kForLiteralSubscriptLegend.find( "--", 4 ) == kForLiteralSubscriptLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );
static_assert( kForTableReaderRows == 2 && kForTableReaderFiles == 16, "the subscript legend says at most 2 lr rows and 16 caller files" );

// present only with lit_cut= (LIT-SITE-DECOY), so the bytes of a block whose cut moved no row do not change; the compact form rides the default
// --legend=compact posture, the long one --legend=full
inline constexpr std::string_view kForLiteralCutLegend =
    "<!-- ripwire for lit: rows near the answer first: a site in a file or directory of its rows, bodies or the literal's own definitions, or one call "
    "from them (not through a hub). lit_cut=N (printed when the cut moved a row): N read sites not rows, when the sites do not all fit: a vendored, "
    "minified or generated copy beside product sites, a site far from the answer, or a row of another table than the one in the answer's file (with "
    "none there: the home table, most rows, then a #define list, then most sites outside functions); a registration the reserve holds is kept; next= "
    "lists every site. -->";
inline constexpr std::string_view kForCompactLiteralCutLegend =
    "<!-- ripwire for lit: near rows first (a file or dir of the answer or the literal's defs, or one call away); lit_cut=N sites not rows: when not "
    "all fit, far ones, another table, vendored copies; next= lists all. -->";
static_assert( kForLiteralCutLegend.find( "--", 4 ) == kForLiteralCutLegend.size() - 3 && kForCompactLiteralCutLegend.find( "--", 4 ) == kForCompactLiteralCutLegend.size() - 3,
               "the only double hyphen in a legend comment is its closing" );

inline bool forLiteralOn()
{
    return std::getenv( "RIPWIRE_NO_LITERAL_ANCHOR" ) == nullptr;
}

struct ForLiteral
{
    std::string text;
    std::string_view shape;   // "quoted" | "const" | "dotted" | "message" | "flag"
    bool             frag = false;   // shape=message: `text` is a fragment of the task's words, the whole text has no site
    std::size_t      tryNo = 1;      // the task's Nth literal (earlier ones were scanned and have no source site): try="N" when > 1
    bool             bare = false;   // WHOLE-TOKEN: shape=flag from a bare kebab token beside an option/flag/setting word (1..kForBareFlagMaxSites sites)
    bool             verbatim = false;   // MSG-VERBATIM: shape=message from a cue-less task's whole text (1..kForVerbatimMaxSites confirmed string sites, no fragments)
};
inline constexpr std::size_t kForBareFlagMaxSites = 8;   // WHOLE-TOKEN: a bare kebab token with more source sites is prose, not one option
inline constexpr std::size_t kForVerbatimMaxSites = 3;   // MSG-VERBATIM: a cue-less whole text with more source sites is no single message

namespace lit_detail
{

// CONST_SHAPED: upper-case letters and digits, starting with a letter, joined by underscores (at least one, none doubled or at an
// end) and at least kForLiteralMinConst bytes; or no underscore and at least kForLiteralMinBareCaps bytes (PYTHONASYNCIODEBUG)
inline bool isConstShaped( std::string_view w ) noexcept
{
    if( w.empty() || !( w[0] >= 'A' && w[0] <= 'Z' ) || w.back() == '_' )
    {
        return false;
    }
    std::size_t underscores = 0;
    for( std::size_t i = 0; i < w.size(); ++i )
    {
        if( w[i] == '_' )
        {
            if( w[i - 1] == '_' )
            {
                return false;
            }
            ++underscores;
        }
        else if( !std::isupper( static_cast<unsigned char>( w[i] ) ) && !std::isdigit( static_cast<unsigned char>( w[i] ) ) )
        {
            return false;
        }
    }
    return underscores > 0 ? w.size() >= kForLiteralMinConst : w.size() >= kForLiteralMinBareCaps;
}

inline std::optional<std::string> quotedSpan( std::string_view task, char q )
{
    for( std::size_t open = task.find( q ); open != std::string_view::npos; open = task.find( q, open + 1 ) )
    {
        const std::size_t close = task.find( q, open + 1 );
        if( close == std::string_view::npos )
        {
            return std::nullopt;
        }
        const std::string_view inner = task.substr( open + 1, close - open - 1 );
        bool letter = false;
        for( const char c : inner )
        {
            letter = letter || std::isalpha( static_cast<unsigned char>( c ) ) != 0;
        }
        // a MESSAGE fragment: two words or more (a single quoted word is a value or a name, read as words by the ranked answer)
        if( inner.size() >= kForLiteralMinQuoted && letter && inner.find_first_not_of( " \t" ) == 0 && inner.back() != ' '
            && inner.find( ' ' ) != std::string_view::npos )
        {
            return std::string( inner );
        }
        open = close;
    }
    return std::nullopt;
}

// the task's whitespace-separated words, in order
inline std::vector<std::string_view> taskWords( std::string_view task )
{
    std::vector<std::string_view> out;
    for( std::size_t i = 0; i < task.size(); )
    {
        const std::size_t a = task.find_first_not_of( " \t", i );
        if( a == std::string_view::npos )
        {
            break;
        }
        const std::size_t b = std::min( task.find_first_of( " \t", a ), task.size() );
        out.push_back( task.substr( a, b - a ) );
        i = b;
    }
    return out;
}

// a word without the quotes and sentence punctuation around it (never parentheses: `f.g.h()` stays a call, dottedKeyOf refuses it)
inline std::string_view stripWordPunct( std::string_view w ) noexcept
{
    constexpr std::string_view kPunct = "\"'`,;:.!?<>[]{}";
    while( !w.empty() && kPunct.find( w.front() ) != std::string_view::npos )
    {
        w.remove_prefix( 1 );
    }
    while( !w.empty() && kPunct.find( w.back() ) != std::string_view::npos )
    {
        w.remove_suffix( 1 );
    }
    return w;
}

inline constexpr std::array<std::string_view, 10> kForLiteralSettingCues{ "setting", "settings", "option", "options", "key", "keys", "command", "commands", "flag", "flags" };
inline constexpr std::array<std::string_view, 6>  kForLiteralMessageCues{ "error", "errors", "notification", "notifications", "message", "messages" };
// the data, doc, build and host words no language table or asset table holds (isFileOrHostSuffix reads those: kLintExtRows, isAssetSpecifier).
// A REFUSAL list (SAFETY (d)1): a word not here and in neither table is a segment of a key.
inline constexpr auto kForLiteralFileSuffixes = std::to_array<std::string_view>(
    { "jsonc", "json5", "mdx", "rst", "htm", "ini", "cfg", "conf", "properties", "env", "lock", "log", "tsv", "sql", "proto", "gradle", "cmake",
      "bazel", "bzl", "hcl", "tf", "tfvars", "tfstate", "plist", "pdf", "zip", "tar", "gz", "jar", "so", "vue", "scala",
      "com", "org", "net", "io", "dev", "ai", "co", "app" } );
// function words: a message or fragment of nothing but these (`the value of the`) says nothing about the code
inline constexpr auto kForLiteralStopWords = std::to_array<std::string_view>(
    { "the", "a", "an", "of", "is", "are", "was", "were", "be", "been", "to", "in", "on", "at", "for", "and", "or", "not", "no", "by", "with",
      "from", "this", "that", "it", "its", "could", "can", "cannot", "would", "should", "will", "may", "must", "do", "does", "did", "has",
      "have", "had", "as", "if", "but", "so", "then", "than", "there" } );
inline constexpr std::array<std::string_view, 17> kForLiteralLeadWords{ "where", "which", "what", "who", "why", "when", "how", "does", "do", "is", "path", "callers", "common", "lowest", "call", "trace", "thread" };

inline bool wordIsOneOf( std::string_view word, std::span<const std::string_view> set )
{
    std::string low( stripWordPunct( word ) );
    std::transform( low.begin(), low.end(), low.begin(), []( unsigned char c ) { return static_cast<char>( std::tolower( c ) ); } );
    return std::find( set.begin(), set.end(), std::string_view( low ) ) != set.end();
}

inline bool isSettingCue( std::string_view w )
{
    return wordIsOneOf( w, kForLiteralSettingCues );
}

inline bool isMessageCue( std::string_view w )
{
    return wordIsOneOf( w, kForLiteralMessageCues );
}

// MSG-VERBATIM (ORCH reports/s0-batch-1111.md §4): a task of kForVerbatimMinWords words or more with no message cue word may still BE a message
// (`Nest can't resolve dependencies of the`): its whole text is tried once, and only a verbatim string site says so
inline constexpr std::size_t kForVerbatimMinWords = 4;
inline bool isVerbatimMessageTask( std::span<const std::string_view> words )
{
    return words.size() >= kForVerbatimMinWords && std::none_of( words.begin(), words.end(), []( std::string_view w ) { return isMessageCue( w ); } );
}

// both ends trimmed of every whitespace byte, newlines included (a default may start on the line after the name)
inline std::string_view trimAllWs( std::string_view v ) noexcept
{
    constexpr std::string_view kBlanks = " \t\r\n\f\v";
    const std::size_t          first   = v.find_first_not_of( kBlanks );
    return first == std::string_view::npos ? std::string_view() : v.substr( first, v.find_last_not_of( kBlanks ) - first + 1 );
}

// a key's last segment that says the dotted word is a file or a host: an extension of kLintExtRows (every indexed language), of
// isAssetSpecifier's assets, or a word of the table above (data, doc and build files, the common host suffixes). A file the index holds is
// refused by its name in renderForLiteralOfTask, whatever its extension. dottedKeysOf applies it below kForLiteralFileMaxSegments segments only.
inline bool isFileOrHostSuffix( std::string_view lastSegment )
{
    if( wordIsOneOf( lastSegment, kForLiteralFileSuffixes ) )
    {
        return true;
    }
    std::string dotted( "." );   // `.rake`, `.astro`: an extension of lintrules.h kLintExtRows (the crawl's own table, 10 rows the first table missed)
    for( const char c : lastSegment )
    {
        dotted += static_cast<char>( std::tolower( static_cast<unsigned char>( c ) ) );
    }
    return std::any_of( std::begin( kLintExtRows ), std::end( kLintExtRows ), [ & ]( const LintExtRow& r ) { return r.ext == dotted; } )
           || tsimport::isAssetSpecifier( "x" + dotted );
}

// `.env.local`, `".terraform.lock.hcl"`: a word that opens with a dot (behind quotes or brackets) is a dotfile, never a key
inline bool opensWithDot( std::string_view raw ) noexcept
{
    const std::size_t at = raw.find_first_not_of( "\"'`(<[{" );
    return at != std::string_view::npos && raw[at] == '.';
}

// ALLOWLIST (SAFETY (d)1): segments of letters, digits, `_` and `-` that open with a letter or `_`, no `-` at a segment's end. Returns the
// segment count, 0 when the word is not of that shape
inline std::size_t keySegments( std::string_view w ) noexcept
{
    std::size_t segments = 0;
    for( std::size_t at = 0; at <= w.size(); ++segments )
    {
        const std::size_t end = std::min( w.find( '.', at ), w.size() );
        const std::string_view seg = w.substr( at, end - at );
        if( seg.empty() || !( std::isalpha( static_cast<unsigned char>( seg[0] ) ) != 0 || seg[0] == '_' ) || seg.back() == '-' )
        {
            return 0;
        }
        for( const char c : seg )
        {
            if( std::isalnum( static_cast<unsigned char>( c ) ) == 0 && c != '_' && c != '-' )
            {
                return 0;
            }
        }
        at = end + 1;
    }
    return segments;
}

// the dotted keys of the task's words, in order, those beside a setting cue word first (`workbench.action.files.save files.autoSave
// setting`: the key the cue names leads); none when there is no key
inline std::vector<std::string> dottedKeysOf( const std::vector<std::string_view>& words )
{
    const bool cue = std::any_of( words.begin(), words.end(), []( std::string_view w ) { return isSettingCue( w ); } );
    std::vector<std::string> beside, rest;
    for( std::size_t i = 0; i < words.size(); ++i )
    {
        const std::string_view w = stripWordPunct( words[i] );
        const std::size_t      n = keySegments( w );
        if( n < 2 || w.size() < kForLiteralMinKeyBytes || opensWithDot( words[i] )
            || ( n < kForLiteralFileMaxSegments && isFileOrHostSuffix( w.substr( w.rfind( '.' ) + 1 ) ) )
            || w.starts_with( "self." ) || w.starts_with( "this." ) )
        {
            continue;
        }
        const bool classShaped = std::isupper( static_cast<unsigned char>( w[0] ) ) != 0;
        const std::string key( w );
        if( !( cue || ( n >= 3 && !classShaped ) ) || std::find( beside.begin(), beside.end(), key ) != beside.end()
            || std::find( rest.begin(), rest.end(), key ) != rest.end() )
        {
            continue;
        }
        const bool near = ( i > 0 && isSettingCue( words[i - 1] ) ) || ( i + 1 < words.size() && isSettingCue( words[i + 1] ) );
        ( near ? beside : rest ).push_back( key );
    }
    beside.insert( beside.end(), rest.begin(), rest.end() );
    return beside;
}

// the first span `q` delimits, its delimiters included. A ' only opens after a space or the start and never closes before a letter or
// digit (`wasn't` is no quote)
inline std::optional<std::string_view> delimitedSpan( std::string_view task, char q )
{
    for( std::size_t a = task.find( q ); a != std::string_view::npos; a = task.find( q, a + 1 ) )
    {
        if( q == '\'' && a > 0 && task[a - 1] != ' ' )
        {
            continue;
        }
        std::size_t b = task.find( q, a + 1 );
        while( q == '\'' && b != std::string_view::npos && b + 1 < task.size() && std::isalnum( static_cast<unsigned char>( task[b + 1] ) ) != 0 )
        {
            b = task.find( q, b + 1 );
        }
        if( b == std::string_view::npos )
        {
            return std::nullopt;
        }
        return task.substr( a, b - a + 1 );
    }
    return std::nullopt;
}

// the first ` or ' delimited span of 3+ words with a message cue outside it
inline std::optional<std::string> quotedMessageOf( std::string_view task )
{
    for( const char q : { '`', '\'' } )
    {
        const std::optional<std::string_view> span = delimitedSpan( task, q );
        if( !span )
        {
            continue;
        }
        const std::string_view inner = span->substr( 1, span->size() - 2 );
        if( taskWords( inner ).size() < kForLiteralMessageWords )
        {
            continue;
        }
        const std::size_t at = std::size_t( span->data() - task.data() );
        const std::string outside = std::string( task.substr( 0, at ) ) + " " + std::string( task.substr( at + span->size() ) );
        for( const std::string_view w : taskWords( outside ) )
        {
            if( isMessageCue( w ) )
            {
                return std::string( inner );
            }
        }
    }
    return std::nullopt;
}

// the whole task minus its leading or trailing cue words, else the words before a cue inside it, when that is 3+ plain words: a stored
// subject is `<message> <cue>`. Refused:
// a task that opens with a question or a verb's own lead word, or holds code punctuation
inline std::optional<std::string> bareMessageOf( std::vector<std::string_view> words )
{
    bool cue = false;
    while( !words.empty() && isMessageCue( words.back() ) )
    {
        words.pop_back();
        cue = true;
    }
    while( !words.empty() && isMessageCue( words.front() ) )
    {
        words.erase( words.begin() );
        cue = true;
    }
    if( !cue )
    {
        // a cue inside the sentence (`Command not found error for an unknown word`): the words before the first cue
        const auto at = std::find_if( words.begin(), words.end(), []( std::string_view w ) { return isMessageCue( w ); } );
        if( at != words.end() )
        {
            words.erase( at, words.end() );
            cue = true;
        }
    }
    if( !cue || words.size() < kForLiteralMessageWords
        || wordIsOneOf( words.front(), kForLiteralLeadWords ) )
    {
        return std::nullopt;
    }
    std::string out;
    for( const std::string_view w : words )
    {
        if( w.find_first_of( "(){}=;`" ) != std::string_view::npos )
        {
            return std::nullopt;
        }
        out += out.empty() ? "" : " ";
        out += w;
    }
    return out;
}
}   // namespace lit_detail

// the words of `text` that are not function words (kForLiteralStopWords)
inline std::size_t contentWords( std::string_view text )
{
    std::size_t n = 0;
    for( const std::string_view w : lit_detail::taskWords( text ) )
    {
        n += lit_detail::wordIsOneOf( w, lit_detail::kForLiteralStopWords ) ? 0 : 1;
    }
    return n;
}

// The tries of a message, in order, at most kForLiteralMessageTries: the whole text, then the longest word run free of placeholders and
// dotted or path words (`asyncio.run`, `{}`, `%s`), that run and its end-anchored fragments, down to 3 words. A source message is
// usually split by a placeholder the task does not spell, so the fragment may be anchored at either end. A try with fewer than
// kForLiteralMessageContent words that are not function words is dropped (`the transaction is`; the whole text needs one and must end in
// it), and the rest are ordered by that count,
// the longest first among equals: a start-anchored stop-word fragment never wins over the fragment that holds the content.
inline std::vector<std::string> forMessageTries( std::string_view message )
{
    const std::vector<std::string_view> words = lit_detail::taskWords( message );
    std::vector<std::string>            all{ std::string( message ) };
    std::size_t bestAt = 0, bestLen = 0;
    for( std::size_t i = 0; i < words.size(); )
    {
        std::size_t j = i;
        const auto  plain = [ & ]( std::string_view w ) { return lit_detail::stripWordPunct( w ).find_first_of( ".:/\\%{}$" ) == std::string_view::npos; };
        while( j < words.size() && plain( words[j] ) )
        {
            ++j;
        }
        if( j - i > bestLen )
        {
            bestAt  = i;
            bestLen = j - i;
        }
        i = j == i ? i + 1 : j;
    }
    const auto joined = [ & ]( std::size_t at, std::size_t n )
    {
        const char* const b = words[at].data();
        const char* const e = words[at + n - 1].data() + words[at + n - 1].size();
        return std::string( lit_detail::stripWordPunct( std::string_view( b, std::size_t( e - b ) ) ) );
    };
    const auto addTry = [ & ]( std::string t )
    {
        if( std::find( all.begin(), all.end(), t ) == all.end() )
        {
            all.push_back( std::move( t ) );
        }
    };
    for( std::size_t n = bestLen; n >= kForLiteralMessageWords; --n )
    {
        addTry( joined( bestAt, n ) );
        addTry( joined( bestAt + bestLen - n, n ) );
    }
    std::vector<std::string> out;
    for( std::size_t i = 0; i < all.size(); ++i )
    {
        // a fragment needs kForLiteralMessageContent content words; the whole text, the task's own words, needs kForLiteralWholeContent
        // and must end in a content word (`must not be empty` yes, `the value of the` no)
        const std::size_t content = contentWords( all[i] );
        const std::vector<std::string_view> tw = lit_detail::taskWords( all[i] );
        const bool        wholeOk = i == 0 && content >= kForLiteralWholeContent && !tw.empty()
                                    && !lit_detail::wordIsOneOf( tw.back(), lit_detail::kForLiteralStopWords );
        if( content >= kForLiteralMessageContent || wholeOk )
        {
            out.push_back( std::move( all[i] ) );
        }
    }
    std::stable_sort( out.begin(), out.end(), []( const std::string& a, const std::string& b ) { return contentWords( a ) > contentWords( b ); } );
    if( out.size() > kForLiteralMessageTries )
    {
        out.resize( kForLiteralMessageTries );
    }
    return out;
}

// the CONST_SHAPED words of the task, in order (trailing/leading punctuation stripped), each once
inline std::vector<std::string> constWordsOf( std::string_view task )
{
    std::vector<std::string> out;
    for( std::string_view w : lit_detail::taskWords( task ) )
    {
        while( !w.empty() && std::string_view( "$(['{<,;:.!?)]}>'`" ).find( w.front() ) != std::string_view::npos )
        {
            w.remove_prefix( 1 );
        }
        while( !w.empty() && std::string_view( "(['{<,;:.!?)]}>'`" ).find( w.back() ) != std::string_view::npos )
        {
            w.remove_suffix( 1 );
        }
        if( lit_detail::isConstShaped( w ) && std::find( out.begin(), out.end(), w ) == out.end() )   // a name repeated in the task is one scan, one slot
        {
            out.emplace_back( w );
        }
    }
    return out;
}

// FLAG-SHAPE-LIT: the `--flag` names of the task (`kubelet --max-pods` -> max-pods), in order, each once: a token `--a-b` (kebab: an inner hyphen),
// or `--name` of kForLiteralMinConst bytes or more right before a flag/option word. Lower-case letters, digits and hyphens only; a trailing `=value`
// or punctuation is cut. Backticked or not (a flag is no code name the ranked answer reads).
inline std::vector<std::string> flagNamesOf( std::string_view task )
{
    std::vector<std::string>            out;
    const std::vector<std::string_view> words = lit_detail::taskWords( task );
    for( std::size_t i = 0; i < words.size(); ++i )
    {
        std::string_view w = words[i];
        while( !w.empty() && std::string_view( "`'\"([{<" ).find( w.front() ) != std::string_view::npos )
        {
            w.remove_prefix( 1 );
        }
        if( !w.starts_with( "--" ) )
        {
            continue;
        }
        w.remove_prefix( 2 );
        const std::size_t eq = w.find( '=' );
        w = eq == std::string_view::npos ? w : w.substr( 0, eq );
        while( !w.empty() && std::string_view( "`'\")]}>,;:.!?" ).find( w.back() ) != std::string_view::npos )
        {
            w.remove_suffix( 1 );
        }
        const bool bytesOk = !w.empty() && std::islower( static_cast<unsigned char>( w.front() ) ) != 0 && w.back() != '-'
                             && std::all_of( w.begin(), w.end(), []( char c ) { return std::islower( static_cast<unsigned char>( c ) ) != 0 || std::isdigit( static_cast<unsigned char>( c ) ) != 0 || c == '-'; } )
                             && w.find( "--" ) == std::string_view::npos;
        const bool kebab = w.find( '-' ) != std::string_view::npos;
        const bool cued  = i + 1 < words.size() && lit_detail::wordIsOneOf( lit_detail::stripWordPunct( words[i + 1] ), std::array<std::string_view, 4>{ "flag", "flags", "option", "options" } );
        if( bytesOk && w.size() >= kForFlagMinName && ( kebab || ( cued && w.size() >= kForLiteralMinConst ) ) && std::find( out.begin(), out.end(), w ) == out.end() )
        {
            out.emplace_back( w );
        }
    }
    return out;
}

// WHOLE-TOKEN (ORCH reports/ideas-verify-fable-1111.md): a BARE kebab token (`escape-time option`, no `--`) right before or after an
// option/flag/setting word, the same bytes flagNamesOf keeps (lower-case letters, digits, an inner hyphen), backticks and quotes stripped.
// Each once, never one flagNamesOf already read dashed. Its <lit shape="flag"> prints only with 1..kForBareFlagMaxSites source sites.
inline std::vector<std::string> bareFlagNamesOf( std::string_view task )
{
    std::vector<std::string>            out;
    const std::vector<std::string>      dashed = flagNamesOf( task );
    const std::vector<std::string_view> words  = lit_detail::taskWords( task );
    static constexpr std::array<std::string_view, 6> kCues{ "option", "options", "flag", "flags", "setting", "settings" };
    const auto cueAt = [ & ]( std::size_t j ) { return j < words.size() && lit_detail::wordIsOneOf( lit_detail::stripWordPunct( words[j] ), kCues ); };
    for( std::size_t i = 0; i < words.size(); ++i )
    {
        std::string_view w = words[i];
        while( !w.empty() && std::string_view( "`'\"([{<" ).find( w.front() ) != std::string_view::npos )
        {
            w.remove_prefix( 1 );
        }
        while( !w.empty() && std::string_view( "`'\")]}>,;:.!?" ).find( w.back() ) != std::string_view::npos )
        {
            w.remove_suffix( 1 );
        }
        const bool bytesOk = w.size() >= kForFlagMinName && std::islower( static_cast<unsigned char>( w.front() ) ) != 0 && w.back() != '-'
                             && w.find( '-' ) != std::string_view::npos && w.find( "--" ) == std::string_view::npos
                             && std::all_of( w.begin(), w.end(), []( char c ) { return std::islower( static_cast<unsigned char>( c ) ) != 0 || std::isdigit( static_cast<unsigned char>( c ) ) != 0 || c == '-'; } );
        if( bytesOk && ( cueAt( i + 1 ) || ( i > 0 && cueAt( i - 1 ) ) ) && std::find( dashed.begin(), dashed.end(), w ) == dashed.end()
            && std::find( out.begin(), out.end(), w ) == out.end() )
        {
            out.emplace_back( w );
        }
    }
    return out;
}

// The task quotes a message literal: a "double-quoted" span (the quoted shape's own reading, lit_detail::quotedSpan) or a
// 'single-quoted' one (lit_detail::delimitedSpan: `wasn't` is no quote) of the same message-fragment shape (quotedSpan read on that
// span). SIZE-2 (forpage.h tailFoldKept): such a task keeps its tail's config and doc rows listed — a quoted message's text lives in a
// string table or a doc, not only in code.
inline bool taskQuotesLiteral( std::string_view task )
{
    if( lit_detail::quotedSpan( task, '"' ) )
    {
        return true;
    }
    const std::optional<std::string_view> span = lit_detail::delimitedSpan( task, '\'' );   // its delimiters included
    return span && lit_detail::quotedSpan( *span, '\'' );
}

// The literals the task names, in the order they are tried: a quoted span (the task's own quoting is the strongest evidence), the
// CONST_SHAPED words, the dotted keys (the one beside a setting cue first), then a message. The caller scans them in order until one
// has a source site (kForLiteralCandidates scans, a message's own tries besides): the first literal with no site no longer hides the next.
inline std::vector<ForLiteral> forLiteralCandidates( std::string_view task )
{
    std::vector<ForLiteral> out;
    if( std::optional<std::string> s = lit_detail::quotedSpan( task, '"' ) )
    {
        out.push_back( ForLiteral{ std::move( *s ), "quoted" } );
    }
    for( std::string& c : constWordsOf( task ) )
    {
        out.push_back( ForLiteral{ std::move( c ), "const" } );
    }
    const std::vector<std::string_view> words = lit_detail::taskWords( task );
    for( std::string& k : lit_detail::dottedKeysOf( words ) )
    {
        out.push_back( ForLiteral{ std::move( k ), "dotted" } );
    }
    std::optional<std::string> m = lit_detail::quotedMessageOf( task );
    if( !m )
    {
        m = lit_detail::bareMessageOf( words );
    }
    if( m )
    {
        out.push_back( ForLiteral{ std::move( *m ), "message" } );
    }
    for( std::string& f : flagNamesOf( task ) )
    {
        out.push_back( ForLiteral{ std::move( f ), "flag" } );   // FLAG-SHAPE-LIT: after every shape that was here before it, the message too, so none of them moves
    }
    for( std::string& f : bareFlagNamesOf( task ) )
    {
        ForLiteral b{ std::move( f ), "flag" };   // WHOLE-TOKEN: after every dashed flag
        b.bare = true;
        out.push_back( std::move( b ) );
    }
    if( !m && lit_detail::isVerbatimMessageTask( words ) )
    {
        ForLiteral v{ std::string( lit_detail::trimAllWs( task ) ), "message" };   // MSG-VERBATIM: last, the whole text, one scan
        v.verbatim = true;
        out.push_back( std::move( v ) );
    }
    for( std::size_t i = 0; i < out.size(); ++i )
    {
        out[i].tryNo = i + 1;
    }
    return out;
}

// shape=table: which trigger a task pulled. AnySite: a registration, table or compile-time word, or "add a new". TableRowOnly: default/handler,
// words of many tasks, so the block prints only when a site reads as a table row. StrongRowOnly (G-STORED-B): no such word at all (a bare subject,
// `new_boxed_executor for HashJoinNode`), so only a STRONG row prints: a registration call (reg=), a top-level macro or call row (tbl="item"), a
// macro-table brace row (a `name! {` / `$macro! {` opener). A dict, list, __all__, #define or const-array row is weak here: counted (weak=), not listed.
enum class TableCue : std::uint8_t
{
    AnySite,
    TableRowOnly,
    StrongRowOnly
};

namespace lit_detail
{
inline constexpr auto kForTableRegistrationCues = std::to_array<std::string_view>(
    { "register", "registers", "registered", "registering", "registration", "registrations", "registry", "registries", "registrar", "registrars", "table", "tables",
      "compile-time" } );
inline constexpr std::array<std::string_view, 4> kForTableValueCues{ "default", "defaults", "handler", "handlers" };
// REGISTRAR-2: where a registered thing is defined, built or handled (`Where is barrier_interval_ms defined`, `How does new_boxed_executor build an
// executor for HashJoinNode`, `where is it handled`), and the two-word forms `turned into`, `get(s) to`: words of many tasks, so like the value cues
// they print only beside a table row or a registration call. Only the words the gold-blind Stage 0 rule fired on (reports/registrar-2.md); no more.
inline constexpr std::array<std::string_view, 6> kForTableSiteCues{ "defined", "declared", "build", "builds", "built", "handled" };
inline constexpr std::array<std::string_view, 3> kForTableExemplarLeads{ "like", "alongside", "following" };

// the task with every backticked span blanked (a cue inside code quotes is code, not the task's word)
inline std::string withoutBackticks( std::string_view task )
{
    std::string out( task );
    bool inside = false;
    for( char& c : out )
    {
        const bool tick = c == '`';
        inside = tick ? !inside : inside;
        c = tick || inside ? ' ' : c;
    }
    return out;
}

// snake_case, camelCase, Pascal with an inner capital, a::b, a.b: a word nobody writes in prose. Allowlist: only these shapes anchor.
inline bool isIdentifierShaped( std::string_view w ) noexcept
{
    if( w.size() < kForTableMinAnchor || std::isalpha( static_cast<unsigned char>( w[0] ) ) == 0 )
    {
        return false;
    }
    bool underscore = false, innerCap = false, lower = false, sep = false;
    for( std::size_t i = 0; i < w.size(); ++i )
    {
        const char c = w[i];
        if( c == '.' || c == ':' )
        {
            if( i == 0 || i + 1 == w.size() || std::isalpha( static_cast<unsigned char>( w[i + 1] ) ) == 0 )
            {
                if( c == ':' && i + 1 < w.size() && w[i + 1] == ':' )
                {
                    continue;
                }
                return false;
            }
            sep = true;
            continue;
        }
        if( !namesplit::isIdentChar( c ) )
        {
            return false;
        }
        underscore = underscore || ( c == '_' && i + 1 < w.size() );
        innerCap   = innerCap || ( i > 0 && std::isupper( static_cast<unsigned char>( c ) ) != 0 && lower );
        lower      = lower || std::islower( static_cast<unsigned char>( c ) ) != 0;
    }
    return lower && ( underscore || innerCap || sep );
}

// a backticked span that can be scanned for: identifier bytes and a few separators, never a flag, a path or a file name
inline bool isTableAnchorSpan( std::string_view w ) noexcept
{
    if( w.size() < kForTableMinAnchor || w.size() > kForTableMaxAnchor || w.front() == '-' )
    {
        return false;
    }
    const bool bytesOk = std::all_of( w.begin(), w.end(), []( char c ) { return namesplit::isIdentChar( c ) || c == '.' || c == ':' || c == '#' || c == '$'; } );
    const std::size_t dot = w.rfind( '.' );
    return bytesOk && ( dot == std::string_view::npos || !isFileOrHostSuffix( w.substr( dot + 1 ) ) );
}

// REGISTRAR-2: words[i] is a site cue: one of kForTableSiteCues (not right after a negation: `is not defined`), or the first word of `turned into` / `get(s) to`
inline bool isSiteCueAt( std::span<const std::string_view> words, std::size_t i )
{
    static constexpr std::array<std::string_view, 1> kTurned{ "turned" }, kInto{ "into" }, kTo{ "to" };
    static constexpr std::array<std::string_view, 2> kGet{ "get", "gets" };
    static constexpr std::array<std::string_view, 6> kNegators{ "not", "never", "isn't", "wasn't", "aren't", "weren't" };
    const std::string_view w    = stripWordPunct( words[i] );
    const std::string_view next = i + 1 < words.size() ? stripWordPunct( words[i + 1] ) : std::string_view();
    // `name x is not defined`, `x was not declared in this scope`: an error message quoting the word, no question about a definition (REG2-FIX1)
    const bool negated = i > 0 && wordIsOneOf( stripWordPunct( words[i - 1] ), std::span<const std::string_view>( kNegators ) );
    return ( wordIsOneOf( w, std::span<const std::string_view>( kForTableSiteCues ) ) && !negated ) || ( wordIsOneOf( w, kTurned ) && wordIsOneOf( next, kInto ) )
           || ( wordIsOneOf( w, kGet ) && wordIsOneOf( next, kTo ) );
}
}   // namespace lit_detail

// the trigger of shape=table, read from the task's own words outside code quotes
inline TableCue forTableCueOf( std::string_view task )
{
    const std::string prose = lit_detail::withoutBackticks( task );
    const std::vector<std::string_view> words = lit_detail::taskWords( prose );
    TableCue cue = TableCue::StrongRowOnly;   // no cue word: the strong rows alone (G-STORED-B)
    std::size_t addAt = SIZE_MAX;
    for( std::size_t i = 0; i < words.size(); ++i )
    {
        const std::string_view w = lit_detail::stripWordPunct( words[i] );
        if( lit_detail::wordIsOneOf( w, std::span<const std::string_view>( lit_detail::kForTableRegistrationCues ) ) )
        {
            return TableCue::AnySite;
        }
        if( i + 1 < words.size() && lit_detail::wordIsOneOf( w, std::array<std::string_view, 1>{ "compile" } )
            && lit_detail::wordIsOneOf( lit_detail::stripWordPunct( words[i + 1] ), std::array<std::string_view, 1>{ "time" } ) )
        {
            return TableCue::AnySite;
        }
        if( lit_detail::wordIsOneOf( w, std::array<std::string_view, 4>{ "add", "adding", "implement", "implementing" } ) )
        {
            addAt = i;
        }
        if( addAt != SIZE_MAX && i <= addAt + 2 && i > addAt && lit_detail::wordIsOneOf( w, std::array<std::string_view, 2>{ "new", "another" } ) )
        {
            return TableCue::AnySite;
        }
        if( lit_detail::wordIsOneOf( w, std::span<const std::string_view>( lit_detail::kForTableValueCues ) ) || lit_detail::isSiteCueAt( words, i ) )
        {
            cue = TableCue::TableRowOnly;
        }
    }
    return cue;
}

// the word after to/into in an add-a-new task names what is added to, not an exemplar of what is added
inline bool addsToTarget( std::span<const std::string_view> words, std::size_t i ) noexcept
{
    static constexpr std::array<std::string_view, 2> kInto{ "to", "into" };
    static constexpr std::array<std::string_view, 4> kAdd{ "add", "adding", "implement", "implementing" };
    return i > 0 && lit_detail::wordIsOneOf( lit_detail::stripWordPunct( words[i - 1] ), std::span<const std::string_view>( kInto ) )
           && std::any_of( words.begin(), words.begin() + std::ptrdiff_t( i ), []( std::string_view w ) { return lit_detail::wordIsOneOf( lit_detail::stripWordPunct( w ), std::span<const std::string_view>( kAdd ) ); } );
}

// one anchor of shape=table, before the index filter. quoted: a backticked span (stands without an index symbol). firm: the task points at it as the
// thing to read (a backticked span, or the sibling after like/alongside/following), so it prints whatever the trigger allows; a bare identifier-shaped
// word, or a backticked span right after `to`/`into` in an add task (the thing changed), prints only beside a real table row.
struct TableAnchor
{
    std::string text;
    bool        quoted = false;
    bool        firm   = false;
};

// the anchors of shape=table, in order, before the index filter
inline std::vector<TableAnchor> forTableAnchorsOf( std::string_view task )
{
    std::vector<TableAnchor> out;
    const auto add = [ & ]( std::string_view w, bool quoted, bool firm )
    {
        if( std::none_of( out.begin(), out.end(), [ & ]( const TableAnchor& a ) { return a.text == w; } ) )
        {
            out.push_back( TableAnchor{ std::string( w ), quoted, firm } );
        }
    };
    for( std::size_t at = task.find( '`' ); at != std::string_view::npos; )
    {
        const std::size_t end = task.find( '`', at + 1 );
        if( end == std::string_view::npos )
        {
            break;
        }
        std::string_view span = task.substr( at + 1, end - at - 1 );
        span = span.ends_with( "()" ) ? span.substr( 0, span.size() - 2 ) : span;
        const std::size_t call = span.rfind( "()." );   // `a.load().b()`: the last link of a call chain is the name
        span = call == std::string_view::npos ? span : span.substr( call + 3 );
        if( lit_detail::isTableAnchorSpan( span ) )
        {
            const std::string before = lit_detail::withoutBackticks( task.substr( 0, at ) );
            const std::vector<std::string_view> beforeWords = lit_detail::taskWords( before );
            add( span, true, !addsToTarget( beforeWords, beforeWords.size() ) );
        }
        at = task.find( '`', end + 1 );
    }
    const std::string prose = lit_detail::withoutBackticks( task );
    const std::vector<std::string_view> words = lit_detail::taskWords( prose );
    for( std::size_t i = 0; i < words.size(); ++i )
    {
        const std::string_view w = lit_detail::stripWordPunct( words[i] );
        const bool afterLead = i > 0 && lit_detail::wordIsOneOf( lit_detail::stripWordPunct( words[i - 1] ), std::span<const std::string_view>( lit_detail::kForTableExemplarLeads ) );
        if( addsToTarget( words, i ) )
        {
            continue;   // `add a new argument to run_it`: the thing changed, no sibling to read
        }
        if( afterLead && w.size() >= kForTableMinAnchor && !lit_detail::wordIsOneOf( w, std::span<const std::string_view>( lit_detail::kForLiteralStopWords ) )
            && std::all_of( w.begin(), w.end(), namesplit::isIdentChar ) )
        {
            add( w, false, true );
        }
        else if( lit_detail::isIdentifierShaped( w ) )
        {
            add( w, false, afterLead );
        }
    }
    return out;
}

struct ForLiteralRender
{
    std::string xml;          // "" = nothing rides
    std::size_t sites = 0;    // src= (source code + string + unclassified sites)
    std::size_t bodies = 0;   // <b>/<x> elements served
    bool        noRoom = false;   // shape=table: sites exist, but not one row fit the bytes left
    bool        unread = false;   // shape=table: a table-rows-only anchor with more sites than are read for a row, none of those read a row: unknown, not "no table"
    bool        cutLegend = false;   // this element carries the lit_cut legend
    bool        tailLegend = false;  // this element carries the tail= legend
    bool        armLegend  = false;  // this element carries the arm= legend
    bool        subLegend  = false;  // this element carries the subscript reg= / lr legend (REG-READER)
};

// LIT-SITE-DECOY: what the ranked answer above the block stands on, read to order the literal's sites by nearness to it
struct LitAnchors
{
    std::span<const NodeId> answer;      // the answer's shown signature rows and the bodies it serves whole
    const Graph*            g = nullptr; // the run's call graph (1-hop nearness); null = no graph reading
};

namespace lit_detail
{
// how near a site stands to the answer's anchors: the answer's source-class rows and the literal's own source definitions
enum class Prox : std::uint8_t
{
    Near = 0,   // in an anchor's file, or its owner is an anchor or calls / is called by one
    Dir  = 1,   // in an anchor's directory
    Far  = 2,   // elsewhere in the product
    Off  = 3    // a vendored, minified or generated copy (isCopyPath)
};

// an anchor called from more functions than this (a generic accessor: getSetting, get) is a hub: calling it puts no site one call from the answer
inline constexpr std::uint32_t kLitHubFanIn = 16;

struct AnchorSet
{
    std::vector<NodeId>           syms;    // sorted, unique
    std::vector<NodeId>           hops;    // syms minus the hubs (kLitHubFanIn): the ones a 1-hop call makes a site near; sorted, unique
    std::vector<std::uint32_t>    files;   // sorted, unique
    std::vector<std::string_view> dirs;    // sorted, unique, root-relative
};

inline void addAnchor( const IngestResult& ing, AnchorSet& a, NodeId id )
{
    if( id < NodeId( ing.symbols.size() ) && subject_detail::sourceClassDef( ing, id ) )
    {
        a.syms.push_back( id );
        a.files.push_back( ing.symbols[id].fileId );
        a.dirs.push_back( siblift_detail::dirOf( rootRelPath( ing, ing.symbols[id].fileId ) ) );
    }
}

// the source-class anchors of `ids` (the answer's, then the literal's definitions); `g` prices the hubs (null: no 1-hop reading at all)
inline AnchorSet anchorSetOf( const IngestResult& ing, std::span<const NodeId> ids, const Graph* g )
{
    AnchorSet a;
    for( const NodeId id : ids )
    {
        addAnchor( ing, a, id );
    }
    const auto dedup = []( auto& v )
    {
        std::ranges::sort( v );
        v.erase( std::ranges::unique( v ).begin(), v.end() );
    };
    dedup( a.syms );
    dedup( a.files );
    std::ranges::sort( a.dirs, sortutil::svLess );   // portablebuildcheck #6b: never the default sv comparator
    a.dirs.erase( std::ranges::unique( a.dirs ).begin(), a.dirs.end() );
    const auto* ro = g != nullptr ? g->inEdges.rowOffsets() : nullptr;
    for( const NodeId s : a.syms )
    {
        if( ro != nullptr && std::size_t( s ) < ing.symbols.size() && ro[s + 1] - ro[s] <= kLitHubFanIn )
        {
            a.hops.push_back( s );
        }
    }
    return a;
}

// the literal's own source definitions: the symbols named its last segment, placed by the segments before it (mention_detail::qualifierPlaces:
// the scope, the file stem or the directory names the qualifier or its last segment). `SyntaxKind.SatisfiesExpression` is the enum member's; a
// generic tail alone (`enabled` of `feature.cache.enabled`, `autoSave` of `files.autoSave`) anchors nothing. A literal with no separator is
// the name itself.
inline std::vector<NodeId> literalDefsOf( const IngestResult& ing, std::string_view literal )
{
    const std::size_t      sep   = literal.find_last_of( ".:#" );
    const std::string_view tail  = sep == std::string_view::npos ? literal : literal.substr( sep + 1 );
    std::string_view       qual  = sep == std::string_view::npos ? std::string_view() : literal.substr( 0, sep );
    while( !qual.empty() && ( qual.back() == ':' || qual.back() == '.' || qual.back() == '#' ) )
    {
        qual.remove_suffix( 1 );   // `a::b`: the qualifier is `a`
    }
    const std::size_t      qsep  = qual.find_last_of( ".:#" );
    const std::string_view qlast = qsep == std::string_view::npos ? qual : qual.substr( qsep + 1 );
    std::vector<NodeId>    out;
    for( NodeId id = 0; id < NodeId( ing.symbols.size() ) && !tail.empty(); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( s.name == tail && ( sep == std::string_view::npos || ( !qual.empty() && ( mention_detail::qualifierPlaces( ing, s, qual ) || mention_detail::qualifierPlaces( ing, s, qlast ) ) ) ) )
        {
            out.push_back( id );
        }
    }
    return out;
}

// `from` calls `to` on the graph (outTargets is ascending within a source)
inline bool callsOnGraph( const Graph& g, NodeId from, NodeId to ) noexcept
{
    if( std::size_t( from ) + 1 >= g.outOff.size() )
    {
        return false;
    }
    const auto b = g.outTargets.begin() + g.outOff[from];
    const auto e = g.outTargets.begin() + g.outOff[from + 1];
    return std::binary_search( b, e, to );
}

// a copy, not authored code: a vendoring directory, a minified file or directory, a generated loader (Yarn's PnP and releases). An authored
// static/ or locale/ file (Django's admin JS, conf/locale/*/formats.py) is product code, so the wider demo/generated tier is not read here.
inline bool isCopyPath( std::string_view p ) noexcept
{
    const std::string_view base = mention_detail::baseNameOf( p );
    if( base.find( ".min." ) != std::string_view::npos || hasDirSegment( p, "min/" ) || hasDirSegment( p, ".yarn/releases/" ) || isYarnPnpFileName( base ) )
    {
        return true;
    }
    for( std::size_t start = 0, slash = p.find( '/' ); slash != std::string_view::npos; start = slash + 1, slash = p.find( '/', start ) )
    {
        const std::string_view dir = p.substr( start, slash - start );
        if( dir == "vendor" || dir == "third_party" || dir == "node_modules" || dir == "bower_components" )
        {
            return true;
        }
    }
    return false;
}

inline Prox proxOf( const IngestResult& ing, const AnchorSet& a, const Graph* g, std::uint32_t fileId, NodeId owner )
{
    const std::string_view p = rootRelPath( ing, fileId );
    if( isCopyPath( p ) )
    {
        return Prox::Off;
    }
    if( std::binary_search( a.files.begin(), a.files.end(), fileId ) || ( owner != kNoNode && std::binary_search( a.syms.begin(), a.syms.end(), owner ) ) )
    {
        return Prox::Near;
    }
    if( owner != kNoNode && g != nullptr
        && std::any_of( a.hops.begin(), a.hops.end(), [ & ]( NodeId s ) { return callsOnGraph( *g, owner, s ) || callsOnGraph( *g, s, owner ); } ) )
    {
        return Prox::Near;
    }
    return std::binary_search( a.dirs.begin(), a.dirs.end(), siblift_detail::dirOf( p ), sortutil::svLess ) ? Prox::Dir : Prox::Far;
}

struct Site
{
    GrepRawHit raw;
    char       k = '?';   // 's' string, 'c' code, '?' unclassified
    bool       quotedKey = false;   // shape=dotted: quotes delimit the key on both sides (`'files.autoSave'`), not a mention inside a sentence
    std::string tbl;                // shape=table: the line that opens the table this site is a row of ("item" at top level); "" = not a table row
    bool        longer = false;     // shape=table: the hit sits inside a longer name; a row only as a registration call's argument (registrationCallOf)
    bool        regCall = false;    // shape=table: tbl holds a registration call's callee (registrationCallOf), printed as reg=, not as a table opener
    bool        regDirect = false;  // regCall: the site is a direct argument of that call (registrationCallOf's direct), no inner call, index or object between
    bool        itemNested = false; // tbl="item" (a top-level call row) whose hit is NOT a direct argument of a registration call on it (`register(wrap(x))`): not strong
    bool        subscript = false;  // REG-READER (a): regCall from a subscript write with a computed key (`storage[resource+"/log"] = x`) in a New*/Register* function
    bool        leadInString = false;   // k='s' and the line's first non-blank byte is in a string too: a line of a multi-line string, no statement of its own
    std::string table;              // subscript: the table written (`storage`, `hass.data[DOMAIN]`), the text before its last `[`
    std::vector<std::uint32_t> more;   // shape=table: the byte offsets of the later hits on this line (the first is raw.byteOffset), at most kForRegLineHits
};

// LIT-SITE-DECOY: the sort tier of each ranked site (0 a near or kept table row, 1 another table row, 2 a near site, 3 a far one) or kCutTier
// (not a row), and how many are cut
inline constexpr std::uint8_t kCutTier = 255;
struct SiteCut
{
    std::vector<std::uint8_t> tier;
    std::size_t               count = 0;
};

// an X-macro list (`#define COMMON_SETTINGS(DECLARE) \`) declares the names it holds; a map, set or array initializer maps or lists them
inline bool declaresTable( std::string_view opener ) noexcept
{
    return lintdetail::ltrim( opener ).starts_with( "#define" );
}

// REGISTRAR-2: a generated or data file (filter.h isDemoOrGeneratedPath, a `.json` file, a `zz_generated`, `_generated.`, `.generated.` or `.pb.`
// file name): its table rows rank after the source's, as a docs or examples path does (isSecondaryPath). Ranked last, never dropped.
inline bool isGeneratedOrDataPath( std::string_view p ) noexcept
{
    const std::size_t      slash = p.rfind( '/' );
    const std::string_view base  = slash == std::string_view::npos ? p : p.substr( slash + 1 );
    return isDemoOrGeneratedPath( p ) || base.ends_with( ".json" ) || base.starts_with( "zz_generated" ) || base.find( "_generated." ) != std::string_view::npos
           || base.find( ".generated." ) != std::string_view::npos || base.find( ".pb." ) != std::string_view::npos;
}

// the home table, when several table files hold the literal and none of their rows stands near the answer: the file with the most table rows of
// the literal; on a tie, the one that declares it (declaresTable); then the one with the most of its sites outside any function (the declaration
// text: doc strings, a registration; a reader in a function body does not count). A tie past these: no home (nothing is cut by it). A generated or
// data file (isGeneratedOrDataPath) holds no home.
inline std::uint32_t homeTableFile( const IngestResult& ing, const std::vector<Site>& rows, const std::vector<GrepHit>& enriched, const std::vector<Prox>& prox )
{
    struct Cand
    {
        std::uint32_t file = 0;
        std::size_t   tableRows = 0, declares = 0, outside = 0;
        auto key() const { return std::tuple{ tableRows, declares, outside }; }
    };
    std::vector<Cand> cands;
    for( std::size_t i = 0; i < enriched.size(); ++i )
    {
        if( rows[i].tbl.empty() || prox[i] == Prox::Off || isGeneratedOrDataPath( rootRelPath( ing, rows[i].raw.fileId ) ) )
        {
            continue;   // a generated or data file is never the home table (REG2-FIX1, CodeRabbit 4478248365): its rows only rank after the source's
        }
        const auto at = std::ranges::find( cands, rows[i].raw.fileId, &Cand::file );
        Cand& c = at != cands.end() ? *at : cands.emplace_back( Cand{ rows[i].raw.fileId } );
        ++c.tableRows;
        c.declares = std::max<std::size_t>( c.declares, declaresTable( rows[i].tbl ) ? 1 : 0 );
    }
    if( cands.size() < 2 )
    {
        return UINT32_MAX;
    }
    for( std::size_t i = 0; i < enriched.size(); ++i )
    {
        const NodeId o = enriched[i].enclosingId;
        const auto at  = std::ranges::find( cands, rows[i].raw.fileId, &Cand::file );
        if( at != cands.end() && ( o == kNoNode || !ReceiverEvidence::callableKind( ing.symbols[o].kind ) ) )
        {
            ++at->outside;
        }
    }
    std::ranges::sort( cands, []( const Cand& a, const Cand& b ) { return a.key() > b.key(); } );
    return cands[0].key() == cands[1].key() ? UINT32_MAX : cands[0].file;
}

// the answer's ids that anchor. More than half of its source-class rows own a site of the literal: the answer is mostly the literal's own readers
// (a body match), so those readers say nothing about where it belongs and do not anchor (their files, directories and calls would make every
// reader near); its other rows and the literal's own definitions still do. A minority of readers (ts-09: 15 of 40 rows) anchors as before.
inline std::vector<NodeId> answerAnchorsOf( const IngestResult& ing, std::span<const NodeId> answer, const std::vector<GrepHit>& enriched )
{
    std::vector<NodeId> readers;
    for( const GrepHit& h : enriched )
    {
        readers.push_back( h.enclosingId );
    }
    std::ranges::sort( readers );
    const auto isReader = [ & ]( NodeId id )
    {
        return id < NodeId( ing.symbols.size() ) && subject_detail::sourceClassDef( ing, id ) && std::ranges::binary_search( readers, id );
    };
    std::vector<NodeId> out( answer.begin(), answer.end() );
    const auto sourceRows = std::ranges::count_if( out, [ & ]( NodeId id ) { return id < NodeId( ing.symbols.size() ) && subject_detail::sourceClassDef( ing, id ); } );
    if( std::ranges::count_if( out, isReader ) * 2 > sourceRows )
    {
        std::erase_if( out, isReader );
    }
    return out;
}

// `rows[i]` pairs with `enriched[i]` (the ranked window); `reserved[i]` != 0: a registration the reserve keeps (pickRows), never cut. `capped`:
// the sites do not all fit the rows, so some are cut, not only ordered. Cuts, only when capped: (1) a vendored, minified or generated copy
// (Prox::Off) when a product site exists; (2) the far sites when some site stands near the answer (file, directory or one call); (3) the table
// rows not near it when a table row stands near it (same file or one call: a table in its directory does not cut the others), or, with none
// near and several tables, the far rows outside the home table file (homeTableFile). An uncapped block is only reordered (copies last).
inline SiteCut cutSites( const IngestResult& ing, const LitAnchors& anchors, std::string_view literal, const std::vector<Site>& rows,
                         const std::vector<GrepHit>& enriched, std::span<const char> reserved, bool tableRows, bool capped )
{
    SiteCut out;
    out.tier.assign( enriched.size(), 1 );
    std::vector<NodeId> ids = answerAnchorsOf( ing, anchors.answer, enriched );
    const std::vector<NodeId> defs = literalDefsOf( ing, literal );
    ids.insert( ids.end(), defs.begin(), defs.end() );
    const AnchorSet set = anchorSetOf( ing, ids, anchors.g );
    std::vector<Prox> prox( enriched.size() );
    bool anyProduct = false, anyNear = false, anyNearTable = false;   // anyNear: a site that is no table row
    for( std::size_t i = 0; i < enriched.size(); ++i )
    {
        prox[i]      = proxOf( ing, set, anchors.g, rows[i].raw.fileId, enriched[i].enclosingId );
        anyProduct   = anyProduct || prox[i] != Prox::Off;
        anyNear      = anyNear || ( ( prox[i] == Prox::Near || prox[i] == Prox::Dir ) && rows[i].tbl.empty() );
        anyNearTable = anyNearTable || ( prox[i] == Prox::Near && !rows[i].tbl.empty() );
    }
    const std::uint32_t homeFile = tableRows && capped && !anyNearTable ? homeTableFile( ing, rows, enriched, prox ) : UINT32_MAX;
    const bool          cutFar   = capped && ( anyNear || anyNearTable );   // something stands near the answer: the far sites are cut, not only ordered
    for( std::size_t i = 0; i < enriched.size(); ++i )
    {
        const bool table    = !rows[i].tbl.empty();
        const bool near     = prox[i] == Prox::Near || prox[i] == Prox::Dir;
        const bool cutTable = table && ( anyNearTable ? prox[i] != Prox::Near : ( homeFile != UINT32_MAX && rows[i].raw.fileId != homeFile && !near ) );
        if( capped && ( i >= reserved.size() || reserved[i] == 0 ) && ( ( prox[i] == Prox::Off && anyProduct ) || cutTable || ( !table && cutFar && !near ) ) )
        {
            out.tier[i] = kCutTier;
            ++out.count;
            continue;
        }
        out.tier[i] = std::uint8_t( ( table ? 0 : 2 ) + ( near ? 0 : 1 ) );   // table rows first, near before far in each
    }
    return out;
}

// shape=dotted: where a hit of a key of `n` bytes at `at` of `text` stands. longer: inside a longer name or a child key (an identifier byte
// on either side, or `.` plus an identifier byte after it); `config.a.b` keeps a.b whole, a prefix is how a context key spells it.
struct KeyHit
{
    bool longer = false;
    bool quoted = false;
};
// the byte before `at` is the LETTER OF AN ESCAPE or of a printf conversion, not a letter of the text: `\n`, `\t`, `\0` (an odd run of
// backslashes before it: `\\n` is a backslash and a real n) or `%s`, `%d`, `%5.2f`, `%ld` (an odd run of `%` before the flags, width and
// length modifiers). The message or key begins right after it: `"\nFailed to get document"`.
inline bool afterEscapeOrVerb( std::string_view text, std::size_t at ) noexcept
{
    if( at < 2 || at > text.size() )
    {
        return false;
    }
    std::size_t slashes = 0;
    for( std::size_t i = at - 1; i > 0 && text[i - 1] == '\\'; --i )
    {
        ++slashes;
    }
    if( slashes % 2 == 1 )
    {
        return true;
    }
    constexpr std::string_view kVerbs = "diouxXeEfFgGaAcspnvTtqb", kMods = "0123456789.+-# *lhzjtLq";
    if( kVerbs.find( text[at - 1] ) == std::string_view::npos )
    {
        return false;
    }
    std::size_t i = at - 1;
    for( std::size_t steps = 0; i > 0 && steps < 8 && kMods.find( text[i - 1] ) != std::string_view::npos; --i, ++steps )
    {
    }
    std::size_t percents = 0;
    for( ; i > 0 && text[i - 1] == '%'; --i )
    {
        ++percents;
    }
    return percents % 2 == 1;
}

inline KeyHit keyHitAt( std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    const auto ident = []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) != 0 || c == '_' || c == '-'; };
    const auto quote = []( char c ) { return c == '"' || c == '\'' || c == '`'; };
    const char before = at > 0 && at <= text.size() ? text[at - 1] : ' ';   // a file that shrank since the scan: unknown, not out of range
    const char after  = at + n < text.size() ? text[at + n] : ' ';
    const char after2 = at + n + 1 < text.size() ? text[at + n + 1] : ' ';
    // an identifier byte before the key joins it to a longer name, except the letter of an escape (`"\nsvc.x.y"`) and a leading `--` (a
    // flag spelled with the key): a `-` joins only behind an identifier byte (`a-svc.x.y`)
    const bool joinsBefore = ident( before ) && !afterEscapeOrVerb( text, at )
                             && !( before == '-' && !( at >= 2 && ident( text[at - 2] ) && text[at - 2] != '-' ) );
    return KeyHit{ joinsBefore || ident( after ) || ( after == '.' && ident( after2 ) ), quote( before ) && quote( after ) };
}

// shape=message: the hit stands on word edges (`this field is` inside `this field isn't` does not). An edge byte that is not a letter,
// digit or `_` (a message that ends in a punctuation mark) needs no check; the letter of an escape or a printf verb before the hit is
// no word byte (afterEscapeOrVerb).
inline bool wordBounded( std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    const auto word = []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) != 0 || c == '_'; };
    if( n == 0 || at + n > text.size() )
    {
        return true;   // a file that changed since the scan: unknown, kept
    }
    return !( word( text[at] ) && at > 0 && word( text[at - 1] ) && !afterEscapeOrVerb( text, at ) )
           && !( word( text[at + n - 1] ) && at + n < text.size() && word( text[at + n] ) );
}

// a row's line cut to `cap` bytes; when the literal sits past the cap the row opens `kForLiteralKeyLead` bytes before it (an ellipsis
// marks the cut), so the row shows what it matched
inline void cutAround( std::string& line, std::string_view needle, std::size_t cap )
{
    const std::size_t at = needle.empty() ? 0 : line.find( needle );
    if( at != std::string::npos && at + needle.size() > cap )
    {
        std::size_t from = at > kForLiteralKeyLead ? at - kForLiteralKeyLead : 0;
        while( from < line.size() && ( static_cast<unsigned char>( line[from] ) & 0xC0 ) == 0x80 )
        {
            ++from;
        }
        line = "\xE2\x80\xA6" + line.substr( from );
    }
    truncateUtf8WithEllipsis( line, cap );
}

// the rows to show, as positions in the rank order: the first `cap`, except that rows `reg` marks (2 = a registration: a quoted key outside
// any function that is itself a property key, 1 = another quoted site outside any function) from past the cap replace the lowest-ranked
// rows of a lower mark until `reserve` rows of that mark or higher are shown, property keys first; ascending, so the rank order is kept
inline std::vector<std::size_t> pickRows( const std::vector<char>& reg, std::size_t cap, std::size_t reserve )
{
    std::vector<std::size_t> pick;
    for( std::size_t i = 0; i < reg.size() && i < cap; ++i )
    {
        pick.push_back( i );
    }
    for( char level = 2; level >= 1; --level )
    {
        std::size_t have = std::size_t( std::count_if( pick.begin(), pick.end(), [ & ]( std::size_t i ) { return reg[i] >= level; } ) );
        for( std::size_t p = cap; p < reg.size() && have < reserve; ++p )
        {
            if( reg[p] != level )
            {
                continue;
            }
            std::size_t q = pick.size();
            while( q > 0 && reg[pick[q - 1]] >= level )
            {
                --q;
            }
            if( q == 0 )
            {
                break;   // every shown row is as much a registration already
            }
            pick.erase( pick.begin() + std::ptrdiff_t( q - 1 ) );
            pick.push_back( p );
            ++have;
        }
    }
    std::sort( pick.begin(), pick.end() );
    return pick;
}

// FLAG-SHAPE-LIT: the `(` of the call whose argument list holds the quoted name at `at`: scanned back from the name's own opening quote and dashes,
// over its line and at most kForRegCallBytes bytes, past the strings and groups it meets. npos when a `[` or `{` opens first or no `(` does.
inline std::size_t openParenBefore( std::string_view text, std::size_t at ) noexcept
{
    if( at > text.size() )
    {
        return std::string_view::npos;
    }
    const std::size_t nl = at == 0 ? std::string_view::npos : text.rfind( '\n', at - 1 );
    const std::size_t ls = nl == std::string_view::npos ? 0 : nl + 1;
    std::size_t from = at;   // the scan back starts before the name's own opening quote and dashes
    while( from > ls && text[from - 1] == '-' )
    {
        --from;
    }
    from -= from > ls && ( text[from - 1] == '"' || text[from - 1] == '\'' || text[from - 1] == '`' ) ? 1 : 0;
    const std::size_t stop = std::max( ls, from > kForRegCallBytes ? from - kForRegCallBytes : std::size_t( 0 ) );
    int  depth = 0;
    char quote = 0;
    for( std::size_t i = from; i-- > stop; )
    {
        const char c = text[i];
        if( quote != 0 )
        {
            quote = c == quote ? 0 : quote;
        }
        else if( c == '"' || c == '\'' || c == '`' )
        {
            quote = c;
        }
        else if( c == ')' || c == ']' || c == '}' )
        {
            ++depth;
        }
        else if( ( c == '(' || c == '[' || c == '{' ) && depth-- == 0 )
        {
            return c == '(' ? i : std::string_view::npos;
        }
    }
    return std::string_view::npos;
}

// the identifier run right before the `(` at `open`: the call's callee (`StringVarP`, `add_argument`; a qualifier before a `.` or `::` is not part of it)
inline std::string_view calleeBefore( std::string_view text, std::size_t open ) noexcept
{
    std::size_t end = open;
    while( end > 0 && ( text[end - 1] == ' ' || text[end - 1] == '\t' ) )
    {
        --end;   // `quiet ("q", ...)`: blanks between the callee and its `(`
    }
    const auto stop = std::find_if_not( std::make_reverse_iterator( text.begin() + std::ptrdiff_t( end ) ), std::make_reverse_iterator( text.begin() ), namesplit::isIdentChar );
    const std::size_t from = std::size_t( stop.base() - text.begin() );
    return text.substr( from, end - from );
}

// C++ TCLAP: the call at `open` constructs a command-line argument object, `ValueArg<uint32_t> concurrency(...)`, `SwitchArg quiet(...)`: the type
// before the object's name ends the line's text up to it with `Arg` or `Arg<...>`
inline bool constructsArgObject( std::string_view text, std::size_t open ) noexcept
{
    const std::size_t      calleeAt = std::size_t( calleeBefore( text, open ).data() - text.data() );
    const std::size_t      nl       = calleeAt == 0 ? std::string_view::npos : text.rfind( '\n', calleeAt - 1 );
    const std::size_t      ls       = nl == std::string_view::npos ? 0 : nl + 1;
    std::string_view       head     = text.substr( ls, calleeAt - ls );
    while( !head.empty() && ( head.back() == ' ' || head.back() == '\t' ) )
    {
        head.remove_suffix( 1 );
    }
    return head.ends_with( "Arg" ) || ( head.ends_with( '>' ) && head.rfind( "Arg<" ) != std::string_view::npos );
}

// What a callee says about a flag's default (FLAG-SHAPE-LIT; the library's own default slot, never a guess from position):
enum class FlagSlot : std::uint8_t
{
    Absent,          // not a flag-definition call (exec.Command, a lookup, a dict, a message)
    NoDefault,       // one, with no positional default: pflag Count/Var/Func, clap `.long(`, nushell `.named(`; a default= keyword may still stand
    AfterName,       // Go flag, pflag, cobra: `String("name", def, usage)`, `StringVar(&v, "name", def, usage)`
    AfterShorthand   // pflag's `P` form: `StringP("name", "n", def, usage)`, `StringVarP(&v, "name", "n", def, usage)`
};
inline FlagSlot flagSlotOf( std::string_view callee ) noexcept
{
    static constexpr auto kTyped = std::to_array<std::string_view>(
        { "String", "Bool", "Int", "Int8", "Int16", "Int32", "Int64", "Uint", "Uint8", "Uint16", "Uint32", "Uint64", "Float32", "Float64", "Duration",
          "StringSlice", "StringArray", "IntSlice", "Int32Slice", "Int64Slice", "UintSlice", "Float32Slice", "Float64Slice", "BoolSlice", "DurationSlice",
          "BytesHex", "BytesBase64", "IP", "IPSlice", "IPMask", "IPNet", "StringToString", "StringToInt", "StringToInt64" } );
    static constexpr auto kBare = std::to_array<std::string_view>(
        { "Count", "CountP", "CountVar", "CountVarP", "Func", "FuncP", "BoolFunc", "BoolFuncP", "Var", "VarP", "long", "named", "switch", "flag", "Flag", "add_flag", "add_option" } );
    const auto typed = [ & ]( std::string_view n )
    {
        n = n.ends_with( "Var" ) ? n.substr( 0, n.size() - 3 ) : n;
        return std::find( kTyped.begin(), kTyped.end(), n ) != kTyped.end();
    };
    if( callee.ends_with( 'P' ) && typed( callee.substr( 0, callee.size() - 1 ) ) )
    {
        return FlagSlot::AfterShorthand;
    }
    if( typed( callee ) )
    {
        return FlagSlot::AfterName;
    }
    return std::find( kBare.begin(), kBare.end(), callee ) != kBare.end() ? FlagSlot::NoDefault : FlagSlot::Absent;
}

// FLAG-SHAPE-LIT: the 0-based index of the top-level argument of the call opened at `open` that holds `at` (commas outside strings and groups between them)
inline std::size_t argIndexAt( std::string_view text, std::size_t open, std::size_t at ) noexcept
{
    std::size_t index = 0;
    int         depth = 0;
    char        quote = 0;
    for( std::size_t i = open + 1; i < at && i < text.size(); ++i )
    {
        const char c = text[i];
        if( quote != 0 )
        {
            i += c == '\\' ? 1 : 0;
            quote = c == quote ? 0 : quote;
        }
        else if( c == '"' || c == '\'' || c == '`' )
        {
            quote = c;
        }
        else if( c == '(' || c == '[' || c == '{' )
        {
            ++depth;
        }
        else if( c == ')' || c == ']' || c == '}' )
        {
            --depth;
        }
        else if( c == ',' && depth == 0 )
        {
            ++index;
        }
    }
    return index;
}

// FLAG-SHAPE-LIT: the hit at `at` stands in the NAME argument of the flag-definition call opened at `open`, not in its default or usage string
// (`fs.String("backendmode", "cachemode", "Backend mode")` has no `cachemode` flag): the first argument, or the second when the first is the variable the flag binds
// (`StringVar(&v, "name", ...)`, `VarP`, `CountVar`); a TCLAP argument object's constructor takes (short, long, ...), so either of its first two
inline bool holdsFlagName( std::string_view text, std::size_t open, std::size_t at ) noexcept
{
    const std::string_view callee    = calleeBefore( text, open );
    const std::size_t      index     = argIndexAt( text, open, at );
    const std::size_t      nameIndex = callee.ends_with( "Var" ) || callee.ends_with( "VarP" ) ? 1 : 0;
    return flagSlotOf( callee ) != FlagSlot::Absent ? index == nameIndex : ( constructsArgObject( text, open ) && index <= 1 );
}

// FLAG-SHAPE-LIT: the hit at `at` of `text` is the whole quoted flag name: a quote before it (after an optional `-` or `--`) and the same quote,
// or a `=` (`"--workers=4"`), right after it. `"max-pods-per-core"` and `use --max-pods to cap` are mentions, not sites. A name with no inner hyphen
// is a common word (`compress`, `cache`): it is a site only in its dashed form (`"--compress"`) or as a flag-definition call's argument
// (flagSlotOf, or a TCLAP argument object's constructor), never a dict value, an `__all__` entry or an error message.
inline bool flagHitAt( std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    if( at == 0 || at > text.size() || n > text.size() - at )
    {
        return false;
    }
    std::size_t b = at;
    for( int dashes = 0; dashes < 2 && b > 0 && text[b - 1] == '-'; ++dashes )
    {
        --b;
    }
    if( b == 0 || ( text[b - 1] != '"' && text[b - 1] != '\'' && text[b - 1] != '`' ) )
    {
        return false;
    }
    const char q = text[b - 1];
    if( at + n >= text.size() || ( text[at + n] != q && text[at + n] != '=' ) )
    {
        return false;
    }
    if( b < at || text.substr( at, n ).find( '-' ) != std::string_view::npos )
    {
        return true;   // dashed, or a kebab name (an inner hyphen discriminates on its own)
    }
    const std::size_t open = openParenBefore( text, at );
    return open != std::string_view::npos && holdsFlagName( text, open, at );
}

// How a shape of <lit> reads its sites: one row of this table per shape, so a new shape is a new row, never a new bool through renderForLiteral.
enum class LitBoundary : std::uint8_t
{
    None,   // shape=quoted|const: every byte-exact hit is a site
    Key,    // shape=dotted: keyHitAt, a hit inside a longer name or a child key is `longer`, quotes around the key rank it
    Word,   // shape=message: wordBounded, a hit inside a longer word is `longer`
    Flag    // shape=flag: a site is the whole quoted string, `--` allowed before it (`"max-pods"`, `"--workers"`); any other hit is a mention
};
struct LitPolicy
{
    LitBoundary      boundary = LitBoundary::None;
    bool             dropCode = false;   // a code row is never printed (the task's words met outside a string are no message)
    std::size_t      rows     = kForLiteralSiteRows;
    std::size_t      reserve  = 0;       // row slots kept for a registration (pickRows)
    std::string_view legend;             // the clause this shape adds to the base legend; "" = none
    bool             tableRows    = false;   // sites are read for a table row (tableRowOf), which rank first and carry tbl=
    std::size_t      contextRows  = kForLiteralContextRows;
    std::size_t      rankedRows   = kForLiteralRankedRows;
};
inline LitPolicy litPolicyOf( std::string_view shape ) noexcept
{
    if( shape == "dotted" )
    {
        return LitPolicy{ LitBoundary::Key, false, kForLiteralSiteRows, kForLiteralRegistrationRows, kForLiteralKeyLegend };
    }
    if( shape == "message" )
    {
        return LitPolicy{ LitBoundary::Word, true, kForLiteralSiteRows, 0, kForLiteralKeyLegend };
    }
    if( shape == "table" )
    {
        return LitPolicy{ LitBoundary::Word, false, kForTableRows, 0, kForLiteralTableLegend, true, kForTableContextRows, kForTableRankedRows };
    }
    if( shape == "flag" )
    {
        return LitPolicy{ LitBoundary::Flag, false, kForLiteralSiteRows, 0, kForLiteralFlagLegend };
    }
    return LitPolicy{};
}

// where a hit of the literal at `at` of `text` stands, by the shape's boundary rule
inline KeyHit literalHitAt( LitBoundary boundary, std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    if( boundary == LitBoundary::Key )
    {
        return keyHitAt( text, at, n );
    }
    if( boundary == LitBoundary::Flag )
    {
        return KeyHit{ false, flagHitAt( text, at, n ) };
    }
    KeyHit h;
    h.longer = boundary == LitBoundary::Word && !wordBounded( text, at, n );
    h.quoted = boundary == LitBoundary::Word && keyHitAt( text, at, n ).quoted;   // shape=table's dotted-tail retry lists quoted keys only
    return h;
}

// shape=table: what a source line looks like as a row of a table. Allowlist: a line of none of these shapes is never a table row.
enum class RowKind : std::uint8_t
{
    None,
    Call,    // `DECLARE(MaxThreads, max_threads, ...`, `impl_stream_node_body!(HashJoin(HashJoinNode) => ...);`, `Register("k", f);`
    Key,     // `"abspath": funcs.AbsPathFunc,`, `InPlacePodVerticalScaling: {`, `"k" => v,`
    Member,  // `Each,`  `Each, Filter,`  `"a",`
    Brace    // `{ barrier_interval_ms, u32, ...`  `("k", f),`  `["k", 1],`  `Row { key: a, n: 1 },`
};
struct RowShape
{
    RowKind          kind = RowKind::None;
    std::string_view head;   // RowKind::Call: the callee, so two calls of one callee are siblings and two different ones are not
};
inline constexpr auto kForTableNotCallee = std::to_array<std::string_view>(
    { "if", "for", "while", "switch", "catch", "return", "sizeof", "assert", "elif", "match", "def", "func", "fn", "function", "class", "struct", "print", "println" } );

inline RowShape rowShapeOf( std::string_view line )
{
    std::string_view t = trimWs( line );
    if( t.empty() )
    {
        return {};
    }
    if( t.front() == '{' || t.front() == '(' || t.front() == '[' )
    {
        const std::string_view in = trimWs( t.substr( 1 ) );
        return !in.empty() && ( namesplit::isIdentChar( in.front() ) || in.front() == '"' ) ? RowShape{ RowKind::Brace, {} } : RowShape{};
    }
    std::size_t keyEnd = 0;
    if( t.front() == '"' || t.front() == '\'' )
    {
        const std::size_t close = t.find( t.front(), 1 );
        if( close == std::string_view::npos )
        {
            return {};
        }
        keyEnd = close + 1;
    }
    else
    {
        keyEnd = taskroute::identifierRunOf( t ).size();
        if( keyEnd == 0 )
        {
            return {};
        }
        const std::size_t bang = keyEnd < t.size() && t[keyEnd] == '!' ? keyEnd + 1 : keyEnd;
        if( bang < t.size() && t[bang] == '(' )
        {
            const std::string_view callee = t.substr( 0, keyEnd );
            return wordIsOneOf( callee, kForTableNotCallee ) ? RowShape{} : RowShape{ RowKind::Call, t.substr( 0, bang ) };
        }
    }
    const std::string_view rest = trimWs( t.substr( keyEnd ) );
    if( rest.empty() || rest.front() == ',' )
    {
        // a member: nothing but bare words and commas on the line, and it ends in a comma or stands alone in a list
        const bool plain = std::all_of( t.begin(), t.end(), []( char c ) { return namesplit::isIdentChar( c ) || c == ',' || c == ' ' || c == '"' || c == '\''; } );
        return plain && t.back() == ',' ? RowShape{ RowKind::Member, {} } : RowShape{};
    }
    if( ( rest.front() == ':' && !rest.starts_with( "::" ) && !rest.starts_with( ":=" ) ) || rest.starts_with( "=>" ) )
    {
        return RowShape{ RowKind::Key, {} };
    }
    return rest.front() == '{' && rest.size() > 1 ? RowShape{ RowKind::Brace, {} } : RowShape{};   // `Row { key: a, n: 1 },`
}

// the line at `start` of `text`, and the start of the next one
inline std::string_view lineAt( std::string_view text, std::size_t start ) noexcept
{
    const std::size_t end = text.find( '\n', start );
    return text.substr( start, end == std::string_view::npos ? std::string_view::npos : end - start );
}

// the nearest line at this indent, walking one way, that is not a closer; `down` next line, else the previous one. A line less indented ends the walk unless `crossLess`.
inline std::optional<std::string_view> siblingLine( std::string_view text, std::size_t rowStart, std::size_t indent, bool down, bool crossLess ) noexcept
{
    std::size_t pos = rowStart;
    for( std::size_t step = 0; step < kForTableSiblingLines; ++step )
    {
        if( down )
        {
            const std::size_t nl = text.find( '\n', pos );
            if( nl == std::string_view::npos || nl + 1 >= text.size() )
            {
                return std::nullopt;
            }
            pos = nl + 1;
        }
        else
        {
            if( pos == 0 )
            {
                return std::nullopt;
            }
            const std::size_t nl = pos >= 2 ? text.rfind( '\n', pos - 2 ) : std::string_view::npos;
            pos = nl == std::string_view::npos ? 0 : nl + 1;
        }
        const std::string_view l = lineAt( text, pos );
        const std::string_view t = trimWs( l );
        if( t.empty() )
        {
            continue;
        }
        const std::size_t in = lintdetail::indentOf( l );
        if( in < indent && !crossLess )
        {
            return std::nullopt;
        }
        if( in == indent && t.front() != '}' && t.front() != ')' && t.front() != ']' )
        {
            return l;
        }
    }
    return std::nullopt;
}

// an opener line's code: trimmed, a trailing comment (` // aws`, ` # aws`, ` #aws`, ` /* aws */`, outside double quotes) and a macro's continuation backslash off
inline std::string_view openerCode( std::string_view line ) noexcept
{
    std::string_view t = trimWs( line );
    bool quoted = false;
    for( std::size_t i = 0; i < t.size(); ++i )
    {
        quoted = t[i] == '"' ? !quoted : quoted;
        const bool hash = t[i] == '#' && i + 1 < t.size() && t[i + 1] != '[' && t[i + 1] != '!';
        if( !quoted && i > 0 && ( t[i - 1] == ' ' || t[i - 1] == '\t' ) && ( t.substr( i, 2 ) == "//" || t.substr( i, 2 ) == "/*" || hash ) )
        {
            t = trimWs( t.substr( 0, i ) );
            break;
        }
    }
    return t.ends_with( '\\' ) ? trimWs( t.substr( 0, t.size() - 1 ) ) : t;
}

// a call whose result is plainly its data, opened on the line: `Object.freeze({`, `new Map([`, `Map.of(`, `frozenset({`, `std::to_array<T>({`, `array(`
inline bool isDataWrapperValue( std::string_view v ) noexcept
{
    static constexpr auto kWrappers = std::to_array<std::string_view>( { "Object.freeze", "new Map", "new Set", "Map.ofEntries", "Map.of", "Set.of", "List.of", "Arrays.asList", "ImmutableMap.of", "frozenset",
                                                                         "dict", "set", "tuple", "mapOf", "listOf", "setOf", "arrayOf", "array", "std::to_array" } );
    for( const std::string_view w : kWrappers )
    {
        if( v.starts_with( w ) )
        {
            std::string_view rest = v.substr( w.size() );
            const std::size_t paren = rest.find( '(' );
            if( paren == std::string_view::npos || ( paren > 0 && rest.front() != '<' ) )
            {
                continue;
            }
            rest = trimWs( rest.substr( paren + 1 ) );
            return rest.empty() || rest == "{" || rest == "[";
        }
    }
    return false;
}

// `name! {`, `name![`, `a::name!{`: a macro invocation with a data bracket. `name!(`, the shape of `assert_eq!(` and `println!(`, only when allowParen
inline bool isMacroOpener( std::string_view v, bool allowParen ) noexcept
{
    v = v.starts_with( '$' ) ? v.substr( 1 ) : v;   // REGISTRAR-2: `$macro! {` inside a macro_rules arm, the table a `for_all_params!(m)` hands its rows to
    const std::size_t bang = v.find( '!' );
    if( bang == std::string_view::npos || bang == 0 || !std::all_of( v.begin(), v.begin() + std::ptrdiff_t( bang ), []( char c ) { return namesplit::isIdentChar( c ) || c == ':'; } ) )
    {
        return false;
    }
    const std::string_view after = trimWs( v.substr( bang + 1 ) );
    return after == "{" || after == "[" || ( allowParen && after == "(" );
}

// a typed composite that opens data: Go `[]T{`, `[...]T{`, `map[K]V{`, `map[K]func() error{` (a parenthesis only in a func type; `[a].map(x => {` is code); Java, C# `new T[] {`, `new List<T> {`
inline bool isCompositeValue( std::string_view v ) noexcept
{
    if( v.back() != '{' )
    {
        return false;
    }
    if( v.starts_with( "new " ) || v.starts_with( "new[" ) )
    {
        return v.find( '(' ) == std::string_view::npos;
    }
    if( !v.starts_with( "[" ) && !v.starts_with( "map[" ) && !v.starts_with( "&[" ) )
    {
        return false;
    }
    for( std::size_t i = v.find( '(' ); i != std::string_view::npos; i = v.find( '(', i + 1 ) )
    {
        if( i < 4 || v.substr( i - 4, 4 ) != "func" )
        {
            return false;
        }
    }
    return true;
}

// a struct literal: `Foo {`, `Foo<T>{`, `&pkg.Options{`, `a::B {`. A type name: an upper case start or a qualified name, so `loop {`, `unsafe {` are none; one token, so `match x {` is none
inline bool isStructValue( std::string_view v ) noexcept
{
    v = v.starts_with( '&' ) ? v.substr( 1 ) : v;
    if( v.size() < 2 || v.back() != '{' )
    {
        return false;
    }
    const std::string_view name = trimWs( v.substr( 0, v.size() - 1 ) );
    int angle = 0;
    for( const char c : name )
    {
        angle += c == '<' ? 1 : ( c == '>' ? -1 : 0 );
        if( !namesplit::isIdentChar( c ) && c != '.' && c != ':' && c != '<' && c != '>' && ( angle == 0 || ( c != ',' && c != ' ' ) ) )
        {
            return false;
        }
    }
    return !name.empty() && ( std::isupper( static_cast<unsigned char>( name.front() ) ) != 0 || name.find( '.' ) != std::string_view::npos || name.find( "::" ) != std::string_view::npos );
}

// How a language reads a bracket after `=` or `return` (the language-specific layer of the opener allowlist; everything else in it is shared):
//   tuple: `(` holds data only in Python (a tuple). In TS, JS it opens an arrow function's parameters (`export const f = (`), elsewhere a parenthesised expression.
//   localBrace: a bare `{` inside a function body is data in Python (a dict), C, C++, Java (an array initialiser), Go, Ruby; not in TS, JS (an object literal built in a
//   function is a call's options or a value, `const opts = {`), Rust (a block) or Swift, Kotlin (a closure).
struct BracketReading
{
    bool tuple      = false;
    bool localBrace = true;
};
inline BracketReading bracketReadingOf( Lang lang ) noexcept
{
    const LangFacts f = langFacts( lang );
    return BracketReading{ f.tupleParens, !f.localBraceNotData };
}

// the right side of an assignment, a return or a key is a data literal. A call's result is not (`make_unique<Pool>(`, `new Hono<E>({`, `wrap_with_prefix(`, `compute(`), nor is code (`() => {`, `function () {`, `match x {`).
// A struct literal only where allowStruct: outside a function it is a table of constants, inside one it is the arguments of a call (`opt := resource.PodResourcesOptions{`)
inline bool isDataValue( std::string_view v, bool allowStruct, BracketReading br ) noexcept
{
    static constexpr auto kLiterals = std::to_array<std::string_view>( { "{", "[", "(", "[{", "[(", "[[", "&[", "&mut [", "&'static [", "%w[", "%i[" } );
    if( v.empty() || ( !br.tuple && ( v == "(" || v == "[(" ) ) )
    {
        return false;   // a tuple outside Python is a parameter list or an expression
    }
    return std::find( kLiterals.begin(), kLiterals.end(), v ) != kLiterals.end() || isDataWrapperValue( v ) || isMacroOpener( v, false ) || isCompositeValue( v ) || ( allowStruct && isStructValue( v ) );
}

// the first `=` of an assignment outside parentheses (`def f(a=[` and `for (let i = 0;` have none; `==`, `!=`, `<=`, `>=`, `=>` are none), or npos
inline std::size_t assignmentAt( std::string_view c ) noexcept
{
    int depth = 0;
    for( std::size_t i = 0; i < c.size(); ++i )
    {
        depth += c[i] == '(' ? 1 : ( c[i] == ')' ? -1 : 0 );
        const char prev = i > 0 ? c[i - 1] : ' ';
        const char next = i + 1 < c.size() ? c[i + 1] : ' ';
        if( depth <= 0 && c[i] == '=' && prev != '=' && prev != '!' && prev != '<' && prev != '>' && next != '=' && next != '>' )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

// `key: {`, `"key": [`, `K: T{`, `'k' => [`: a row that is itself a literal, nested in a table (an `if x: {` or a callback is not: the key is one identifier or one quoted string)
inline bool isKeyedLiteral( std::string_view c, bool allowStruct, BracketReading br ) noexcept
{
    std::size_t keyEnd = 0;
    if( c.front() == '"' || c.front() == '\'' )
    {
        const std::size_t close = c.find( c.front(), 1 );
        keyEnd = close == std::string_view::npos ? 0 : close + 1;
    }
    else
    {
        keyEnd = taskroute::identifierRunOf( c ).size();
    }
    const std::string_view rest = trimWs( c.substr( keyEnd ) );
    const bool colon = rest.starts_with( ':' ) && !rest.starts_with( "::" ) && !rest.starts_with( ":=" );
    if( keyEnd == 0 || ( !colon && !rest.starts_with( "=>" ) ) )
    {
        return false;
    }
    return isDataValue( trimWs( rest.substr( colon ? 1 : 2 ) ), allowStruct, br );
}

// `enum E {`, `export const enum E {`, `pub(crate) enum E {`, `typedef enum {`, `enum class E : int {`: no `=`, no parameter list, the word enum among the first ones
inline bool isEnumOpener( std::string_view c ) noexcept
{
    for( std::size_t at = c.find( "enum" ); at != std::string_view::npos; at = c.find( "enum", at + 1 ) )
    {
        const bool edges = ( at == 0 || c[at - 1] == ' ' || c[at - 1] == ')' ) && at + 4 < c.size() && ( c[at + 4] == ' ' || c[at + 4] == '{' );
        const std::string_view before = c.substr( 0, at );
        if( edges && c.find( '=' ) == std::string_view::npos && ( before.find( '(' ) == std::string_view::npos || before.starts_with( "pub(" ) ) )
        {
            return true;
        }
    }
    return false;
}

// C++ brace initialisation with no `=`: `static constexpr std::array<T, 8> kNames{`, `const std::map<K, V> kM {`. The word before `{` is the declared name: a JS destructuring
// `const {` (an import binding) and a Java `static {` initialiser block declare none
inline bool isBraceInitDecl( std::string_view c ) noexcept
{
    const auto isLead = []( std::string_view w ) { return w == "static" || w == "const" || w == "constexpr" || w == "inline"; };
    const std::string_view first = taskroute::identifierRunOf( c );
    const bool lead = isLead( first ) || c.starts_with( "std::" );
    const bool notType = c.find( "struct" ) == std::string_view::npos && c.find( "class" ) == std::string_view::npos && c.find( "union" ) == std::string_view::npos;
    if( !lead || !notType || c.back() != '{' || c.find( '(' ) != std::string_view::npos || c.find( '=' ) != std::string_view::npos )
    {
        return false;
    }
    const std::string_view head = trimWs( c.substr( 0, c.size() - 1 ) );
    std::size_t at = head.size();
    while( at > 0 && namesplit::isIdentChar( head[at - 1] ) )
    {
        --at;
    }
    const std::string_view name = head.substr( at );
    return !name.empty() && at > 0 && !isLead( name );
}

// What an opener line proves about the rows under it. ALLOWLIST (SAFETY (d)(1)): a line that is none of these is no table, and neither is what stands under it.
//   Root: a data opener, by language. C, C++: `T t[] = {`, `#define X(M) \`, `FOO_TABLE(`, `static constexpr std::array<T, 8> kX{`. Go: `var T = map[K]V{`, `x := []T{`, `return []T{`.
//         Rust: `const T: &[R] = &[`, `pub static M: [R; 2] = [`, `name! {`, `vec![`, `name!(` outside a function. TS, JS: `export const T = {`, `export default {`, `const T: R[] = [`, `module.exports = {`,
//         `Object.freeze({`, `new Map([`. Python: `T = {`, `T = [`, `T = (`, `T: dict[K, V] = {`, `frozenset({`. Java, C#: `T[] t = new T[] {`, `Map.of(`. A struct literal outside a function: `const L: Foo = Foo {`, `var X = T{`.
//   EnumBody: members of an enum (only a Member row is a row of it; a Rust variant's fields are not).
//   Nested: a literal inside a literal, which proves nothing yet: `{`, `}, {`, `key: {`, `.field = {`, and outside a function `Row {`, `key: Row {`. The walk goes on to the line above it.
//   Transparent: `namespace x {`, `mod x {`, `extern "C" {`: what stands in it is top level.
//   None: everything else. A declaration (`struct S {`, `interface I {`, `type T = {`, `class C {`, `impl X {`), a call's arguments (`x = foo(`, `new Hono<E>({`, `foo(k=[`), a statement (`if (x) {`, `for (;;) {`,
//         `} else {`), a callback (`describe("x", () => {`, `(function () {`), a function's own header, a closer (`};`), an import (`use a::{`, `import {`, `from x import (`, `export {`).
enum class OpenerKind
{
    None,
    Root,
    EnumBody,
    Nested,
    Transparent
};
inline OpenerKind classifyOpener( std::string_view c, bool inFunction, BracketReading br ) noexcept
{
    static constexpr auto kNotData = std::to_array<std::string_view>( { "else", "do", "try", "case", "default", "finally", "with", "async", "await", "yield", "throw", "new" } );
    if( c.starts_with( "#define" ) )
    {
        return OpenerKind::Root;
    }
    if( c.empty() || ( c.back() != '{' && c.back() != '[' && c.back() != '(' ) )
    {
        return OpenerKind::None;
    }
    if( c == "{" || c == "[" || c == "(" || c == "}, {" || c == "},{" || c == "], [" || c == "), (" )
    {
        return OpenerKind::Nested;
    }
    const std::string_view first = taskroute::identifierRunOf( c );
    if( first == "export" && ( trimWs( c.substr( 6 ) ) == "default {" || trimWs( c.substr( 6 ) ) == "default [" ) )
    {
        return OpenerKind::Root;
    }
    if( first == "return" )
    {
        const std::string_view value = trimWs( c.substr( 6 ) );
        return ( br.localBrace || value != "{" ) && isDataValue( value, false, br ) ? OpenerKind::Root : OpenerKind::None;   // a return is in a function body
    }
    if( wordIsOneOf( first, kForTableNotCallee ) || wordIsOneOf( first, kNotData ) || c.front() == '}' )
    {
        return OpenerKind::None;
    }
    if( c.starts_with( "namespace " ) || c.starts_with( "inline namespace " ) || c.starts_with( "mod " ) || c.starts_with( "pub mod " ) || c == "extern \"C\" {" )
    {
        return c.back() == '{' ? OpenerKind::Transparent : OpenerKind::None;
    }
    if( isEnumOpener( c ) )
    {
        return OpenerKind::EnumBody;
    }
    if( isKeyedLiteral( c, !inFunction, br ) || ( !inFunction && isStructValue( c ) ) )
    {
        return OpenerKind::Nested;
    }
    if( isMacroOpener( c, !inFunction ) || ( !inFunction && c.size() > 2 && c.back() == '(' && c.find( ' ' ) == std::string_view::npos && std::none_of( c.begin(), c.end(), []( char ch ) { return std::islower( static_cast<unsigned char>( ch ) ) != 0; } ) ) || isBraceInitDecl( c ) )
    {
        return OpenerKind::Root;
    }
    const std::size_t eq = assignmentAt( c );
    if( eq == std::string_view::npos || ( first.empty() && c.front() != '.' && c.front() != '[' && c.front() != '$' && c.front() != '@' ) )
    {
        return OpenerKind::None;   // no assignment, or its left side is a line's tail (`> = {`, the end of a multi-line type)
    }
    std::string_view decl = c;
    for( const std::string_view lead : { std::string_view( "export " ), std::string_view( "declare " ), std::string_view( "pub " ) } )
    {
        decl = decl.starts_with( lead ) ? trimWs( decl.substr( lead.size() ) ) : decl;
    }
    if( ( decl.starts_with( "type " ) || decl.starts_with( "using " ) ) && decl.find( '=' ) > decl.find( ' ' ) + 1 )
    {
        return OpenerKind::None;   // `type T = {`, `using U = struct {`: a declaration; `type = {` is a variable
    }
    const std::string_view value = trimWs( c.substr( eq + 1 ) );
    if( ( inFunction && !br.localBrace && value == "{" ) || !isDataValue( value, !inFunction, br ) )
    {
        return OpenerKind::None;
    }
    return c.front() == '.' || c.front() == '[' ? OpenerKind::Nested : OpenerKind::Root;   // C `.field = {`, `[KEY] = {`: inside a table
}

// a line an opener walk reads through at any indent: a comment, or a preprocessor line other than #define (`#ifdef` at column 0 inside a table)
inline bool openerWalkSkips( std::string_view t ) noexcept
{
    return !t.starts_with( "#define" ) && ( t.front() == '#' || t.starts_with( "//" ) || t.starts_with( "/*" ) || t.starts_with( "*" ) );
}

// the line above `pos` that holds text, and its start, or nullopt at the top of the file
inline std::optional<std::string_view> prevTextLine( std::string_view text, std::size_t& pos ) noexcept
{
    while( pos > 0 )
    {
        const std::size_t nl = pos >= 2 ? text.rfind( '\n', pos - 2 ) : std::string_view::npos;
        pos = nl == std::string_view::npos ? 0 : nl + 1;
        const std::string_view l = lineAt( text, pos );
        if( !trimWs( l ).empty() )
        {
            return l;
        }
    }
    return std::nullopt;
}

struct TableOpener
{
    OpenerKind  kind = OpenerKind::None;   // Root, EnumBody or Transparent when one was proven; None otherwise
    std::string text;                      // the opener as written
};

// a bracket alone on its line (Allman style): its declaration is the line above, at its indent. `T t[] =` + `{` reads as `T t[] = {`; `int main()` + `{` is no table
inline TableOpener allmanOpener( std::string_view text, std::size_t pos, std::size_t indent, std::string_view bracket, bool inFunction, BracketReading br )
{
    const std::optional<std::string_view> above = prevTextLine( text, pos );
    if( !above || lintdetail::indentOf( *above ) != indent )
    {
        return {};
    }
    std::string joined( openerCode( *above ) );
    joined.append( " " ).append( bracket );
    const OpenerKind k = classifyOpener( joined, inFunction, br );
    return k == OpenerKind::Nested || k == OpenerKind::None ? TableOpener{} : TableOpener{ k, joined };
}

// The opener of the literal a row at `rowStart` stands in. Going up, a less indented line must be an opener the allowlist knows: a closer, a statement or a declaration ends
// the walk with no claim, so a row never takes the opener of a closed block. A C++ raw string's lines (a column 0 `)", 0) \` up to its `R"(`) are text, not structure.
inline TableOpener tableOpenerOf( std::string_view text, std::size_t rowStart, std::size_t indent, bool inFunction, BracketReading br )
{
    std::size_t pos = rowStart;
    std::size_t cur = indent;
    bool inRaw = false;
    for( std::size_t step = 0; cur > 0 && pos > 0 && step < kForTableOpenerLines; ++step )
    {
        const std::optional<std::string_view> l = prevTextLine( text, pos );
        if( !l )
        {
            break;
        }
        const std::string_view t = trimWs( *l );
        if( inRaw || t.starts_with( ")\"" ) )
        {
            inRaw = t.find( "R\"" ) == std::string_view::npos;
            continue;
        }
        const std::size_t in = lintdetail::indentOf( *l );
        if( in >= cur || openerWalkSkips( t ) )
        {
            continue;
        }
        const std::string_view code = openerCode( *l );
        const OpenerKind k = classifyOpener( code, inFunction, br );
        if( code == "{" || code == "[" || code == "(" )
        {
            TableOpener a = allmanOpener( text, pos, in, code, inFunction, br );
            if( a.kind != OpenerKind::None )
            {
                return a;
            }
        }
        if( k != OpenerKind::Nested )
        {
            return k == OpenerKind::None ? TableOpener{} : TableOpener{ k, std::string( t ) };
        }
        cur = in;
    }
    return {};
}

// a row at column 0 of a table written flat: `T t[] = {` + `{ "a" },` + `{ "b" },`: the lines above of the row's own shape, then the opener
inline TableOpener flatOpenerOf( std::string_view text, std::size_t rowStart, RowKind kind, bool inFunction, BracketReading br )
{
    std::size_t pos = rowStart;
    for( std::size_t step = 0; step < kForTableSiblingLines; ++step )
    {
        const std::optional<std::string_view> l = prevTextLine( text, pos );
        if( !l )
        {
            break;
        }
        if( rowShapeOf( *l ).kind == kind )
        {
            continue;
        }
        const OpenerKind k = classifyOpener( openerCode( *l ), inFunction, br );
        return k == OpenerKind::Root || k == OpenerKind::EnumBody ? TableOpener{ k, std::string( trimWs( *l ) ) } : TableOpener{};
    }
    return {};
}

// shape=table, rank only, among table rows and among other rows: a site under documentation, examples or an integration app comes after the product's own. A table row outranks any other row wherever it stands.
inline bool isSecondaryPath( std::string_view p ) noexcept
{
    static constexpr std::array<std::string_view, 8> kSegments{ "docs", "doc", "examples", "example", "samples", "snippets", "website", "integration" };
    while( !p.empty() )
    {
        const std::size_t slash = p.find( '/' );
        if( slash == std::string_view::npos )
        {
            return false;   // the last segment is the file's own name
        }
        if( std::find( kSegments.begin(), kSegments.end(), p.substr( 0, slash ) ) != kSegments.end() )
        {
            return true;
        }
        p.remove_prefix( slash + 1 );
    }
    return false;
}

// The table this source line is a row of, or "": a row of an allowed shape, a sibling of the same shape at its indent, and an opener the allowlist proves
// (classifyOpener); or a macro row at top level (a Rust `name!(`, an ALLCAPS callee, outside any function), which is a registration with no sibling needed; or a call row at top level with
// a sibling ("item"). The owner the parser found makes this stricter, never looser: inside a function a call is a statement, never a row (`log_info("x");` twice is two statements,
// not a table), and a struct literal is the arguments of a call. A call row whose callee IS the anchor is a call of it (`run_it(1)` twice in a script), not a row of a table that holds it.
inline std::string tableRowOf( std::string_view text, std::size_t byteOffset, bool callableOwner, BracketReading br )
{
    if( byteOffset >= text.size() )
    {
        return {};   // a file that changed since the scan: unknown, no claim
    }
    const std::size_t nl    = byteOffset == 0 ? std::string_view::npos : text.rfind( '\n', byteOffset - 1 );
    const std::size_t start = nl == std::string_view::npos ? 0 : nl + 1;
    const std::string_view line = lineAt( text, start );
    const RowShape shape = rowShapeOf( line );
    if( shape.kind == RowKind::None || ( callableOwner && shape.kind == RowKind::Call ) )
    {
        return {};
    }
    if( shape.kind == RowKind::Call )
    {
        const std::size_t headAt = std::size_t( shape.head.data() - text.data() );
        if( byteOffset >= headAt && byteOffset < headAt + shape.head.size() )
        {
            return {};   // a call OF the anchor is no row of it
        }
    }
    const std::size_t indent = lintdetail::indentOf( line );
    const TableOpener opener = indent > 0 ? tableOpenerOf( text, start, indent, callableOwner, br )
                                          : ( shape.kind == RowKind::Call ? TableOpener{ OpenerKind::Transparent, {} } : flatOpenerOf( text, start, shape.kind, callableOwner, br ) );
    const bool enumMember = opener.kind == OpenerKind::EnumBody && shape.kind == RowKind::Member;
    if( opener.kind != OpenerKind::Root && !enumMember && !( opener.kind == OpenerKind::Transparent && shape.kind == RowKind::Call ) )
    {
        return {};   // no proven opener: no claim. "item" is a top level call only
    }
    const auto same = [ & ]( std::optional<std::string_view> l )
    {
        if( !l )
        {
            return false;
        }
        const RowShape o = rowShapeOf( *l );
        return o.kind == shape.kind && o.head == shape.head;
    };
    const bool macroRow = shape.kind == RowKind::Call && !callableOwner
                          && ( shape.head.ends_with( '!' ) || std::none_of( shape.head.begin(), shape.head.end(), []( char c ) { return std::islower( static_cast<unsigned char>( c ) ) != 0; } ) );
    const bool crossLess = shape.kind == RowKind::Call;   // a call row's text may span raw lines at any indent (`DECLARE(.., R"(` over a description)
    if( !macroRow && !same( siblingLine( text, start, indent, true, crossLess ) ) && !same( siblingLine( text, start, indent, false, crossLess ) ) )
    {
        return {};
    }
    return opener.kind == OpenerKind::Transparent ? std::string( "item" ) : opener.text;
}

// REGISTRAR-2: where a hit stands, for telling a call's argument from a declaration. Built once per file (lang flags) and per hit (the enclosing symbol).
struct RegHitCtx
{
    std::string_view enclosingName;           // the symbol whose span holds the hit ("" = none): a call named like it is its own signature
    bool             enclosedByType = false;  // that symbol is a class, struct, interface or named type: a call-shaped line in its body is a member, not a call
    bool             cFamily        = false;  // C, C++, Objective-C: a `: a_(x),` member-initializer list looks like calls
    bool             rust           = false;  // `'` opens a char literal or a lifetime
    bool             hashComments   = false;  // `#` starts a comment (Python, Ruby, shell, YAML, TOML, Elixir, GDScript)
};
inline RegHitCtx regLangCtxOf( Lang lang ) noexcept
{
    RegHitCtx c;
    switch( lang )
    {
        case Lang::Cpp: case Lang::C: case Lang::ObjC: c.cFamily = true; break;
        case Lang::Rust: c.rust = true; break;
        case Lang::Python: case Lang::Ruby: case Lang::Bash: case Lang::Yaml: case Lang::Toml: case Lang::Elixir: case Lang::GDScript: c.hashComments = true; break;
        default: break;
    }
    return c;
}

// REGISTRAR-2: the open paren at `paren` is a registration call that opens its line: the callee chain right before it (`a.b.name` or `a::b::name`, blanks
// allowed before the paren, an `@` before the chain for a decorator, only blanks before that) is named for a registration. Its line up to the paren,
// or nothing. Not a call, whatever its name (REG2-FIX1, rv-reg2 F1): (a) the callee is the name of the symbol the hit sits in (its own signature:
// `CommandRunner(const BuildConfig& c);`, `Registry::RegisterHandler(Handler h)`, a JS method `registerHandler(h) {`); (b) the hit sits in the body
// of a type, outside a decorator (a Rust enum's tuple variant, a TypeScript interface member); (c) in C and C++, the line follows a `:` or `,`
// (a member-initializer list).
inline std::optional<std::string_view> registrationOpenerAt( std::string_view text, std::size_t paren, const RegHitCtx& ctx = {} ) noexcept
{
    std::size_t e = paren;
    while( e > 0 && ( text[e - 1] == ' ' || text[e - 1] == '\t' ) )
    {
        --e;   // `register_handler (x)`
    }
    std::size_t b = e;
    while( b > 0 )
    {
        if( namesplit::isIdentChar( text[b - 1] ) || text[b - 1] == '.' )
        {
            --b;
        }
        else if( text[b - 1] == ':' && b > 1 && text[b - 2] == ':' )
        {
            b -= 2;   // `registry::register_handler(`
        }
        else
        {
            break;
        }
    }
    const std::string_view callee = text.substr( b, e - b );
    const bool decorator = b > 0 && text[b - 1] == '@';
    std::size_t ls = decorator ? b - 1 : b;
    while( ls > 0 && ( text[ls - 1] == ' ' || text[ls - 1] == '\t' ) )
    {
        --ls;
    }
    const bool opensLine = ls == 0 || text[ls - 1] == '\n';
    if( !opensLine || callee.empty() || ( std::isalpha( static_cast<unsigned char>( callee.front() ) ) == 0 && callee.front() != '_' )
        || !reg_detail::isRegistrationCallee( callee, decorator ) )
    {
        return std::nullopt;
    }
    const std::size_t      sep  = callee.find_last_of( ".:" );
    const std::string_view last = sep == std::string_view::npos ? callee : callee.substr( sep + 1 );
    if( ( !ctx.enclosingName.empty() && last == ctx.enclosingName ) || ( ctx.enclosedByType && !decorator ) )
    {
        return std::nullopt;
    }
    if( ctx.cFamily )
    {
        std::size_t p = ls;
        while( p > 0 && ( text[p - 1] == ' ' || text[p - 1] == '\t' || text[p - 1] == '\n' || text[p - 1] == '\r' ) )
        {
            --p;
        }
        if( p > 0 && ( text[p - 1] == ',' || ( text[p - 1] == ':' && !( p > 1 && text[p - 2] == ':' ) ) ) )
        {
            return std::nullopt;
        }
    }
    return trimWs( text.substr( ls, paren + 1 - ls ) );
}

// a `{` that opens a block body (a function, an arrow function, a closure), not a dict, an object or a struct literal: the byte before it, past
// blanks and newlines, is `)` (`function (a) {`, `func(w, r) {`), the `>` of `=>` or `->`, or a Rust closure's `|`
inline bool opensBlockBody( std::string_view text, std::size_t brace ) noexcept
{
    std::size_t p = brace;
    while( p > 0 && ( text[p - 1] == ' ' || text[p - 1] == '\t' || text[p - 1] == '\n' || text[p - 1] == '\r' ) )
    {
        --p;
    }
    if( p == 0 )
    {
        return false;
    }
    const char c = text[p - 1];
    return c == ')' || c == '|' || ( c == '>' && p > 1 && ( text[p - 2] == '=' || text[p - 2] == '-' ) );
}

// the call parens and braces still open where the window of `registrationCallOf` ends, read forward from a line start: strings, char literals and
// comments are skipped (a `(` inside one opens nothing), `;` ends the statement (every open paren before it is closed)
struct RegScan
{
    struct Open
    {
        std::size_t pos;
        char        c;
    };
    std::vector<Open> open;
    char              quote = 0;       // the quote byte of the string being read, or 0
    bool              triple = false;  // a triple-quoted string (Python): it ends at the next triple, not at a newline
    bool              lineComment = false, blockComment = false;

    // a `'` that opens a char literal (`'('`, `'\n'`) and not a Rust lifetime (`'a`)
    static bool isCharLiteral( std::string_view text, std::size_t i ) noexcept
    {
        return i + 2 < text.size() && ( text[i + 1] == '\\' || text[i + 2] == '\'' );
    }
    void closeTo( char opener )
    {
        const auto at = std::find_if( open.rbegin(), open.rend(), [ & ]( const Open& o ) { return o.c == opener; } );
        if( at != open.rend() )
        {
            open.erase( ( at + 1 ).base(), open.end() );
        }
    }
    void step( std::string_view text, std::size_t& i, std::size_t end, const RegHitCtx& ctx )
    {
        const char c = text[i];
        if( lineComment )
        {
            lineComment = c != '\n';
            return;
        }
        if( blockComment )
        {
            if( c == '*' && i + 1 < end && text[i + 1] == '/' )
            {
                blockComment = false;
                ++i;
            }
            return;
        }
        if( quote != 0 )
        {
            if( c == '\\' )
            {
                ++i;
            }
            else if( triple )
            {
                if( c == quote && i + 2 < end && text[i + 1] == quote && text[i + 2] == quote )
                {
                    quote = 0;
                    i += 2;
                }
            }
            else if( c == quote || ( c == '\n' && quote != '`' ) )
            {
                quote = 0;
            }
            return;
        }
        switch( c )
        {
            case '"': case '\'': case '`':
                if( c == '\'' && ctx.rust && !isCharLiteral( text, i ) )
                {
                    return;   // a lifetime
                }
                quote  = c;
                triple = c != '`' && i + 2 < end && text[i + 1] == c && text[i + 2] == c;
                i += triple ? 2 : 0;
                return;
            case '#':
                lineComment = ctx.hashComments && ( i == 0 || text[i - 1] == ' ' || text[i - 1] == '\t' || text[i - 1] == '\n' );
                return;
            case '/':
                if( !ctx.hashComments && i + 1 < end && text[i + 1] == '/' )
                {
                    lineComment = true;
                }
                else if( !ctx.hashComments && i + 1 < end && text[i + 1] == '*' )
                {
                    blockComment = true;
                    ++i;
                }
                return;
            case ';': open.clear(); return;
            case '(': case '{': case '[': open.push_back( Open{ i, c } ); return;
            case ')': closeTo( '(' ); return;
            case '}': closeTo( '{' ); return;
            case ']': closeTo( '[' ); return;
            default: return;
        }
    }
};

// the innermost call still open at the hit (`scan`) that is a registration call: its opener line, or "". A block body `{` ends the walk (a closure's
// statements are not the call's arguments); `[` groups are passed. `*direct`: no group opened between that call's `(` and the hit.
inline std::string innermostRegistration( std::string_view text, const RegScan& scan, const RegHitCtx& ctx, bool* direct )
{
    // a 1-based cursor counts down to zero: `k-- > 0` wraps k to SIZE_MAX on its final test, which -fsanitize=integer reports (ingest_names.h)
    for( std::size_t cursor = scan.open.size(); cursor > 0; --cursor )
    {
        const std::size_t    k = cursor - 1;
        const RegScan::Open& o = scan.open[k];
        if( o.c == '{' && opensBlockBody( text, o.pos ) )
        {
            return {};
        }
        const std::optional<std::string_view> opener = o.c == '(' ? registrationOpenerAt( text, o.pos, ctx ) : std::nullopt;
        if( opener )
        {
            if( direct != nullptr )
            {
                *direct = k + 1 == scan.open.size();
            }
            return std::string( *opener );
        }
    }
    return {};
}

// REGISTRAR-2: the registration call whose arguments hold the hit at `at`, or "": the text from at most kForRegCallLines lines and kForRegCallBytes
// bytes above the hit (from a line start, after the last `;`) is read forward; each '(' left open is a call the hit is an argument of, innermost
// first; the first whose callee chain opens its line and is named for a registration (registrationOpenerAt) is the row's opener: its line up to
// that '('. The walk ends at an open `{` that starts a block body (opensBlockBody: a closure's statements are not the arguments of the call that
// holds the closure). `*direct` (when given): the hit is a whole argument of that call, no `(`, `[` or `{` opened between them (a hit nested in
// another call, an index or an object literal is an argument of that one). A definition (`func NewHandler(`, `def register(`) is no call: a keyword stands before the name. Parens in strings and
// comments are skipped (RegScan). A call opened above the window is not found: the row's absence is no claim (the table legend says how far it reads).
inline std::string registrationCallOf( std::string_view text, std::size_t at, const RegHitCtx& ctx = {}, bool* direct = nullptr )
{
    if( at > text.size() )
    {
        return {};
    }
    std::size_t start = at > kForRegCallBytes ? at - kForRegCallBytes : 0;
    for( std::size_t i = at, lines = 0; i > start; --i )
    {
        if( text[i - 1] == '\n' && ++lines > kForRegCallLines )
        {
            start = i;
            break;
        }
    }
    if( start > 0 && text[start - 1] != '\n' )
    {
        const std::size_t nl = text.find( '\n', start );
        start = nl == std::string_view::npos ? at : nl + 1;   // read from a line start: a string's quote state is unknown mid-line
    }
    RegScan scan;
    for( std::size_t i = start; i < at; ++i )
    {
        scan.step( text, i, at, ctx );
    }
    return innermostRegistration( text, scan, ctx, direct );
}

// REGISTRAR-2: the name holding the hit at `at` is a whole argument of a call: the identifier run around it stands between `(` or `,` and `,` or `)`
// (`async_reg(hass, handle_get_states)`), never a callee (`async_get_turn_on_trigger(x)`) or a member of a chain (`self._turn_on.async_register(`).
// An identifier run longer than kForRegIdentBytes either side is a blob, not a name: no argument, and the walk stays bounded however often a short
// anchor repeats inside it.
inline bool isArgumentName( std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    if( at > text.size() || n > text.size() - at )
    {
        return false;
    }
    std::size_t b = at, e = at + n;
    while( b > 0 && namesplit::isIdentChar( text[b - 1] ) )
    {
        if( at - b >= kForRegIdentBytes )
        {
            return false;
        }
        --b;
    }
    while( e < text.size() && namesplit::isIdentChar( text[e] ) )
    {
        if( e - ( at + n ) >= kForRegIdentBytes )
        {
            return false;
        }
        ++e;
    }
    while( b > 0 && ( text[b - 1] == ' ' || text[b - 1] == '\t' || text[b - 1] == '\n' || text[b - 1] == '\r' ) )
    {
        --b;
    }
    while( e < text.size() && ( text[e] == ' ' || text[e] == '\t' || text[e] == '\n' || text[e] == '\r' ) )
    {
        ++e;
    }
    return b > 0 && ( text[b - 1] == '(' || text[b - 1] == ',' ) && e < text.size() && ( text[e] == ',' || text[e] == ')' );
}

// remove the ranked rows flagged in `drop` (parallel to `enriched`, and to the first rows of `rows`); the count removed
inline std::size_t dropRows( std::vector<Site>& rows, std::vector<GrepHit>& enriched, const std::vector<char>& drop )
{
    std::size_t out = 0, n = 0;
    for( std::size_t i = 0; i < enriched.size(); ++i )
    {
        if( drop[i] == 0 )
        {
            if( out != i )
            {
                rows[out]     = std::move( rows[i] );
                enriched[out] = std::move( enriched[i] );
            }
            ++out;
        }
        else
        {
            ++n;
        }
    }
    if( n > 0 )
    {
        rows.erase( rows.begin() + std::ptrdiff_t( out ), rows.begin() + std::ptrdiff_t( enriched.size() ) );
        enriched.resize( out );
    }
    return n;
}

// the symbol kinds whose body holds members, not statements
inline bool isTypeKind( SymKind k ) noexcept
{
    static constexpr std::array<SymKind, 4> kTypeBodyKinds{ SymKind::Class, SymKind::Struct, SymKind::Interface, SymKind::NamedType };
    return std::find( kTypeBodyKinds.begin(), kTypeBodyKinds.end(), k ) != kTypeBodyKinds.end();
}

// REG-READER (a): a function whose name says it builds or registers (New*, new_*, Register*, register_*, an async_ prefix aside): the table it fills
// with computed keys is a registry. The name, not proof; a qualified name is read by its last part.
inline bool isRegistrarFnName( std::string_view name ) noexcept
{
    const std::size_t cut = name.find_last_of( ".:" );
    std::string_view  n   = cut == std::string_view::npos ? name : name.substr( cut + 1 );
    n                     = n.starts_with( "async_" ) ? n.substr( 6 ) : n;
    const auto lead       = [ & ]( std::string_view p )
    {
        return n.starts_with( p ) && ( n.size() == p.size() || n[p.size()] == '_' || std::isupper( static_cast<unsigned char>( n[p.size()] ) ) != 0 );
    };
    return lead( "New" ) || lead( "new" ) || lead( "Register" ) || lead( "register" );
}

// the first byte of `t` from `from` on, outside quotes, at which `stop( i, c )` says true, or npos when the line ends first
template <class Stop>
inline std::size_t firstUnquotedWhere( std::string_view t, std::size_t from, Stop&& stop ) noexcept
{
    for( std::size_t i = from; i < t.size(); ++i )
    {
        const char c = t[i];
        if( c == '"' || c == '\'' || c == '`' )
        {
            for( ++i; i < t.size() && t[i] != c; i += t[i] == '\\' ? 2 : 1 )
            {
            }
            continue;
        }
        if( stop( i, c ) )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

// the close of the bracket group opened at `open` (quotes skipped), or npos when the line ends first
inline std::size_t bracketCloseOf( std::string_view t, std::size_t open ) noexcept
{
    int depth = 0;
    return firstUnquotedWhere( t, open, [ & ]( std::size_t, char c ) { depth += c == '[' ? 1 : ( c == ']' ? -1 : 0 ); return depth == 0; } );
}

// one subscript write a line opens with: `recv[key] = v` (recv a name chain: `a.b`, `a->b`, `a::b`, earlier index groups `hass.data[DOMAIN]`). Offsets are
// into `t`; `open`/`close` bracket the key. Allowlist: a keyword or a declaration first (`return x[k] = `, `const a = b[k]`), an annotation (`x: T = `), a
// compound or a comparison (`+=`, `==`) is none.
struct SubscriptWrite
{
    std::size_t open = 0, close = 0, eq = 0;
};
inline std::optional<SubscriptWrite> subscriptWriteOf( std::string_view t ) noexcept
{
    std::size_t    i = 0;
    SubscriptWrite w;
    bool           indexed = false;
    while( i < t.size() )
    {
        const std::size_t run = taskroute::identifierRunOf( t.substr( i ) ).size();
        if( run == 0 || std::isdigit( static_cast<unsigned char>( t[i] ) ) != 0 )
        {
            return std::nullopt;
        }
        i += run;
        indexed = false;
        while( i < t.size() && t[i] == '[' )
        {
            const std::size_t close = bracketCloseOf( t, i );
            if( close == std::string_view::npos )
            {
                return std::nullopt;
            }
            w.open  = i;
            w.close = close;
            indexed = true;
            i       = close + 1;
        }
        const std::size_t sep = t.substr( i ).starts_with( "->" ) || t.substr( i ).starts_with( "::" ) ? 2 : ( i < t.size() && t[i] == '.' ? 1 : 0 );
        if( sep == 0 )
        {
            break;
        }
        i += sep;
    }
    while( i < t.size() && ( t[i] == ' ' || t[i] == '\t' ) )
    {
        ++i;
    }
    if( !indexed || i >= t.size() || t[i] != '=' || ( i + 1 < t.size() && t[i + 1] == '=' ) )
    {
        return std::nullopt;
    }
    w.eq = i;
    return w;
}

// the end of the statement that starts at `t` (a `;` outside quotes and bracket groups), or t.size(): a later statement on the line is not the write
inline std::size_t statementEndOf( std::string_view t ) noexcept
{
    static constexpr std::string_view kOpens = "([{", kCloses = ")]}";
    int                               depth  = 0;
    const std::size_t                 end    = firstUnquotedWhere( t, 0,
                                                    [ & ]( std::size_t, char c )
                                                    {
                                                        depth += kOpens.find( c ) != std::string_view::npos ? 1 : ( kCloses.find( c ) != std::string_view::npos ? -1 : 0 );
                                                        return c == ';' && depth <= 0;
                                                    } );
    return end == std::string_view::npos ? t.size() : end;
}

// a key that is one literal (`"pods"`, `'k'`, `3`, `-1`, `0x10`, `1_000`, `2.5`): the table rule's own business, not a computed key
inline bool isLiteralKey( std::string_view key ) noexcept
{
    key = trimWs( key );
    if( key.empty() )
    {
        return true;
    }
    std::size_t close = 1;
    while( close < key.size() && key[close] != key.front() )
    {
        close += key[close] == '\\' ? 2 : 1;
    }
    const bool substituted = key.front() == '`' && key.find( "${" ) != std::string_view::npos;   // a template literal with a substitution is computed
    const bool quoted    = key.size() >= 2 && ( key.front() == '"' || key.front() == '\'' || key.front() == '`' ) && close == key.size() - 1 && !substituted;
    const std::size_t sign   = key.front() == '-' || key.front() == '+' ? 1 : 0;   // a number token: a digit first, then digits, letters (0x, e, L), `_` or `.`
    const bool        number = sign < key.size() && std::isdigit( static_cast<unsigned char>( key[sign] ) ) != 0
                        && std::all_of( key.begin() + std::ptrdiff_t( sign ), key.end(),
                                        []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) != 0 || c == '_' || c == '.'; } );
    return quoted || number;
}

// REG-READER (a): a row whose hit is the key or the value of a subscript write with a computed key, in a function named for building or registering,
// is a registration: reg= `table[key] =`. A hit in the table's own name is none (every write of it would be a row).
inline void subscriptRowOf( std::string_view text, Site& row, std::string_view enclosingName )
{
    if( row.longer || row.leadInString || !isRegistrarFnName( enclosingName ) || row.raw.byteOffset >= text.size() )
    {
        return;
    }
    const std::size_t nl    = row.raw.byteOffset == 0 ? std::string_view::npos : text.rfind( '\n', row.raw.byteOffset - 1 );
    const std::size_t start = nl == std::string_view::npos ? 0 : nl + 1;
    const std::string_view line = lineAt( text, start );
    const std::size_t lead      = line.find_first_not_of( " \t" );
    if( lead == std::string_view::npos )
    {
        return;
    }
    const std::string_view               t = line.substr( lead );
    const std::optional<SubscriptWrite> w  = subscriptWriteOf( t );
    if( !w )
    {
        return;
    }
    const std::size_t keyAt   = start + lead + w->open;
    const std::size_t stmtEnd = start + lead + statementEndOf( t );   // `storage[k] = v; consume(x)`: a hit in `consume(x)` is not the write's
    const auto        inWrite = [ & ]( std::size_t at ) { return at >= keyAt && at < stmtEnd; };
    const bool hitPast = inWrite( row.raw.byteOffset ) || std::any_of( row.more.begin(), row.more.end(), [ & ]( std::uint32_t m ) { return inWrite( m ); } );
    if( !hitPast || isLiteralKey( t.substr( w->open + 1, w->close - w->open - 1 ) ) )
    {
        return;
    }
    row.tbl       = std::string( trimWs( t.substr( 0, w->eq + 1 ) ) );
    row.table     = std::string( t.substr( 0, w->open ) );
    row.regCall   = true;
    row.regDirect = true;
    row.subscript = true;
}

// the registration call a row's hit is an argument of (tbl, regDirect): the first hit's call stays the fallback, and a later hit of the line that is a DIRECT argument of one
// is preferred (`r.register(wrap(f), f)`)
inline void registrationOfRow( std::string_view text, Site& row, const RegHitCtx& ctx )
{
    row.tbl = registrationCallOf( text, row.raw.byteOffset, ctx, &row.regDirect );
    for( std::size_t m = 0; m < row.more.size() && ( row.tbl.empty() || !row.regDirect ); ++m )
    {
        bool        direct = false;
        std::string call   = registrationCallOf( text, row.more[m], ctx, &direct );
        if( !call.empty() && ( row.tbl.empty() || direct ) )
        {
            row.tbl       = std::move( call );
            row.regDirect = direct;
        }
    }
    if( row.tbl.empty() && !ctx.enclosedByType )
    {
        subscriptRowOf( text, row, ctx.enclosingName );   // REG-READER (a): else a subscript write into a registry, in a function named for one
    }
}

// a top-level call row (tbl="item") is strong (G-STORED-B) as a registration call's DIRECT argument only: `register(wrap(x))` at module level is the same nested shape the
// in-function registration rejects
inline bool itemIsNested( std::string_view text, std::size_t at, const RegHitCtx& ctx )
{
    bool direct = true;
    return !registrationCallOf( text, at, ctx, &direct ).empty() && !direct;
}

// shape=table: read each ranked site for a table row; true when one is. A site that is no row of a table may be an argument of a registration
// call (registrationCallOf, tried at every hit of its line), anywhere: in a function body too, and a hit inside a longer name (`handle_get_states`)
// only so. A site of a longer name that is no such argument is dropped from `rows` and `enriched` (counted in `longerDropped`, said as longer=).
template<typename LoadFile>
inline bool markTableRows( const IngestResult& ing, std::vector<Site>& rows, std::vector<GrepHit>& enriched, LoadFile&& loadFile, const std::string& loadedText,
                           std::size_t& longerDropped )
{
    bool              any = false;
    std::vector<char> drop( enriched.size(), 0 );
    for( std::size_t i = 0; i < enriched.size(); ++i )
    {
        loadFile( rows[i].raw.fileId );
        const NodeId     owner         = enriched[i].enclosingId;
        const bool       callableOwner = owner != kNoNode && ReceiverEvidence::callableKind( ing.symbols[owner].kind );
        const Lang       lang          = langOfPath( ing.files[rows[i].raw.fileId] );
        rows[i].tbl = rows[i].longer ? std::string() : tableRowOf( loadedText, rows[i].raw.byteOffset, callableOwner, bracketReadingOf( lang ) );
        if( rows[i].tbl.empty() )
        {
            RegHitCtx ctx = regLangCtxOf( lang );
            if( owner != kNoNode )
            {
                ctx.enclosingName  = ing.symbols[owner].name;
                ctx.enclosedByType = isTypeKind( ing.symbols[owner].kind );
            }
            registrationOfRow( loadedText, rows[i], ctx );
            rows[i].regCall = !rows[i].tbl.empty();
            drop[i]         = rows[i].longer && rows[i].tbl.empty();
        }
        else if( rows[i].tbl == "item" )
        {
            rows[i].itemNested = itemIsNested( loadedText, rows[i].raw.byteOffset, regLangCtxOf( lang ) );
        }
        any = any || !rows[i].tbl.empty();
    }
    longerDropped += dropRows( rows, enriched, drop );
    return any;
}

// REG2-FIX1 (rv-reg2 F3): the last part of a dotted name (`editor.mode` -> `mode`), tried after the name itself found nothing, lists only the rows where it is
// a quoted key (`'ValidationError': (...)`, `.method('redirect')`) and the tail's own definition: any other site of a common word is a mention, not the thing
// the task named. False when no site is a quoted key (nothing is listed). `dropped` counts the sites left out (said as tail=).
inline bool keepTailKeyRows( const IngestResult& ing, std::string_view tail, std::vector<Site>& rows, std::vector<GrepHit>& enriched, std::size_t& dropped )
{
    std::vector<char> drop( enriched.size(), 0 );
    bool              anyKey = false;
    for( std::size_t i = 0; i < enriched.size(); ++i )
    {
        const NodeId owner = enriched[i].enclosingId;
        const bool   def   = owner != kNoNode && ing.symbols[owner].name == tail && ing.symbols[owner].line == enriched[i].line;
        anyKey             = anyKey || rows[i].quotedKey;
        drop[i]            = !( rows[i].quotedKey || def );
    }
    if( !anyKey )
    {
        return false;
    }
    dropped += dropRows( rows, enriched, drop );
    return true;
}

// G-STORED-B: a STRONG row, the only kind a task with no cue word lists: a registration call's direct argument (reg=; a site nested in an inner call, an index
// or an object literal is not one), a top-level macro or call row
// (tbl="item"), or a row of a macro table (`for_all_params! {`, `$macro! {`). Allowlist: a dict, list, __all__, #define, enum or const-array row is weak.
inline bool isStrongRow( const Site& r ) noexcept
{
    return ( r.regCall && r.regDirect ) || ( r.tbl == "item" && !r.itemNested ) || ( !r.tbl.empty() && isMacroOpener( openerCode( r.tbl ), /*allowParen=*/false ) );
}

// a table row's tbl= attribute onto its <ls>; the opener is raw source text. No opener, no attribute.
inline void appendTblAttr( std::string& xml, std::string opener, RedactCounts* redact, std::vector<char>& esc, std::string_view attr = " tbl=\"" )
{
    if( !opener.empty() )
    {
        redactInPlace( opener, redact );
        truncateUtf8WithEllipsis( opener, kForTableOpenerBytes );
        xml.append( attr ).append( escapeXml( opener, esc ) ).push_back( '"' );
    }
}

// `'files.autoSave': {`: the quoted key is followed by a colon on its line (a property key, the way a schema registers a setting)
inline bool keyIsProperty( std::string_view line, std::string_view key ) noexcept
{
    const std::size_t at = line.find( key );
    if( at == std::string_view::npos )
    {
        return false;
    }
    const std::size_t colon = line.find_first_not_of( " \t", at + key.size() + 1 );
    return colon != std::string_view::npos && line[colon] == ':';
}

// shape=dotted: how much of a registration a site is, 0 none: 1 a quoted string site outside any function or method, 2 one whose key is a
// property key (`'files.autoSave': {`)
inline char registrationMark( const IngestResult& ing, const Site& s, NodeId owner, std::string_view line, std::string_view key )
{
    if( !s.quotedKey || s.k != 's' || ( owner != kNoNode && ReceiverEvidence::callableKind( ing.symbols[owner].kind ) ) )
    {
        return 0;
    }
    return keyIsProperty( line, key ) ? 2 : 1;
}

// shape=message: the rows that are not code (a task's words met outside a string are no message)
inline void dropCodeRows( std::vector<Site>& rows )
{
    rows.erase( std::remove_if( rows.begin(), rows.end(), []( const Site& r ) { return r.k == 'c'; } ), rows.end() );
}

// text-line helpers for the docstring position test: the previous line of the one starting at `ls` (its start moves back to that
// line's start), trimmed of '\r'; false at the top of the file
inline bool prevLine( const std::string& text, std::size_t& ls, std::string_view& line ) noexcept
{
    if( ls == 0 )
    {
        return false;
    }
    const std::size_t nl = ls - 1;   // text[nl] == '\n'
    const std::size_t r  = nl == 0 ? std::string::npos : text.rfind( '\n', nl - 1 );
    const std::size_t pb = r == std::string::npos ? 0 : r + 1;
    line                 = std::string_view( text ).substr( pb, nl - pb );
    if( !line.empty() && line.back() == '\r' )
    {
        line.remove_suffix( 1 );
    }
    ls = pb;
    return true;
}

// the previous line that holds code (not blank, not a whole-line # comment)
inline bool prevCodeLine( const std::string& text, std::size_t& ls, std::string_view& line ) noexcept
{
    while( prevLine( text, ls, line ) )
    {
        const std::string_view t = lintdetail::ltrim( line );
        if( !t.empty() && t.front() != '#' )
        {
            return true;
        }
    }
    return false;
}

// step back through code lines until one is indented LESS than `limit` (at most 200 lines); false when the top of the file comes first
inline bool climbBelow( const std::string& text, std::size_t& pos, std::string_view& line, std::size_t limit ) noexcept
{
    for( std::size_t steps = 0; lintdetail::indentOf( line ) >= limit; ++steps )
    {
        if( steps >= 200 || !prevCodeLine( text, pos, line ) )
        {
            return false;
        }
    }
    return true;
}

// `start` opens a (r/b/u-prefixed) triple-quoted string that is the first thing on its line: ls = that line's start, ind = its indent
inline bool opensTripleQuoteLine( const std::string& text, std::size_t start, std::size_t& ls, std::size_t& ind ) noexcept
{
    if( start >= text.size() )
    {
        return false;
    }
    for( ls = start; ls > 0 && text[ls - 1] != '\n'; --ls )
    {
    }
    const std::size_t fs = ls + lintdetail::indentOf( std::string_view( text ).substr( ls, start - ls ) );
    ind                  = fs - ls;
    return start - fs <= 2 && pythonDocstringQuote( std::string_view( text ).substr( fs, 8 ) ).size() == 3;
}

// a code line that ends a statement header: a trailing ':' (a trailing # comment aside)
inline bool endsWithColon( std::string_view line ) noexcept
{
    // the whole-line form keeps `def f(x="#"):` a header (its '#' is inside a string); only a def/class header line takes it, so a
    // trailing comment that ends in a colon (`x = x + 1  # note:`) is no header (train 42b, rv-mf1-lit-delta N2)
    const std::string_view lead = line.substr( std::min( line.find_first_not_of( " \t" ), line.size() ) );
    const bool header = lead.starts_with( "def " ) || lead.starts_with( "async def " ) || lead.starts_with( "class " );
    return lintdetail::rtrim( line.substr( 0, line.rfind( '#' ) ) ).ends_with( ':' ) || ( header && lintdetail::rtrim( line ).ends_with( ':' ) );
}

// A Python DOCSTRING: a triple-quoted string statement that is the FIRST statement of a module, class or def body — the line
// before it (comments and blank lines aside) closes a `def` / `async def` / `class` header with a ':' (a signature may span lines),
// or there is none (the top of the module). The same string opening a call-argument line (`raise E(\n """msg""")`), sitting in an
// `if` body or following other statements is a string SITE: the parse says String, this decides whether it is documentation. The
// caller applies it to Python only (langFacts leadingDocstring); another language's triple quote is a raw string, its comments
// are the parse's own Comment tier.
inline bool isPythonDocstringAt( const std::string& text, std::size_t start ) noexcept
{
    std::size_t ls = 0, ind = 0;
    if( !opensTripleQuoteLine( text, start, ls, ind ) )
    {
        return false;   // not the first thing on its line, or not a triple-quoted string
    }
    std::size_t      pos = ls;
    std::string_view line;
    if( !prevCodeLine( text, pos, line ) )
    {
        return true;   // nothing but comments before it: the module docstring
    }
    // the header's first line: the nearest code line indented LESS than the string (a multi-line signature closes with `) -> T:` at
    // the def's own indent; its parameters sit deeper or at the string's indent)
    if( !endsWithColon( line ) || !climbBelow( text, pos, line, ind ) )
    {
        return false;
    }
    std::string_view t = lintdetail::ltrim( line );
    if( !t.empty() && std::string_view( ")]}" ).find( t[0] ) != std::string_view::npos )   // `) -> None:` — on to the line that opened it
    {
        const std::size_t closeIndent = lintdetail::indentOf( line );
        if( !prevCodeLine( text, pos, line ) || !climbBelow( text, pos, line, closeIndent + 1 ) )
        {
            return false;
        }
        t = lintdetail::ltrim( line );
    }
    return t.starts_with( "def " ) || t.starts_with( "async def " ) || t.starts_with( "class " );
}

// FLAG-SHAPE-LIT: [begin, end) of each top-level argument of the call opened at `open`; empty when it does not close within kForRegCallBytes bytes
inline std::vector<std::pair<std::size_t, std::size_t>> callArgsAt( std::string_view text, std::size_t open )
{
    std::vector<std::pair<std::size_t, std::size_t>> args;
    std::size_t argStart = open + 1;
    int         depth    = 0;
    char        quote    = 0;
    const std::size_t end = std::min( text.size(), open + 1 + kForRegCallBytes );
    for( std::size_t i = open + 1; i < end; ++i )
    {
        const char c = text[i];
        if( quote != 0 )
        {
            i += c == '\\' ? 1 : 0;
            quote = c == quote ? 0 : quote;
            continue;
        }
        if( c == '"' || c == '\'' || c == '`' )
        {
            quote = c;
        }
        else if( c == '(' || c == '[' || c == '{' )
        {
            ++depth;
        }
        else if( ( c == ')' || c == ']' || c == '}' ) && depth-- == 0 )
        {
            args.emplace_back( argStart, i );
            return args;
        }
        else if( c == ',' && depth == 0 )
        {
            args.emplace_back( argStart, i );
            argStart = i + 1;
        }
    }
    return {};
}


// boost's `po::value<int>()->default_value(10)`: the text inside the call's parens, a paren inside a string default (`default_value(")")`) not counted
inline std::optional<std::string_view> boostDefaultOf( std::string_view arg ) noexcept
{
    const std::size_t call = arg.find( "default_value(" );
    char quote = 0;
    for( std::size_t i = call == std::string_view::npos ? arg.size() : call + 14, depth = 1; i < arg.size(); ++i )
    {
        const char c = arg[i];
        if( quote != 0 )
        {
            i += c == '\\' ? 1 : 0;
            quote = c == quote ? 0 : quote;
            continue;
        }
        quote = c == '"' || c == '\'' ? c : quote;
        depth += c == '(' ? 1 : 0;
        depth -= c == ')' ? 1 : 0;
        if( depth == 0 )
        {
            return trimAllWs( arg.substr( call + 14, i - call - 14 ) );
        }
    }
    return std::nullopt;
}

// the default a keyword argument names: `default=8` (argparse, click), `default_value = "info"` / `default_value_t = 64` (clap derive), `default: 8`
// (a JS option object), or boost's `po::value<int>()->default_value(10)`; nullopt when the argument is none of these
inline std::optional<std::string_view> keywordDefaultOf( std::string_view arg ) noexcept
{
    for( const std::string_view key : { std::string_view( "default_value_t" ), std::string_view( "default_value" ), std::string_view( "default" ) } )
    {
        if( arg.starts_with( key ) )
        {
            const std::string_view rest = trimWs( arg.substr( key.size() ) );
            if( !rest.empty() && ( rest.front() == '=' || rest.front() == ':' ) && !rest.starts_with( "==" ) )
            {
                return trimAllWs( rest.substr( 1 ) );
            }
        }
    }
    return boostDefaultOf( arg );
}

// FLAG-SHAPE-LIT: a Rust clap/structopt derive attribute that defines a flag, `#[arg(long = "cache-size", default_value_t = 64)]`, `#[clap(...)]`, `#[structopt(...)]`:
// the callee right after `#[`. A plain `arg(...)` call, or another attribute (`#[serde(default = ...)]`), is no flag definition.
inline bool isRustFlagAttribute( std::string_view text, std::string_view callee ) noexcept
{
    static constexpr auto kAttrs = std::to_array<std::string_view>( { "arg", "clap", "structopt" } );
    if( std::find( kAttrs.begin(), kAttrs.end(), callee ) == kAttrs.end() )
    {
        return false;
    }
    std::size_t before = std::size_t( callee.data() - text.data() );
    while( before > 0 && ( text[before - 1] == ' ' || text[before - 1] == '\t' ) )
    {
        --before;
    }
    return before >= 2 && text[before - 1] == '[' && text[before - 2] == '#';
}

// FLAG-SHAPE-LIT: a call outside the typed flag APIs (flagSlotOf) that still DEFINES a flag and may carry its `default=` keyword: argparse `add_argument`, click and typer
// `option` / `Option` / `argument` / `Argument`, optparse `add_option`, a JS `.option(`, and boost's `("name", po::value<T>()->default_value(x), "usage")` chain, whose
// call has no callee name (the `(` follows an `add_options()` or the previous `)`)
inline bool definesFlagByKeyword( std::string_view text, std::size_t open, std::string_view callee ) noexcept
{
    static constexpr auto kDefiners = std::to_array<std::string_view>( { "add_argument", "add_option", "option", "Option", "argument", "Argument", "addOption", "addArgument" } );
    if( std::find( kDefiners.begin(), kDefiners.end(), callee ) != kDefiners.end() )
    {
        return true;
    }
    if( isRustFlagAttribute( text, callee ) )
    {
        return true;
    }
    std::size_t before = open;
    while( before > 0 && std::isspace( static_cast<unsigned char>( text[before - 1] ) ) != 0 )
    {
        --before;
    }
    return callee.empty() && before > 0 && text[before - 1] == ')';
}

// FLAG-SHAPE-LIT: the argument in the default slot is the default: a quoted string there is the default whatever it holds (`"hello world"`, `"key=value"`) when the usage
// text is the last argument (Go flag and pflag take exactly name, default, usage); with more arguments after the slot a quoted sentence reads as usage text, and an unquoted
// `k=v` is a keyword argument
inline bool isDefaultSlotText( std::string_view d, bool usageLast ) noexcept
{
    const bool quoted = !d.empty() && ( d.front() == '"' || d.front() == '\'' );
    return !d.empty() && !( quoted && !usageLast && d.find( ' ' ) != std::string_view::npos ) && !( !quoted && d.find( '=' ) != std::string_view::npos );
}

// FLAG-SHAPE-LIT: the default argument of the call whose argument list holds the flag name at `at` (a whole quoted argument): a `default=`-style
// keyword argument of any call (keywordDefaultOf), else the flag API's own default slot (flagSlotOf: the argument right after the name, two after it
// for pflag's `P` form) when one more argument (the usage text) follows it. A call that is no flag-definition call (flagSlotOf: exec.Command, a nushell
// `.named`, a click alias `"-v"`) has no default here. Read from the text over at most kForRegCallBytes bytes; "" when none.
inline std::string flagDefaultAt( std::string_view text, std::size_t at )
{
    const std::size_t open = openParenBefore( text, at );
    if( open == std::string_view::npos )
    {
        return {};
    }
    const std::vector<std::pair<std::size_t, std::size_t>> args = callArgsAt( text, open );
    const auto argText = [ & ]( std::size_t k ) { return trimAllWs( text.substr( args[k].first, args[k].second - args[k].first ) ); };
    const std::string_view callee  = calleeBefore( text, open );
    const FlagSlot         slot    = flagSlotOf( callee );
    const bool             defines = slot != FlagSlot::Absent || definesFlagByKeyword( text, open, callee );   // `lookup("max-pods", default=64)` is no flag definition
    std::size_t nameArg = SIZE_MAX;
    for( std::size_t k = 0; k < args.size(); ++k )
    {
        nameArg = at >= args[k].first && at < args[k].second ? k : nameArg;
        if( const std::optional<std::string_view> kw = defines ? keywordDefaultOf( argText( k ) ) : std::nullopt )
        {
            return std::string( *kw );
        }
    }
    if( nameArg == SIZE_MAX || ( slot != FlagSlot::AfterName && slot != FlagSlot::AfterShorthand ) )
    {
        return {};
    }
    const std::size_t defArg = nameArg + ( slot == FlagSlot::AfterShorthand ? 2 : 1 );
    if( defArg + 1 >= args.size() )
    {
        return {};   // no argument after the default (the usage text): not the flag-set shape
    }
    const std::string_view d = argText( defArg );
    return isDefaultSlotText( d, defArg + 2 == args.size() ) ? std::string( d ) : std::string();
}

// FLAG-SHAPE-LIT: the field a default argument names (`c.MaxPods` -> MaxPods), or "": a dotted chain of identifiers whose last link is at least
// kForFlagMinName bytes. A literal, a call, a CONST word or a bare name is no field.
inline std::string_view defaultFieldOf( std::string_view def ) noexcept
{
    const std::size_t dot = def.rfind( '.' );
    if( dot == std::string_view::npos || dot == 0 || def.size() - dot - 1 < kForFlagMinName || std::isdigit( static_cast<unsigned char>( def.front() ) ) != 0 )
    {
        return {};
    }
    const bool chain = std::all_of( def.begin(), def.end(), []( char c ) { return namesplit::isIdentChar( c ) || c == '.' || c == '&' || c == '*'; } );
    const std::string_view f = def.substr( dot + 1 );
    return chain && std::isalpha( static_cast<unsigned char>( f.front() ) ) != 0 ? f : std::string_view();
}

// the text is ONE quoted literal: its closing quote (escapes skipped) is the last byte, so `"a" + input + "b"` is an expression
inline bool isOneQuotedLiteral( std::string_view v ) noexcept
{
    std::size_t close = 1;
    while( close < v.size() && v[close] != v.front() )
    {
        close += v[close] == '\\' ? 2 : 1;
    }
    return v.size() >= 2 && close == v.size() - 1;
}

// FLAG-SHAPE-LIT: the right side of an assignment is a constant: a number, a quoted string, true/false, a CONST word, or a name that says it is a
// default (`DefaultMaxPods`). A field or a call (`in.MaxPods`, `f()`) is not.
inline bool isConstantValue( std::string_view v ) noexcept
{
    v = trimWs( v );
    while( !v.empty() && ( v.back() == ',' || v.back() == ';' ) )
    {
        v = trimWs( v.substr( 0, v.size() - 1 ) );
    }
    if( v.empty() )
    {
        return false;
    }
    if( v.front() == '"' || v.front() == '\'' )
    {
        return isOneQuotedLiteral( v );
    }
    if( std::isdigit( static_cast<unsigned char>( v.front() ) ) != 0 || ( v.front() == '-' && v.size() > 1 && std::isdigit( static_cast<unsigned char>( v[1] ) ) != 0 ) )
    {
        return std::all_of( v.begin() + 1, v.end(), []( char c ) { return std::isalnum( static_cast<unsigned char>( c ) ) != 0 || c == '_' || c == '.'; } );
    }
    if( v == "true" || v == "false" || v == "True" || v == "False" )
    {
        return true;
    }
    const bool ident = std::all_of( v.begin(), v.end(), []( char c ) { return namesplit::isIdentChar( c ); } );
    return ident && ( isConstShaped( v ) || v.starts_with( "Default" ) || v.starts_with( "default" ) );
}

// FLAG-SHAPE-LIT: the assigned expression at the start of `rest` (the line after `=` or `:`): up to the first `;`, `//`, `/*` or ` #` outside a string, so a trailing
// comment or a second statement on the line does not hide a constant (`obj.MaxPods = 110 // default`)
inline std::string_view assignedExprOf( std::string_view rest ) noexcept
{
    char quote = 0;
    for( std::size_t i = 0; i < rest.size(); ++i )
    {
        const char c = rest[i];
        if( quote != 0 )
        {
            i += c == '\\' ? 1 : 0;
            quote = c == quote ? 0 : quote;
        }
        else if( c == '"' || c == '\'' || c == '`' )
        {
            quote = c;
        }
        else if( c == ';' || ( c == '/' && i + 1 < rest.size() && ( rest[i + 1] == '/' || rest[i + 1] == '*' ) ) || ( c == '#' && i > 0 && ( rest[i - 1] == ' ' || rest[i - 1] == '\t' ) ) )
        {
            return rest.substr( 0, i );
        }
    }
    return rest;
}

// FLAG-SHAPE-LIT: the line at `at` (a hit of `field`) writes a constant to the field: `x.F = <const>` (not `==`) or a struct-literal key `F: <const>`
inline bool isConstantWriteAt( std::string_view text, std::size_t at, std::size_t n ) noexcept
{
    if( at + n > text.size() || ( at + n < text.size() && namesplit::isIdentChar( text[at + n] ) ) )
    {
        return false;
    }
    const std::size_t ls  = at == 0 ? 0 : ( text.rfind( '\n', at - 1 ) == std::string_view::npos ? 0 : text.rfind( '\n', at - 1 ) + 1 );
    const std::size_t nl  = text.find( '\n', at );
    const std::string_view after = trimWs( text.substr( at + n, ( nl == std::string_view::npos ? text.size() : nl ) - at - n ) );
    const bool dotted = at > 0 && text[at - 1] == '.';
    if( dotted && after.starts_with( '=' ) && !after.starts_with( "==" ) )
    {
        return isConstantValue( assignedExprOf( after.substr( 1 ) ) );
    }
    const bool opensLine = trimWs( text.substr( ls, at - ls ) ).empty();
    if( opensLine && after.starts_with( ':' ) && !after.starts_with( "::" ) && !after.starts_with( ":=" ) )
    {
        return isConstantValue( assignedExprOf( after.substr( 1 ) ) );
    }
    return false;
}

using LineRange = std::pair<std::uint32_t, std::uint32_t>;   // inclusive, 1-based

// the excerpt of a body: its signature line `first` plus a window [site-before, site+after] per site line, clipped to
// [first, last], overlapping or touching windows merged; ascending and disjoint. `armHeads` (parallel to siteLines, 0 = none): a window
// starts there instead, at the head of the match arm or case that holds its site (armHeadAbove)
// the first line of site line `l`'s window: the arm head `head` above it when there is one (0 = none), else kForLiteralExcerptBefore up
inline std::uint32_t excerptWindowStart( std::uint32_t l, std::uint32_t head ) noexcept
{
    if( head > 0 && head < l )
    {
        return head;
    }
    return l > kForLiteralExcerptBefore ? l - kForLiteralExcerptBefore : 1u;
}

inline std::vector<LineRange> excerptRanges( const std::vector<std::uint32_t>& siteLines, std::uint32_t first, std::uint32_t last,
                                             const std::vector<std::uint32_t>& armHeads = {} )
{
    std::vector<LineRange> w{ LineRange{ first, first } };
    for( std::size_t i = 0; i < siteLines.size(); ++i )
    {
        const std::uint32_t l = siteLines[i];
        const std::uint32_t a = std::max( first, excerptWindowStart( l, i < armHeads.size() ? armHeads[i] : 0 ) );
        const std::uint32_t b = std::min( last, l + kForLiteralExcerptAfter );
        if( a <= b )
        {
            w.push_back( LineRange{ a, b } );
        }
    }
    std::sort( w.begin(), w.end() );
    std::vector<LineRange> merged;
    for( const LineRange& r : w )
    {
        if( !merged.empty() && r.first <= merged.back().second + 1 )
        {
            merged.back().second = std::max( merged.back().second, r.second );
        }
        else
        {
            merged.push_back( r );
        }
    }
    return merged;
}

// the byte offset where each line of `text` starts (line 1 at index 0)
inline std::vector<std::size_t> lineStartsOf( std::string_view text )
{
    const std::vector<std::uint32_t> breaks = lineBreaksOf( text );   // serialize.h: the newline offsets
    std::vector<std::size_t>         starts( breaks.size() + 1, 0 );
    std::transform( breaks.begin(), breaks.end(), starts.begin() + 1, []( std::uint32_t b ) { return std::size_t( b ) + 1; } );
    return starts;
}

// the lines of every range of `text`, each range newline-joined (the grep verb's own slicing core, search.h grepLineRangeText),
// the ranges joined by a line holding one ellipsis. `starts` = lineStartsOf( text ), computed once by a caller that also reads lines by number
inline std::string linesOfRangesAt( const std::string& text, const std::vector<LineRange>& ranges, const std::vector<std::size_t>& starts )
{
    const std::uint32_t count = grepRealLineCount( text, starts );
    std::string         out;
    for( const LineRange& r : ranges )
    {
        const std::uint32_t b = std::min( r.second, count );
        if( r.first < 1 || r.first > b )
        {
            continue;
        }
        out += out.empty() ? std::string_view() : std::string_view( "\n\xE2\x80\xA6\n" );
        out += grepLineRangeText( text, starts, count, r.first, b );
    }
    return out;
}
inline std::string linesOfRanges( const std::string& text, const std::vector<LineRange>& ranges )
{
    return linesOfRangesAt( text, ranges, lineStartsOf( text ) );
}

// cut every line of `lines` longer than `cap` bytes on a UTF-8 boundary (an ellipsis marks the cut); true when one was cut
inline bool capLineBytes( std::string& lines, std::size_t cap )
{
    if( lines.size() <= cap )
    {
        return false;
    }
    std::string out;
    bool        cut = false;
    for( std::size_t at = 0; at <= lines.size(); )
    {
        const std::size_t end  = std::min( lines.find( '\n', at ), lines.size() );
        std::string       line = lines.substr( at, end - at );
        cut                    = cut || line.size() > cap;
        truncateUtf8WithEllipsis( line, cap );
        out += line;
        out += end < lines.size() ? "\n" : "";
        at = end + 1;
    }
    if( cut )
    {
        lines = std::move( out );
    }
    return cut;
}

inline std::string rangesAttr( const std::vector<LineRange>& ranges )
{
    std::string out;
    for( const LineRange& r : ranges )
    {
        out += out.empty() ? "" : ",";
        out += std::to_string( r.first );
        if( r.second > r.first )
        {
            out += "-" + std::to_string( r.second );
        }
    }
    return out;
}
// BODY-ABOVE-CHECK (OS-6 finding 1): `head` (` l= p= n=`) stands in a <b> element of `served`, the body printed whole above. A hop row
// (`<h l= p= n=>`) or a fold's skip carries the same attributes and printed no body: it is no `body="above"` (rw-02 P1 said above for a body
// the answer never served). Neither is a <b truncated="1">, whose lines may stop before the site (a 115-line body cut at line 87).
inline bool servedBodyHead( std::string_view served, std::string_view head ) noexcept
{
    for( std::size_t at = served.find( head ); at != std::string_view::npos; at = served.find( head, at + 1 ) )
    {
        const std::size_t open  = served.rfind( '<', at );
        const std::size_t close = open == std::string_view::npos ? std::string_view::npos : served.find( '>', open );
        if( open != std::string_view::npos && served.substr( open, 3 ) == "<b " && close > at && close != std::string_view::npos
            && served.substr( open, close - open ).find( " truncated=\"1\"" ) == std::string_view::npos )
        {
            return true;   // a whole <b>; a truncated one (lines=1-87/115) may leave the site out, so this answer serves its own excerpt
        }
    }
    return false;
}

// EXCERPT-ARM: the line opens a match arm or a case of `lang` (allowlist): a Rust, C# or PHP `Pat => {` / `Pat =>` (its pattern's parens
// balanced, no assignment or declaration before the arrow: never a JS `x => {` callback), a `case X:` / `default:` (C, C++, Java, JS, TS, Go,
// C#, Swift, Python `match`), a Python `elif`/`else:`, a Ruby `when`/`elsif`/`else`, a C-family or Go `else if (...) {` / `} else {`. An `if`,
// a loop, a function or anything else is no arm.
inline bool isArmHead( std::string_view code, Lang lang ) noexcept
{
    const std::string_view t = trimWs( code );
    if( t.empty() )
    {
        return false;
    }
    const auto startsWord = [ & ]( std::string_view w ) { return t.starts_with( w ) && ( t.size() == w.size() || !namesplit::isIdentChar( t[w.size()] ) ); };
    const ArmOpeners  family = langFacts( lang ).armOpeners;
    const std::size_t arrow  = t.find( "=>" );
    if( family == ArmOpeners::FatArrow && arrow != std::string_view::npos && arrow > 0 && ( t.ends_with( "=>" ) || t.ends_with( "{" ) ) )
    {
        int depth = 0;
        for( std::size_t i = 0; i < arrow; ++i )
        {
            depth += t[i] == '(' || t[i] == '[' ? 1 : ( t[i] == ')' || t[i] == ']' ? -1 : 0 );
            const bool assign = t[i] == '=' && ( i == 0 || std::string_view( "=!<>" ).find( t[i - 1] ) == std::string_view::npos ) && ( i + 1 >= t.size() || t[i + 1] != '=' );
            if( depth < 0 || assign )
            {
                return false;
            }
        }
        return depth == 0 && !startsWord( "let" ) && !startsWord( "const" ) && !startsWord( "var" ) && !startsWord( "return" ) && !startsWord( "fn" ) && !startsWord( "pub" );
    }
    // `case X:`; a `case: {` is a JS or TS object key (no label has nothing between `case` and the colon)
    const bool caseLabel = startsWord( "case" ) && !trimWs( t.substr( 4 ) ).starts_with( ':' );
    if( ( caseLabel || startsWord( "default" ) ) && ( t.ends_with( ':' ) || t.ends_with( ": {" ) || t.ends_with( ":{" ) ) )
    {
        return true;
    }
    if( family == ArmOpeners::PythonElif )
    {
        return ( startsWord( "elif" ) || startsWord( "else" ) ) && t.ends_with( ':' );
    }
    if( family == ArmOpeners::RubyWhen )
    {
        return startsWord( "when" ) || startsWord( "elsif" ) || t == "else";
    }
    const std::string_view e = t.starts_with( '}' ) ? trimWs( t.substr( 1 ) ) : t;
    return ( e.starts_with( "else if" ) || e == "else {" || e == "else{" ) && t.ends_with( '{' );
}

// the `n` bytes at `p` of `t` stand as a whole identifier (not inside a longer one, not a member after a `.`)
inline bool wholeWordAt( std::string_view t, std::size_t p, std::size_t n ) noexcept
{
    return ( p == 0 || ( !namesplit::isIdentChar( t[p - 1] ) && t[p - 1] != '.' ) ) && ( p + n >= t.size() || !namesplit::isIdentChar( t[p + n] ) );
}
inline std::string_view lineAtNumber( const std::string& text, const std::vector<std::size_t>& starts, std::uint32_t l ) noexcept
{
    const std::size_t b = starts[l - 1];
    const std::size_t e = l < starts.size() ? starts[l] - 1 : text.size();
    return std::string_view( text ).substr( b, e > b ? e - b : 0 );
}

// the line `l` heads an arm of a block that a line above it opens with one of `words` (`switch`, `select`, `match`): the nearest line above (below `first`) that is
// less indented than `l`, or, with `aligned`, that stands at its indent and is no `case X:` / `default:` label of the same block (gofmt and many C++ styles align the
// labels with the `switch` header). A JS or TS object literal's `default: {` key (`return {`, `x = {`, `f({`) opens no such block.
inline bool opensBlockAbove( const std::string& text, const std::vector<std::size_t>& starts, std::uint32_t l, std::uint32_t first, std::span<const std::string_view> words, bool aligned )
{
    const std::size_t in = lintdetail::indentOf( lineAtNumber( text, starts, l ) );
    for( std::uint32_t k = l; k-- > first && k > 0; )
    {
        const std::string_view line = lineAtNumber( text, starts, k );
        const std::string_view t    = trimWs( line );
        if( t.empty() )
        {
            continue;
        }
        const std::size_t ind  = lintdetail::indentOf( line );
        const std::string_view code = openerCode( line );
        const auto has = [ & ]() { return std::any_of( words.begin(), words.end(), [ & ]( std::string_view w ) { return namesplit::containsWordBoundedBy( code, w, namesplit::isIdentChar ); } ); };
        if( ind < in )
        {
            return has();
        }
        if( aligned && ind == in )
        {
            const std::string_view c = trimWs( code );
            const auto word = [ & ]( std::string_view w ) { return c.starts_with( w ) && ( c.size() == w.size() || !namesplit::isIdentChar( c[w.size()] ) ); };
            const bool label = ( word( "case" ) && !trimWs( c.substr( 4 ) ).starts_with( ':' ) ) || ( word( "default" ) && c.ends_with( ':' ) );
            if( !label && has() )
            {
                return true;   // the `switch (x) {` header standing at the labels' own indent
            }
            // a label, a closing brace or a body line at the labels' indent: on up
        }
    }
    return false;
}

// the line `l` (the head `code` of an arm, per isArmHead) holds up as one: a `default:` needs a `switch` or `select` block above it (not a JS or TS object key), and a
// `pat => {` (Rust, C#, PHP) a `match` or `switch` block above it (a standalone `x => {` callback is no arm)
inline bool armHeadHoldsUp( const std::string& text, const std::vector<std::size_t>& starts, std::uint32_t l, std::uint32_t first, std::string_view code, Lang lang )
{
    static constexpr std::array<std::string_view, 2> kSwitchWords{ "switch", "select" };
    static constexpr std::array<std::string_view, 2> kMatchWords{ "match", "switch" };
    const std::string_view t = trimWs( code );
    if( t.starts_with( "default" ) )
    {
        return opensBlockAbove( text, starts, l, first, kSwitchWords, /*aligned=*/true );
    }
    return langFacts( lang ).armOpeners != ArmOpeners::FatArrow || t.find( "=>" ) == std::string_view::npos || opensBlockAbove( text, starts, l, first, kMatchWords, /*aligned=*/false );
}

// EXCERPT-ARM: the head line of the match arm or case that holds the site at `site` (1-based), when the window [site-1, ...] leaves it out
// and it stands at most kForLiteralArmLines lines up, below `first` (the signature); 0 otherwise. The walk climbs the lines that open a less
// indented block: one already inside the window is shown, so the walk goes on to the next (rw-02: an `else {` at site-1 inside the arm
// `(Table, Source) => {` seven lines up); the first one above the window must be an arm (isArmHead), anything else ends it with no widening.
inline std::uint32_t armHeadAbove( const std::string& text, const std::vector<std::size_t>& starts, std::uint32_t site, std::uint32_t first, Lang lang )
{
    const auto lineText = [ & ]( std::uint32_t l ) { return lineAtNumber( text, starts, l ); };
    if( site < 2 || site > starts.size() )
    {
        return 0;
    }
    const std::uint32_t windowStart = site > kForLiteralExcerptBefore ? site - kForLiteralExcerptBefore : 1u;
    std::size_t         cur         = lintdetail::indentOf( lineText( site ) );
    for( std::uint32_t l = site - 1; l > first && l + kForLiteralArmLines >= site; --l )
    {
        const std::string_view line = lineText( l );
        const std::string_view t    = trimWs( line );
        const std::size_t      in   = lintdetail::indentOf( line );
        if( t.empty() || in >= cur || openerWalkSkips( t ) )
        {
            continue;
        }
        cur = in;
        if( l >= windowStart )
        {
            continue;   // an opener the window already shows: the arm, if any, is further up
        }
        const std::string_view code = openerCode( line );
        return isArmHead( code, lang ) && armHeadHoldsUp( text, starts, l, first, code, lang ) ? l : 0;
    }
    return 0;
}

// <x> for the body [first, last] of `s` in `text`: the signature line and one window per site line (l= lists the ranges, of= the body,
// next= the whole body); arm="1" when a window starts at the head of the match arm or case holding its site (armHeadAbove)
inline std::string excerptElement( const std::string& text, const std::string& path, const Symbol& s, std::uint32_t first, std::uint32_t last,
                                   const std::vector<std::uint32_t>& siteLines, RedactCounts* redact, bool* armWidened = nullptr )
{
    std::vector<char>      esc;
    const std::vector<std::size_t> starts = lineStartsOf( text );   // once per body: armHeadAbove reads lines by number, linesOfRanges slices them
    std::vector<std::uint32_t> heads( siteLines.size(), 0 );
    bool                       widened = false;
    for( std::size_t i = 0; i < siteLines.size(); ++i )
    {
        heads[i] = armHeadAbove( text, starts, siteLines[i], first, s.lang );
        widened  = widened || heads[i] > 0;
    }
    const std::vector<LineRange> ranges = excerptRanges( siteLines, first, last, heads );
    std::string x = "<x p=\"";
    x += escapeXml( path, esc );
    x += "\" n=\"";
    x += escapeXml( s.name, esc );
    x += "\" l=\"" + rangesAttr( ranges ) + "\" of=\"" + std::to_string( first ) + "-" + std::to_string( last ) + "\"";
    x += widened ? " arm=\"1\"" : "";
    if( armWidened != nullptr )
    {
        *armWidened = *armWidened || widened;
    }
    // train 42b T-3: each window line is cut at kForLiteralLineBytes like an <ls> row (a minified one-line body printed 48.9 KB
    // whole); cut="1" says a line was cut, next= prints the whole body
    std::string lines = linesOfRangesAt( text, ranges, starts );
    redactInPlace( lines, redact );   // CR 4423843223: a window of raw source is a body-emission seam; redact BEFORE the cut so a key is never half-cut
    const bool  cut   = capLineBytes( lines, kForLiteralLineBytes );
    x += cut ? " cut=\"1\"" : "";
    x += nextAttrXml( nextFlag( "--expand=", path + ":" + std::to_string( s.line ) + ":" + s.name ) );
    x += "><![CDATA[";
    appendCdataSafe( lines, x );
    x += "]]></x>";
    return x;
}
}   // namespace lit_detail

// shape=table: what a later <lit> of one task inherits from the earlier ones
struct ForLiteralLimits
{
    std::size_t byteCap    = SIZE_MAX;   // element bytes left for rows and bodies
    bool        withLegend = true;       // only the first element of a task carries the legend comments
    bool        tableOnly  = false;      // TableCue::TableRowOnly: no table row, no block
    bool        cutLegendAbove = false;  // an earlier element of the task carries the lit_cut legend
    bool        tailKeysOnly   = false;  // the last part of a dotted name, tried after the name found nothing: only quoted-key rows and its definition are listed
    bool        strongOnly     = false;  // TableCue::StrongRowOnly: only registration calls, top-level macro/call rows and macro-table rows are listed (weak=)
    bool        tailLegendAbove = false; // an earlier element of the task carries the tail= legend
    bool        armLegendAbove  = false; // an earlier element of the task carries the arm= legend
    bool        subLegendAbove  = false; // an earlier element of the task carries the subscript reg= / lr legend
};

namespace lit_detail
{
// FLAG-SHAPE-LIT: the default a flag row names (def=, on row `row`) and the constant writes of the field it names (ld rows)
struct FlagDefault
{
    std::size_t row = SIZE_MAX;   // the row that carries def=; SIZE_MAX = none
    std::string text;             // def=, cut to kForFlagDefaultMaxBytes and redacted
    std::string writesXml;        // the <ld> rows, at most kForFlagWriteRows
    std::size_t writeCount = 0;   // writes=: every constant write read
    bool        writesFloor = false;   // the field's scan was partial or past kForFlagWriteHits: writes= is a floor
};

// one file's text at a time, read once per run of hits in it
struct OneFileText
{
    std::uint32_t file = UINT32_MAX;
    std::string   text;
    std::vector<std::size_t> starts;   // lineStartsOf( text ), built on first use per file
    bool          haveStarts = false;
    bool          useMemo    = true;    // the span-tier memo may be read and written (false under --no-cache)
    bool          curFailed  = false;   // the file now held could not be read
    bool          unread     = false;   // a read failed since last cleared: its empty text is "could not read", not "no hits"
    const std::string& of( const IngestResult& ing, std::uint32_t fileId )
    {
        if( file != fileId )
        {
            file       = fileId;
            haveStarts = false;
            std::optional<std::string> read = docparse::detail::readWholeFile( diskPath( ing, fileId ) );
            curFailed  = !read.has_value();
            text       = std::move( read ).value_or( std::string() );
        }
        unread = unread || curFailed;   // every use of a file that could not be read counts, not only the first
        return text;
    }
    const std::vector<std::size_t>& startsOfText()
    {
        if( !haveStarts )
        {
            starts     = lineStartsOf( text );
            haveStarts = true;
        }
        return starts;
    }
};

// the type spelling next to a name in a signature: after it (`c *kubeletconfig.Config`, `c: &mut Config`, `c Config`; `at` = the byte after the name) or
// before it (C++ and Java `const Config& c`; `at` = the name's first byte). The last segment of a qualified type; "" when nothing stands there.
// A word that stands between a name and its type (`mut`, `const`) or before a declared name (`var x`) is passed over.
inline std::string_view typeNextTo( std::string_view sig, std::size_t at, bool after ) noexcept
{
    static constexpr auto kNoise = std::to_array<std::string_view>( { "mut", "const", "struct", "dyn", "var", "let", "val", "static", "final", "pub", "auto", "func", "fn", "def" } );
    const auto            isRun  = []( char c ) { return namesplit::isIdentChar( c ) || c == '.' || c == ':'; };
    const std::string_view skip  = after ? std::string_view( " \t:*&[]" ) : std::string_view( " \t*&" );
    std::string_view       id;
    do
    {
        while( after ? at < sig.size() && skip.find( sig[at] ) != std::string_view::npos : at > 0 && skip.find( sig[at - 1] ) != std::string_view::npos )
        {
            after ? ++at : --at;
        }
        const std::size_t from = at;
        while( after ? at < sig.size() && isRun( sig[at] ) : at > 0 && isRun( sig[at - 1] ) )
        {
            after ? ++at : --at;
        }
        id = after ? sig.substr( from, at - from ) : sig.substr( at, from - at );
    } while( std::find( kNoise.begin(), kNoise.end(), id ) != kNoise.end() );
    const std::size_t k = id.find_last_of( ".:" );
    return k == std::string_view::npos ? id : id.substr( k + 1 );
}

// the type name of the parameter or receiver `name` in a signature; "" when it names none (an untyped parameter, a type shared by a list `a, b *T`)
inline std::string_view paramTypeIn( std::string_view sig, std::string_view name ) noexcept
{
    for( std::size_t p = sig.find( name ); !name.empty() && p != std::string_view::npos; p = sig.find( name, p + 1 ) )
    {
        if( !wholeWordAt( sig, p, name.size() ) )
        {
            continue;
        }
        for( const std::string_view type : { typeNextTo( sig, p + name.size(), true ), typeNextTo( sig, p, false ) } )
        {
            if( !type.empty() )
            {
                return type;
            }
        }
    }
    return {};
}

// the candidates that stand in code: a write in a comment or a string is no write (the span tier says which). A candidate in a file the span tier did not parse (or past
// kForLiteralTierFiles files) is kept and `floor` is set: the count is then not a verified total.
inline std::vector<GrepRawHit> codeWritesOf( const IngestResult& ing, const std::vector<GrepRawHit>& candidates, bool useMemo, bool& floor )
{
    std::vector<std::uint32_t> tierFiles;
    std::vector<std::string>   tierPaths;
    for( const GrepRawHit& r : candidates )
    {
        if( tierFiles.size() < kForLiteralTierFiles && std::find( tierFiles.begin(), tierFiles.end(), r.fileId ) == tierFiles.end() )
        {
            tierFiles.push_back( r.fileId );
            tierPaths.push_back( diskPath( ing, r.fileId ) );
        }
    }
    const SpanTierBatch     batch = spanTiersOfFiles( std::span<const std::string>( tierPaths ), useMemo );
    std::vector<GrepRawHit> writes;
    for( const GrepRawHit& r : candidates )
    {
        const std::size_t idx = std::size_t( std::find( tierFiles.begin(), tierFiles.end(), r.fileId ) - tierFiles.begin() );
        const bool        classified = idx < batch.perFile.size() && batch.perFile[idx].isParsed;
        const SpanTier    tier       = classified ? spanTierAt( batch.perFile[idx], r.byteOffset ) : SpanTier::Code;
        floor = floor || !classified;
        if( tier != SpanTier::Comment && tier != SpanTier::String )
        {
            writes.push_back( r );
        }
    }
    return writes;
}

// the source-tier constant writes of `field` (isConstantWriteAt), the scan's first kForFlagWriteHits hits, those in code (codeWritesOf); floor when the scan was cut or
// a candidate could not be classified
inline std::pair<std::vector<GrepRawHit>, bool> constantWritesOf( const IngestResult& ing, const std::string& field, OneFileText& files )
{
    const GrepCollection    fc    = grepCollect( ing, field, /*regex=*/false, /*noPrefilter=*/false );
    bool                    floor = !fc.cleanScan() || fc.raw.size() > kForFlagWriteHits;
    std::vector<GrepRawHit> candidates;
    for( std::size_t k = 0; k < fc.raw.size() && k < kForFlagWriteHits; ++k )
    {
        const GrepRawHit&      r = fc.raw[k];
        const std::string_view p = rootRelPath( ing, r.fileId );
        if( pathTierOf( p ) == PathTier::Source && !isBareWordCodePath( p ) && isConstantWriteAt( files.of( ing, r.fileId ), r.byteOffset, field.size() ) )
        {
            candidates.push_back( r );
        }
    }
    std::vector<GrepRawHit> writes = codeWritesOf( ing, candidates, files.useMemo, floor );
    return { std::move( writes ), floor };
}

// the order the write rows print in: a write in a function or file named for defaults first (SetDefaults_*, defaults.go), else scan order
inline std::vector<std::size_t> defaultsFirstOrder( const IngestResult& ing, const std::vector<GrepHit>& wh )
{
    std::vector<int> rank( wh.size() );   // computed once per row, not per comparison
    for( std::size_t k = 0; k < wh.size(); ++k )
    {
        std::string w = wh[k].enclosing + " " + std::string( rootRelPath( ing, wh[k].fileId ) );
        std::transform( w.begin(), w.end(), w.begin(), []( unsigned char c ) { return static_cast<char>( std::tolower( c ) ); } );
        rank[k] = w.find( "default" ) != std::string::npos ? 0 : 1;
    }
    std::vector<std::size_t> order( wh.size() );
    for( std::size_t k = 0; k < order.size(); ++k )
    {
        order[k] = k;
    }
    std::stable_sort( order.begin(), order.end(), [ & ]( std::size_t a, std::size_t b ) { return rank[a] < rank[b]; } );
    return order;
}

// one <ld p= l= in= ink=> row: the write's line, leading blanks dropped, redacted and cut to kForLiteralLineBytes
template <class RelPath>
inline void appendWriteRow( std::string& xml, const IngestResult& ing, const GrepHit& w, const RelPath& relPath, RedactCounts* redact, std::vector<char>& esc,
                            std::string_view tag = "ld" )
{
    xml.append( "<" ).append( tag ).append( " p=\"" );
    xml += escapeXml( relPath( w.fileId ), esc );
    xml += "\" l=\"" + std::to_string( w.line ) + "\"";
    if( w.enclosingId != kNoNode )
    {
        xml += " in=\"";
        xml += escapeXml( w.enclosing, esc );
        xml += "\" ink=\"";
        xml += symTag( ing.symbols[w.enclosingId].kind );
        xml += "\"";
    }
    const std::size_t lead = w.text.find_first_not_of( " \t" );
    std::string       line = lead == std::string::npos ? std::string() : w.text.substr( lead );
    redactInPlace( line, redact );
    truncateUtf8WithEllipsis( line, kForLiteralLineBytes );
    xml += "><![CDATA[";
    appendCdataSafe( line, xml );
    xml.append( "]]></" ).append( tag ).push_back( '>' );
}

// the owner of the field `def` names (`c.MaxPods`), as a name the code around its writes spells: the type of the receiver `c` in the signature of the
// function holding the flag row (`c *kubeletconfig.Config` -> Config), else for a package-level variable `config` its declared type, else its own name
// (an anonymous struct's declaration spells it); "" when nothing says (no enclosing function, an untyped parameter, a chain `a.b.F`, `this`/`self`)
inline std::string ownerTypeOf( const IngestResult& ing, const GrepHit& row, std::string_view def, OneFileText& files )
{
    while( !def.empty() && ( def.front() == '&' || def.front() == '*' ) )
    {
        def.remove_prefix( 1 );
    }
    const std::size_t dot = def.rfind( '.' );
    if( dot == std::string_view::npos || row.enclosingId == kNoNode )
    {
        return {};
    }
    const std::string_view recv = def.substr( 0, dot );
    if( !std::all_of( recv.begin(), recv.end(), []( char c ) { return namesplit::isIdentChar( c ); } ) )
    {
        return {};
    }
    const auto sigTypeOf = [ & ]( const Symbol& s ) -> std::string
    {
        const std::string& t = files.of( ing, s.fileId );
        return s.sigStartByte < s.sigEndByte && s.sigEndByte <= t.size() ? std::string( paramTypeIn( std::string_view( t ).substr( s.sigStartByte, s.sigEndByte - s.sigStartByte ), recv ) ) : std::string();
    };
    if( std::string type = sigTypeOf( ing.symbols[row.enclosingId] ); !type.empty() )
    {
        return type;
    }
    const auto var = std::find_if( ing.symbols.begin(), ing.symbols.end(), [ & ]( const Symbol& s ) { return s.kind == SymKind::Var && s.name == recv; } );
    if( var == ing.symbols.end() || recv.size() < kForFlagMinName )
    {
        return {};
    }
    std::string type = sigTypeOf( *var );
    return type.empty() ? std::string( recv ) : type;
}

// the write `w` belongs to the owner type: the function holding it names the type (signature or body), or, outside any function, one of the
// kForFlagOwnerMaxLines lines above it does (a struct literal `Config{`). A name match: no type check.
inline bool writeNamesOwner( const IngestResult& ing, const GrepHit& w, std::string_view type, OneFileText& files )
{
    const std::string& t = files.of( ing, w.fileId );
    if( w.enclosingId != kNoNode )
    {
        const Symbol& s = ing.symbols[w.enclosingId];
        return s.fileId == w.fileId && s.sigStartByte < s.endByte && s.endByte <= t.size() && namesplit::containsWordBoundedBy( std::string_view( t ).substr( s.sigStartByte, s.endByte - s.sigStartByte ), type, namesplit::isIdentChar );
    }
    const std::vector<std::size_t>& starts = files.startsOfText();
    if( w.line < 1 || w.line > starts.size() )
    {
        return false;
    }
    const std::size_t lo = starts[w.line > kForFlagOwnerMaxLines ? w.line - 1 - kForFlagOwnerMaxLines : 0];
    const std::size_t hi = w.line < starts.size() ? starts[w.line] : t.size();
    return namesplit::containsWordBoundedBy( std::string_view( t ).substr( lo, hi - lo ), type, namesplit::isIdentChar );
}

// the first of `hits` (the shown rows, `rows` parallel) that is no comment and whose call names a default (flagDefaultAt), and when that default names a
// field (defaultFieldOf) of a receiver whose type is known (ownerTypeOf), the field's constant writes in code that names that type
template <class RelPath>
inline FlagDefault flagDefaultOfRows( const IngestResult& ing, const std::vector<Site>& rows, const std::vector<GrepHit>& hits, const RelPath& relPath,
                                      RedactCounts* redact, std::vector<char>& esc, bool useMemo )
{
    FlagDefault out;
    OneFileText files;
    files.useMemo = useMemo;
    for( std::size_t i = 0; i < hits.size() && out.row == SIZE_MAX; ++i )
    {
        if( rows[i].k != 'c' )
        {
            out.text = flagDefaultAt( files.of( ing, rows[i].raw.fileId ), rows[i].raw.byteOffset );
            out.row  = out.text.empty() ? SIZE_MAX : i;
        }
    }
    redactInPlace( out.text, redact );   // before the cut: a key is never half-cut
    const std::string field( defaultFieldOf( out.text ) );
    const std::string owner = field.empty() ? std::string() : ownerTypeOf( ing, hits[out.row], out.text, files );
    out.writesFloor = !field.empty() && owner.empty();   // def= names a field whose receiver type is unknown: no write scan ran, so writes="0" is not a total
    if( !owner.empty() )
    {
        files.unread            = false;
        auto [ writes, floor ]  = constantWritesOf( ing, field, files );
        out.writesFloor         = floor;
        std::vector<GrepHit> wh = grepEnrich( ing, std::span<const GrepRawHit>( writes ) );
        wh.erase( std::remove_if( wh.begin(), wh.end(), [ & ]( const GrepHit& w ) { return !writeNamesOwner( ing, w, owner, files ); } ), wh.end() );
        out.writesFloor = out.writesFloor || files.unread;   // a write file that could not be read again is an omitted write
        out.writeCount                       = wh.size();
        const std::vector<std::size_t> order = defaultsFirstOrder( ing, wh );
        for( std::size_t k = 0; k < order.size() && k < kForFlagWriteRows; ++k )
        {
            appendWriteRow( out.writesXml, ing, wh[order[k]], relPath, redact, esc );
        }
    }
    truncateUtf8WithEllipsis( out.text, kForFlagDefaultMaxBytes );
    return out;
}

// REG-READER (b): `name` at `at` of `line` reads the table: `name[k]` that is not the left side of `=`, or `name.get(` / `name.Get(`. A longer name or a
// field of another receiver (`p.storage[`) is not this table.
inline bool readsTableAt( std::string_view line, std::size_t at, std::string_view name ) noexcept
{
    if( at > 0 && ( taskroute::wordByte( line[at - 1] ) || line[at - 1] == '.' || line[at - 1] == '>' || line[at - 1] == ':' ) )
    {
        return false;
    }
    const std::size_t      after = at + name.size();
    const std::string_view rest  = line.substr( after );
    if( rest.starts_with( ".get(" ) || rest.starts_with( ".Get(" ) )
    {
        return true;
    }
    if( rest.empty() || rest.front() != '[' )
    {
        return false;
    }
    const std::size_t close = bracketCloseOf( line, after );
    if( close == std::string_view::npos )
    {
        return false;
    }
    const std::size_t j = line.find_first_not_of( " \t", close + 1 );
    return !( j != std::string_view::npos && line[j] == '=' && ( j + 1 >= line.size() || line[j + 1] != '=' ) );
}

// `v` (an assigned value, `await` aside) IS a call of `fn`: a receiver chain (`p.`, `self->`, `ns::`) and then `fn(`
inline bool valueIsCallOf( std::string_view v, std::string_view fn ) noexcept
{
    v = v.starts_with( "await " ) ? trimWs( v.substr( 6 ) ) : v;
    while( !v.empty() && std::isdigit( static_cast<unsigned char>( v.front() ) ) == 0 )
    {
        const std::string_view run  = taskroute::identifierRunOf( v );
        const std::string_view rest = v.substr( run.size() );
        if( run.empty() || ( run == fn && trimWs( rest ).starts_with( "(" ) ) )
        {
            return !run.empty();
        }
        const std::size_t sep = rest.starts_with( "->" ) || rest.starts_with( "::" ) ? 2 : ( rest.starts_with( "." ) ? 1 : 0 );
        if( sep == 0 )
        {
            return false;
        }
        v = rest.substr( sep );
    }
    return false;
}

// a line's statement with a leading declaration word (`const`, `let`, `var`, `auto`, `final`, `val`) stepped over: the declared name comes first
inline std::string_view pastDeclWord( std::string_view t ) noexcept
{
    static constexpr std::array<std::string_view, 6> kDeclWords{ "auto", "const", "final", "let", "val", "var" };
    const std::string_view                           word = taskroute::identifierRunOf( t );
    const bool decl = std::find( kDeclWords.begin(), kDeclWords.end(), word ) != kDeclWords.end() && word.size() < t.size() && ( t[word.size()] == ' ' || t[word.size()] == '\t' );
    return decl ? trimWs( t.substr( word.size() ) ) : t;
}

// a caller's local that holds what the builder returns: `s := p.NewRESTStorage(`, `s, err := NewX(`, `s = await register_x(`, `const s = registerX(`; "" when the
// line is none. The call must BE the assigned value (a receiver chain before it, `await` aside): `s = choose(NewX())` binds what choose returns, not the table.
inline std::string_view boundToCallOf( std::string_view line, std::string_view fn ) noexcept
{
    const std::string_view t    = pastDeclWord( trimWs( line ) );
    const std::string_view name = taskroute::identifierRunOf( t );
    std::size_t            i    = name.size();
    while( i < t.size() && ( t[i] == ' ' || t[i] == ',' || taskroute::wordByte( t[i] ) ) )
    {
        ++i;   // `s, err` before the assignment
    }
    const std::size_t op = t.substr( i ).starts_with( ":=" ) ? 2 : ( i < t.size() && t[i] == '=' && ( i + 1 >= t.size() || t[i + 1] != '=' ) ? 1 : 0 );
    return !name.empty() && op != 0 && !fn.empty() && valueIsCallOf( trimWs( t.substr( i + op ) ), fn ) ? name : std::string_view();
}

// the quoted parts of a computed key (`resource+"/log"` -> "/log"), which a reader's literal key shares
inline std::vector<std::string_view> quotedPartsOf( std::string_view key )
{
    std::vector<std::string_view> out;
    for( std::size_t i = 0; i < key.size(); ++i )
    {
        const char q = key[i];
        if( q != '"' && q != '\'' )
        {
            continue;
        }
        const std::size_t e = key.find( q, i + 1 );
        if( e == std::string_view::npos )
        {
            break;
        }
        if( e > i + 1 )
        {
            out.push_back( key.substr( i + 1, e - i - 1 ) );
        }
        i = e;
    }
    return out;
}

struct TableReaders
{
    std::string xml;            // the <lr> rows, at most kForTableReaderRows
    std::size_t count = 0;      // readers=: every read found in the files read
    bool        floor = false;  // a file could not be read, or callers past kForTableReaderFiles were not read: readers= is a floor
};

// REG-READER (b): the files a subscript row's table may be read in: the row's own, then the files of its function's callers by path, at most
// kForTableReaderFiles of them (`floor` when more were left)
inline std::vector<std::uint32_t> readerFilesOf( const IngestResult& ing, const Graph* g, NodeId owner, std::uint32_t rowFile, bool& floor )
{
    std::vector<std::uint32_t> files{ rowFile };
    if( g == nullptr || std::size_t( owner ) >= g->inEdges.rows() )
    {
        floor = true;   // no graph to find the callers on: their files went unread, so readers= cannot be a total
        return files;
    }
    const auto*                ro = g->inEdges.rowOffsets();
    const auto*                ci = g->inEdges.colIndices();
    std::vector<std::uint32_t> callerFiles;
    for( std::uint32_t e = ro[owner]; e < ro[owner + 1]; ++e )
    {
        callerFiles.push_back( ing.symbols[ci[e]].fileId );
    }
    std::sort( callerFiles.begin(), callerFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return std::tie( ing.files[a], a ) < std::tie( ing.files[b], b ); } );
    callerFiles.erase( std::unique( callerFiles.begin(), callerFiles.end() ), callerFiles.end() );
    callerFiles.erase( std::remove( callerFiles.begin(), callerFiles.end(), rowFile ), callerFiles.end() );
    floor = callerFiles.size() > kForTableReaderFiles;
    files.insert( files.end(), callerFiles.begin(), callerFiles.begin() + std::ptrdiff_t( std::min( callerFiles.size(), kForTableReaderFiles ) ) );
    return files;
}

// the first read of any of `names` on `line` at or past `from` (npos: none): a walk over the line's identifier runs, each run that is a name tried as a read
inline std::size_t tableReadOnLine( std::string_view line, const std::vector<std::string>& names, std::size_t from = 0 ) noexcept
{
    std::size_t i = from;
    while( i < line.size() )
    {
        const std::size_t run = taskroute::identifierRunOf( line.substr( i ) ).size();
        if( run == 0 )
        {
            ++i;
            continue;
        }
        const std::string_view from = line.substr( i );   // a name may be a chain (`self._handlers`, `hass.data[DOMAIN]`)
        if( std::any_of( names.begin(), names.end(), [ & ]( const std::string& n ) { return from.starts_with( n ) && readsTableAt( line, i, n ); } ) )
        {
            return i;
        }
        i += run;
    }
    return std::string_view::npos;
}

// the reads of `names` on the line at byte `ls` that stand in code (a comment or a string holds none), each one added to `count` (`consume(t[a], t[b])` is
// two); the first one's offset in the line, or npos
inline std::size_t codeReadsOnLine( std::string_view line, std::size_t ls, const std::vector<std::string>& names, const SpanTierMap& tiers, std::size_t& count ) noexcept
{
    std::size_t first = std::string_view::npos;
    for( std::size_t at = tableReadOnLine( line, names ); at != std::string_view::npos; at = tableReadOnLine( line, names, at + 1 ) )
    {
        const SpanTier tier = spanTierAt( tiers, std::uint32_t( ls + at ) );
        if( tier != SpanTier::Comment && tier != SpanTier::String )
        {
            ++count;
            first = std::min( first, at );
        }
    }
    return first;
}

// one file's reads of the table (a local bound to the call of `fn` reads it too, in the writer's file as in a caller's), the reads in a comment or a string
// (`tiers`) left out: every read is counted in `count`, and each line holding one is a row, with 0 when the line shares a quoted part of the key
inline void tableReadsInFile( std::string_view text, std::uint32_t fileId, const SpanTierMap& tiers, std::string_view fn, const std::string& table,
                              std::span<const std::string_view> parts, std::vector<std::pair<int, GrepRawHit>>& found, std::size_t& count )
{
    std::vector<std::string> names{ table };
    std::uint32_t            lineNo = 1;
    for( std::size_t ls = 0; ls < text.size(); ++lineNo )
    {
        const std::size_t      le    = std::min( text.find( '\n', ls ), text.size() );
        const std::string_view line  = text.substr( ls, le - ls );
        const std::string_view bound = boundToCallOf( line, fn );
        if( !bound.empty() && std::find( names.begin(), names.end(), bound ) == names.end() )
        {
            names.emplace_back( bound );
        }
        const std::size_t first = codeReadsOnLine( line, ls, names, tiers, count );
        if( first != std::string_view::npos )
        {
            const bool shares = std::any_of( parts.begin(), parts.end(), [ & ]( std::string_view p ) { return line.find( p ) != std::string_view::npos; } );
            found.emplace_back( shares ? 0 : 1, GrepRawHit{ fileId, lineNo, std::uint32_t( ls + first ) } );
        }
        ls = le + 1;
    }
}

// the answer above the block names `table`: raw in a CDATA body, or escaped in an attribute (`p-&gt;storage` in a signature)
inline bool answerNamesTable( std::string_view served, const std::string& table, std::vector<char>& esc )
{
    const std::string escaped( escapeXml( table, esc ) );
    return taskHasCue( served, std::array<DocNoiseCue, 1>{ DocNoiseCue{ table, false } } )
           || ( escaped != table && taskHasCue( served, std::array<DocNoiseCue, 1>{ DocNoiseCue{ escaped, false } } ) );
}

// the reads of `table` in `files` (each read once, its comment/string spans from the span tier: a file it did not parse keeps every read); `out.count` counts
// them, `out.floor` is set when a file could not be read
inline std::vector<std::pair<int, GrepRawHit>> tableReadsInFiles( const IngestResult& ing, const std::vector<std::uint32_t>& files, bool useMemo, std::string_view fn,
                                                                  const std::string& table, std::span<const std::string_view> parts, TableReaders& out )
{
    std::vector<std::string> paths;
    for( const std::uint32_t f : files )
    {
        paths.push_back( diskPath( ing, f ) );
    }
    const SpanTierBatch                     tiers = spanTiersOfFiles( std::span<const std::string>( paths ), useMemo );
    const SpanTierMap                       unparsed;   // Code everywhere: a read is kept where the tier is unknown
    std::vector<std::pair<int, GrepRawHit>> found;
    for( std::size_t f = 0; f < files.size(); ++f )
    {
        const std::optional<std::string> read = docparse::detail::readWholeFile( paths[f] );
        out.floor                            = out.floor || !read.has_value();
        tableReadsInFile( read ? std::string_view( *read ) : std::string_view(), files[f], f < tiers.perFile.size() ? tiers.perFile[f] : unparsed, fn, table, parts, found,
                          out.count );
    }
    return found;
}

// REG-READER (b): the reads of the table the first shown subscript row writes, in the row's file and the files of its function's callers. Only for a table the
// answer above the block already names (`served`): elsewhere the block keeps its bytes. Reads whose line shares a quoted part of the written key come
// first, then file (the row's own, then callers' by path) and line order.
template <class RelPath>
inline TableReaders tableReadersOf( const IngestResult& ing, const Graph* g, const std::vector<Site>& rows, const std::vector<GrepHit>& hits, std::size_t shown,
                                    std::string_view served, const RelPath& relPath, RedactCounts* redact, std::vector<char>& esc, bool useMemo )
{
    TableReaders out;
    std::size_t  pick = 0;
    while( pick < shown && !( rows[pick].subscript && hits[pick].enclosingId != kNoNode && answerNamesTable( served, rows[pick].table, esc ) ) )
    {
        ++pick;
    }
    if( pick >= shown )
    {
        return out;
    }
    const Site&                         row   = rows[pick];
    const std::string&                  name  = ing.symbols[hits[pick].enclosingId].name;
    const std::size_t                   dot   = name.find_last_of( ".:" );   // npos + 1 would wrap (-fsanitize=integer)
    const std::string_view              fn    = std::string_view( name ).substr( dot == std::string::npos ? 0 : dot + 1 );
    const std::vector<std::uint32_t>    files = readerFilesOf( ing, g, hits[pick].enclosingId, row.raw.fileId, out.floor );
    const std::vector<std::string_view> parts = quotedPartsOf( std::string_view( row.tbl ).substr( row.table.size() ) );
    std::vector<std::pair<int, GrepRawHit>> found = tableReadsInFiles( ing, files, useMemo, fn, row.table, parts, out );
    std::stable_sort( found.begin(), found.end(), []( const auto& a, const auto& b ) { return a.first < b.first; } );
    std::vector<GrepRawHit> raw;
    for( std::size_t k = 0; k < found.size() && k < kForTableReaderRows; ++k )
    {
        raw.push_back( found[k].second );
    }
    for( const GrepHit& h : grepEnrich( ing, std::span<const GrepRawHit>( raw ) ) )
    {
        appendWriteRow( out.xml, ing, h, relPath, redact, esc, "lr" );
    }
    return out;
}
}   // namespace lit_detail

// THE BLOCK. `served` = the answer's own bytes after <sigs> (bodies, fold, slot, hops): a body whose <b … l= p= n=> head is in it
// is not printed again. `useMemo` = the span-tier memo (false under --no-cache). `compactLegend` = the default --legend=compact dialect.
inline ForLiteralRender renderForLiteral( const IngestResult& ing, const ForLiteral& lit, std::string_view rootArg, std::string_view served,
                                          RedactCounts* redact, bool useMemo, bool compactLegend, const ForLiteralLimits& limits = {},
                                          const LitAnchors& anchors = {} )
{
    ForLiteralRender out;
    if( lit.text.empty() || ing.files.empty() )
    {
        return out;
    }
    const GrepCollection collected = grepCollect( ing, lit.text, /*regex=*/false, /*noPrefilter=*/false );
    if( collected.raw.empty() )
    {
        return out;   // nothing found: no claim (a partial index cannot prove the literal unused)
    }
    const std::string rootPrefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    const auto relPath = [ & ]( std::uint32_t f ) -> std::string
    {
        return rootArg.empty() ? std::string( ing.files[f] ) : std::string( rw::sarif::rootRelativeUri( ing.files[f], rootPrefix ) );
    };
    // ── path tiers, then the span tier of every source hit file (bounded, in the scan's order: classified files first) ─────────
    const lit_detail::LitPolicy policy = lit_detail::litPolicyOf( lit.shape );
    std::uint32_t loadedFile = UINT32_MAX;
    std::string   loadedText;
    const auto loadFile = [ & ]( std::uint32_t fileId )
    {
        if( loadedFile != fileId )
        {
            loadedFile = fileId;
            loadedText = docparse::detail::readWholeFile( diskPath( ing, fileId ) ).value_or( std::string() );
        }
    };
    std::size_t testHits = 0, docHits = 0, commentHits = 0, longerHits = 0, mentionHits = 0;
    std::vector<lit_detail::Site> src;
    std::vector<std::uint32_t>    srcFiles;
    for( const GrepRawHit& r : collected.raw )
    {
        const std::string_view p = rootRelPath( ing, r.fileId );
        const PathTier         t = pathTierOf( p );
        if( t == PathTier::TestOrBench )
        {
            ++testHits;
        }
        else if( t == PathTier::Doc || isBareWordCodePath( p ) )
        {
            ++docHits;
        }
        else
        {
            lit_detail::KeyHit keyHit;
            if( policy.boundary != lit_detail::LitBoundary::None )
            {
                loadFile( r.fileId );
                keyHit = lit_detail::literalHitAt( policy.boundary, loadedText, r.byteOffset, lit.text.size() );
                if( policy.boundary == lit_detail::LitBoundary::Flag && !keyHit.quoted )
                {
                    ++mentionHits;   // shape=flag: not the whole quoted name (usage text, a longer flag): a mention, counted, never a row
                    continue;
                }
                if( keyHit.longer
                    && !( policy.tableRows && lit_detail::isArgumentName( loadedText, r.byteOffset, lit.text.size() )
                          && !lit_detail::registrationCallOf( loadedText, r.byteOffset, lit_detail::regLangCtxOf( langOfPath( ing.files[r.fileId] ) ) ).empty() ) )
                {
                    ++longerHits;
                    continue;
                }
            }
            if( srcFiles.empty() || srcFiles.back() != r.fileId )
            {
                srcFiles.push_back( r.fileId );
            }
            src.push_back( lit_detail::Site{ r, '?', keyHit.quoted, {}, keyHit.longer } );
        }
    }
    std::vector<std::string> tierPaths;
    for( std::size_t i = 0; i < srcFiles.size() && i < kForLiteralTierFiles; ++i )
    {
        tierPaths.push_back( diskPath( ing, srcFiles[i] ) );
    }
    const SpanTierBatch batch = spanTiersOfFiles( std::span<const std::string>( tierPaths ), useMemo );
    std::vector<lit_detail::Site> rows;
    bool anyUnclassified = false;   // CR (train 42b harvest): a source site the span tier never saw is invisible to comment=, which is then a floor
    for( lit_detail::Site& s : src )
    {
        std::size_t idx = SIZE_MAX;
        for( std::size_t i = 0; i < tierPaths.size(); ++i )
        {
            if( srcFiles[i] == s.raw.fileId )
            {
                idx = i;
                break;
            }
        }
        if( idx != SIZE_MAX && idx < batch.perFile.size() && batch.perFile[idx].isParsed )
        {
            const SpanTierMap& m = batch.perFile[idx];
            const SpanTier     t = spanTierAt( m, s.raw.byteOffset );
            if( t == SpanTier::Comment )
            {
                ++commentHits;
                continue;
            }
            if( t == SpanTier::String && langFacts( langOfPath( ing.files[s.raw.fileId] ) ).leadingDocstring )
            {
                // a Python docstring (the first statement of a module / class / def body): documentation, counted with the comments
                const auto        it    = std::upper_bound( m.startByte.begin(), m.startByte.end(), s.raw.byteOffset );
                const std::size_t start = it == m.startByte.begin() ? 0 : m.startByte[std::size_t( it - m.startByte.begin() ) - 1];
                loadFile( s.raw.fileId );
                if( lit_detail::isPythonDocstringAt( loadedText, start ) )
                {
                    ++commentHits;
                    continue;
                }
            }
            s.k = t == SpanTier::String ? 's' : 'c';
            if( s.k == 's' )
            {
                loadFile( s.raw.fileId );
                const std::size_t nl   = s.raw.byteOffset == 0 ? std::string::npos : loadedText.rfind( '\n', s.raw.byteOffset - 1 );
                const std::size_t lead = loadedText.find_first_not_of( " \t", nl == std::string::npos ? 0 : nl + 1 );
                s.leadInString         = lead != std::string::npos && spanTierAt( m, std::uint32_t( lead ) ) == SpanTier::String;
            }
        }
        else
        {
            anyUnclassified = true;   // past kForLiteralTierFiles, or a file the span tier did not parse: k="?"
        }
        rows.push_back( s );
    }
    // one row per source LINE (a line holding the literal twice is one site), enriched for its owner, then ordered: sites inside a
    // function or method first, string before code before unclassified, the scan's own order within each class
    std::vector<GrepRawHit> all;
    {
        std::vector<lit_detail::Site> lines;
        for( const lit_detail::Site& r : rows )
        {
            if( lines.empty() || lines.back().raw.fileId != r.raw.fileId || lines.back().raw.line != r.raw.line )
            {
                lines.push_back( r );
            }
            else
            {
                lines.back().k = r.k == 's' ? 's' : lines.back().k;
                if( policy.tableRows && lines.back().more.size() < kForRegLineHits )
                {
                    lines.back().more.push_back( r.raw.byteOffset );   // a later hit of the line may be the registration's argument (`h.register(h)`)
                }
            }
            if( lines.back().raw.fileId == r.raw.fileId && lines.back().raw.line == r.raw.line )
            {
                lines.back().quotedKey = lines.back().quotedKey || r.quotedKey;
                lines.back().longer    = lines.back().longer && r.longer;   // one whole-word hit makes the line a whole-word site
            }
        }
        rows = std::move( lines );
    }
    if( policy.dropCode )
    {
        lit_detail::dropCodeRows( rows );   // a code row is never printed (all code: no block)
    }
    out.sites = rows.size();
    // MSG-VERBATIM counts confirmed string sites only (CR 4540061404): a k='?' row (span tier unparsed) may be code or a comment
    const std::size_t verbatimStrings = lit.verbatim ? std::size_t( std::ranges::count( rows, 's', &lit_detail::Site::k ) ) : 0;
    if( ( lit.bare && rows.size() > kForBareFlagMaxSites ) || ( lit.verbatim && ( verbatimStrings == 0 || verbatimStrings > kForVerbatimMaxSites ) ) )
    {
        return ForLiteralRender{};   // WHOLE-TOKEN / MSG-VERBATIM: too many sites to be the one option or message the task names
    }
    if( rows.empty() )
    {
        return out;   // no source site: nothing to anchor on (test/doc/comment counts alone answer nothing; measured as noise, ld2-django-09)
    }
    std::size_t ranked = std::min( rows.size(), policy.rankedRows );
    for( std::size_t i = 0; i < ranked; ++i )
    {
        all.push_back( rows[i].raw );
    }
    std::vector<GrepHit> enriched = grepEnrich( ing, std::span<const GrepRawHit>( all ) );
    ASSUME( enriched.size() == all.size(), "grepEnrich returns one row per windowed hit" );
    std::size_t tailDropped = 0;   // limits.tailKeysOnly: sites of the tail that are no quoted key and no definition, not listed
    std::size_t weakDropped = 0;   // limits.strongOnly: read sites that are no strong row, not listed (weak=)
    std::size_t readSites   = 0;   // shape=table: the source sites read for a table row (read= when fewer than src=)
    if( policy.tableRows )
    {
        const bool anyMarked = lit_detail::markTableRows( ing, rows, enriched, loadFile, loadedText, longerHits );
        const bool keysOk    = !limits.tailKeysOnly || lit_detail::keepTailKeyRows( ing, lit.text, rows, enriched, tailDropped );
        const bool anyRow    = keysOk && ( limits.tailKeysOnly ? std::any_of( rows.begin(), rows.begin() + std::ptrdiff_t( enriched.size() ), []( const lit_detail::Site& r ) { return !r.tbl.empty(); } ) : anyMarked );
        ranked    = enriched.size();
        readSites = ranked;
        out.sites = rows.size();
        if( keysOk && anyRow && limits.strongOnly )
        {
            std::vector<char> weak( enriched.size(), 0 );   // G-STORED-B: no cue word, so only the strong rows are listed; the rest is weak=
            for( std::size_t i = 0; i < weak.size(); ++i )
            {
                weak[i] = lit_detail::isStrongRow( rows[i] ) ? 0 : 1;
            }
            weakDropped = lit_detail::dropRows( rows, enriched, weak );
            ranked      = enriched.size();
        }
        if( !keysOk || ranked == 0 || ( !anyRow && limits.tableOnly ) )
        {
            ForLiteralRender none;
            none.unread = out.sites > readSites;   // the sites past the cap were not read: the caller says so
            return none;
        }
    }
    std::vector<std::size_t> order( enriched.size() );
    for( std::size_t i = 0; i < order.size(); ++i )
    {
        order[i] = i;
    }
    const auto rankSite = [ & ]( std::size_t i )
    {
        const bool callable = enriched[i].enclosingId != kNoNode && ReceiverEvidence::callableKind( ing.symbols[enriched[i].enclosingId].kind );
        const std::string_view path = rootRelPath( ing, rows[i].raw.fileId );
        return ( policy.tableRows && ( lit_detail::isSecondaryPath( path ) || lit_detail::isGeneratedOrDataPath( path ) ) ? 6 : 0 ) + ( policy.tableRows && rows[i].tbl.empty() ? 12 : 0 ) + ( policy.boundary == lit_detail::LitBoundary::Key && !rows[i].quotedKey ? 6 : 0 ) + ( callable != policy.tableRows ? 0 : 3 ) + ( rows[i].k == 's' ? 0 : ( rows[i].k == 'c' ? 1 : 2 ) );
    };
    std::vector<int> rank( enriched.size() );   // hoisted out of the comparators: each site's path scans run once (rv-reg2 F7)
    for( std::size_t i = 0; i < rank.size(); ++i )
    {
        rank[i] = rankSite( i );
    }
    // LIT-SITE-DECOY: nearness to the answer above the block (its rows and bodies, and the literal's own definitions) orders the sites and,
    // when they do not all fit, cuts the far ones (lit_cut=). A CI, vendored or generated copy is never a row beside a product site.
    // the registrations the reserve keeps (pickRows: kForLiteralRegistrationRows quoted keys outside any function, property keys first, in rank
    // order) are never cut, so a far registration still holds its slot (rv-lit-site F3: cockroach-05's settings registry)
    std::vector<char> reserved( enriched.size(), 0 );
    if( policy.reserve > 0 )
    {
        std::vector<std::pair<int, std::size_t>> marked;   // (-mark, rank), site
        std::vector<std::size_t>                 at;
        for( std::size_t i = 0; i < enriched.size(); ++i )
        {
            const char m = lit_detail::registrationMark( ing, rows[i], enriched[i].enclosingId, enriched[i].text, lit.text );
            if( m > 0 )
            {
                marked.emplace_back( -int( m ) * 1000 + rank[i], i );
            }
        }
        std::ranges::stable_sort( marked, {}, &std::pair<int, std::size_t>::first );
        for( std::size_t k = 0; k < marked.size() && k < policy.reserve; ++k )
        {
            reserved[marked[k].second] = 1;
        }
    }
    const lit_detail::SiteCut cut = lit_detail::cutSites( ing, anchors, lit.text, rows, enriched, reserved, policy.tableRows, rows.size() > policy.rows );
    std::stable_sort( order.begin(), order.end(), [ & ]( std::size_t a, std::size_t b )
                      {
                          const auto key = [ & ]( std::size_t i ) { return std::pair{ cut.tier[i], rank[i] }; };
                          return key( a ) < key( b );
                      } );
    // lit_cut= is said when the cut moved a row: a cut site the old order (rank alone) would have listed; otherwise capped= already says it
    bool cutMovedRow = false;
    if( cut.count > 0 )
    {
        std::vector<std::size_t> old( order.size() );
        for( std::size_t i = 0; i < old.size(); ++i )
        {
            old[i] = i;
        }
        std::stable_sort( old.begin(), old.end(), [ & ]( std::size_t a, std::size_t b ) { return rank[a] < rank[b]; } );
        std::vector<char> oldRegistration( old.size(), 0 );   // the old pick, registration slots and all (pickRows below, on the old order)
        for( std::size_t i = 0; policy.reserve > 0 && i < old.size(); ++i )
        {
            oldRegistration[i] = lit_detail::registrationMark( ing, rows[old[i]], enriched[old[i]].enclosingId, enriched[old[i]].text, lit.text );
        }
        const std::vector<std::size_t> oldPick = lit_detail::pickRows( oldRegistration, policy.rows, policy.reserve );
        cutMovedRow = std::any_of( oldPick.begin(), oldPick.end(), [ & ]( std::size_t p ) { return cut.tier[old[p]] == lit_detail::kCutTier; } );
    }
    std::erase_if( order, [ & ]( std::size_t i ) { return cut.tier[i] == lit_detail::kCutTier; } );
    std::vector<char> registration( order.size(), 0 );   // by rank position: a quoted key outside any function (shape=dotted)
    for( std::size_t i = 0; policy.reserve > 0 && i < order.size(); ++i )
    {
        registration[i] = lit_detail::registrationMark( ing, rows[order[i]], enriched[order[i]].enclosingId, enriched[order[i]].text, lit.text );
    }
    const std::vector<std::size_t> pick = lit_detail::pickRows( registration, policy.rows, policy.reserve );
    std::vector<GrepHit>          hits;
    std::vector<lit_detail::Site> shownRows;
    for( const std::size_t p : pick )
    {
        hits.push_back( std::move( enriched[order[p]] ) );
        shownRows.push_back( rows[order[p]] );
    }
    rows = std::move( shownRows );

    // ── the owner bodies: distinct callable owners of the shown rows, in row order ───────────────────────────────────────────
    std::vector<char>   esc;
    std::vector<NodeId> owners;
    std::vector<char>   ownerAbove;   // parallel: 1 = already printed by the answer, 2 = body held by the kForLiteralBodies cap, 0 = otherwise
    std::string         bodiesXml;
    bool                armWindow = false;   // an excerpt window starts at the head of the arm holding its site: arm="1", its legend clause
    for( const GrepHit& h : hits )
    {
        if( h.enclosingId == kNoNode || !ReceiverEvidence::callableKind( ing.symbols[h.enclosingId].kind )
            || std::find( owners.begin(), owners.end(), h.enclosingId ) != owners.end() )
        {
            continue;
        }
        const Symbol&     s    = ing.symbols[h.enclosingId];
        const std::string path = relPath( s.fileId );
        std::string head = " l=\"" + std::to_string( s.line ) + "\" p=\"";
        head += escapeXml( path, esc );
        head += "\" n=\"";
        head += escapeXml( s.name, esc );
        head += "\"";
        const bool above = lit_detail::servedBodyHead( served, head );
        owners.push_back( h.enclosingId );
        ownerAbove.push_back( above ? 1 : ( out.bodies >= kForLiteralBodies ? 2 : 0 ) );
        if( above || out.bodies >= kForLiteralBodies )
        {
            continue;
        }
        const std::string text = docparse::detail::readWholeFile( diskPath( ing, s.fileId ) ).value_or( std::string() );
        if( text.empty() )
        {
            continue;
        }
        const std::uint32_t first = layout::lineOf( text, s.sigStartByte );
        const std::uint32_t last  = layout::lineOf( text, s.endByte > 0 ? s.endByte - 1 : 0 );
        if( last >= first && last - first < kForLiteralWholeBodyLines )   // a short body is served whole (nothing to leave out)
        {
            std::optional<std::string> body = renderBodyElement( ing, h.enclosingId, /*capBytes=*/0, /*compress=*/false, redact, rootArg, nullptr );
            if( body && body->size() <= kForLiteralBodyCapBytes && bodiesXml.size() + body->size() <= limits.byteCap )
            {
                bodiesXml += *body;
                ++out.bodies;
                continue;
            }
        }
        // an excerpt of a longer body: its signature line and one window per shown site this owner holds (never the span between)
        std::vector<std::uint32_t> siteLines;
        for( const GrepHit& o : hits )
        {
            if( o.enclosingId == h.enclosingId )
            {
                siteLines.push_back( o.line );
            }
        }
        bool        armed   = false;
        std::string excerpt = lit_detail::excerptElement( text, path, s, first, last, siteLines, redact, &armed );
        if( bodiesXml.size() + excerpt.size() > limits.byteCap )
        {
            ownerAbove.back() = 2;   // past the byte cap, as past the body cap: the row says body="held"
            continue;
        }
        bodiesXml += excerpt;
        ++out.bodies;
        armWindow = armWindow || armed;
    }

    // ── FLAG-SHAPE-LIT: the first shown string row whose call names a default (def=), and the constant writes of the field it names (ld) ──
    lit_detail::FlagDefault flag;
    if( policy.boundary == lit_detail::LitBoundary::Flag )
    {
        flag = lit_detail::flagDefaultOfRows( ing, rows, hits, relPath, redact, esc, useMemo );
    }

    // ── the rows ──────────────────────────────────────────────────────────────────────────────────────────────────────────
    const std::string_view needle = policy.boundary != lit_detail::LitBoundary::None ? std::string_view( lit.text ) : std::string_view();   // a cut row opens near it
    std::string rowsXml;
    std::size_t contextRows = 0;
    std::size_t shownRowCount = 0;
    bool        byteCut       = false;
    for( std::size_t i = 0; i < hits.size(); ++i )
    {
        const GrepHit& h = hits[i];
        const std::size_t rowStartAt = rowsXml.size();
        rowsXml += "<ls p=\"";
        rowsXml += escapeXml( relPath( h.fileId ), esc );
        rowsXml += "\" l=\"" + std::to_string( h.line ) + "\" k=\"";
        rowsXml += rows[i].k == 's' ? "string" : ( rows[i].k == 'c' ? "code" : "?" );
        rowsXml += "\"";
        if( h.enclosingId != kNoNode )
        {
            rowsXml += " in=\"";
            rowsXml += escapeXml( h.enclosing, esc );
            rowsXml += "\" ink=\"";
            rowsXml += symTag( ing.symbols[h.enclosingId].kind );
            rowsXml += "\"";
            const auto it = std::find( owners.begin(), owners.end(), h.enclosingId );
            if( it != owners.end() && ownerAbove[std::size_t( it - owners.begin() )] != 0 )
            {
                rowsXml += ownerAbove[std::size_t( it - owners.begin() )] == 1 ? " body=\"above\"" : " body=\"held\"";
            }
        }
        std::string line = h.text;
        const std::size_t lead = line.find_first_not_of( " \t" );
        line = lead == std::string::npos ? std::string() : line.substr( lead );
        redactInPlace( line, redact );   // CR 4423843223: the matched line is raw source text; redact before the cut
        lit_detail::cutAround( line, needle, kForLiteralLineBytes );
        const bool callableOwner = h.enclosingId != kNoNode && ReceiverEvidence::callableKind( ing.symbols[h.enclosingId].kind );
        lit_detail::appendTblAttr( rowsXml, rows[i].tbl, redact, esc, rows[i].regCall ? std::string_view( " reg=\"" ) : std::string_view( " tbl=\"" ) );
        if( i == flag.row )
        {
            rowsXml += " def=\"";
            rowsXml += escapeXml( flag.text, esc );
            rowsXml += "\"";
        }
        if( ( policy.tableRows ? !rows[i].tbl.empty() : rows[i].k == 's' && !callableOwner ) && contextRows < policy.contextRows )
        {
            // a string site outside any function (a table entry, an error-code map): the lines after it hold what it builds
            const std::string text = docparse::detail::readWholeFile( diskPath( ing, h.fileId ) ).value_or( std::string() );
            const std::uint32_t lastLine = text.empty() ? h.line : layout::lineOf( text, text.size() - 1 );
            const std::uint32_t b = std::min( h.line + kForLiteralContextLines, lastLine );
            if( !text.empty() && b > h.line )
            {
                line = lit_detail::linesOfRanges( text, { lit_detail::LineRange{ h.line, b } } );
                redactInPlace( line, redact );   // CR 4423843223: the lines after a table entry are raw source text too
                truncateUtf8WithEllipsis( line, kForLiteralLineBytes * ( kForLiteralContextLines + 1 ) );
                rowsXml += " lines=\"" + std::to_string( h.line ) + "-" + std::to_string( b ) + "\"";
                ++contextRows;
            }
        }
        rowsXml += "><![CDATA[";
        appendCdataSafe( line, rowsXml );
        rowsXml += "]]></ls>";
        if( rowsXml.size() + bodiesXml.size() > limits.byteCap )
        {
            rowsXml.resize( rowStartAt );   // a cut stands on a row boundary, never inside a line
            byteCut = true;
            break;
        }
        ++shownRowCount;
    }
    lit_detail::TableReaders readers;
    if( policy.tableRows )
    {
        readers = lit_detail::tableReadersOf( ing, anchors.g, rows, hits, shownRowCount, served, relPath, redact, esc, useMemo );
        if( rowsXml.size() + bodiesXml.size() + readers.xml.size() > limits.byteCap )
        {
            readers.xml.clear();   // the lr rows do not fit what the cap left: readers= still counts every read, so none listed says they were cut
        }
    }
    ReaderCallers callers;   // READER-CALLERS: who calls the functions the shown rows sit in (never on a table: its lr rows read it)
    if( !policy.tableRows )
    {
        callers = renderReaderCallers( ing, anchors.g, std::span<const NodeId>( owners ), relPath, esc );
    }
    const bool subscriptShown = policy.tableRows && std::any_of( rows.begin(), rows.begin() + std::ptrdiff_t( shownRowCount ), []( const lit_detail::Site& r ) { return r.subscript; } );
    if( byteCut && shownRowCount == 0 )
    {
        ForLiteralRender none;
        none.noRoom = true;   // not one row fits what the cap left: the caller counts this anchor as skipped
        return none;
    }

    std::string& x = out.xml;
    if( limits.withLegend )
    {
        x = compactLegend ? std::string( kForCompactLiteralLegend ) : std::string( kForLiteralLegend );
        x += !policy.legend.empty() ? policy.legend : ( lit.tryNo > 1 ? kForLiteralKeyLegend : std::string_view() );
        x += policy.boundary == lit_detail::LitBoundary::Flag && lit.tryNo > 1 ? kForLiteralFlagTryLegend : std::string_view();   // the flag clause carries no try= sentence of its own
        x += limits.strongOnly ? kForLiteralStrongLegend : std::string_view();   // the whole task has no cue word: every element of it lists strong rows only
    }
    if( armWindow && !limits.armLegendAbove )
    {
        x += kForLiteralArmLegend;   // present only with arm= (EXCERPT-ARM)
        out.armLegend = true;
    }
    if( tailDropped > 0 && !limits.tailLegendAbove )
    {
        x += kForLiteralTailLegend;   // present only with tail= (rv-reg2-delta D4: not on every shape=table answer)
        out.tailLegend = true;
    }
    if( subscriptShown && !limits.subLegendAbove )
    {
        x += kForLiteralSubscriptLegend;   // present only with a subscript reg= row (REG-READER)
        out.subLegend = true;
    }
    if( callers.rows > 0 || !callers.xml.empty() )
    {
        x += kReaderCallersLegend;   // present only with lc/lcn rows (READER-CALLERS)
    }
    if( cutMovedRow && !limits.cutLegendAbove )
    {
        x += compactLegend ? kForCompactLiteralCutLegend : kForLiteralCutLegend;   // present only with lit_cut=
        out.cutLegend = true;
    }
    x += "<lit s=\"";
    x += escapeXml( lit.text, esc );
    x += "\" shape=\"";
    x += lit.shape;
    x += "\" hits=\"" + std::to_string( collected.raw.size() ) + "\" src=\"" + std::to_string( out.sites ) + "\" shown=\""
         + std::to_string( shownRowCount ) + "\"";
    if( shownRowCount < out.sites )
    {
        x += " capped=\"1\"";
    }
    x += policy.tableRows && out.sites > readSites ? " read=\"" + std::to_string( readSites ) + "\"" : std::string();
    x += longerHits > 0 ? " longer=\"" + std::to_string( longerHits ) + "\"" : std::string();
    x += tailDropped > 0 ? " tail=\"" + std::to_string( tailDropped ) + "\"" : std::string();
    x += weakDropped > 0 ? " weak=\"" + std::to_string( weakDropped ) + "\"" : std::string();
    x += mentionHits > 0 ? " mention=\"" + std::to_string( mentionHits ) + "\"" : std::string();
    x += !lit_detail::defaultFieldOf( flag.text ).empty() ? " writes=\"" + std::to_string( flag.writeCount ) + "\"" : std::string();
    x += readers.count > 0 || readers.floor ? " readers=\"" + std::to_string( readers.count ) + "\"" : std::string();
    x += lit.frag ? " frag=\"1\"" : "";
    x += lit.tryNo > 1 ? " try=\"" + std::to_string( lit.tryNo ) + "\"" : std::string();
    x += cutMovedRow ? " lit_cut=\"" + std::to_string( cut.count ) + "\"" : std::string();
    x += " comment=\"" + std::to_string( commentHits ) + "\" test=\"" + std::to_string( testHits ) + "\" doc=\"" + std::to_string( docHits ) + "\"";
    if( !collected.cleanScan() || anyUnclassified || flag.writesFloor || readers.floor )
    {
        x += " floor=\"1\"";
    }
    x += nextAttrXml( nextFlag( "--grep=", lit.text ) );
    const std::string inner = rowsXml + flag.writesXml + readers.xml + bodiesXml + callers.xml + "</lit>";
    // bytes= is the element's own size from its open tag on (the legend comment excluded): a fixed point over its own digits
    const std::size_t openAt = x.find( "<lit " );
    const std::size_t fixed  = ( x.size() - openAt ) + std::string_view( " bytes=\"\">" ).size() + inner.size();
    std::size_t       bytes  = fixed;
    while( fixed + std::to_string( bytes ).size() != bytes )   // the digits count themselves: converges in <= 2 steps
    {
        bytes = fixed + std::to_string( bytes ).size();
    }
    x += " bytes=\"" + std::to_string( bytes ) + "\">";
    x += inner;
    ENSURES( x.size() - openAt == bytes, "bytes= is the element's own size" );
    return out;
}

// a file of the index named `name` (a dotted word that is a file's name is no key, whatever its extension)
inline bool namesIndexedFile( const IngestResult& ing, std::string_view name )
{
    return std::any_of( ing.files.begin(), ing.files.end(),
                        [ & ]( const auto& f ) { const std::string_view p( f ); return p.ends_with( name ) && ( p.size() == name.size() || p[p.size() - name.size() - 1] == '/' ); } );
}

// the first try of a message (forMessageTries) that has a string site, or nothing
inline ForLiteralRender renderMessageTries( const IngestResult& ing, const ForLiteral& lit, std::string_view rootArg, std::string_view served,
                                            RedactCounts* redact, bool useMemo, bool compactLegend, const LitAnchors& anchors )
{
    if( lit.verbatim )
    {
        return renderForLiteral( ing, lit, rootArg, served, redact, useMemo, compactLegend, {}, anchors );   // MSG-VERBATIM: the whole text, no fragments
    }
    for( const std::string& t : forMessageTries( lit.text ) )
    {
        ForLiteral tried = lit;
        tried.text       = t;
        tried.frag       = t != lit.text;
        ForLiteralRender r = renderForLiteral( ing, tried, rootArg, served, redact, useMemo, compactLegend, {}, anchors );
        if( !r.xml.empty() )
        {
            return r;
        }
    }
    return {};
}

// G-STORED-B: a no-cue task scans a compound name (a type, a snake_case or qualified name), never a plain English word (`register`, `open`, `index`): one
// lower-case word, with no `_`, `::`, `.`, digit or inner capital, names too many sites to be the one the task means (rv-forliteral-3 section 2)
inline bool isOneLowerWord( std::string_view w ) noexcept
{
    return !w.empty() && std::count_if( w.begin(), w.end(), []( char c ) { return c >= 'a' && c <= 'z'; } ) == std::ptrdiff_t( w.size() );
}

// a word of the task is an anchor of shape=table when the index holds a symbol of that name (a backticked span stands on its own quoting)
inline bool forTableAnchorKeeps( const IngestResult& ing, std::string_view word, bool quoted )
{
    if( quoted )
    {
        return true;
    }
    if( word.starts_with( "self." ) || word.starts_with( "this." ) )
    {
        return false;   // a member chain, never a table's key (dottedKeysOf's rule)
    }
    const size_t sep = word.find_last_of( ".:#" );
    const std::string_view tail = sep == std::string_view::npos ? word : word.substr( sep + 1 );   // the name an index symbol carries
    return tail.size() >= kForTableMinAnchor && std::any_of( ing.symbols.begin(), ing.symbols.end(), [ & ]( const Symbol& s ) { return s.name == tail; } );
}

// shape=table: the walk over a task's anchors, one try each, under the caps on work done (scans: an anchor with no site costs one too; elements printed;
// one byte cap). An anchor past a cap is counted (skipped), never dropped.
enum class TableTry : std::uint8_t
{
    Unkept,   // not an anchor here: a file's name, or a word the index holds no symbol of
    Empty,    // tried: no element (no site, no row, or past a cap)
    Printed
};
struct TableWalk
{
    const IngestResult& ing;
    std::string_view    rootArg, served;
    RedactCounts*       redact;
    bool                useMemo, compactLegend;
    const LitAnchors&   anchors;
    TableCue            cue;
    ForLiteralRender    out;
    std::size_t         printed = 0, scanned = 0, skipped = 0, used = 0;
    std::string         firstSkipped;

    void skip( const std::string& word )
    {
        ++skipped;
        firstSkipped = firstSkipped.empty() ? word : firstSkipped;
    }
    // `late`: an anchor the index holds no symbol of, tried on the cue's row-only reading alone. `tail`: the last part of a dotted name (lateTableAnchor),
    // which lists only quoted-key rows and its definition
    TableTry tryAnchor( const TableAnchor& anchor, bool late, bool tail = false )
    {
        const std::string& word = anchor.text;
        if( namesIndexedFile( ing, word ) || ( !late && !forTableAnchorKeeps( ing, word, anchor.quoted ) ) || ( cue == TableCue::StrongRowOnly && isOneLowerWord( word ) ) )
        {
            return TableTry::Unkept;
        }
        if( printed >= kForTableAnchors || scanned >= kForLiteralCandidates || used + kForTableElementBytes >= kForTableByteCap )
        {
            skip( word );
            return TableTry::Empty;
        }
        ++scanned;
        ForLiteralLimits limits{ kForTableByteCap - used - kForTableElementBytes, out.xml.empty(), cue != TableCue::AnySite || !anchor.firm, out.cutLegend, tail,
                                 cue == TableCue::StrongRowOnly, out.tailLegend, out.armLegend, out.subLegend };
        ForLiteral lit{ word, "table" };
        ForLiteralRender r = renderForLiteral( ing, lit, rootArg, served, redact, useMemo, compactLegend, limits, anchors );
        if( r.noRoom || r.unread )
        {
            skip( word );   // scanned, and counted once more as skipped: it printed nothing
            return TableTry::Empty;
        }
        if( r.xml.empty() )
        {
            return TableTry::Empty;
        }
        ++printed;
        used += r.xml.size() - r.xml.find( "<lit " );   // element bytes: the legend comments before the first are not
        out.xml += r.xml;
        out.sites += r.sites;
        out.bodies += r.bodies;
        out.cutLegend = out.cutLegend || r.cutLegend;
        out.tailLegend = out.tailLegend || r.tailLegend;
        out.armLegend  = out.armLegend || r.armLegend;
        out.subLegend  = out.subLegend || r.subLegend;
        return TableTry::Printed;
    }
};

// REGISTRAR-2: the second pass of the walk. A dotted anchor (`pydantic.ValidationError`, `light.turn_on`) that printed nothing is tried by its last
// segment, the name a registration row writes (`'ValidationError': (...)`), unless the task names that segment itself. An identifier-shaped word the
// index holds no symbol of (a generated type, `HashJoinNode` from a .proto; a key only a macro or a decorator writes) is tried when the cue prints only
// beside a table row (a row-only or strong-only cue). Both after every anchor of the task, so neither takes an earlier anchor's scan.
inline std::optional<TableAnchor> lateTableAnchor( const IngestResult& ing, const TableAnchor& a, TableTry tried, TableCue cue, std::span<const TableAnchor> own )
{
    const std::string_view word = a.text;
    const std::size_t      dot  = word.rfind( '.' );
    if( tried == TableTry::Unkept )
    {
        const bool unindexed = cue != TableCue::AnySite && !a.quoted && dot == std::string_view::npos && !namesIndexedFile( ing, word ) && lit_detail::isIdentifierShaped( word );
        return unindexed ? std::optional<TableAnchor>( a ) : std::nullopt;
    }
    if( tried != TableTry::Empty || dot == std::string_view::npos || word.find( "::" ) != std::string_view::npos || dot + 1 + kForTableMinAnchor > word.size() )
    {
        return std::nullopt;
    }
    const std::string_view tail = word.substr( dot + 1 );
    const bool named = std::any_of( own.begin(), own.end(), [ & ]( const TableAnchor& o ) { return o.text == tail; } );
    return named ? std::nullopt : std::optional<TableAnchor>( TableAnchor{ std::string( tail ), a.quoted, a.firm } );
}

// shape=table, the last try: every kept anchor with a site prints its own <lit>, all under one byte cap. `capped` = what the earlier shapes
// left unscanned, which stays said. An anchor the cap left out is counted the way a literal past the scan cap is.
inline ForLiteralRender renderForTableOfTask( const IngestResult& ing, std::string_view task, std::string_view rootArg, std::string_view served,
                                              RedactCounts* redact, bool useMemo, bool compactLegend, const LitAnchors& anchors )
{
    const std::vector<TableAnchor> own = forTableAnchorsOf( task );
    if( own.empty() )
    {
        return {};   // no backticked span and no identifier-shaped word: nothing to scan (a bare-prose task costs no scan)
    }
    const TableCue cue = forTableCueOf( task );
    TableWalk walk{ ing, rootArg, served, redact, useMemo, compactLegend, anchors, cue, {} };
    std::vector<std::pair<TableAnchor, bool>> later;   // (anchor, unindexed)
    for( const TableAnchor& anchor : own )
    {
        const TableTry tried = walk.tryAnchor( anchor, false );
        std::optional<TableAnchor> l = lateTableAnchor( ing, anchor, tried, cue, own );
        if( l && std::none_of( later.begin(), later.end(), [ & ]( const auto& e ) { return e.first.text == l->text; } ) )   // `a.k` and `b.k` retry `k` once
        {
            later.emplace_back( std::move( *l ), tried == TableTry::Unkept );
        }
    }
    for( const auto& [anchor, unindexed] : later )
    {
        walk.tryAnchor( anchor, unindexed, /*tail=*/!unindexed );
    }
    ForLiteralRender out = std::move( walk.out );
    if( walk.skipped > 0 && ( cue != TableCue::StrongRowOnly || !out.xml.empty() ) )   // a no-cue walk that listed no strong row leaves the answer as it was
    {
        out.xml += std::string( kForLiteralCapLegend ) + "<lit_capped scanned=\"" + std::to_string( walk.scanned ) + "\" skipped=\"" + std::to_string( walk.skipped )
                   + "\"" + nextAttrXml( nextFlag( "--grep=", walk.firstSkipped ) ) + "/>";
    }
    return out;
}

// the block of the task's literals: each in order (forLiteralCandidates) until one has a source site, at most kForLiteralCandidates scans
// besides a message, which walks its tries
// SIZE-1 (size-trim): the row-attribute clauses of the lit legends, present-only on the task's printed elements. The first element
// carries the legends for all of them (ForLiteralLimits::withLegend), so the whole block is read, once, after the last element.
inline constexpr std::string_view kForLiteralBodyClause = "; body=above: printed above, held: its owner body is past the 3-body cap, not printed";
inline constexpr std::string_view kForCompactLiteralBodyClause = "; body=above|held: printed above|past the 3-body cap";
inline constexpr std::string_view kForLiteralLongerClause = "; longer= source sites inside a longer name, child key or word, counted, never rows";
inline constexpr std::string_view kForLiteralTryClause = " try=N: the task's Nth literal anchored; the ones before it had no source site or were not scanned.";
static_assert( kForLiteralLegend.contains( kForLiteralBodyClause ) && kForCompactLiteralLegend.contains( kForCompactLiteralBodyClause )
                   && kForLiteralKeyLegend.contains( kForLiteralLongerClause ) && kForLiteralKeyLegend.contains( kForLiteralTryClause ),
               "the lit row clauses are spelled as the legends carry them" );
inline ForLiteralRender litLegendPresentOnly( ForLiteralRender r, bool compactLegend )
{
    eraseAbsentClause( r.xml, compactLegend ? kForCompactLiteralBodyClause : kForLiteralBodyClause, r.xml.contains( " body=\"" ) );
    eraseAbsentClause( r.xml, kForLiteralLongerClause, r.xml.contains( " longer=\"" ) );
    eraseAbsentClause( r.xml, kForLiteralTryClause, r.xml.contains( " try=\"" ) );
    return r;
}

// FOR-SCAN-ONCE: the table walk's first kForLiteralCandidates kept anchors (TableWalk::tryAnchor's keep rule; a late form is not foreseen
// and reads alone)
inline void appendTableScanPlan( const IngestResult& ing, std::string_view task, std::vector<std::string>& plan )
{
    const std::vector<TableAnchor> own = forTableAnchorsOf( task );
    if( own.empty() )
    {
        return;
    }
    const TableCue cue  = forTableCueOf( task );
    std::size_t    kept = 0;
    for( const TableAnchor& anchor : own )
    {
        if( kept < kForLiteralCandidates && !namesIndexedFile( ing, anchor.text ) && forTableAnchorKeeps( ing, anchor.text, anchor.quoted )
            && !( cue == TableCue::StrongRowOnly && isOneLowerWord( anchor.text ) ) )
        {
            ++kept;
            plan.push_back( anchor.text );
        }
    }
}

// FOR-SCAN-ONCE: the patterns renderForLiteralOfTask may scan for `task`, in its order: every candidate its loop reaches (kForLiteralCandidates
// scans, a message's tries besides), then the table walk's anchors. The loop stops at the first literal with a site and the walk runs only when
// none has one, so this is a superset of one call's scans: the caller opens a GrepScanBatch with it, and one read of the corpus serves every
// scan the block makes. The walk is foreseen with the loop because the commonest pair is a cue-less task's whole text (MSG-VERBATIM, which
// rarely has a site) and then its table anchors: staged, they would be two reads.
inline std::vector<std::string> forLiteralScanPlan( const IngestResult& ing, std::string_view task )
{
    std::vector<std::string> plan;
    std::size_t              scans = 0;
    for( const ForLiteral& lit : forLiteralCandidates( task ) )
    {
        const bool message = lit.shape == "message";
        if( ( !message && lit.shape == "dotted" && namesIndexedFile( ing, lit.text ) ) || ( !message && scans >= kForLiteralCandidates ) )
        {
            continue;
        }
        scans += message ? 0 : 1;
        if( message && !lit.verbatim )
        {
            std::ranges::move( forMessageTries( lit.text ), std::back_inserter( plan ) );
        }
        else
        {
            plan.push_back( lit.text );
        }
    }
    appendTableScanPlan( ing, task, plan );
    return plan;
}

inline ForLiteralRender renderForLiteralOfTask( const IngestResult& ing, std::string_view task, std::string_view rootArg, std::string_view served,
                                                RedactCounts* redact, bool useMemo, bool compactLegend, const LitAnchors& anchors = {} )
{
    std::size_t scans = 0, skipped = 0;
    std::string firstSkipped;
    for( const ForLiteral& lit : forLiteralCandidates( task ) )
    {
        const bool message = lit.shape == "message";
        if( !message && lit.shape == "dotted" && namesIndexedFile( ing, lit.text ) )
        {
            continue;
        }
        if( !message && scans >= kForLiteralCandidates )
        {
            skipped += 1;
            firstSkipped = firstSkipped.empty() ? lit.text : firstSkipped;
            continue;
        }
        scans += message ? 0 : 1;
        ForLiteralRender r = message ? renderMessageTries( ing, lit, rootArg, served, redact, useMemo, compactLegend, anchors )
                                     : renderForLiteral( ing, lit, rootArg, served, redact, useMemo, compactLegend, {}, anchors );
        if( !r.xml.empty() )
        {
            return litLegendPresentOnly( std::move( r ), compactLegend );
        }
    }
    // no earlier shape anchored: the last try, shape=table (it never prints beside them)
    ForLiteralRender table = renderForTableOfTask( ing, task, rootArg, served, redact, useMemo, compactLegend, anchors );
    if( skipped > 0 )
    {
        // the cap was hit and nothing scanned anchored: say so (no <lit>: no site was found, so the block's attributes would claim one)
        table.xml = std::string( kForLiteralCapLegend ) + "<lit_capped scanned=\"" + std::to_string( scans ) + "\" skipped=\"" + std::to_string( skipped )
                    + "\"" + nextAttrXml( nextFlag( "--grep=", firstSkipped ) ) + "/>" + table.xml;
    }
    return litLegendPresentOnly( std::move( table ), compactLegend );
}
}   // namespace rw
