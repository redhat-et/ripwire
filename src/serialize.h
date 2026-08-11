#pragma once

// serialize.h — minified, escaped XML serialization. Streamed through a 64 KB
// buffer (no whole-document string), terse schema, every name/path XML-escaped.

#include "model.h"
#include "arch.h"        // P3: builtinLayer() — the file-node layer= tag
#include "lintrules.h"   // §P9.4: langOfPath / dependencyCapable — packDeps' dep_files= denominator
#include "resolve.h"     // S6-C: canonicalId() — the `id=` canonical symbol string (shared with the resolver)
#include "redact.h"      // deterministic secret redaction of emitted body content (opt-out --no-redact)
#include "infra/sortutil.h"    // numeric-key radix helpers for rank/file score order
#include "infra/jsonesc.h"     // F9: jsonesc::utf8SeqLen — the canonical UTF-8-sequence-length core (was duplicated here)
#include "notes.h"       // L3: field-notes NoteIndex — the retrieval-time surfacing lookup (INERT when null)
#include "pageview.h"    // §P8: pageWindow / pageDisclosure — the shared --limit/--offset contract (packDeps)

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>    // §H7 degrade seam: std::getenv for the non-release fault switch
#include <cstring>
#include <optional>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// XML 1.0 forbids the C0 control set even ESCAPED (0x00-0x08, 0x0B, 0x0C, 0x0E-0x1F — only \t \n \r
// are legal Chars): a stray form-feed in an otherwise-legal source file would break the G4 xmllint
// gate. Substitute a space — deterministic, applied identically in escapeXml and the CDATA copies.
inline char xmlSafeByte( char c ) noexcept
{
    return ( static_cast<unsigned char>( c ) < 0x20 && c != '\t' && c != '\n' && c != '\r' ) ? ' ' : c;
}

// ── §B12.7 + CA4 verifier F-MED-1 — THE C0 DIALECT DIVERGENCE, AND ITS TELL ─────────────────────────────
// The XML and JSON dialects do not agree about C0 controls and invalid UTF-8, and they CANNOT: XML 1.0
// forbids the C0 set even escaped (only \t \n \r are legal Chars) so xmlSafeByte must substitute a space,
// and an invalid sequence must become '?', while JSON has \u00XX for every control byte. jsonesc.h's own
// header records the decision from the other side: the JSON escaper is the FAITHFUL one and stays faithful,
// because normalizing there would make the two dialects agree by making BOTH lossy.
//
// What was wrong was not the divergence — it was that the lossy side said nothing. `<ctx task=…>`, whose
// entire §B1.7 point is being the VERBATIM copy of the user's task, silently was not; and `EmittedBody::text`
// is recorded at packBodies' push_back BEFORE appendCdataSafe, so a def holding ESC + Latin-1 reached XML at
// 140 B scrubbed and JSON at 148 B raw with nothing anywhere saying so.
//
// So the lossy side now DISCLOSES: `scrubbed="1"` on the XML surface that lost bytes, and its JSON twin
// beside the same field — the JSON is byte-faithful and does not need the warning for itself, but a consumer
// diffing the two dialects is owed the fact from either one. THE MARKERS ARE A CLOSED SET, and each XML one
// has exactly one JSON counterpart: `task_scrubbed=`/`route_scrubbed=` on the root (ctxRootOpen) twin
// `"task_xml_scrubbed"`/`"route_xml_scrubbed"` (ctxRootJsonScrubKeys, right below it — one function, so a
// call site cannot emit the field and skip the question), and `<b scrubbed="1">` twins `"xml_scrubbed"` on
// the JSON body object. test/bodydialectcheck.sh arm (H) sweeps that table in BOTH directions rather than
// the one marker that already worked. This predicate is the single decision behind all six: true iff
// escapeXml/appendCdataSafe would CHANGE bytes (a C0 other than \t\n\r, or an invalid UTF-8 sequence).
// Entity-escaping (& < > " ') is NOT lossy — it round-trips exactly — and must not set the flag, or every
// document on earth would wear it.
inline bool xmlScrubIsLossy( std::string_view s ) noexcept
{
    const char*       d = s.data();
    const std::size_t n = s.size();
    for( std::size_t i = 0; i < n; )
    {
        const unsigned char c = static_cast<unsigned char>( d[i] );
        if( c < 0x20 && c != '\t' && c != '\n' && c != '\r' )
        {
            return true; // xmlSafeByte -> ' '
        }
        if( c < 0x80 ) { ++i; continue; }
        const int len = jsonesc::utf8SeqLen( d, i, n );
        if( len == 0 )
        {
            return true; // escapeXml -> '?', appendCdataSafe -> '?'
        }
        i += std::size_t( len );
    }
    return false;
}

// W3FIX M2 — the three LEGAL control chars (\t \n \r) still cannot be written LITERALLY by escapeXml, for two
// independent reasons that both bite the §B1.7 verbatim task attribute:
//   (a) G4 forbids a '\n' anywhere outside CDATA, and `--for=$'a\nb'` put one straight into `<ctx task="a?b">`
//       — a two-line document out of a serializer whose contract is one line;
//   (b) XML ATTRIBUTE-VALUE NORMALIZATION (XML 1.0 §3.3.3) replaces a literal \t/\n/\r in an attribute with a
//       SPACE at parse time, so even where the raw byte was tolerated the parser handed back a DIFFERENT
//       string than the user typed — §B1.7's whole point is that the attribute is the verbatim copy.
// A numeric character reference survives normalization exactly (the parser un-escapes it AFTER normalizing),
// so `&#10;` round-trips to '\n' while emitting no literal newline. Emitted for element text too: there a
// char reference parses back to the identical character, so one rule serves both seams and no call site has
// to know which kind of node it is writing into. Near-golden-neutral, not fully: a plain --whereis over a
// .tsv file (bench/recalleval labels) legitimately carries real tabs into t= attributes, where the old code
// emitted a literal tab an XML parser silently normalized to a space — the reference there is a FIX, not a
// hostile-input path (seam-verifier NIT, 2026-07-29). Everywhere else on this repo the references appear
// only on hostile input.
inline const char* xmlControlCharRef( char c ) noexcept
{
    switch( c )
    {
        case '\t': return "&#9;";
        case '\n': return "&#10;";
        case '\r': return "&#13;";
        default:   return nullptr;
    }
}

// F9: utf8SeqLen used to be duplicated here (byte-identical logic to jsonesc.h's copy, just re-commented) —
// now forwards to the one canonical core in jsonesc.h (zero project includes, so pulling it in here adds no
// cycle risk). Kept as a `using` so every call site below (escapeXml, appendCdataSafe) is unchanged.
using jsonesc::utf8SeqLen;

// escape & < > " ' (ampersand FIRST) into `out`; returns a view into it. Reused per call. Byte < 0x20 is
// scrubbed to a space (xmlSafeByte) or, for the three legal control chars, written as a numeric character
// reference (xmlControlCharRef — see M2 above: G4 + attribute-value normalization); an invalid UTF-8 sequence
// (A4-F20) is scrubbed to '?' so the emitted name/path/doc-comment/sig text is always well-formed XML AND
// valid UTF-8 regardless of source bytes.
inline std::string_view escapeXml( std::string_view s, std::vector<char>& out )
{
    out.clear();
    out.reserve( s.size() + 16 );

    const auto put  = [ & ]( const char* lit ) { while( *lit ) { out.push_back( *lit++ ); } };
    const char*       d = s.data();
    const std::size_t n = s.size();
    for( std::size_t i = 0; i < n; )
    {
        const char c = d[i];
        switch( c )
        {
            case '&':  put( "&amp;" );  ++i; break;
            case '<':  put( "&lt;" );   ++i; break;
            case '>':  put( "&gt;" );   ++i; break;
            case '"':  put( "&quot;" ); ++i; break;
            case '\'': put( "&apos;" ); ++i; break;
            case '\t':
            case '\n':
            case '\r': put( xmlControlCharRef( c ) );  ++i; break;   // M2: verbatim round-trip, no literal control byte
            default:
                if( static_cast<unsigned char>( c ) < 0x80 ) { out.push_back( xmlSafeByte( c ) ); ++i; }
                else if( const int len = utf8SeqLen( d, i, n ); len == 0 ) { out.push_back( '?' ); ++i; }   // scrub invalid UTF-8
                else
                {
                    for( int k = 0; k < len; ++k )
                    {
                        out.push_back( d[i + k] );
                    }
                    i += std::size_t( len );
                }
        }
    }
    return std::string_view( out.data(), out.size() );
}

// ── THE FIXED-BUFFER RULE (CA4 §B14) — the one place it is written down ───────────────────────────────────
// **Never `snprintf` ALREADY-ESCAPED or already-markup text into a fixed `char[]`.** Compose it on
// `std::string`.
//
// The test that separates a breaching site from a safe one is WHICH SIDE OF THE BUFFER THE ESCAPER SITS ON:
//   escape-then-snprintf  → the cut lands in the ESCAPED form: mid-entity (`&am`), mid-attribute-name,
//                           mid-UTF-8 sequence, or before the element's own `/>`. The document is broken and
//                           the process still exits 0 — a G4 breach a caller cannot detect.
//   snprintf-then-escape  → the cut only shortens PROSE, and the escaper then runs over the shortened text.
//                           Ugly, never malformed. `lanes.h:698`/`:723` are safe for exactly this reason.
// The escaping is what makes truncation dangerous, not the length: a 512-byte buffer breaks at 228 RAW bytes
// once `&` expands 5:1 and `'` 6:1 before the buffer is written.
//
// A CLAMP IS THE WRONG REMEDY (§H1's recorded reason): it trades a visible breach for a silently wrong path.
// Truncation that must happen belongs to the budget layer, which emits a marker; a buffer must never decide it.
//
// Three occurrences before the rule was swept — `tracelocus.h`'s `char row[640]` (gated, tracelocus only),
// `gitmine.h`'s input-side twin (gated, gitmine only), then §B14's six emitters. `test/fixedbufsweep.sh` is
// the sweep: it re-derives EVERY `snprintf` call in `src/` that interpolates a `%s`, classifies each against
// a committed table, and FAILS on any call the table does not know about — so the next one is a red gate on
// the commit that introduces it, not a finding three rounds later.
//
// W3FIX M3 — THE ONE COMMENT-ECHO SCRUB. Every task-shaped verb echoes the user's own query inside an XML
// COMMENT, and each site hand-rolled the SAME '--'-collapse (main.cpp --for, packtask.h, mcpverbs.h, exemplar,
// tracelocus.h) while none of them scrubbed the bytes an XML comment cannot carry. So `--for=$'a\001b'` and
// `--pack-task=$'a\377b'` both made xmllint reject the whole document (G4), and `$'a\nb'` put a raw newline
// outside CDATA — the ATTRIBUTE half of §B1.7 was hardened by escapeXml and the comment half was not.
//
// The comment is the READABLE echo (the attribute beside it is the verbatim one), so the scrub is lossy on
// purpose and states its three rules in one place:
//   1. '--' runs collapse to a single '-'   — "--" is ill-formed inside a comment and "-->" would close it;
//   2. every control byte becomes a space   — C0 is illegal XML even escaped (xmlSafeByte), and \t\n\r are
//      legal XML but forbidden outside CDATA by G4; a character reference is NOT expanded inside a comment,
//      so `&#10;` there would be literal text pretending to be an escape — a space is the honest scrub;
//   3. an invalid UTF-8 sequence becomes '?' — same rule appendCdataSafe applies to bodies.
// Byte-identical to the hand-rolled std::unique collapse for every input that carried no control byte and no
// invalid sequence, which is what makes it a drop-in everywhere the old collapse stood. A trailing '-' is
// deliberately KEPT: no site ends its comment with user text (fixed legend prose always follows), so "a-"
// cannot become "--->" and dropping it would silently lose a character the reader typed. Pure text in, pure
// text out.
//
// CA4 §B4 — THE ENUMERATION, RE-DERIVED FROM SOURCE (this header used to claim "a drop-in at all six echo
// sites", and that count had rotted: `main.cpp`'s queryRouteNote was never converted, so the true figure was
// never six, and a reader auditing from the comment alone would have stopped one site short — trap #5/#12).
// The honest form is a LIST, not a number, and it is machine-checked: `test/fixedbufsweep.sh` re-derives
// `git grep -c 'xmlCommentText(' -- src/` (excluding this definition) and FAILS if it disagrees with the
// count on the CALL-SITES line below, so the next divergence is a red gate rather than a stale sentence.
//
//   CALL-SITES: 11
//     main.cpp     --for task echo · --exemplar request note · --query route note       (3)
//     packtask.h   task · mention · co-change-boost · doc-mention notes                 (4)
//     mcpverbs.h   for/pack-task task · exemplar request note                           (2)
//     tracelocus.h --from-trace src note                                                (1)
//     serialize.h  the <b>/<o> per-symbol name echo inside a comment                    (1)
// 2026-08-08 (final-sweep): 14 -> 11. L1 (density audit) dropped the comment-echoed `route note` from THREE
// of the fourteen sites — main.cpp's --for route note, packtask.h's route note, and mcpverbs.h's route
// reason — because the route= attribute (ctxRootOpen, attribute-escaped) is now the ONE copy of that text
// (test/routeoncecheck.sh pins the single-copy contract); the comment echo was a duplicated ~230-260 B per
// routed call that a scrub still had to run over. The 14th (`main.cpp`'s queryRouteNote, --query) landed in
// the wave-3 merge, and the mechanism worked as designed: this line still read 13, (S4) went red naming the
// true figure, and the fix was one line. That is the whole point — the count is now load-bearing rather
// than decorative.
inline std::string xmlCommentText( std::string_view raw )
{
    std::string out;
    out.reserve( raw.size() );

    const char*       d = raw.data();
    const std::size_t n = raw.size();
    for( std::size_t i = 0; i < n; )
    {
        const unsigned char c = static_cast<unsigned char>( d[i] );
        if( c < 0x20 )                                                          // rule 2 — every control byte, \t\n\r included
        { out += ' ';  ++i;  continue; }
        if( c == '-' && !out.empty() && out.back() == '-' )                      // rule 1 — collapse the run, don't drop content
        { ++i;  continue; }
        if( c < 0x80 ) { out += d[i];  ++i;  continue; }
        if( const int len = utf8SeqLen( d, i, n ); len == 0 ) { out += '?';  ++i; }   // rule 3
        else { out.append( d + i, std::size_t( len ) );  i += std::size_t( len ); }
    }
    return out;
}

// §B1.7 — THE VERBATIM TASK ECHO. Every task-shaped verb prints its header prose inside an XML COMMENT,
// where "--" is ill-formed and "-->" would close the comment early, so the echo of the user's own query is
// dash-COLLAPSED before it goes in ("--for's default" → "-for's default"). That scrub is correct and stays;
// what was wrong is that the collapsed text was the ONLY copy in XML, so the two dialects disagreed about
// the string the user typed (--json echoes it raw). An ATTRIBUTE has no such restriction — this renders the
// root element's opening tag carrying the VERBATIM task and route note, beside the comment's readable
// scrubbed echo. Empty task AND empty route ⇒ a bare "<ctx>", so every other verb's bytes are untouched.
//
// W3FIX M2 — the LIMIT of "verbatim", stated because a caller comparing the two dialects will find it: \t \n \r
// round-trip EXACTLY (escapeXml writes them as character references, which survive attribute-value
// normalization), but the rest of the C0 set becomes a space, because XML 1.0 forbids those bytes in a document
// even as a character reference — there is no encoding of them for this format to choose. The --json dialect,
// which has no such rule, stays byte-verbatim for all of them. XML scrubs one class of byte; it no longer
// silently rewrites the whitespace a user actually typed.
inline std::string ctxRootOpen( std::string_view task, std::string_view routeNote )
{
    std::vector<char> esc;
    std::string       out = "<ctx";
    if( !task.empty() )      { out += " task=\"";   out += escapeXml( task, esc );       out += "\""; }
    if( !routeNote.empty() ) { out += " route=\"";  out += escapeXml( routeNote, esc );  out += "\""; }
    // §B12.7's TELL. Emitted ONLY when the scrub actually lost bytes, so it is absent on every ordinary
    // document (same silence-means-nothing-happened convention route=/over_ceiling use) and the goldens do
    // not move. Present, it says: this attribute is NOT the verbatim copy its contract promises, and the
    // --json dialect of the same field is. Named per-field because a task can be lossy while its route note
    // is not — a single root-level bit would make the reader guess which one.
    if( !task.empty() && xmlScrubIsLossy( task ) )
    {
        out += " task_scrubbed=\"1\"";
    }
    if( !routeNote.empty() && xmlScrubIsLossy( routeNote ) )
    {
        out += " route_scrubbed=\"1\"";
    }
    out += ">";
    return out;
}

// ── ctxRootOpen's JSON TWIN, and the reason it is one function rather than a rule ─────────────────────────
// The header above promises the scrub fact is legible "from either one" of the two dialects. It was not: the
// tree had ONE emitter of the JSON twin (the body writer's "xml_scrubbed") against THREE XML markers, so for
// the task echo — the header's own headline example — VT/FF/ESC/invalid-UTF-8 all produced task_scrubbed="1"
// in XML and nothing whatsoever in JSON, on --for and --pack-task alike. The machinery was right and the
// coverage was one call site short, which is what a promise phrased as a RULE gets you.
//
// So the JSON side is a function, taking the same two strings ctxRootOpen takes and reading the same single
// predicate. A call site that emits the "task" key emits this beside it and cannot answer the question
// differently, because it does not answer it at all. The keys are absent on clean input (the
// silence-means-nothing-happened convention route=/over_ceiling use), so no ordinary document moves a byte.
// Named with the xml_ prefix like the body twin: JSON is the FAITHFUL dialect, and what it is disclosing is
// something the OTHER dialect lost.
inline std::string ctxRootJsonScrubKeys( std::string_view task, std::string_view routeNote )
{
    std::string keys;
    if( !task.empty() && xmlScrubIsLossy( task ) )
    {
        keys += ",\"task_xml_scrubbed\":true";
    }
    if( !routeNote.empty() && xmlScrubIsLossy( routeNote ) )
    {
        keys += ",\"route_xml_scrubbed\":true";
    }
    return keys;
}

// CDATA-body scrub shared by packSource / packBodies / packOutline: split any "]]>" so the CDATA section
// stays valid, scrub forbidden C0 control bytes (xmlSafeByte, G4), AND replace invalid UTF-8 sequences with
// '?' (A4-F20 — a stray Latin-1 byte in a source body otherwise makes xmllint reject the whole document).
// Single pass, appends into caller-owned `safe`; deterministic + locale-independent. On all-valid input the
// output is byte-identical to the prior inline loops (golden-neutral).
inline void appendCdataSafe( std::string_view body, std::string& safe )
{
    const char*       d = body.data();
    const std::size_t n = body.size();
    for( std::size_t i = 0; i < n; )
    {
        if( i + 2 < n && d[i] == ']' && d[i + 1] == ']' && d[i + 2] == '>' )
        { safe += "]]]]><![CDATA[>";  i += 3;  continue; }
        const unsigned char c = static_cast<unsigned char>( d[i] );
        if( c < 0x80 ) { safe += xmlSafeByte( d[i] ); ++i; }
        else if( const int len = utf8SeqLen( d, i, n ); len == 0 ) { safe += '?'; ++i; }   // scrub invalid UTF-8
        else { safe.append( d + i, std::size_t( len ) ); i += std::size_t( len ); }
    }
}

// streamed writer: fwrite on fill + on flush; one syscall per 64 KB, never per token.
class XmlWriter
{
public:
    explicit XmlWriter( std::FILE* out ) noexcept : m_out( out ) {}
    ~XmlWriter() { flush(); }
    XmlWriter( const XmlWriter& )            = delete;
    XmlWriter& operator=( const XmlWriter& ) = delete;

    void write( std::string_view s ) noexcept
    {
        const char* p = s.data();
        std::size_t  n = s.size();
        while( n )
        {
            const std::size_t room = kCap - m_used;
            const std::size_t take = n < room ? n : room;
            std::memcpy( m_buf + m_used, p, take );
            m_used += take;  p += take;  n -= take;
            if( m_used == kCap )
            {
                flush();
            }
        }
    }

    void flush() noexcept
    {
        if( m_used )
        {
            // A4-F18: a short fwrite (disk full, broken pipe, quota) previously went UNNOTICED — the map was
            // silently truncated and ripwire still exited 0. Latch the failure so the caller can turn it into a
            // nonzero exit + one stderr line (the failed fwrite also sets ferror(m_out), the seam main reads).
            const std::size_t wrote = std::fwrite( m_buf, 1, m_used, m_out );
            if( wrote != m_used )
            {
                m_writeError = true;
            }
            m_used = 0;
        }
    }

    // A4-F18: true once any fwrite in this writer's lifetime failed to write every byte. main can also observe
    // the same condition via ferror(stdout) after the final flush (the failing fwrite sets the stream's error
    // indicator), which is how the exit-code wiring reaches it without threading a bool through every emitter.
    bool hadWriteError() const noexcept { return m_writeError; }

private:
    static constexpr std::size_t kCap = 65536;
    std::FILE*  m_out;
    std::size_t m_used = 0;
    bool        m_writeError = false;
    char        m_buf[ kCap ];
};

// L3 field-notes surfacing: attach `<note d="ISO-date"><![CDATA[text]]></note>` children for a symbol or file
// `target` (a canonical id, or a path). INERT when `ni == nullptr` (no/empty notes file) → it writes ZERO
// bytes, so the whole pipeline stays byte-identical to the pre-feature output on every verb (the L3 inertness
// contract, gated by cmp). Notes are DATA, never instructions: the date rides an XML-escaped attribute, the
// text a CDATA section that the shared appendCdataSafe splits on any "]]>" — so hostile note text (XML
// metachars, an embedded CDATA-close) can never break the G4 well-formedness gate. `esc` is the caller's
// reusable escape scratch. Emits in the note file's sorted order (deterministic). Additive: it only ever
// appends new child elements, never touches the element it decorates.
// Emit ONE `<note>` element, shared by renderNoteChildren (the retrieval-time surfacing below) and the CLI's
// --notes listing handler (main.cpp) — one place spells the sha/branch attribute shape, so the two can never
// drift apart. `d=` is always present; `sha=`/`branch=` are OMITTED entirely on a legacy (unstamped) note
// rather than emitted empty — an absent attribute is unambiguously "no provenance recorded", never confused
// with a resolvable-but-empty one. The sha is shown ABBREVIATED (notes::shortSha, 7 hex — terse, matching
// git's own --abbrev default); the full sha lives only in .ripwire_notes on disk.
inline void appendOneNote( std::string& out, const notes::Note& n, std::vector<char>& esc )
{
    out += "<note d=\"";  out += escapeXml( n.date, esc );  out += "\"";
    if( !n.sha.empty() )
    {
        out += " sha=\"";  out += escapeXml( notes::shortSha( n.sha ), esc );  out += "\"";
        if( !n.branch.empty() ) { out += " branch=\"";  out += escapeXml( n.branch, esc );  out += "\""; }
    }
    out += ">";
    std::string safe;  safe.reserve( n.text.size() );
    appendCdataSafe( n.text, safe );
    out += "<![CDATA[";  out += safe;  out += "]]></note>";
}

// The writer-sink form: one wrapper over the string form, so the element's shape is spelled exactly once.
inline void appendOneNote( XmlWriter& w, const notes::Note& n, std::vector<char>& esc )
{
    std::string out;  appendOneNote( out, n, esc );  w.write( out );
}

// W3-N2: RENDER the auto-surfaced note children instead of streaming them straight out, so a BUDGETED
// emitter can charge their exact emitted size. The JSON sibling has done this since §B1.3 (the notes are
// pre-rendered and jsonSigEntryCost adds `e.notes.size()`); the XML side emitted them for free, which put
// a note-heavy tree measurably over a tight --token-budget while JSON honored the same ceiling. Returns ""
// for a null index / no hits, so the wrapper below stays byte-identical on a tree with no notes.
inline std::string renderNoteChildren( const notes::NoteIndex* ni, const std::string& target, std::vector<char>& esc )
{
    std::string out;
    if( !ni )
    {
        return out;
    }
    const std::vector<std::uint32_t>* hits = ni->find( target );
    if( !hits )
    {
        return out;
    }
    for( std::uint32_t i : *hits )
    {
        appendOneNote( out, ni->notes[i], esc );
    }
    return out;
}


// D5 — THE TWO NOTE LOOKUP KEYS. A raw CRAWL-ROOT-PREFIXED path (ing.files[...], spelled `<root>/<relative>`
// verbatim, arch.h §S2) is root-relativized against the NoteIndex's OWN root so it matches the ROOT-RELATIVE
// keys notes are stored under (notes.h::normalizeNoteTarget); `rawPath` itself is never mutated, only the
// lookup key (never anything emitted as `p=`). The symbol key adds canonicalId, which degrades to the bare
// name when scope is empty, so a free function's SYM target is unaffected.
//
// §B1.3: these are the ONLY spellings of both rules — the JSON note emitter needs byte-identical keys, and a
// second spelling down there is exactly how two serializations of one note set drift apart. Both are
// NULL-SAFE and return "" for a null index, which is what lets every caller (XML or JSON) hand the result
// straight to an emitter that already no-ops on a target with no hits: no `if( ni )` guard per call site,
// and no pair of two-line wrappers whose bodies differ only in which key they build.
inline std::string fileNoteTarget( const notes::NoteIndex* ni, const std::string& rawPath )
{
    return ni ? std::string( relForHash( rawPath, ni->root ) ) : std::string{};
}

inline std::string symbolNoteTarget( const notes::NoteIndex* ni, const IngestResult& ing, const Symbol& s )
{
    return ni ? canonicalIdRelTo( ing, s, ni->root ) : std::string{};
}

// ── T1: per-language token calibration ──────────────────────────────────────────────────────────────
// est_tokens is ONE number over a heterogeneous XML map. A single chars/N divisor is ±20-35% wrong
// because (a) the map is majority terse MARKUP, not raw code, and (b) the per-language BPE spread
// still moves the content bytes. We DELIBERATELY do NOT vendor a BPE table — Claude's tokenizer is
// not public (§2f: a vendored blob buys exactness for the WRONG tokenizer). Instead a declarative
// constexpr table of MEASURED bytes/token, calibrated against tiktoken o200k_base over per-language
// ripwire map outputs (test/tokenbudgetcheck.sh records the corpus + MAPE). o200k↔cl100k spread on
// our minified output is ≤4% (measured), well inside the headroom margin, so one family suffices.
//
// The estimate = (accurate envelope + content byte model) / (symbol-language-weighted bytes/token).
// Bytes are attributed to the MARKUP ENVELOPE (near-constant density) vs per-symbol CONTENT (names/
// paths, whose language sets the divisor), then divided by the weighted rate — never a flat /4.
struct TokenCalib
{
    Lang        lang;
    double      bytesPerToken;   // measured B/tok of ripwire map output in this language (o200k_base)
};

// MEASURED B/tok of the whole minified map per dominant language (o200k_base; see the check's corpus).
// Markup dominates the stream so the spread is compressed to ~2.36-2.59; the table keeps the honest
// per-language differences rather than pretending they vanish. Unknown/absent → kBytesPerTokenDefault.
inline constexpr TokenCalib kTokenCalib[] =
{
    { Lang::Cpp,        2.46 },   // C++/ObjC++ identifiers + terse tags
    { Lang::ObjC,       2.46 },
    { Lang::Python,     2.36 },   // snake_case + shorter names → denser tokens
    { Lang::TypeScript, 2.59 },
    { Lang::Go,         2.53 },
    { Lang::Rust,       2.59 },
    { Lang::Swift,      2.55 },
    { Lang::JavaScript, 2.59 },   // same identifier shape as TypeScript
    { Lang::Bash,       2.50 },   // short command names + $VARs; mid-band
    { Lang::Java,       2.55 },   // verbose CamelCase identifiers; upper-mid band
    { Lang::Ruby,       2.40 },   // snake_case + short method names, prose-like; denser
    { Lang::Markdown,   2.56 },   // heading text tokenizes like prose
    { Lang::Json,       3.10 },   // measured 2026-07 (n=108): package.json/tsconfig.json, o200k_base
    { Lang::CSharp,     2.55 },   // B6.2: REASONED, not yet measured (no corpus run) — verbose PascalCase
                                   // identifiers put it in Java's band; recalibrate once tokenbudgetcheck
                                   // gets a C# corpus sample. Unlike Json, `s.lang==CSharp` never reaches
                                   // this table via estimateTokens's contentBytesByLang[13] index (it
                                   // clamps into the Unknown bucket, model.h's documented headroom) — this
                                   // entry only feeds bytesPerTokenFor's OTHER direct callers (serialize.h).
    { Lang::C,          2.46 },   // L3: REASONED, not measured — same short snake_case/terse identifier
                                   // convention as C++ (they share a lexicon; a C corpus is not meaningfully
                                   // denser/sparser than the C++ one this rate was measured on), so C
                                   // borrows Cpp's exact rate rather than guessing a new one. Same headroom
                                   // clamp as CSharp above: `s.lang==C` never reaches contentBytesByLang[13].
    { Lang::Toml,       3.10 },   // REASONED, not measured — TOML borrows Json's exact rate rather than
                                   // guessing a new one: both lanes emit t="sec" symbols whose names ARE the
                                   // config keys, so the emitted stream has the same shape (short dotted/
                                   // snake-case key text inside dense markup) that made Json the sparse
                                   // outlier at 3.10. Recalibrate together with Json when tokenbudgetcheck
                                   // next gets a config-file corpus sample. Same headroom clamp as CSharp/C
                                   // above: `s.lang==Toml` (16) never reaches contentBytesByLang[13].
    { Lang::Yaml,       3.10 },   // REASONED, not measured — the third data-config lane borrows the same
                                   // Json rate for the same reason as Toml directly above: identical emitted
                                   // shape (t="sec" rows whose names ARE the config keys). Recalibrate with
                                   // Json/Toml together. Same headroom clamp: `s.lang==Yaml` (17) never
                                   // reaches contentBytesByLang[13].
};
inline constexpr double kBytesPerTokenDefault = 2.50;   // Unknown-language / empty-map fallback (mid-band)

// Full DEF BODY text (packBodies / --expand) tokenizes far LEANER than the map's signature-dense content:
// method bodies carry indentation, braces, and repeated whitespace that BPE merges aggressively — MEASURED
// ~3.8 B/tok on real o200k (vs ~2.46 for C++ SIGNATURE markup). Using the signature rate on body bytes
// over-reads ~24% (buildGraph body is ~8.8K real tokens, not ~11K). So the
// --expand body estimate scales body text at THIS rate, keeping markup/callee-sigs at their own (denser) rates.
inline constexpr double kBytesPerTokenBody = 3.80;

// The DENSEST (smallest B/tok) rate across the table = the most tokens a byte can cost. --max-tokens
// converts its byte-fit budget with THIS conservative rate so the real token count of the packed map
// never exceeds the requested ceiling regardless of the corpus's language mix. (Python is densest.)
inline constexpr double kMinBytesPerToken = 2.36;

// --max-tokens fits to a fraction of the requested budget so the number is a CEILING, not a target
// (§2f: a 90%-of-budget headroom factor beats chasing exactness against a tokenizer we can't see).
inline constexpr double kBudgetHeadroom = 0.90;

// W3FIX H2/M1 — THE SINGLE-ENTRY OVERSHOOT TOLERANCE. The task lenses (--for, --pack-task) state a hard byte
// ceiling in their own header (budgetTokens x kMinBytesPerToken), but their ranking section emits its FIRST
// entry WHOLE — a symbol's signature is not divisible, so a bundle whose first row is large lands a little
// over the ceiling with nothing left to trim. The design has always accepted that overshoot; it was written
// down twice as a bare 1.15 in test/bundleidcheck.sh and test/partitioncheck.sh and NOWHERE in the code, so
// the emitters could not consult the tolerance they are judged against and instead compared against the bare
// ceiling. That mismatch is what made the ceiling disclosure fire on a 1.8%-over document and then push it to
// 15% over with the disclosure's own bytes. This is the ONE number: at or under it, the bundle is conformant
// and says nothing; past it, the lens has provably failed to trim to fit and labels itself over_ceiling.
inline constexpr double kCeilingFirstEntryTolerance = 1.15;

// The delivered-byte allowance a lens is judged against for a given token budget — ceiling x the tolerance
// above, in ONE expression so --for and --pack-task cannot drift apart on the arithmetic.
inline constexpr std::size_t ceilingAllowanceBytes( std::size_t budgetTokens ) noexcept
{
    return std::size_t( double( budgetTokens ) * kMinBytesPerToken * kCeilingFirstEntryTolerance );
}

// CA4 §B3 — the SAME bar, for a lens whose caller resolved the token budget into BYTES before the call.
// --from-trace's FromTraceInputs carries `bundleBudgetBytes` (already tokens x kMinBytesPerToken x
// kBudgetHeadroom), so it cannot call the sibling above without a `budgetTokens` field its two call sites do
// not have. Algebraically identical, which is the point of expressing it here rather than open-coding a
// second constant: bytes x (tolerance / headroom) == tokens x rate x headroom x tolerance / headroom
// == tokens x rate x tolerance == ceilingAllowanceBytes( tokens ). One expression, so the three task lenses
// cannot drift apart on the arithmetic.
inline constexpr std::size_t ceilingAllowanceFromBudgetBytes( std::size_t budgetBytes ) noexcept
{
    return std::size_t( double( budgetBytes ) * ( kCeilingFirstEntryTolerance / kBudgetHeadroom ) );
}

// The three sentences a ceiling ladder splices into a header. Supplied by the caller because each lens writes
// its comment in its own punctuation (--for uses [bracket notes], --pack-task a | pipe-separated report).
struct CeilingLadderNotes { std::string_view echoDropped, echoAndRouteDropped, overCeiling; };

// THE CEILING LADDER, one implementation for both task lenses — --for and --pack-task climbed identical rungs
// in identical order, and a duplicated ladder is a ladder that will diverge. `build( withRouteAttr,
// withTaskEcho, extraNotes )` returns the header for that shape; this PRICES shapes and returns the one to
// emit, so a caller can never price a shape it then fails to build (the failure mode of the string-surgery
// version this replaced). Rungs, cheapest information loss first:
//   (a) as built — returned untouched when it already fits, which is the overwhelmingly common case;
//   (b) the comment's task echo dropped: a byte-for-byte DUPLICATE, since the verbatim copy stays in task=;
//   (c) that plus the verbatim route= attribute — the first rung that costs unique information;
//   (d) nothing reaches the allowance: the header AS BUILT plus an over_ceiling sentence, because a caller who
//       hit the wall is owed the complete bundle and an honest label, not a mutilated bundle.
// Every candidate is measured WITH its own disclosure bytes included. Pure function of its inputs — no clock,
// no map order — so the chosen shape is deterministic.
template<typename BuildFn>
inline std::string climbCeilingLadder( BuildFn&& build, std::string_view builtHeader, std::size_t payloadBytes,
                                       std::size_t byteCeiling, bool hasRouteAttr, const CeilingLadderNotes& notes )
{
    const auto fits = [ & ]( std::size_t headerBytes ) { return headerBytes + payloadBytes <= byteCeiling; };
    if( fits( builtHeader.size() ) )
    {
        return std::string( builtHeader );
    }

    std::string candidate = build( /*withRouteAttr=*/true, /*withTaskEcho=*/false, notes.echoDropped );
    if( !fits( candidate.size() ) && hasRouteAttr )
    {
        candidate = build( /*withRouteAttr=*/false, /*withTaskEcho=*/false, notes.echoAndRouteDropped );
    }
    if( !fits( candidate.size() ) )
    {
        candidate = build( /*withRouteAttr=*/true, /*withTaskEcho=*/true, notes.overCeiling );
    }
    return candidate;
}

// ── B0.3 rank-adaptive --for payload budget (R1 hypothesis #4) ────────────────────────────────────────
// The --for lens spends the same per-result payload on rank 40 as on rank 1, and long conceptual queries
// (the A7 token blocker: production ceiling p95 +62.9%) surface doc-heavy winners. Downstream-LLM accuracy
// measurably DEGRADES with context length (R1's context-rot evidence), so the tail is trimmed by a rule
// that is a PURE function of (global rank, these fixed byte limits) — deterministic, query-independent:
//   rank 1..kForDocFullRankCount        → untouched (full doc excerpt + full signature);
//   rank ..kForDocExcerptRankCount      → doc excerpt truncated to kForDocExcerptBytes (UTF-8-safe + "…");
//   rank beyond kForDocExcerptRankCount → signature-only (no doc), signature capped at kForTailSigBytes.
// Applied ONLY when the caller opts in (the --for lens and the MCP `for` verb) — --pack-signatures, the
// default map, --format=candidates, and the golden are untouched by construction (default param off).
inline constexpr std::size_t kForDocFullRankCount    = 12;
inline constexpr std::size_t kForDocExcerptRankCount = 24;
inline constexpr std::size_t kForDocExcerptBytes     = 96;
inline constexpr std::size_t kForTailSigBytes        = 160;

// ── B0 round 2 (H1): GLOBAL deterministic payload budget for the ranked --for bundle ─────────────────
// The rank tiers above cut only ~1% of the measured LocBench payload: the worst bundles are dominated by
// the TOP-12 full entries with long doc comments (payload p50 12,776 B / p95 18,793 B), and the paired
// token budget holds iff the whole response is capped at ≤ ~8,000 B (measured; 7,500 B ⇒ paired p95 ratio
// 1.000). So the --for lens (CLI --for + MCP `for` verb ONLY — never --pack-signatures, the default map,
// or the candidates export) enforces a fixed default budget over the whole bundle; the <sigs> block is
// where trimming happens, via a LADDER that is a pure function of (global rank, these constants), applied
// from the tail upward AFTER the rank tiers:
//   A. tail (rank > kForDocExcerptRankCount)  : signature shrinks 160 → kForCapTailSigBytes;
//   B. rank 13..24                            : doc excerpt dropped;
//   C. rank 1..12                             : doc capped at kForDocExcerptBytes;
//   D. rank 5..12                             : doc dropped, signature capped at kForTailSigBytes;
//   E. rank 1..4                              : signature capped at kForTailSigBytes (doc keeps its
//                                               kForDocExcerptBytes floor — never below sig 160 + doc 96);
//   F. entries of rank ≥ 5 dropped whole, tail-first (rank 1..4 always survive at the floor).
// Each single-entry action re-checks the budget, so the ladder stops at the first fitting state —
// deterministic, query-independent, and self-announcing (capped="1" on <sigs>). An EXPLICIT
// --token-budget=N overrides the default (N tokens × the conservative byte rate), so a caller who asks
// for a bigger (or smaller) bundle beats the default.
inline constexpr std::size_t kForPayloadBudgetBytes = 7500;
inline constexpr std::size_t kForCapTailSigBytes    = 96;

// deterministic UTF-8-safe prefix cut + a visible ellipsis (the honest "there was more" marker); the
// boundary back-off mirrors docCommentBefore's cap cut. No-op when the text already fits.
inline void truncateUtf8WithEllipsis( std::string& s, std::size_t maxBytes )
{
    if( s.size() <= maxBytes )
    {
        return;
    }
    std::size_t cut = maxBytes;
    while( cut > 0 && ( static_cast<unsigned char>( s[cut] ) & 0xC0 ) == 0x80 )
    {
        --cut;
    }
    s.resize( cut );
    s += "\xE2\x80\xA6";   // U+2026 ellipsis
}

inline constexpr double bytesPerTokenFor( Lang l ) noexcept
{
    for( const TokenCalib& c : kTokenCalib )
    {
        if( c.lang == l )
        {
            return c.bytesPerToken;
        }
    }
    return kBytesPerTokenDefault;
}

// ── §H7: THE one conversion from EMITTED BYTES to reported tokens ──────────────────────────────────
// est_tokens used to be a per-PAYLOAD formula, and the formulas did not keep up with the emitters:
// estimateTokens() below models the map's kept symbol SET, --expand grew a second estimator of its own
// (estimateExpandBodyTokens), and the remaining payloads were never charged at all — one measured number
// covered four different documents (MEASURED on src/, --top-k=10: bare map 1435 B, --metrics 2129 B,
// --pack-signatures 12850 B, --pack-top-n=3 67143 B, --outline 2668 B, all reporting est_tokens=507, up
// to ~52x under). A formula per payload is exactly how that recurs, so no emitter estimates its own size
// any more: each one MEASURES the bytes it actually wrote and converts them HERE, at the calibrated rate
// for what those bytes ARE (a kTokenCalib / model-weighted rate for markup+signatures,
// kBytesPerTokenBody for def bodies and raw source). Rounds to nearest so the number never systematically
// under-reads. VERIFY, not a clamp: a non-positive rate is a corrupt caller, never a runtime condition.
inline std::size_t tokensForEmittedBytes( std::size_t emittedBytes, double bytesPerToken ) noexcept
{
    VERIFY( bytesPerToken > 0.0 );
    return std::size_t( double( emittedBytes ) / bytesPerToken + 0.5 );
}

// A header that PRINTS est_tokens is part of the document est_tokens describes, so its own digit count feeds
// back into the number. Emitters whose header is a plain string iterate that to a fixpoint (serialize(), and
// recall.h's buildRecall before it); emitters whose header can only be produced by writing to a stream price
// the digit string with this reserve instead — 8 digits covers any document up to ~100M tokens, i.e. ≈3
// tokens of slack, far inside the estimate's own accuracy band.
inline constexpr std::size_t kEstTokensFieldReserve = 8;

// §H7 — a payload SECTION appended after the map (<sigs>, <src>, <bodies>, <outline>), rendered and charged
// in ONE step: the bytes it will actually contribute, and what those bytes cost at the rate appropriate to
// what they ARE. Every such block goes through here, which is the point — a new appended section cannot be
// added without naming its rate, and cannot be added without being charged. That replaces the previous
// arrangement, where --expand grew a bespoke estimator (estimateExpandBodyTokens: ~90 lines, a second read
// of every file, mirroring packBodies' accounting closely enough to be "honest ±15%") and the other three
// sections were simply never counted.
//
// DEGRADE: an open_memstream failure leaves isRendered false — the caller streams that section directly and
// est_tokens then does not cover it, which is exactly the pre-§H7 behaviour for that one run, never a
// fabricated number. Callers with a cheaper fallback estimate (--expand has one) may use it instead.
struct ChargedSection
{
    std::string xml;                 // the rendered bytes — empty when the section emits nothing, or on degrade
    std::size_t tokens     = 0;      // tokensForEmittedBytes( xml.size(), the section's own rate )
    bool        isRendered = false;  // false ⇒ open_memstream failed; the caller must emit this section directly
};

// ── THE est_tokens FAMILY'S ONE BUFFER SEAM, and the fault switch that makes its degrade path REACHABLE ──
// The wave-1 verifier's declared coverage debt: these `open_memstream` failure paths were NEVER exercised,
// so trap #3 ("a gate arm that asserts a degrade path must FAIL, not skip, on a build that cannot observe
// alerts") was unanswered for §H7. `open_memstream` fails on ALLOCATION, not on fd exhaustion, so no
// `ulimit -n` harness comes near it — the failure has to be injected.
//
// One seam for two reasons. (1) The family's degrade CONTRACT is one contract — the section/document still
// emits complete, correct bytes; est_tokens falls back to the MODELLED number; a DEGRADED_PATH_ALERT says
// which — and a contract restated at five call sites is a contract that diverges at one of them.
// (2) A single switch then exercises the whole family, which is what test/estchargecheck.sh's degrade arm
// asserts against.
//
// THE SWITCH EXISTS ONLY ON THE NON-NDEBUG FLAVOUR — the same flavour `DEGRADED_PATH_ALERT` itself exists
// on. The hook and the observation it enables therefore appear and disappear TOGETHER: a release build has
// neither, and `isChargeBufferFaultInjected()` is `constexpr false` there, so the branch and the getenv are
// both deleted (G2/G3: zero release cost, no behaviour to diverge). Read ONCE per process, so the answer
// cannot change mid-document and determinism holds.
//
// REJECTED ALTERNATIVE (the brief asks for a hook-free route if one is cleaner): interposing
// `open_memstream` itself — macOS `__DATA,__interpose` + DYLD_INSERT_LIBRARIES, Linux LD_PRELOAD. It needs a
// per-platform shim compiled inside the gate; it fails EVERY memstream in the process, including the cache
// and sidecar paths, which confounds the very assertion that matters ("the bytes are still complete and
// correct"); and it fights the ASan runtime, which this gate must also run under. Scoping the fault to the
// est_tokens family is what keeps the assertions clean, so the in-source switch wins on honesty, not effort.
#ifndef NDEBUG
inline bool isChargeBufferFaultInjected() noexcept
{
    static const bool isOn = []() noexcept
    {
        // CA4 w1fix2-verifier G4: this read `value[0] == '1'`, so `=10`, `=1x` and `=1000000` all injected the
        // fault — a prefix test where the contract is a switch. EXACT "1" is the only ON value; anything else,
        // including "0", "true" and the empty string, is OFF.
        const char* value = std::getenv( "RIPWIRE_FAULT_CHARGE_BUFFER" );
        return value != nullptr && std::strcmp( value, "1" ) == 0;
    }();
    return isOn;
}
#else
inline constexpr bool isChargeBufferFaultInjected() noexcept { return false; }
#endif

// Drop-in for `open_memstream` at every est_tokens-family measurement buffer. nullptr ⇒ the caller takes its
// own documented degrade path; this function never reports a failure it did not have.
inline std::FILE* openChargeBuffer( char** bufOut, std::size_t* sizeOut ) noexcept
{
    if( isChargeBufferFaultInjected() )
    {
        return nullptr; // ENOMEM-class, on demand, non-release only
    }
    return open_memstream( bufOut, sizeOut );
}

// ── §B4b: the <ctx> WRAPPER RULE for a verb that appends a section beside serialize()'s root ─────────────
// serialize() OWNS a root element — it writes `<r …>` and it writes `</r>` — so anything a caller emits after
// it is a SECOND top-level element and the document is not XML. G4 ("output | xmllint --noout clean") is one
// of the four hard guardrails, and `--around` breached it at exit 0: `--around=buildRecall` tailed
// `…</f></r><compose>…</compose>`, xmllint said "Extra content at the end of the document", ripwire said 0.
// MEASURED 5 of 135 sampled symbols on this repo — every focus symbol whose ego-graph carries compose or
// route edges — and the pre-wave binary breaches byte-identically, so it was pre-existing, not wave damage.
//
// The other two serialize() call sites already had the answer: runDefaultMap wraps <r> plus its four appended
// sections in <ctx>…</ctx> whenever `hasExtension`, and the --for lens roots everything in ctxRootOpen().
// This is that wrapper, expressed once, for the call site that never got it.
//
// The predicate is what will ACTUALLY BE EMITTED, not what edges exist: packCompose/packRoutes write nothing
// when no edge touches the relevant node set, and a bare <ctx></ctx> around <r> would be 11 bytes of wrapper
// disclosing nothing. A section whose charge DEGRADED (isRendered=false) is re-rendered straight to the sink
// by emitChargedSection, so its byte count is unknown here — assume it emits and wrap, which is well-formed
// either way.
inline constexpr std::size_t kCtxWrapBytes = 11;   // "<ctx>" (5) + "</ctx>" (6) — charged, per trap #8

struct CtxWrap
{
    bool        isNeeded = false;
    std::size_t tokens   = 0;   // the wrapper's own charge, 0 when it is not emitted
};

inline bool sectionWillEmit( const ChargedSection& section, bool hasEdges ) noexcept
{
    return hasEdges && ( !section.isRendered || !section.xml.empty() );
}

// The whole decision — wrap or not, and what it costs — as ONE value, so the calling verb carries no boolean
// algebra and no rate arithmetic of its own.
inline CtxWrap ctxWrapFor( const ChargedSection& a, bool aHasEdges, const ChargedSection& b, bool bHasEdges ) noexcept
{
    if( !sectionWillEmit( a, aHasEdges ) && !sectionWillEmit( b, bHasEdges ) )
    {
        return {};
    }
    return { true, tokensForEmittedBytes( kCtxWrapBytes, kBytesPerTokenDefault ) };
}

template<typename RenderFn>
inline ChargedSection chargeSection( RenderFn&& render, double bytesPerToken )
{
    ChargedSection  sec;
    char*           buf = nullptr;
    std::size_t     sz  = 0;
    std::FILE*      mem = openChargeBuffer( &buf, &sz );
    if( !mem )
    {
        DEGRADED_PATH_ALERT( "chargeSection: open_memstream failed — this payload section streams uncharged" );
        return sec;
    }
    render( mem );
    std::fflush( mem );
    std::fclose( mem );
    if( buf ) { sec.xml.assign( buf, sz );  std::free( buf ); }
    sec.tokens     = tokensForEmittedBytes( sec.xml.size(), bytesPerToken );
    sec.isRendered = true;
    return sec;
}

// The other half of the contract, and the ONLY correct way to spend a ChargedSection: write the bytes that
// were charged, or — when the charge degraded — render the section directly at the same inputs, so the
// document is complete either way. It is a named seam rather than an if/else at each site because §F1 added
// four more emission points to the one runDefaultMap already had as a local lambda, and "charged bytes if
// rendered, else re-render" copied five times is the shape that eventually gets copied WRONG (emitting the
// empty xml of a degraded section, which loses the section silently — the failure this whole item is about).
template<typename RenderFn>
inline void emitChargedSection( std::FILE* out, const ChargedSection& sec, RenderFn&& renderDirect )
{
    if( sec.isRendered )
    {
        std::fwrite( sec.xml.data(), 1, sec.xml.size(), out );
    }
    else
    {
        renderDirect();
    }
}

// estimateTokens' answer: the modelled token count AND the modelled byte total it was derived from.
// Publishing the byte total is what makes the model's language-weighted RATE reusable by a caller that
// has MEASURED bytes — and that split is deliberate, because the two halves of the model have very
// different accuracy. The per-language mix (kTokenCalib) is measured and good; the byte counting is a
// handful of fixed per-element constants that know nothing about --metrics decoration, id=, overloads=,
// bind=, prov= or the multi-root prologue, which is why the modelled byte total ran ~13% under the real
// document even on the bare map. So serialize() takes the RATE from here and the BYTES from the document
// it actually emitted.
struct TokenEstimate
{
    std::size_t tokens     = 0;   // modelled tokens for the kept symbol set
    std::size_t modelBytes = 0;   // the byte total that model priced (markup envelope + per-language content)

    // this symbol set's own language-weighted bytes/token; the mid-band default for an empty/degenerate map
    double bytesPerToken() const noexcept
    {
        return tokens > 0 ? double( modelBytes ) / double( tokens ) : kBytesPerTokenDefault;
    }
};

// The near-constant markup ENVELOPE the map always carries, in bytes: the leading schema comment +
// the <r>…</r> root + the stats preamble comment. Measured on the default (non-scip) header; the
// estimate is informational (a ceiling for --max-tokens headroom), so a few bytes of drift between
// header variants is immaterial. Content (file/symbol/edge markup + names) is added per-element below.
inline constexpr std::size_t kEnvelopeBytes = 320;

// Per-element MARKUP byte costs (default map), measured against real output:
//   <f p="…">…</f>            = 12 + path            (+9 when a builtin layer= tag is present)
//   <s t="…" n="…" …></s>     = 19 + name            (+11 for k=, +6+canon when scoped; metrics adds more)
//   <c n="…"/>                = 9  + callee-name
inline constexpr std::size_t kFileMarkupBytes   = 12;
inline constexpr std::size_t kSymMarkupBytes    = 19 + 11;   // base tags + the default k="0.XXXX" attr
inline constexpr std::size_t kEdgeMarkupBytes   = 9;

// ── T3: fill-aware auto-ordering ────────────────────────────────────────────────────────────────────
// MEASURED (Anthropic): query/actionable content at the END of a long input = up to +30%. §2f/§2g
// refine WHEN it matters: the U-curve (primacy+recency both fine) holds while the window is <50%
// full; beyond ~50% fill, recency dominates monotonically, so --most-important-last is the right
// default ONLY for large outputs — for a small map, order is free (no measured effect either way),
// so we do NOT disturb it (golden-neutral). kNominalWindowTokens follows the smaller point measured
// in §2a's dose-response study (32K, LongCodeBench); the fill threshold is half of it.
//
// NOT SHIPPED (T7 §2g, measured-and-declined): bimodal emission (rank #1 top + #2 bottom) is a free
// reorder but --eval structurally cannot score it (ranking-recovery is order-invariant) — it needs an
// LLM-in-the-loop harness ripwire deliberately avoids, so it stays a documented open question, not a
// T3 dependency. Markdown-KV/table sub-encoding was also measured (T7): a per-symbol Markdown-KV
// block is +17% tokens (never amortizes); a Markdown TABLE only wins at >=4 rows on a tabular slice
// (~7% on a whole --metrics map) — marginal with format-contract risk, evaluated and DEFERRED, not
// built here.
inline constexpr std::size_t kNominalWindowTokens  = 32000;                       // §2a's smaller measured dose-response point
inline constexpr std::size_t kFillOrderThreshold   = kNominalWindowTokens / 2;    // ~16000: the measured "recency dominates" crossover

// Extracted T1 byte-model (was inline in serialize()) so the auto-order decision (T3) and the actual
// emission use the IDENTICAL estimate — one implementation, no drift between "decided" and "reported".
// Pure function of the kept symbol set; independent of emit ORDER (bytes are the same regardless of
// which end a symbol lands on), so it is safe to call BEFORE the ordering decision it feeds.
//
// §H7: this model is now the RATE SOURCE and the fill-order oracle, no longer the reported est_tokens.
// The T3 auto-order decision has to be made before a byte of the map exists (the decision picks the emit
// ORDER, so it cannot wait for the emitted bytes), which is precisely what a pure function of the symbol
// set is for; the REPORTED size describes the finished document and is measured. Both are documented at
// their use sites in serialize().
inline TokenEstimate estimateTokens( const IngestResult& ing, const std::vector<NodeId>& order, std::size_t keep,
                                     const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets )
{
    std::size_t                      markupBytes = kEnvelopeBytes;
    double                           contentBytesByLang[ 13 ] = { 0 };   // indexed by Lang enum (13 values)
    static_assert( int( Lang::Unknown ) == 12, "contentBytesByLang sized for the 13-value Lang enum" );
    std::vector<char>                seen( ing.files.size(), 0 );
    for( std::size_t k = 0; k < keep; ++k )
    {
        const NodeId        id = order[k];
        const Symbol&       s  = ing.symbols[id];
        const std::uint32_t f  = s.fileId;
        const int           li = int( s.lang ) < 13 ? int( s.lang ) : int( Lang::Unknown );
        if( !seen[f] )
        {
            seen[f] = 1;
            markupBytes += kFileMarkupBytes;
            contentBytesByLang[ li ] += double( ing.files[f].size() );   // the file PATH is content, at this file's language
        }
        markupBytes += kSymMarkupBytes;
        contentBytesByLang[ li ] += double( s.name.size() );
        if( !s.scope.empty() )
        {
            markupBytes += 6;
            contentBytesByLang[ li ] += double( ing.files[f].size() + s.scope.size() + s.name.size() + 4 );
        }
        for( std::uint32_t e = outOff[id]; e < outOff[id + 1]; ++e )
        {
            markupBytes += kEdgeMarkupBytes;
            contentBytesByLang[ li ] += double( ing.symbols[ outTargets[e] ].name.size() );
        }
    }

    // Weighted token estimate: envelope+markup at the mid-band rate, each language's content at its own
    // measured B/tok. Rounds to nearest (0.5 up) so the reported number never systematically under-reads.
    double estTokensF   = double( markupBytes ) / kBytesPerTokenDefault;
    double modelBytesF  = double( markupBytes );
    for( int l = 0; l < 13; ++l )
    {
        if( contentBytesByLang[ l ] > 0.0 )
        {
            estTokensF  += contentBytesByLang[ l ] / bytesPerTokenFor( Lang( l ) );
            modelBytesF += contentBytesByLang[ l ];
        }
    }
    return TokenEstimate{ std::size_t( estTokensF + 0.5 ), std::size_t( modelBytesF + 0.5 ) };
}

// §P6.3: const/non-const overloads (svector.h's buf()/buf() const, begin()/begin() const, end()/end()
// const) canonicalize to the SAME id= — canonicalId() is path::scope::name, it has no notion of signature
// or const-qualification — so a per-file bucket built straight from `order` carries one row per NodeId and
// two rows print byte-identical name/id/rank, telling a reader nothing extra. collapseOverloadRows()
// pre-filters a bucket down to one representative NodeId per (kind,id) BEFORE serialize()'s print loop
// ever sees it, so that loop keeps iterating a plain vector with NO added branch — every decision this
// collapse needs (first-occurrence tracking, counting) lives here instead of inflating the cognitive
// complexity of the already-large function that loop lives in.
struct OverloadRows
{
    std::vector<NodeId>        id;          // one representative NodeId per printed row, original order
    std::vector<std::uint32_t> overloads;    // parallel: 1 = no collision, N>1 = N rows collapsed into this one
};

inline OverloadRows collapseOverloadRows( const IngestResult& ing, const std::vector<NodeId>& bucket )
{
    OverloadRows out;
    rw::HashMap<std::string, std::size_t> rowOf;   // (kind,id) key -> index into out.id/out.overloads
    for( NodeId nodeId : bucket )
    {
        const Symbol&     s   = ing.symbols[nodeId];
        const std::string key = std::string( symTag( s.kind ) ) + '\x1f' + canonicalId( ing.files[ s.fileId ], s.scope, s.name );
        const auto         it  = rowOf.find( key );
        if( it == rowOf.end() ) { rowOf[key] = out.id.size();  out.id.push_back( nodeId );  out.overloads.push_back( 1 ); }
        else
        {
            ++out.overloads[ it->second ];
            // Deterministic representative choice, independent of traversal order: --most-important-last
            // / T3 auto-flip walk this SAME bucket reversed, and if the min-id NodeId weren't pinned here
            // the "first occurrence" would flip between the two overloads — printing a very-slightly
            // different k= (each overload NodeId carries its own independently-computed PageRank) and
            // breaking the set-equality a reader (and fillordercheck's #9) expects between two orderings
            // of the identical symbol set. The lower NodeId always wins, so content is order-invariant.
            if( nodeId < out.id[it->second] )
            {
                out.id[it->second] = nodeId;
            }
        }
    }
    return out;
}

// " overloads=\"N\"" when N>1 rows collapsed into this one; empty (writes nothing) in the overwhelming
// common case (every id unique) — the golden map stays byte-identical wherever no collision exists.
inline std::string overloadsAttr( std::uint32_t n )
{
    return n > 1 ? ( " overloads=\"" + std::to_string( n ) + "\"" ) : std::string();
}

// ── how THIS map was produced: the three OPTIONAL annotations, as one value ──────────────────────────
// Each is a fact about the RUN rather than about the corpus, each is absent on the default path, and each
// used to arrive as its own trailing defaulted pointer — the signature had reached 24 positional arguments
// and a 25th would have been indistinguishable from the 24th at the call site. Defaulted ⇒ every field
// null ⇒ `<r>` stays exactly `<r>`, zero token cost, byte-identical golden map, and — the house rule this
// exists to protect — NO git subprocess is ever added to the bare default path.
struct MapAnnotations
{
    // NOTE — the three fields below are initialized POSITIONALLY at the call site (main.cpp's mapAnn), so any
    // new annotation goes at the END of this struct, never in front of them.
    const std::size_t* changedCount = nullptr;   // D6: --map-diff's teleport-seed file count → `changed=N` in the
                                                 // header comment. Non-null even at 0 (a clean tree), so a caller can tell a
                                                 // clean-tree map-diff — teleport degrades to uniform, i.e. byte-identical to
                                                 // the default map — from a real diff without shelling out to git itself.
    const std::string* atStamp      = nullptr;   // r26-stamp Task A: gitstamp::stampAt → ` at="<sha>[+dirty]"` on `<r>`, for the
                                                 // maps whose caller ALREADY ran git (--map-diff's diff, --rank-by=churn's mining).
    const std::string* churnWindow  = nullptr;   // §A9.6: --rank-by=churn's effective window label ("18mo", or the --since value
                                                 // when it resolved) → ` rank_by="churn" window="…"`, so a ranking mined entirely
                                                 // from git history is not byte-shaped like a PageRank map.

    // §B13.4: `--max-tokens=N` fits the map against a BYTE ceiling — N x kMinBytesPerToken x kBudgetHeadroom —
    // while the map REPORTS est_tokens in the language-weighted currency, so a caller who asked for 1500
    // received a document reporting 1216 (81% of the budget) with the shortfall disclosed NOWHERE, and a
    // --help that invites composing --max-tokens with --token-budget as if the two Ns were the same unit.
    // Both numbers now travel with the map they shaped. Null for every caller that did not pass
    // --max-tokens ⇒ zero token cost, byte-identical default map.
    //
    // §F5 (CA4 wave-1 verifier): isOverCeiling is the label that keeps the cap a cap. The DISCLOSURE this item
    // added costs 185-312 B, and at small N the map's fixed floor (envelope + legend + this clause + these two
    // attributes) exceeds ceilingBytes with ZERO symbols of content — MEASURED at N=400: ceiling 849 B, emitted
    // 975 B, 15% over, rc=0, stderr empty, the 849 stated inside the 975-byte document. Three more members of
    // the same class ride in the same way, all of them "the probe priced a shape the emission did not build":
    // --map-diff's changed=/at= (+31 B), --rank-by=churn's rank_by=/window= plus kChurnRankLegend (+~200 B) and
    // the T3 auto-flip's longer order= spelling (+11 B). The fit is now priced with the SAME MapAnnotations and
    // the same autoOrder the emission uses (main.cpp), and where the floor still cannot fit, the map SAYS so
    // rather than overshooting in silence — the over_ceiling treatment --for/--pack-task/--recall already have.
    // Monotone by construction: the label only ADDS bytes, and a document already past the ceiling cannot come
    // back under by growing, so there is no oscillation to iterate out.
    struct MaxTokensFit
    {
        std::size_t askedTokens   = 0;
        std::size_t ceilingBytes  = 0;
        bool        isOverCeiling = false;   // ⇒ ` over_ceiling="1"`; absent means the cap was honoured (measured, not assumed)
    };
    const MaxTokensFit* maxTokensFit = nullptr;

    // §B2.1 (CA4): the SAME defect §B1.2 fixed for churn, on the three rankers nobody swept in with it.
    // --rank-by=authority / hub / rrf emitted a header keyset-identical to pagerank's in BOTH dialects while
    // k= underneath meant something else entirely — MEASURED on src/, top row: pagerank 0.0957, authority
    // 0.8254, hub 0.1679, rrf 0.0338, four different quantities under one attribute name and no tell. Churn
    // could not use this field because its stamp also carries a window; these three have no window, so the
    // annotation is the bare ranker LABEL and `churnWindow` stays the churn-only path. Static storage
    // (kRankByLabel below) ⇒ safe to hold as a bare pointer, same rule as `marker`.
    const char* rankByLabel = nullptr;
};

// §B2.1 — the ranker-specific legend clause, one per non-default ranker, emitted ONLY on that ranker's map
// for the same reason kChurnRankLegend is: a flag-only fact does not belong in the string every other run
// shares. Each names WHAT k= is on that map and says the scores are not comparable across rankers, which is
// the actual hazard — the numbers all look like ranks and only one of them is PageRank.
// G4: no "--" anywhere inside an XML comment ⇒ flag names written bare.
struct RankByDisclosure { const char* label; const char* legend; };
inline constexpr RankByDisclosure kRankByDisclosure[] = {
    { "authority",
      "<!-- rank_by=authority: k= is a HITS AUTHORITY score (how much the graph's hub code points at this symbol), not PageRank importance; "
      "the scale differs from every other ranker's, so a k= here is not comparable with a k= from another rank_by -->" },
    { "hub",
      "<!-- rank_by=hub: k= is a HITS HUB score (how much this symbol points at high-authority code), not PageRank importance; "
      "the scale differs from every other ranker's, so a k= here is not comparable with a k= from another rank_by -->" },
    { "rrf",
      "<!-- rank_by=rrf: k= is a RECIPROCAL-RANK-FUSION score over pagerank plus the two HITS axes — a fused rank position, not an importance mass; "
      "the scale differs from every other ranker's, so a k= here is not comparable with a k= from another rank_by -->" },
};

// The label → clause lookup. Returns nullptr for an unstamped map (the default pagerank path) so the caller's
// null check is the same one it makes for churn. Table-driven per the house rule: a new ranker adds a ROW.
inline const char* rankByLegendFor( const char* label ) noexcept
{
    if( label == nullptr )
    {
        return nullptr;
    }
    for( const RankByDisclosure& d : kRankByDisclosure )
    {
        if( std::string_view( d.label ) == label )
        {
            return d.legend;
        }
    }
    return nullptr;
}

// The `at=` stamp's definition, in ONE place for every verb that prints the stamp. Found by the CA4
// legend-coverage sweep: the identical `at="<sha>[+dirty]"` attribute is emitted by the map, --hotspots,
// --owners, --cochange, --test-gate, --edit-check, --whereis and --quality-delta, and was defined by TWO of
// them — the §B7 shape, spread over eight surfaces. A shared constant rather than eight sentences, so the
// definition cannot drift into eight wordings the way the truncation vocabulary did before §P8.
inline constexpr const char* kAtStampLegend =
    "<!-- at= is the git commit these numbers were computed at; a trailing +dirty means the working tree "
    "differed from that commit, so the numbers describe the tree, not the commit -->";

// §A9.6 — the churn-ranked map's own legend clause, emitted ONLY on that path. The v1 legend is a fixed
// string every other run shares byte-for-byte, and a churn-only fact does not belong inside it.
// The ev_why= value ("guard-return:2,loop-escape:1"): tags in kEvWhyTagTable's fixed declaration order,
// only non-zero counts, comma-separated — one formatter shared by BOTH dialects so the XML and JSON
// spellings can never drift (jsonparitycheck's standing posture). The charset is closed (tag literals,
// ':', ',', digits), so the value needs no XML or JSON escaping. Composed on std::string, never through
// a fixed char buffer — test/fixedbufsweep.sh's own rule for variable-length markup-bound text.
inline std::string evWhyString( const Symbol& s )
{
    std::string why;
    for( std::size_t tagIndex = 0; tagIndex < kEvWhyTagCount; ++tagIndex )
    {
        if( s.evWhy[ tagIndex ] == 0 )
        {
            continue;
        }
        if( !why.empty() )
        {
            why += ',';
        }
        why += kEvWhyTagTable[ tagIndex ];
        why += ':';
        why += std::to_string( unsigned( s.evWhy[ tagIndex ] ) );
    }
    return why;
}

inline constexpr const char* kChurnRankLegend =
    "<!-- rank_by=churn: k= is a git CHANGE-FREQUENCY prior over window=, not call-graph importance; "
    "the same corpus ranked by pagerank orders differently -->";

// §B7.3 (CA4) — the --metrics row vocabulary, emitted ONLY on a map that carries it, for the same reason
// kChurnRankLegend is. The flag decorates every <s> row with up to thirteen attributes and shipped with NO
// legend at all: the v1 legend defines t/p/n/id/k/c/amb/overloads and stops, so a reader met in= out= cx=
// ccx= role= loc= params= nest= locals= cbo= lcom4= amp= tested= with nothing to read them against. role= is
// the one that can actively mislead — here it is a fan-in THRESHOLD with a single value, while the same
// attribute name on the use-site verb carries call|read|write|import|extends, and that verb discloses its
// own vocabulary in-legend. Absence is meaningful for five of these (locals= joined the group at Phase 1,
// local-variable-indexing, PLAN.md 2026-08-06 evening: absent for every non-C/C++ def, model.h
// localsCountedLang) and is stated rather than left to be inferred from a missing attribute.
// G4: no "--" anywhere inside an XML comment ⇒ flag names written bare.
// Kept TERSE for kMaxTokensFitLegend's reason — it rides on every --metrics map and is charged. A 715 B
// first draft made estchargecheck #9 red: that arm allows the two dialects' est_tokens to differ by the
// ENCODING overhead but not by a factor, and 715 B of XML-only comment is content, not encoding (XML 1145
// vs JSON 719 tokens, past the 25% bar). The long form of these definitions belongs in --help, which is not
// charged against anyone's budget; what a reader needs IN BAND is the key-to-meaning map itself.
inline constexpr const char* kMetricsLegend =
    "<!-- metrics: in=fan-in out=fan-out cx=cyclomatic ccx=cognitive loc=lines params=count nest=MAX-depth "
    "humps=regions-reaching-the-nesting-bar deep=lines-inside-them(floor,see deep_floor) "
    "(humps/deep are the PROFILE nest= cannot give: nest= is a max, so one deep line and a body that is deep "
    "throughout report the same number; deep/loc is the fraction. Both absent exactly when nest<bar — "
    "not-deep, never a hidden 0. deep counts LINES and humps counts REGIONS, and two regions can share a "
    "line, so deep BELOW humps is legal: a one-line if/else at the bar is 2 regions on 1 line) "
    "locals=local-var-decl-count(floor,C/C++-only,see locals_floor) "
    "ppalt=preproc-alternative-branches-in-body(#else/#elif; metrics sum ALL branches, no single build "
    "compiles them all) "
    "ev=essential-cx(McCabe: 1=fully structured, 2+=jumps block extract-method; absent on a cx row means "
    "exactly 1; floor per ev_floor — noreturn calls/macro-hidden exits unseen; not counted: &&/||, Rust ? "
    "and yield/await/defer, hence Bash carries no ev) ev_why=which-jumps-raised-it tag:count "
    "cbo=coupling lcom4=cohesion "
    "amp=change-amplification tested=1 role=hub(fan-in 8+; uses spells role "
    "call|macro|read|write|import|extends). Absent=N/A, never 0. -->";

// §B13.4 — the --max-tokens fit's own legend clause, emitted ONLY on a map --max-tokens shaped, for the same
// reason kChurnRankLegend is: a flag-only fact does not belong in the string every other run shares. It names
// the two currencies explicitly, because the whole defect was that they were never named: the CEILING is
// bytes (the DENSEST calibrated language rate x a 90% headroom, so N is a cap that holds for any language
// mix and any tokenizer drift), while est_tokens is this corpus's own language-weighted estimate — so a
// conformant fit lands BELOW the N you asked for, by design, and fit_bytes= is the number actually honoured.
// Kept DELIBERATELY terse — it is charged against the very ceiling it describes (--max-tokens=500 buys only
// ~1062 bytes in total), so the full statement of the consequence lives in --help, not here.
// G4: no "--" ANYWHERE inside an XML comment. The flag names this clause has to talk about are therefore
// written bare ("token-budget", not "--token-budget"); spelling one with its dashes made xmllint reject the
// whole document ("Double hyphen within comment"), caught by tokenbudgetcheck #5.
// §F5: the clause also has to define over_ceiling, because THIS clause is part of the very floor that makes it
// fire — at a small max_tokens the legend plus the envelope exceed fit_bytes with zero symbols emitted, and a
// marker no legend defines is the §B7 class this round is already closing. Kept to one hyphenated phrase for
// that reason, and spelled WITHOUT the `=1` the attribute carries so that the literal `over_ceiling=1` occurs
// in a document only where the map actually asserts it (a gate greping the marker cannot match its own gloss).
inline constexpr const char* kMaxTokensFitLegend =
    "<!-- max_tokens=asked fit_bytes=honoured: fit_bytes = max_tokens x 2.36 (densest-language B/tok) x 0.90 "
    "headroom, a CONSERVATIVE cap, so est_tokens (this corpus's own rate) lands ~10-20% BELOW max_tokens by "
    "design; the token-budget gate compares against est_tokens, not fit_bytes; "
    "over_ceiling=floor-alone-exceeded-fit_bytes(absent=cap-held) -->";

// Serialize the top-K symbols (by rank, ties by id) grouped by file, to `out`.
//   rank[i]      = PageRank of symbol i               (size = symbols.size())
//   outOff/outTargets = resolved out-edges per symbol (CSR: targets of i are
//                       outTargets[outOff[i] .. outOff[i+1]) )  → the <c> children
//   mostImportantLast: EXPLICIT --most-important-last (hard force-on; unchanged behaviour).
//   autoOrder: T3 — when true AND mostImportantLast/stable are NOT explicitly set, the emit order
//              auto-flips to important-last once est_tokens crosses kFillOrderThreshold. Callers that
//              want the pre-T3 behaviour (e.g. --around's ego-graph, or the --max-tokens probe pass)
//              pass autoOrder=false and keep the prior explicit-only semantics.
inline void serialize( std::FILE* out, const IngestResult& ing, const std::vector<float>& rank,
                       const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                       int topK, bool mostImportantLast = false,
                       bool metrics = false, const std::vector<std::uint32_t>* fanIn = nullptr,
                       const std::vector<std::uint32_t>* ambOut = nullptr, bool stable = false,
                       const std::vector<std::uint8_t>* outProv = nullptr,
                       // Q-compute per-symbol metrics — surfaced on --metrics ONLY (descriptive facts, never gates).
                       // All optional (nullptr ⇒ that attribute is omitted); loc/params/nest live on Symbol itself.
                       const std::vector<std::uint32_t>* cbo    = nullptr,   // Q5a distinct in-repo dependency targets
                       const std::vector<std::uint8_t>*  tested = nullptr,   // Q2   referenced from a test-path file
                       const std::vector<std::uint32_t>* lcom4  = nullptr,   // Q4   class cohesion (kLcom4NA ⇒ omit)
                       const std::vector<std::uint32_t>* amp    = nullptr,   // Q2   change-amplification (callers + co-change partners)
                       const std::vector<std::uint32_t>* unresolvedOut = nullptr,  // honesty lever #2: per-symbol lang-filtered
                                                                                   // unresolved calls; summed into `unresolved=N`
                       const std::vector<std::string>*   bind = nullptr,      // A4-R5 per-symbol cross-language binding
                                                                               // label (graph.h g.bindLabel) — JNI decoded
                                                                               // Java_pkg_Cls_method → "pkg.Cls.method".
                                                                               // Emitted as bind="…" ONLY when non-empty
                                                                               // (nullptr/empty-vector default ⇒ zero
                                                                               // token cost, byte-identical golden map).
                       bool autoOrder = false,                               // T3: fill-aware auto important-last (see above)
                       std::size_t* outEstTokens = nullptr,                  // --token-budget: hand back the SAME est_tokens the
                                                                              // header prints (no second counter) — nullptr ⇒ unused
                       std::size_t extraPayloadTokens = 0,                   // §H7 (was extraBodyTokens): tokens of
                                                                              // EVERY block the caller appends after this map —
                                                                              // <sigs>, <src>, <bodies>, <outline> — each MEASURED
                                                                              // from its rendered bytes by the caller (main.cpp's
                                                                              // renderMapPayload) and converted through
                                                                              // tokensForEmittedBytes. The old name said "body"
                                                                              // and only --expand ever filled it, which is
                                                                              // precisely why the four siblings went uncharged.
                       const MapAnnotations& ann = {},                       // how THIS map was produced (see MapAnnotations
                                                                              // above); defaulted ⇒ byte-identical golden map.
                       // §B6 M10: keep the files=/symbols=/shown=/order= stanza on the FIRST SCREEN even under
                       // `stable`. --stable moves it to a TRAILING comment to protect the cacheable prefix, which is
                       // right for a CLI map a provider KV-caches and wrong for the MCP `analyze` verb, whose result
                       // is ONE tool payload an agent reads top-down: there the reader met 197 of 6368 symbols with
                       // no denominator and no order marker until the last line. The stanza is emitted ONCE either
                       // way (never both places), so no count is stated twice. Only the MCP analyze front door
                       // passes true; every CLI caller keeps the default and stays byte-identical.
                       bool statsFirstScreen = false )
{
    const std::size_t* changedCount = ann.changedCount;
    const std::string* mapAtStamp   = ann.atStamp;
    const std::string* churnWindow  = ann.churnWindow;
    const std::size_t S = ing.symbols.size();

    // rank order: (rank desc, id asc) — the id tie-break makes the top-K deterministic.
    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );

    const std::size_t keep = std::min<std::size_t>( topK > 0 ? std::size_t( topK ) : S, S );

    // bucket the kept symbols by file, files ordered by their best (first-seen) rank.
    std::vector<std::vector<NodeId>> buckets( ing.files.size() );
    std::vector<std::uint32_t>       fileOrder;
    std::vector<char>                seen( ing.files.size(), 0 );

    for( std::size_t k = 0; k < keep; ++k )
    {
        const NodeId        id = order[k];
        const Symbol&       s  = ing.symbols[id];
        const std::uint32_t f  = s.fileId;
        if( !seen[f] ) { seen[f] = 1;  fileOrder.push_back( f ); }
        buckets[f].push_back( id );
    }

    // T1/§H7: the byte MODEL. It keeps two jobs and loses one. It still decides the T3 emit order below
    // (which has to be decided before any byte exists — see §H7 at estimateTokens) and it still supplies
    // the language-weighted bytes/token RATE, the half of it that is actually measured. What it no longer
    // does is REPORT the size: the reported est_tokens is computed from the document's emitted bytes in
    // PHASE 2 below, because a model of the symbol set cannot see --metrics decoration or an appended
    // payload, which is how four different documents came to report one number (§H7).
    // T3 note: the auto-order decision keys off the MAP's own estimate, NOT the payload — the fill-order
    // heuristic reasons about the map that gets reordered; the appended <bodies>/<sigs>/<src> blocks are
    // emitted after and cannot be reordered, so they must not shift the map's primacy/recency decision.
    const TokenEstimate mapEst      = estimateTokens( ing, order, keep, outOff, outTargets );
    const std::size_t   mapEstTokens = mapEst.tokens;

    // T3: fill-aware auto important-last. A PURE function of estTokens (itself a pure function of the
    // kept symbol set) → deterministic, byte-identical run-to-run. Only engages when the caller opted
    // in (autoOrder) AND neither --stable nor an explicit --most-important-last already decided the
    // order — an explicit flag always wins, auto-order never overrides a user's stated intent. Does
    // NOT trigger on the small default map (test/fixture est_tokens=619, src/ ~10.6K — both far under
    // the ~16K threshold) so the golden output is unchanged.
    const bool autoFlip         = autoOrder && !stable && !mostImportantLast && mapEstTokens > kFillOrderThreshold;
    const bool effImportantLast = mostImportantLast || autoFlip;

    // --stable: emit in PATH / symbol-id order (not rank order) so re-running on a slowly-changing repo
    // keeps a byte-identical PREFIX → free provider KV-cache hits. Selection stays rank-based (the top-K
    // membership is unchanged); only the emit order is stabilized. Takes precedence over --most-important-last.
    if( stable )
    {
        std::sort( fileOrder.begin(), fileOrder.end(),
                   [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
        for( std::vector<NodeId>& b : buckets )
        {
            std::sort( b.begin(), b.end() );                   // by symbol id == file+line order (stable)
        }
    }
    // --most-important-last (explicit) OR T3 auto-flip: emit highest-rank file/symbol LAST (some models
    // weight end-of-context more heavily). Order-only; det-gate still holds.
    else if( effImportantLast )
    {
        std::reverse( fileOrder.begin(), fileOrder.end() );
        for( std::vector<NodeId>& b : buckets )
        {
            std::reverse( b.begin(), b.end() );
        }
    }

    std::vector<char> esc;

    // The prov= legend is appended ONLY under --scip (outProv present) so the default header stays
    // byte-identical to the pre-overlay output (no golden churn); prov="scip" marks a SCIP-pinned precise edge.
    // §A8.7: shown= (in the `stats` comment below) counts overload-MERGED rows individually — rows +
    // Σ(overloads-1) == shown — but overloads= itself (overloadsAttr(), above) was absent from this legend,
    // the one clause that closes that arithmetic for a reader who has only the map, not the source.
    // §H7: the legend is now COMPOSED into a string rather than streamed, because est_tokens can only be
    // written once the document it describes has been measured (PHASE 2 below) and the legend's own bytes
    // are part of what it describes.
    std::string legend = outProv
        ? "<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) prov=scip(precise;else name-based) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->"
        : "<!-- ripwire v1 t=fn|method|cls|struct|iface|var|sec|macro(#define;degraded:body-is-replacement-text,edges-cross-expansion) p=path layer=arch-layer(opt) n=name id=canonical(path::scope::name,when-scoped) k=rank c=call amb=ambiguous-calls(read-source) overloads=N-same-name-defs-merged-into-this-row(absent-if-1;shown=counts-them-individually,so-rows+sum(overloads-1)=shown) hdr:unresolved=call-name-defined-only-in-a-lang-incompatible-file (edges heuristic) r:est_tokens=hdr-copy(none-if-stable) -->";
    if( churnWindow != nullptr )
    {
        legend += kChurnRankLegend; // §A9.6, churn-only (see the constant)
    }
    // §B2.1: the same treatment for authority/hub/rrf. Mutually exclusive with the churn arm by construction
    // (main.cpp fills exactly one of the two fields), and null on the default pagerank map ⇒ zero bytes there.
    if( const char* rbLegend = rankByLegendFor( ann.rankByLabel ) )
    {
        legend += rbLegend;
    }
    if( metrics )
    {
        legend += kMetricsLegend; // §B7.3, metrics-only (ditto)
    }
    // Beyond the brief, found by the CA4 legend-coverage sweep: `at=` is the ONE root attribute the map can
    // emit that no map legend ever defined — §B7.1 fixed exactly this on the quality-delta screen and the map
    // is the other surface that prints it. Emitted only on the runs that carry the stamp (map-diff / churn),
    // so the default map is untouched and the clause is charged where the attribute is.
    if( mapAtStamp != nullptr && !mapAtStamp->empty() )
    {
        legend += kAtStampLegend;
    }
    if( ann.maxTokensFit != nullptr )
    {
        legend += kMaxTokensFitLegend; // §B13.4, --max-tokens-only (ditto)
    }

    // header honesty gauges: ambiguous=resolver guessed among >1 in-repo def (read source); unresolved=the callee
    // name IS defined in-repo but EVERY def was language-filtered — a plausibly-internal, cross-language-filtered
    // edge (NOT counted for genuine externals like stdlib/third-party, whose name has no in-repo def at all).
    std::size_t ambTotal = 0;                                  // global honesty gauge: how many calls the
    if( ambOut )
    {
        for( std::uint32_t v : *ambOut )
        {
            ambTotal += v; // resolver could not pin to one target
        }
    }
    std::size_t unresolvedTotal = 0;                           // honesty lever #2 gauge: how many calls hit an
    if( unresolvedOut )
    {
        for( std::uint32_t v : *unresolvedOut )
        {
            unresolvedTotal += v; // in-repo name, all defs lang-filtered
        }
    }
    std::size_t preciseTotal = 0;                              // how many out-edges the SCIP index pinned
    if( outProv )
    {
        for( std::uint8_t v : *outProv )
        {
            preciseTotal += ( v ? 1u : 0u );
        }
    }
    char precAttr[ 40 ];  precAttr[ 0 ] = '\0';                // emitted ONLY under --scip (else absent → no golden churn)
    if( outProv )
    {
        std::snprintf( precAttr, sizeof( precAttr ), " precise=%zu", preciseTotal );
    }
    // Multi-root workspace (A13): `roots=N` joins the header gauges and a
    // `<root l="LABEL" p="PATH"/>` prologue opens <r> — ONLY when N≥2 (single-root output byte-unchanged).
    char rootsAttr[ 32 ];  rootsAttr[ 0 ] = '\0';
    if( ing.rootLabels.size() >= 2 )
    {
        std::snprintf( rootsAttr, sizeof( rootsAttr ), " roots=%zu", ing.rootLabels.size() );
    }
    // D6: --map-diff's teleport-seed file count, ONLY when the caller passes changedCount
    // (nullptr for every non-map-diff caller ⇒ zero token cost, byte-identical golden map). A clean
    // tree reports "changed=0" so the caller can see the teleport degraded to uniform without shelling
    // out to git a second time — that map is otherwise byte-identical to the plain default map.
    char changedAttr[ 40 ];  changedAttr[ 0 ] = '\0';
    if( changedCount )
    {
        std::snprintf( changedAttr, sizeof( changedAttr ), " changed=%zu", *changedCount );
    }
    // §P0.5d: how many otherwise-indexable files the crawl dropped for exceeding a per-file size ceiling —
    // --max-file-size, or (§B13.1) the .json lane's fixed 256 KB config ceiling that --max-file-size does not
    // raise. `--max-file-size=8K` dropped ~296 of ~759 files on this repo and files= reported the survivors as
    // if they WERE the corpus. Emitted ONLY when non-zero, per the house rule — absent means nothing was
    // skipped, so a default run over a tree with nothing oversized stays byte-identical.
    char skippedAttr[ 48 ];  skippedAttr[ 0 ] = '\0';
    if( !ing.skippedOversize.empty() )
    {
        std::snprintf( skippedAttr, sizeof( skippedAttr ), " skipped_oversize=%zu", ing.skippedOversize.size() );
    }
    // §B13.4: --max-tokens=N asked for a TOKEN count and got a BYTE ceiling. Both numbers, on the map that
    // was shaped by them, so the ~10% the headroom leaves unused is a disclosed fact rather than a silent
    // one. Emitted ONLY under --max-tokens (nullptr for every other caller ⇒ byte-identical default map).
    // §F5: over_ceiling=1 rides the same attr — a cap that can be overshot is not a cap, so where the map's
    // fixed floor cannot fit inside fit_bytes the map states that instead of quietly exceeding it. See
    // MapAnnotations::MaxTokensFit for the four ways the cap was breached and why the label is monotone.
    char fitAttr[ 96 ];  fitAttr[ 0 ] = '\0';
    if( ann.maxTokensFit != nullptr )
    {
        std::snprintf( fitAttr, sizeof( fitAttr ), " max_tokens=%zu fit_bytes=%zu%s",
                       ann.maxTokensFit->askedTokens, ann.maxTokensFit->ceilingBytes,
                       ann.maxTokensFit->isOverCeiling ? " over_ceiling=1" : "" );
    }
    // order= marker: T3's auto-flip must be OBSERVABLE, not a silent behaviour change — "important-
    // last(auto:fill)" is distinct from the explicit "important-last" so a reader (or a diff) can tell
    // the ordering was the fill-aware heuristic, not a requested flag.
    const char* orderAttr = stable ? "stable"
                          : mostImportantLast ? "important-last"
                          : autoFlip ? "important-last(auto:fill)"
                          : "important-first";

    // ── the HEAD and the TAIL, as BUILDERS ─────────────────────────────────────────────────────────────
    // Both state est_tokens, and est_tokens describes the whole document including them, so the digit count
    // feeds back into the number: PHASE 2 below iterates these to a fixpoint. buildRecall (recall.h) has the
    // identical fixpoint for the identical reason — "the header, last: it REPORTS est_tokens, so it can only
    // be written once the payload is measured". Pure functions of estTokens + the attrs computed above.
    const auto buildStats = [ & ]( std::size_t estTokens ) -> std::string
    {
        // summary preamble: counts so the agent knows the map's scope + est size. §B14 — was `char stats[480]`,
        // and the LATENT member of that class: every interpoland is bounded, but the worst-case format width
        // is 80 literal bytes + 7×20 (%zu at UINT64_MAX) + 251 (precAttr 39 + rootsAttr 31 + changedAttr 39 +
        // skippedAttr 47 + fitAttr 95, each buffer's max strlen) + 25 (`important-last(auto:fill)`) = **496 B**,
        // 497 with the NUL, against a 480-byte buffer. It sat at 432/480 on this repo, so it was one new header
        // attribute away from truncating — and a cut here deletes the trailing ` -->`, which turns the ENTIRE
        // document into one unterminated comment. Composed on std::string, the margin question disappears.
        std::string stats = "<!-- files=";
        stats += std::to_string( ing.files.size() );
        stats += " symbols=";    stats += std::to_string( S );
        stats += " edges=";      stats += std::to_string( outTargets.size() );
        stats += " shown=";      stats += std::to_string( keep );
        stats += " est_tokens="; stats += std::to_string( estTokens );
        stats += " ambiguous=";  stats += std::to_string( ambTotal );
        stats += " unresolved="; stats += std::to_string( unresolvedTotal );
        stats += precAttr;  stats += rootsAttr;  stats += changedAttr;  stats += skippedAttr;  stats += fitAttr;
        stats += " order=";      stats += orderAttr;
        stats += " -->";
        return stats;
    };
    // --stable: volatile counts move to a TRAILING comment (out of the cacheable prefix) — unless the caller
    // asked for the first-screen placement (§B6 M10, the MCP analyze verb), in which case they stay here and
    // the trailing copy is suppressed. Exactly one of the two builders emits `stats`.
    const auto buildHead = [ & ]( std::size_t estTokens ) -> std::string
    {
        std::string h = legend;
        if( !stable || statsFirstScreen )
        {
            h += buildStats( estTokens );
        }
        // r26-stamp Task A: ` at="..."` ONLY when the caller passed a non-empty stamp (--map-diff); every other
        // caller passes nullptr, so the hot default-map path pays a pointer compare, not a git call. at= stays
        // FIRST — the `<r at="<sha>` byte sequence gitstampcheck.sh pins is unchanged.
        h += "<r";
        if( mapAtStamp != nullptr && !mapAtStamp->empty() ) { h += " at=\"";  h += *mapAtStamp;  h += "\""; }
        // §A9.6: after at= (so gitstampcheck's `<r at="<sha>` byte sequence is unmoved) — see MapAnnotations.
        if( churnWindow != nullptr ) { h += " rank_by=\"churn\" window=\"";  h += escapeXml( *churnWindow, esc );  h += "\""; }
        // §B2.1: the windowless rankers stamp the same attribute in the same slot. `else if` states the
        // exclusivity the caller guarantees, so a future edit that fills both cannot emit rank_by= twice.
        else if( ann.rankByLabel != nullptr ) { h += " rank_by=\"";  h += ann.rankByLabel;  h += "\""; }
        // §P8: est_tokens as a MACHINE-READABLE root attribute. The map reported its own size only inside the
        // comment above, and a conformant parser may discard comments — so the number a budget-aware caller most
        // needs was unreachable. Additive: the comment is kept, and this carries the SAME `estTokens` value
        // (one estimator). --stable omits it on the precedent of the k= rank attribute below: --stable buys a
        // byte-stable PREFIX, the root element is that prefix, and est_tokens is globally volatile.
        if( !stable ) { char estAttr[ 40 ];  std::snprintf( estAttr, sizeof( estAttr ), " est_tokens=\"%zu\"", estTokens );  h += estAttr; }
        h += ">";
        return h;
    };
    const auto buildTail = [ & ]( std::size_t estTokens ) -> std::string
    {
        return ( stable && !statsFirstScreen ) ? buildStats( estTokens ) : std::string{};
    };

    // ── PHASE 1: render <r>'s CHILDREN into a buffer ────────────────────────────────────────────────────
    // §H7: est_tokens must charge the bytes the document actually carries, not a model of the symbol set —
    // the model prices neither --metrics decoration nor an appended payload, which is how one number came to
    // stand for five documents. So: measure, decide, then write (the order --recall's emitRecallBudgeted and
    // the --for lens's pre-rendered sigs block already impose on themselves).
    //
    // DEGRADE: an open_memstream failure keeps the whole map — the head goes out FIRST carrying the MODELLED
    // estimate (the pre-§H7 number, so this path is no worse than the old behaviour, never a fabricated one)
    // and the children stream straight to `out` behind it.
    char*       childBuf = nullptr;
    std::size_t childSz  = 0;
    std::FILE*  childMem = openChargeBuffer( &childBuf, &childSz );
    if( !childMem )
    {
        DEGRADED_PATH_ALERT( "serialize: open_memstream failed — est_tokens reports the MODELLED bytes, not the emitted ones" );
    }

    const std::size_t modelledTokens = mapEstTokens + extraPayloadTokens;
    XmlWriter         w( childMem ? childMem : out );
    if( !childMem )
    {
        w.write( buildHead( modelledTokens ) );
    }
    // §P8 collision: this prologue spelled its LABEL `l=`, the two characters 22 other sites use for a LINE
    // NUMBER — including the <f p= …> rows just below. Renamed: the label had exactly two references in the
    // tree (both updated here) against 15+ readers of the line-number meaning that must not move.
    if( ing.rootLabels.size() >= 2 )
    { // A13 prologue: label → root path, canonical order
        for( std::size_t r = 0; r < ing.rootLabels.size(); ++r )
        {
            w.write( "<root label=\"" );  w.write( escapeXml( ing.rootLabels[r], esc ) );
            w.write( "\" p=\"" );     w.write( escapeXml( r < ing.rootPaths.size() ? ing.rootPaths[r] : std::string(), esc ) );
            w.write( "\"/>" );
        }
    }
    for( std::uint32_t f : fileOrder )
    {
        w.write( "<f p=\"" );  w.write( escapeXml( ing.files[f], esc ) );  w.write( "\"" );
        if( const char* fl = builtinLayer( ing.files[f] ); *fl ) { w.write( " layer=\"" );  w.write( fl );  w.write( "\"" ); }   // P3
        w.write( ">" );

        // §P6.3: see collapseOverloadRows() above — const/non-const overload pairs are already folded to
        // one representative row per (kind,id) before this loop runs, so the loop body below is unchanged
        // shape (no added branch): it just iterates a shorter vector.
        const OverloadRows rows = collapseOverloadRows( ing, buckets[f] );

        for( std::size_t i = 0; i < rows.id.size(); ++i )
        {
            const NodeId         id  = rows.id[i];
            const Symbol&        s   = ing.symbols[id];
            const std::uint32_t  out = outOff[id + 1] - outOff[id];
            w.write( "<s t=\"" );  w.write( symTag( s.kind ) );
            w.write( "\" n=\"" );  w.write( escapeXml( s.name, esc ) );  w.write( "\"" );   // close n="…" here so id= can follow

            // S6-C: the canonical SCIP-style id `path::scope::name` — emitted ONLY when it ADDS disambiguation,
            // i.e. it differs from the bare name (the symbol has an enclosing scope). For a free function the
            // canonical id equals the name, so it is skipped — no token cost, no golden churn for scope-less
            // symbols. Two same-named methods on different classes thus carry DISTINCT ids here.
            const std::string canon = canonicalId( ing.files[ s.fileId ], s.scope, s.name );
            if( canon != s.name ) { w.write( " id=\"" );  w.write( escapeXml( canon, esc ) );  w.write( "\"" ); }

            w.write( overloadsAttr( rows.overloads[i] ) );   // see overloadsAttr() above — empty in the common case

            // A4-R5: bind="pkg.Cls.method" — the decoded JNI binding label (graph.h g.bindLabel), when this
            // symbol has one. Unconditional (not --metrics-gated): it is an identity fact like id=, not a
            // descriptive stat. Omitted whenever bind is nullptr or the per-symbol label is empty (the
            // overwhelming common case) → zero token cost, byte-identical golden map on non-JNI corpora.
            if( bind && id < bind->size() && !(*bind)[id].empty() )
            {
                w.write( " bind=\"" );  w.write( escapeXml( (*bind)[id], esc ) );  w.write( "\"" );
            }

            char ambs[ 24 ];  ambs[ 0 ] = '\0';   // "fast guessed K of this symbol's call targets — read source"
            if( ambOut && id < ambOut->size() && ( *ambOut )[id] > 0 )
            {
                std::snprintf( ambs, sizeof( ambs ), " amb=\"%u\"", ( *ambOut )[id] );
            }

            // PageRank k= is GLOBALLY volatile (any edit perturbs every rank) → omit it in --stable mode
            // so the prefix stays byte-identical for unedited files (provider KV-cache hits). Default keeps k=.
            char kbuf[ 24 ];  kbuf[ 0 ] = '\0';
            if( !stable )
            {
                std::snprintf( kbuf, sizeof( kbuf ), " k=\"%.4f\"", double( rank[id] ) );
            }

            // Q-compute descriptive attrs (loc/params/nest/locals/cbo/lcom4/tested), built into a side buffer
            // that is appended before the closing '>' of the metrics attr. ALL --metrics-only; absent by
            // default so the golden map is byte-identical. params/nest/locals emitted only for fns/methods
            // (kind guard) so a class/sec never carries a 0 it can't have; lcom4 only for class-kinds with
            // methods (kLcom4NA sentinel omits) — mutually exclusive with the fn/method group, which is why
            // the buffer sizing below only has to cover ONE of the two groups' worst case, not both summed.
            // 96 -> 160 (Phase 1, local-variable-indexing, PLAN.md 2026-08-06 evening): the fn/method worst
            // case grew by locals="4294967295" locals_floor="1" (38 B) on top of the pre-existing
            // loc+params+nest+cbo+amp+tested run (~88 B) — 96 would silently TRUNCATE (appendf's qe-clamp
            // makes truncation safe from a buffer-overrun standpoint, but a truncated attr run is malformed
            // XML, not a degrade worth shipping quietly). 160 -> 192 (ppalt disclosure): ppalt="65535"
            // (+14 B) put the summed fn/method worst case within a rounding error of 160; 192 restores the
            // same real headroom over the recomputed worst case.
            char qbuf[ 192 ];  qbuf[ 0 ] = '\0';
            if( metrics )
            {
                char* qp = qbuf; char* const qe = qbuf + sizeof( qbuf );
                // A4-F8: snprintf returns the WOULD-HAVE-written length; on truncation `qp += ret` pushes qp
                // PAST qe, then the next size_t(qe-qp) underflows to a huge size → unbounded stack write. Clamp
                // qp to qe after every append (once full, further appends write nothing and stay clamped).
                // fmt is always a string literal at every call site below — the non-literal warning is
                // an artifact of routing it through the lambda parameter
                const auto appendf = [ & ]( const char* fmt, auto... args )
                {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
                    const int r = std::snprintf( qp, std::size_t( qe - qp ), fmt, args... );
#pragma clang diagnostic pop
                    if( r > 0 )
                    {
                        qp = ( r < qe - qp ) ? qp + r : qe;
                    }
                };
                // loc: physical line span — always meaningful (SIZE is the master variable — report it first).
                if( s.loc > 0 )
                {
                    appendf( " loc=\"%u\"", s.loc );
                }
                const bool isFn = ( s.kind == SymKind::Function || s.kind == SymKind::Method );
                if( isFn )
                {
                    appendf( " params=\"%u\"", unsigned( s.params ) );
                    appendf( " nest=\"%u\"", unsigned( s.maxNest ) );
                    // The nesting PROFILE beside the max (model.h Symbol::humps/deepLoc). nest= alone cannot
                    // distinguish a long run of shallow scoped steps from a body that sustains depth — both
                    // report their deepest line and nothing about how much of the function is that deep.
                    // Omitted, never a bare 0, when no region reached quality::kNestBar: that is exactly
                    // nest < kNestBar, which the row already carries, so absence is lossless rather than a
                    // truncation (test/nestprofilecheck.sh arm 5 pins the equivalence in both directions).
                    if( s.humps > 0 )
                    {
                        appendf( " humps=\"%u\" deep=\"%u\" deep_floor=\"1\"", unsigned( s.humps ), unsigned( s.deepLoc ) );
                    }
                    // Phase 1 (local-variable-indexing, PLAN.md 2026-08-06 evening): locals= is ABSENT — never
                    // a bare "0" — for every def outside model.h's localsCountedLang (MVP: C/C++ only), so a
                    // reader never mistakes "not counted for this language" for "counted, and there are none".
                    // locals_floor="1" always rides alongside a present locals=: `int a,b;` counts as ONE
                    // declaration-statement, not two names (see cc_isCountableLocalDecl's own comment).
                    if( localsCountedLang( s.lang ) )
                    {
                        appendf( " locals=\"%u\" locals_floor=\"1\"", unsigned( s.locals ) );
                    }
                    // ppalt disclosure: the body carries preproc branches that never coexist at compile
                    // time, so this row's structural metrics are sums over ALL of them (model.h Symbol::
                    // ppAlt). ABSENT when 0 — presence itself is the signal.
                    if( s.ppAlt > 0 )
                    {
                        appendf( " ppalt=\"%u\"", unsigned( s.ppAlt ) );
                    }
                }
                if( cbo && id < cbo->size() )
                {
                    appendf( " cbo=\"%u\"", (*cbo)[id] );
                }
                if( lcom4 && id < lcom4->size() && ( *lcom4 )[id] != 0xFFFFFFFFu )
                { // 0xFFFFFFFF = kLcom4NA (graph.h) ⇒ omit
                    appendf( " lcom4=\"%u\"", (*lcom4)[id] );
                }
                if( amp && id < amp->size() )
                {
                    appendf( " amp=\"%u\"", (*amp)[id] );
                }
                if( tested && id < tested->size() && ( *tested )[id] )
                { // omit when 0 (lean output)
                    appendf( " tested=\"1\"" );
                }
            }

            char attr[ 320 ];   // descriptive metric attrs (fan-in/out/cx/role/amb + Q-compute qbuf) — facts, never
                                // gates. The name quote + id= are already written above; this opens with a space.
                                // The closing '>' is written separately below so the ev run — composed on
                                // std::string, never a fixed char buffer (fixedbufsweep's own rule: ev_why= is
                                // variable-length text) — can sit inside the element.
            if( metrics && fanIn )
            {
                const std::uint32_t in = ( id < fanIn->size() ) ? (*fanIn)[id] : 0u;
                std::snprintf( attr, sizeof( attr ), " in=\"%u\" out=\"%u\" cx=\"%u\" ccx=\"%u\"%s%s%s%s",
                               in, out, s.cx, s.ccx, ( in >= 8 ? " role=\"hub\"" : "" ), qbuf, ambs, kbuf );
            }
            else
            {
                std::snprintf( attr, sizeof( attr ), "%s%s", ambs, kbuf );
            }
            w.write( attr );
            // Essential complexity (model.h Symbol::ev), --metrics only. Emitted iff ev >= 2: ev >= 1 for any
            // walked fn/method body, so on a row carrying cx= ABSENT means exactly ev == 1 — lossless in the
            // strictest sense, and never a bare ev="1" (G4 + the honesty contract point the same way). Routed
            // through evCountedLang so an uncovered language (Bash) reads as "not counted", never "counted, 1".
            // ev_floor="1" always rides along: noreturn calls, macro-hidden returns and unresolvable gotos are
            // invisible to the syntactic walk and can only RAISE the true value. ev_why= is the reason
            // breakdown that keeps §10.1-Option-A honest (a guard-heavy row is visibly not a knot).
            if( metrics && ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && evCountedLang( s.lang ) && s.ev >= 2u )
            {
                std::string evRun = " ev=\"" + std::to_string( s.ev ) + "\" ev_floor=\"1\" ev_why=\"" + evWhyString( s ) + "\"";
                w.write( evRun );
            }
            w.write( ">" );

            for( std::uint32_t e = outOff[id]; e < outOff[id + 1]; ++e )
            {
                w.write( "<c n=\"" );
                w.write( escapeXml( ing.symbols[ outTargets[e] ].name, esc ) );
                // A4-R5: prov="scip" on a SCIP-pinned (precise) edge, prov="binding" on an FFI
                // binding-table edge (pybind/extern-C/JNI). Absent = name-based guess (the common case →
                // zero token cost). outProv parallels outTargets exactly, so index `e` is the same edge.
                if( outProv && e < outProv->size() && ( *outProv )[e] )
                {
                    w.write( ( *outProv )[e] == 2u ? "\" prov=\"binding" : "\" prov=\"scip" );
                }
                w.write( "\"/>" );
            }
            w.write( "</s>" );
        }
        w.write( "</f>" );
    }
    w.write( "</r>" );

    // ── PHASE 2: measure, decide, then write ────────────────────────────────────────────────────────────
    // The children are complete; `w` has nothing more to write on either path. Flush BEFORE closing the
    // memstream (the writer's destructor also flushes, but by then m_used is 0, so it never touches a closed
    // stream). On the degrade path there is nothing to measure — the head already went out — so only the
    // trailing summary is left.
    w.flush();
    if( !childMem )
    {
        w.write( buildTail( modelledTokens ) );   // trailing volatile summary — kept out of the byte-stable prefix
        w.flush();
        if( outEstTokens )
        {
            *outEstTokens = modelledTokens;
        }
        return;
    }

    std::fflush( childMem );
    std::fclose( childMem );
    std::string childrenStr;
    if( childBuf ) { childrenStr.assign( childBuf, childSz );  std::free( childBuf ); }

    // The fixpoint: est_tokens covers head + children + tail, and head/tail both PRINT est_tokens, so the
    // digit count feeds back. Converges in ≤2 passes in practice (each extra digit moves the estimate by
    // <1 token); the bound is 4, matching recall.h's.
    //
    // WHAT THE LOOP GUARANTEES (CA4 verifier L4 — the previous wording claimed an equality this loop does not
    // deliver): the LAST built pair is always the pair emitted, and ON CONVERGENCE — the `break`, i.e. the
    // number stopped moving — that pair's own bytes are exactly the bytes `estTokens` was measured over, so the
    // document's stated number describes the document. On the BOUND (4 passes without convergence, not observed
    // on any measured corpus) the emitted head/tail were rebuilt from the last `next` while `next` was measured
    // over the PREVIOUS pair's widths, which differ only in the digit count of one field: at most a few bytes,
    // i.e. a residual well under one token, and never a fabricated number. The honest statement is "converged ⇒
    // exact; bounded ⇒ within a digit's worth of bytes", not "always exact".
    std::size_t estTokens = modelledTokens;
    std::string head      = buildHead( estTokens );
    std::string tail      = buildTail( estTokens );
    for( int pass = 0; pass < 4; ++pass )
    {
        const std::size_t next = tokensForEmittedBytes( head.size() + childrenStr.size() + tail.size(),
                                                        mapEst.bytesPerToken() ) + extraPayloadTokens;
        if( next == estTokens )
        {
            break;
        }
        estTokens = next;
        head      = buildHead( estTokens );
        tail      = buildTail( estTokens );
    }
    if( outEstTokens )
    {
        *outEstTokens = estTokens; // --token-budget reads THIS value — never a second counter
    }

    std::fwrite( head.data(), 1, head.size(), out );
    std::fwrite( childrenStr.data(), 1, childrenStr.size(), out );
    if( !tail.empty() )
    {
        std::fwrite( tail.data(), 1, tail.size(), out );
    }
}

// --pack-top-n: append raw source of the top-N files (by aggregate symbol rank),
// as CDATA, capped at budgetBytes; the last file is truncated at a newline with a marker.
// Emitted AFTER </r> — a hybrid graph+source bundle (intentionally not a single XML doc).
//
// §B10.1 (W3-N1's discipline, extended): `redact` is REQUIRED — no default. Raw file source is the widest
// credential seam this binary has, so a caller must state which run it belongs to; nullptr = --no-redact,
// spelled deliberately. Both call sites already passed it, so this costs nothing and buys the compile error.
inline void packSource( std::FILE* out, const IngestResult& ing, const std::vector<float>& rank,
                        int topN, std::size_t budgetBytes, RedactCounts* redact )
{
    const std::size_t F = ing.files.size();
    std::vector<float> fileRank( F, 0.f );
    for( const Symbol& s : ing.symbols )
    {
        fileRank[s.fileId] += rank[s.id];
    }

    std::vector<std::uint32_t> order( F );
    for( std::uint32_t i = 0; i < F; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, fileRank );

    XmlWriter         w( out );
    std::vector<char> esc;
    std::size_t       used = 0;
    const std::size_t keep = std::min<std::size_t>( topN > 0 ? std::size_t( topN ) : 0, F );

    for( std::size_t k = 0; k < keep && used < budgetBytes; ++k )
    {
        std::FILE* in = std::fopen( diskPath( ing, order[k] ).c_str(), "rb" );
        if( !in )
        {
            continue; // graceful: file gone
        }

        std::string body;
        char        buf[ 4096 ];
        std::size_t n;
        while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
        {
            body.append( buf, n );
        }
        std::fclose( in );

        bool truncated = false;
        if( used + body.size() > budgetBytes )                 // truncate at a newline + UTF-8 boundary
        {
            const std::size_t room = budgetBytes - used;
            std::size_t cut = body.rfind( '\n', room );
            if( cut == std::string::npos )
            {
                cut = room;
            }
            // never cut mid-codepoint: back off any UTF-8 continuation bytes (10xxxxxx) so the
            // CDATA stays valid UTF-8 (otherwise xmllint / the G4 guardrail rejects it)
            while( cut > 0 && ( static_cast<unsigned char>( body[cut] ) & 0xC0 ) == 0x80 )
            {
                --cut;
            }
            body.resize( cut );
            truncated = true;
        }

        // Redact credential shapes from the raw file body BEFORE CDATA-encoding — this is a
        // body-emission seam (whole source files pasted into an LLM). Applied post-truncation (redaction
        // only ever shrinks/relabels, never grows past the budget in a way that matters). No-op under --no-redact.
        redactInPlace( body, redact );

        std::string safe;  safe.reserve( body.size() );        // split ]]>; scrub C0 controls (G4) + invalid UTF-8 (A4-F20)
        appendCdataSafe( body, safe );

        w.write( "<src p=\"" );  w.write( escapeXml( ing.files[ order[k] ], esc ) );  w.write( "\"><![CDATA[" );
        w.write( safe );
        if( truncated )
        {
            w.write( "\n<!-- truncated -->" );
        }
        w.write( "]]></src>" );
        used += safe.size();   // charge EMITTED CDATA bytes (post ]]> expansion), not raw body
    }
    w.flush();
}

// clean a signature slice [a,b): stop at the body '{' or the prototype-terminating ';', collapse
// whitespace runs to single spaces, cap length. Shared by --pack-signatures and the Lego contract.
//
// §B0 family (W3-N1): a SIGNATURE is emitted text too — a default argument carries whatever literal the
// author wrote (`int f( const char* key = "AKIA…" )`), so this is a credential seam exactly like a doc
// comment or a body. `redact` is REQUIRED (no default): every present and future call site must state
// which run it belongs to, so a new sig-emitting clone cannot silently opt out. nullptr = --no-redact,
// the same convention redactInPlace already has.
//
// Order matters twice: redaction runs on the EMITTED extent (the prefix before '{' / ';') so a secret
// inside a body we never print is not counted, and it runs BEFORE the kMaxSig cap so a secret straddling
// the cap cannot survive as a half-visible prefix.
inline std::string cleanSig( const char* data, std::size_t a, std::size_t b, RedactCounts* redact )
{
    std::string_view raw( data + a, b - a );
    if( const std::size_t stop = raw.find_first_of( "{;" ); stop != std::string_view::npos )
    {
        raw = raw.substr( 0, stop );
    }

    std::string redacted;
    if( redact != nullptr && redactSecrets( raw, redacted, *redact ) )
    {
        raw = redacted;
    }

    constexpr std::size_t  kMaxSig = 240;
    std::string            sig;  sig.reserve( raw.size() < kMaxSig ? raw.size() : kMaxSig );
    bool                   inSpace = false;
    for( char c : raw )
    {
        if( c == ' ' || c == '\t' || c == '\n' || c == '\r' )
        { if( !sig.empty() && !inSpace ) { sig.push_back( ' ' ); inSpace = true; } }
        else
        {
            // hard cap — never cut mid-codepoint (G4): if the byte we are ABOUT to drop is a UTF-8
            // continuation (10xxxxxx), the tail codepoint straddles the cap → back off the partial
            // continuation run and its lead byte (same rule as the packSource budget cut).
            if( sig.size() >= kMaxSig )
            {
                if( ( static_cast<unsigned char>( c ) & 0xC0 ) == 0x80 )
                {
                    std::size_t cut = sig.size();
                    while( cut > 0 && ( static_cast<unsigned char>( sig[cut - 1] ) & 0xC0 ) == 0x80 )
                    {
                        --cut;
                    }
                    sig.resize( cut > 0 ? cut - 1 : 0 );
                }
                break;
            }
            sig.push_back( c ); inSpace = false;
        }
    }
    while( !sig.empty() && sig.back() == ' ' )
    {
        sig.pop_back();
    }
    return sig;
}

// purity hint from the signature alone (no ingest/cache change): `constexpr`/`consteval` (≈ provably
// pure) or a trailing `const` qualifier after the parameter list (a const method — reads, doesn't
// mutate `this`). A descriptive "safe to depend on" fact, not a proof. (constexpr never appears in a
// parameter list, so the substring test is collision-free; the trailing-const test looks only past
// the last ')', avoiding const-ref parameters like `const vector3f&`.)
inline bool pureFromSig( const std::string& sig, Lang lang = Lang::Cpp )
{
    if( sig.find( "constexpr" ) != std::string::npos || sig.find( "consteval" ) != std::string::npos )
    {
        return true;
    }
    if( lang == Lang::Swift )
    { // a non-`mutating` func doesn't mutate its value-type receiver (the const-equivalent);
        return sig.find( "func " ) != std::string::npos && sig.find( "mutating" ) == std::string::npos;   // a hint — imprecise for class (reference-type) methods
    }
    const std::size_t rp = sig.rfind( ')' );   // C/C++/ObjC: a trailing `const` after the parameter list
    return rp != std::string::npos && sig.find( "const", rp ) != std::string::npos;
}

// L2: the doc comment immediately above a definition — consecutive // /// //! //< lines, or a /* … */
// (Doxygen /** */) block sitting directly above (only whitespace between). Flattened + capped. "" if none.
// Lexical back-scan over the already-read source — no AST, no cache change. Human intent is the highest-
// signal context per token (the whole reason for L2).
inline std::string docCommentBefore( const std::string& src, std::size_t defStart )
{
    if( defStart == 0 || defStart > src.size() )
    {
        return {};
    }
    std::size_t lineStart = defStart;                                          // back up to the def's line start
    while( lineStart > 0 && src[lineStart - 1] != '\n' )
    {
        --lineStart;
    }
    if( lineStart == 0 )
    {
        return {};
    }

    const auto strip = []( std::string_view l ) -> std::string_view           // drop leading ws + //,/// markers + a space
    {
        std::size_t t = 0;
        while( t < l.size() && ( l[t] == ' ' || l[t] == '\t' || l[t] == '*' ) )
        {
            ++t;
        }
        while( t < l.size() && l[t] == '/' )
        {
            ++t;
        }
        while( t < l.size() && ( l[t] == '!' || l[t] == '<' || l[t] == '*' ) )
        {
            ++t;
        }
        if( t < l.size() && l[t] == ' ' )
        {
            ++t;
        }
        std::string_view r = l.substr( t );
        while( !r.empty() && ( r.back() == ' ' || r.back() == '\t' || r.back() == '\r' ) )
        {
            r.remove_suffix( 1 );
        }
        if( r.size() >= 2 && r.back() == '/' && r[r.size() - 2] == '*' )
        {
            r.remove_suffix( 2 ); // trailing */
        }
        while( !r.empty() && ( r.back() == ' ' || r.back() == '\t' || r.back() == '*' ) )
        {
            r.remove_suffix( 1 );
        }
        return r;
    };

    std::vector<std::string_view> rev;                                        // comment lines, bottom-up
    std::size_t cur = lineStart;
    for( int guard = 0; cur > 0 && guard < 12; ++guard )
    {
        const std::size_t le = cur - 1;                                       // the '\n' ending the line above
        std::size_t ls = le;
        while( ls > 0 && src[ls - 1] != '\n' )
        {
            --ls;
        }
        std::string_view line( src.data() + ls, le > ls ? le - ls : 0 );
        std::size_t tt = 0;
        while( tt < line.size() && ( line[tt] == ' ' || line[tt] == '\t' ) )
        {
            ++tt;
        }
        const std::string_view tl = line.substr( tt );
        const bool isLineComment  = tl.size() >= 2 && tl[0] == '/' && tl[1] == '/';
        const bool isBlockPiece   = !tl.empty() && ( tl[0] == '*' || ( tl.size() >= 2 && tl[0] == '/' && tl[1] == '*' )
                                                     || ( tl.size() >= 2 && tl[ tl.size() - 1 ] == '/' && tl[ tl.size() - 2 ] == '*' ) );
        if( isLineComment || isBlockPiece )
        {
            rev.push_back( tl );
            cur = ls;
            if( tl.size() >= 2 && tl[0] == '/' && tl[1] == '*' )
            {
                break;
            }
        }
        else
        {
            break; // first non-comment line → stop
        }
    }
    if( rev.empty() )
    {
        return {};
    }

    std::string doc;
    for( auto it = rev.rbegin(); it != rev.rend(); ++it )
    {
        const std::string_view piece = strip( *it );
        if( piece.empty() )
        {
            continue;
        }
        if( !doc.empty() )
        {
            doc += ' ';
        }
        doc += std::string( piece );
        if( doc.size() >= 200 )
        {
            // never cut mid-codepoint (G4): back off any UTF-8 continuation bytes at the cap, same rule
            // as the packSource budget cut. (The decorative trailing-strip below happens to eat partial
            // sequences too — its alnum test is ASCII-only — but make the guarantee explicit here.)
            std::size_t cut = 200;
            while( cut > 0 && ( static_cast<unsigned char>( doc[cut] ) & 0xC0 ) == 0x80 )
            {
                --cut;
            }
            doc.resize( cut );
            break;
        }
    }
    // strip decorative leading/trailing non-alphanumeric runs (── box dividers, ===, ***), keep the label
    const auto alnum = []( char c ) { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ); };
    std::size_t b0 = 0, b1 = doc.size();
    while( b0 < b1 && !alnum( doc[b0] ) )
    {
        ++b0;
    }
    while( b1 > b0 && !alnum( doc[b1 - 1] ) )
    {
        --b1;
    }
    return doc.substr( b0, b1 - b0 );
}

// --compress (P2-B): strip block comments /* … */ and line comments // … from a body string, while
// preserving comment-like text that appears INSIDE string or char literals.  Also collapses runs of
// 3+ blank (whitespace-only) lines down to a single blank line, and drops leading-whitespace-only lines
// that follow stripping (i.e. lines that contained only a comment and are now empty).
//
// Correctness guarantee: a "//" or "/*" that appears inside a "…" or '…' literal is NEVER treated as
// a comment.  We track the lexer state through the following states:
//   NORMAL       → default; comments and literals start here
//   IN_STRING    → inside "…"; ends at an unescaped "
//   IN_CHAR      → inside '…'; ends at an unescaped '
//   IN_RAW       → inside R"delim(…)delim" (C++ raw string); ends at )delim"
//   IN_LINE_CMT  → inside // …; ends at the next \n (the \n is kept so line count is preserved)
//   IN_BLK_CMT   → inside /* … */; the entire span including markers is consumed
//
// NOTE: does NOT strip the <doc> doc-comment field — that is emitted separately by the call site and
// is never passed into this function (only the raw body bytes [sigStartByte, endByte) are compressed).
inline std::string compressBody( std::string_view src )
{
    // Phase 1: lex out comments, preserving content inside string/char literals.
    //
    //  output: the source with all comment content removed; literal content intact.
    //  We output character-by-character into `out` for simplicity (the budget-capped
    //  bodies are not huge — typically <200 KB — so quadratic string appending is fine).
    std::string out;
    out.reserve( src.size() );

    const std::size_t N = src.size();
    std::size_t       i = 0;

    while( i < N )
    {
        const char c = src[i];

        // ── String literal "…" ────────────────────────────────────────────────────────────
        if( c == '"' )
        {
            // Check for C++ raw string R"delim(
            if( i >= 1 && src[i - 1] == 'R' && ( i < 2 || src[i - 2] != '\\' ) )
            {
                // Raw string: collect delimiter between " and (
                std::size_t j = i + 1;
                std::string delim;
                while( j < N && src[j] != '(' && src[j] != '\n' )
                {
                    delim += src[j++];
                }
                if( j < N && src[j] == '(' )
                {
                    // We're inside R"delim(...).  Copy everything verbatim until )delim"
                    const std::string terminator = ")" + delim + "\"";
                    out += src.substr( i, j - i + 1 );   // R"delim(
                    i = j + 1;
                    const std::size_t termLen = terminator.size();
                    while( i < N )
                    {
                        if( i + termLen <= N && src.substr( i, termLen ) == terminator )
                        {
                            out += terminator;
                            i += termLen;
                            break;
                        }
                        out += src[i++];
                    }
                    continue;
                }
                // Not a raw string (malformed R"... without a paren) — fall through to
                // regular string literal handling below.
            }

            // Regular double-quoted string literal.
            out += c;  // emit the opening "
            ++i;
            while( i < N )
            {
                const char sc = src[i];
                out += sc;
                if( sc == '\\' && i + 1 < N ) { out += src[++i]; }   // escape: skip next char
                else if( sc == '"' )
                {
                    break; // end of string
                }
                ++i;
            }
            ++i;   // step past the closing "
            continue;
        }

        // ── Char literal '…' ──────────────────────────────────────────────────────────────
        if( c == '\'' )
        {
            out += c;  // opening '
            ++i;
            while( i < N )
            {
                const char sc = src[i];
                out += sc;
                if( sc == '\\' && i + 1 < N ) { out += src[++i]; }
                else if( sc == '\'' )
                {
                    break;
                }
                ++i;
            }
            ++i;
            continue;
        }

        // ── Comment detection (only reached OUTSIDE string/char literals) ─────────────────
        if( c == '/' && i + 1 < N )
        {
            // Line comment: // …  — consume to end of line, emit a newline to preserve line count.
            if( src[i + 1] == '/' )
            {
                while( i < N && src[i] != '\n' )
                {
                    ++i;
                }
                // leave the \n to be emitted in the NORMAL branch below
                continue;
            }
            // Block comment: /* … */ — consume entirely (no newline kept; blank lines handle the gap)
            if( src[i + 1] == '*' )
            {
                i += 2;   // skip /*
                while( i + 1 < N && !( src[i] == '*' && src[i + 1] == '/' ) )
                {
                    if( src[i] == '\n' )
                    {
                        out += '\n'; // preserve newlines so line numbers survive
                    }
                    ++i;
                }
                if( i + 1 < N )
                {
                    i += 2; // skip */
                }
                continue;
            }
        }

        // ── Normal character — emit as-is ─────────────────────────────────────────────────
        out += c;
        ++i;
    }

    // Phase 2: post-process the comment-stripped text:
    //   (a) Drop lines that are now whitespace-only (previously held only a comment).
    //   (b) Collapse runs of 3+ blank lines → a single blank line.
    //
    // "Blank line" = a line whose trimmed content is empty.  We preserve lines that have ANY
    // non-whitespace content after comment stripping (this keeps intentional blank lines between
    // logical blocks — only the *excess* is collapsed).
    std::string result;
    result.reserve( out.size() );

    std::size_t pos      = 0;
    int         blanks   = 0;    // consecutive blank lines seen so far
    bool        firstLine = true; // suppress leading blanks at the very start of a body

    const std::size_t M = out.size();
    while( pos < M )
    {
        // Find end of line.
        std::size_t eol = out.find( '\n', pos );
        if( eol == std::string::npos )
        {
            eol = M;
        }

        const std::string_view line( out.data() + pos, eol - pos );

        // Is this line blank (all whitespace)?
        bool isBlank = true;
        for( char ch : line )
        {
            if( ch != ' ' && ch != '\t' && ch != '\r' )
            {
                isBlank = false;
                break;
            }
        }

        if( isBlank )
        {
            // Suppress leading blank lines at the very start of a body (artifact of stripping
            // the opening comment of a function body), and collapse 3+ consecutive blanks.
            if( !firstLine )
            {
                ++blanks;
            }
            // Emit at most one blank line (we allow up to 2 accumulated before we start collapsing;
            // the spec says "runs of 3+ → single blank", so blanks==1 and blanks==2 are both fine).
            if( !firstLine && blanks <= 2 )
            {
                result += '\n';   // the blank line itself (the \n that terminated the previous line)
            }
            // If blanks > 2: suppress (collapse).
        }
        else
        {
            // Non-blank line: reset counter, emit.
            blanks    = 0;
            firstLine = false;
            result.append( out.data() + pos, eol - pos );
            if( eol < M )
            {
                result += '\n';
            }
        }

        pos = ( eol < M ) ? eol + 1 : M;
    }

    // Trim a single trailing newline that may have been added (cosmetic).
    while( !result.empty() && result.back() == '\n' )
    {
        result.pop_back();
    }
    return result;
}

// --pack-signatures: emit each top-N ranked definition's SIGNATURE (declaration up to
// the body), bodies elided — ~70% fewer tokens than raw source while keeping the structural shape.
// Grouped by file, capped at budgetBytes. Emitted AFTER </r>, like packSource. With L2: a <doc> child.
// Q3 QUALITY LENS (--for only): the quality facts for the symbols the agent is about to touch, folded
// onto the <d> blocks so a single read-time bundle carries steering signal (facts fed at read time
// measurably change output). ALL optional (nullptr ⇒ that attribute is omitted) so the plain
// --pack-signatures call-site — which passes none of them — stays byte-identical to its golden/gates.
// churn is PER-FILE (indexed by fileId); clone/tested/amp are PER-SYMBOL (indexed by symbol id). ccx is
// already emitted under metrics=true, so the lens = ccx (there) + churn/clone/tested/amp (here).
// append one `,"key":"escaped-value"` field to a JSON object under construction, IN PLACE — jsonesc::escapeInto
// appends, so no per-field scratch string is needed (the reused-buffer posture jsonesc documents).
inline void appendJsonStrField( std::string& out, const char* keyWithComma, std::string_view value )
{
    out += keyWithComma;  out += '"';
    jsonesc::escapeInto( value, out, false, true, false );
    out += '"';
}

// P2.4 — the `,"cx":…,"ccx":…[,"in":…]` metrics run of a JSON signature row. "in" is emitted ONLY when a
// fan-in vector was actually supplied: an absent key means "not measured", never a fabricated 0 (which reads
// as "nobody calls this"). Mirrors sigRowHead's rule for the XML sibling.
inline void appendJsonMetricFields( std::string& out, const Symbol& s, NodeId id, const std::vector<std::uint32_t>* fanIn )
{
    char num[ 64 ];
    std::snprintf( num, sizeof( num ), ",\"cx\":%u,\"ccx\":%u", s.cx, s.ccx );
    out += num;
    if( fanIn && id < fanIn->size() )
    { std::snprintf( num, sizeof( num ), ",\"in\":%u", ( *fanIn )[ id ] );  out += num; }
}

// P2.3 — the canonical `path::scope::name` id, but ONLY when it ADDS an enclosing scope: a free function's
// canonical id IS its bare name, so repeating it would cost tokens and disambiguate nothing. "" ⇒ emit no
// id= / "id" at all. ONE definition of the rule, shared by the XML and JSON signature-row writers below and
// matching the default map's <s id="…"> convention exactly.
inline std::string scopedCanonicalId( const IngestResult& ing, const Symbol& s )
{
    VERIFY( s.fileId < ing.files.size() );
    std::string canon = canonicalId( ing.files[ s.fileId ], s.scope, s.name );
    return canon == s.name ? std::string{} : canon;
}

// P2.3/P2.4 — the per-row descriptive facts sigRowHead() folds in, grouped (not individual params) so the
// helper stays well under the params-regression bar. `lens` is the pre-rendered churn/amp/clone/tested attr
// run; `pure` is " pure=\"1\"" or "". Both are borrowed views onto the caller's stack buffers.
struct SigRowFacts
{
    bool                              metrics = false;
    const std::vector<std::uint32_t>* fanIn   = nullptr;   // nullptr / short ⇒ in= is OMITTED, never printed as 0
    const char*                       lens    = "";
    const char*                       pure    = "";
};

// P2.3/P2.4 — the exact "<d …>" opening tag of ONE signature row, defined once so the two-phase (globally
// budgeted) emitter and the streaming emitter can never drift by a byte: the budget ledger measures exactly
// the string this returns.
// P2.3 — n= (and id= when the canonical `path::scope::name` ADDS an enclosing scope; a free function's
// canonical id IS its bare name, so it costs zero bytes there) is the CHAIN KEY: without it a reader had to
// parse a C++ declarator out of the signature text to chain into --expand/--callers. Same canonicalId form
// the default map's <s id="…"> uses, so an id read out of a bundle addresses the same symbol in either lens.
// The `l=` prefix is DELIBERATELY kept first — existing consumers key on the "<d l=" opening.
// P2.4 — in= is emitted ONLY when a fan-in vector was actually supplied. A bundle assembled without one used
// to print in="0", which reads as "nobody calls this" — a FALSE ZERO. An absent attribute means "not
// measured"; in="0" now means, and only means, a measured zero.
inline std::string sigRowHead( const IngestResult& ing, NodeId id, const SigRowFacts& facts, std::vector<char>& esc )
{
    VERIFY( id < ing.symbols.size() );
    const Symbol& s = ing.symbols[ id ];
    VERIFY( s.fileId < ing.files.size() );

    // declaration line, then identity (the chain key)
    char lineAttr[ 32 ];
    std::snprintf( lineAttr, sizeof( lineAttr ), "<d l=\"%u\" n=\"", s.line );
    std::string head = lineAttr;
    head += escapeXml( s.name, esc );          // escapeXml returns a view INTO esc — copy before the next call
    head += "\"";
    if( const std::string canon = scopedCanonicalId( ing, s ); !canon.empty() )
    { head += " id=\"";  head += escapeXml( canon, esc );  head += "\""; }

    // descriptive facts — cx/ccx/in only under metrics; the Q3 lens + pure ride along either way
    char tail[ 192 ];
    if( facts.metrics )
    {
        char inAttr[ 24 ];  inAttr[ 0 ] = '\0';
        if( facts.fanIn && id < facts.fanIn->size() )
        {
            std::snprintf( inAttr, sizeof( inAttr ), " in=\"%u\"", ( *facts.fanIn )[ id ] );
        }
        std::snprintf( tail, sizeof( tail ), " cx=\"%u\" ccx=\"%u\"%s%s%s>", s.cx, s.ccx, inAttr, facts.lens, facts.pure );
    }
    else
    {
        std::snprintf( tail, sizeof( tail ), "%s%s>", facts.lens, facts.pure );
    }
    head += tail;
    return head;
}

// ── §A4a — THE ONE SIGNATURE-PAYLOAD TRIM LADDER (steps A..F, kForPayloadBudgetBytes above) ──────────
// Extracted from packSignatures so the JSON sibling runs the SAME ladder rather than a second copy of it:
// §A4a found `--for --json` byte-identical at --token-budget=1000 and 20000 because the
// JSON emitter had no budget at all, and the honest fix is one ladder with two serializations — a cloned
// ladder is exactly the "new clone of a reused helper" --quality-delta gates on, and two copies is how the
// XML and JSON trims would silently diverge one round from now.
//
// Format-agnostic by construction: every decision it makes reads only (globalRank, doc, sig, dropped) on an
// entry and (wrapBytes, entryBegin, entryEnd, liveCount) on its file — never a tag, brace, or quote. The
// FORMAT lives entirely in the caller's `entryCost`, which reports the exact emitted byte cost of one entry
// in that caller's own serialization (0 for a dropped entry). Templated on the caller's own row structs
// (duck-typed on those member names) so neither emitter has to reshape its rows to call this.
//
// `total` is the running exact byte total of the whole block and is updated in place. NOTE on the delta
// order: an action can GROW an entry by a couple of bytes (the appended ellipsis on a barely-over string),
// so subtract the old cost first and add the new one — never form `before - after` (it can be negative,
// i.e. unsigned-overflow UB under G1's -fsanitize=integer). `total >= before` always holds (before is a
// summand of total).
template<class EntryT, class FileT, class CostFn>
inline void trimSigLadder( std::vector<EntryT>& entries, std::vector<FileT>& files,
                           std::size_t& total, std::size_t effectiveBudget, CostFn entryCost )
{
    const auto fits      = [ & ] { return total <= effectiveBudget; };
    const auto shrinkSig = [ & ]( EntryT& e, std::size_t cap )
    { total -= entryCost( e ); truncateUtf8WithEllipsis( e.sig, cap ); total += entryCost( e ); };
    const auto dropDoc   = [ & ]( EntryT& e )
    { total -= entryCost( e ); e.doc.clear(); total += entryCost( e ); };
    const auto capDoc    = [ & ]( EntryT& e, std::size_t cap )
    { total -= entryCost( e ); truncateUtf8WithEllipsis( e.doc, cap ); total += entryCost( e ); };

    // ladder steps A..F (see kForPayloadBudgetBytes above); entries walk tail → head. Plain
    // pre-decrement countdown loops — `k-- > 0` wraps at 0, which G1's -fsanitize=integer traps.
    for( std::size_t k = entries.size(); k > 0 && !fits(); )
    { // A: tail sigs 160 → 96
        if( --k; entries[k].globalRank > kForDocExcerptRankCount )
        {
            shrinkSig( entries[k], kForCapTailSigBytes );
        }
    }
    for( std::size_t k = entries.size(); k > 0 && !fits(); )
    { // B: rank 13..24 lose the excerpt
        if( --k; entries[k].globalRank > kForDocFullRankCount && entries[k].globalRank <= kForDocExcerptRankCount )
        {
            dropDoc( entries[k] );
        }
    }
    for( std::size_t k = entries.size(); k > 0 && !fits(); )
    { // C: rank 1..12 doc capped at 96
        if( --k; entries[k].globalRank <= kForDocFullRankCount )
        {
            capDoc( entries[k], kForDocExcerptBytes );
        }
    }
    for( std::size_t k = entries.size(); k > 0 && !fits(); )
    { // D: rank 5..12 doc dropped + sig capped
        if( --k; entries[k].globalRank > 4 && entries[k].globalRank <= kForDocFullRankCount ) { dropDoc( entries[k] ); shrinkSig( entries[k], kForTailSigBytes ); }
    }
    for( std::size_t k = entries.size(); k > 0 && !fits(); )
    { // E: rank 1..4 sig capped (doc floor stays)
        if( --k; entries[k].globalRank <= 4 )
        {
            shrinkSig( entries[k], kForTailSigBytes );
        }
    }
    for( std::size_t fi = files.size(); fi > 0 && !fits(); )                 // F: drop whole entries, tail file first
    {
        FileT& sf = files[ --fi ];
        for( std::size_t k = sf.entryEnd; k > sf.entryBegin && !fits(); )
        {
            EntryT& e = entries[ --k ];
            if( e.dropped || e.globalRank <= 4 )
            {
                continue; // rank 1..4 always survive (the floor)
            }
            total -= entryCost( e );
            e.dropped = true;
            if( --sf.liveCount == 0 && sf.entryEnd > sf.entryBegin )
            {
                total -= sf.wrapBytes; // wrapper goes with its last entry
            }
        }
    }
}

// §B10.1 — WHY `redact` KEEPS ITS DEFAULT HERE, and it is not an oversight. W3-N1's rule is "REQUIRED, no
// default, so a new emitting clone cannot silently opt out", and packSource / packOutline / buildRecall have
// now all taken it (their `redact` is the LAST parameter, so dropping the default costs nothing). Here it is
// a MIDDLE parameter with six more defaulted parameters behind it, and C++ requires defaults to be trailing:
// removing this one is ill-formed unless churnPerFile/cloneMember/tested/amp/rankAdaptivePayload/
// payloadBudgetBytes/noteIndex all lose theirs too, which rewrites every call site across main.cpp,
// mcpverbs.h, packtask.h and tracelocus.h — four files, three concurrent lanes. packBodies is the same shape
// (four trailing defaults). So the compile net is 8 of 10, and the two the compiler cannot hold are held by
// test/fixedbufsweep.sh's population sweep instead: a new sig/body emitter shows up there as an
// unclassified site. Reordering the parameter list is the real fix and belongs to a round that owns all four
// files at once.
inline void packSignatures( std::FILE* out, const IngestResult& ing, const std::vector<float>& rank,
                            int topN, std::size_t budgetBytes,
                            bool metrics = false, const std::vector<std::uint32_t>* fanIn = nullptr,
                            const std::vector<char>* impure = nullptr, RedactCounts* redact = nullptr,
                            const std::vector<std::uint32_t>* churnPerFile = nullptr,   // Q3 per-FILE recent-commit count (git; omit w/o git)
                            const std::vector<std::uint8_t>*  cloneMember  = nullptr,   // Q3 per-symbol: 1 = a member of a duplicate-clone group
                            const std::vector<std::uint8_t>*  tested       = nullptr,   // Q3 per-symbol: 1 = referenced from a test-path file
                            const std::vector<std::uint32_t>* amp          = nullptr,   // Q3 per-symbol change-amplification (callers + co-change partners)
                            bool rankAdaptivePayload = false,    // B0.3: rank-adaptive doc/sig budget (--for lens only; see the constants above)
                            std::size_t payloadBudgetBytes = 0,  // H1 (B0 r2): GLOBAL byte budget for this <sigs> block — 0 = no global
                                                                 //   budget (the pre-H1 path, byte-identical); only the --for lens and the
                                                                 //   MCP `for` verb pass one (kForPayloadBudgetBytes minus the sibling blocks)
                            const notes::NoteIndex* noteIndex = nullptr )   // L3: field notes — surfaces <note> children on each <f>
                                                                            //   (path target) and <d> (canonical-id target). nullptr ⇒ INERT
                                                                            //   (byte-identical). W3-N2: note bytes are CHARGED to the budget
                                                                            //   (as the JSON sibling charges them) but the ladder never TRIMS a
                                                                            //   note — user-attached memory always survives; the payload around
                                                                            //   it shrinks to make room. Charging nothing put a note-heavy tree
                                                                            //   56% over a tight --token-budget the JSON mode honored.
{
    // budgetBytes == 0 ⇒ UNLIMITED (A3-F1): the MCP `for` verb has no byte budget, and 0 must never mean
    // "cap at zero bytes" (the cap fired before the first signature and emitted a bare <sigs></sigs>).
    // Matches writeRecall's "0 = no cap" convention; the CLI always passes a real budget (default 64 KB).
    if( budgetBytes == 0 )
    {
        budgetBytes = SIZE_MAX;
    }

    const std::size_t S = ing.symbols.size();

    // top-N symbols by (rank desc, id asc)
    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );
    const std::size_t keep = std::min<std::size_t>( topN > 0 ? std::size_t( topN ) : S, S );

    // bucket kept symbols by file; files ordered by first-seen (best) rank
    std::vector<std::vector<NodeId>> buckets( ing.files.size() );
    std::vector<std::uint32_t>       fileOrder;
    std::vector<char>                seen( ing.files.size(), 0 );
    for( std::size_t k = 0; k < keep; ++k )
    {
        const std::uint32_t f = ing.symbols[ order[k] ].fileId;
        if( !seen[f] ) { seen[f] = 1; fileOrder.push_back( f ); }
        buckets[f].push_back( order[k] );
    }

    // B0.3: the payload rule keys on each kept symbol's GLOBAL rank (emission below is file-grouped and
    // source-ordered, so the rank must be recorded before the per-file re-sort). 1-based; 0 = not kept.
    std::vector<std::uint32_t> globalRankOf;
    if( rankAdaptivePayload )
    {
        globalRankOf.assign( S, 0 );
        for( std::size_t k = 0; k < keep; ++k )
        {
            globalRankOf[order[k]] = std::uint32_t( k + 1 );
        }
    }

    XmlWriter         w( out );
    std::vector<char> esc;
    std::size_t       used = 0;

    // ── H1 (B0 round 2): two-phase GLOBALLY-BUDGETED emission for the --for lens ─────────────────────
    // Derive every entry exactly as the streaming loop below would (same gates, same rank tiers, same
    // budgetBytes accounting, same redaction order) but into memory; then, if the exact emitted byte
    // count exceeds payloadBudgetBytes, walk the deterministic trim LADDER (kForPayloadBudgetBytes doc
    // above) until it fits; then emit. When nothing trims, the emitted bytes are identical to the
    // streaming path by construction (same strings, same order).
    if( rankAdaptivePayload && payloadBudgetBytes > 0 )
    {
        struct SigFile
        {
            std::uint32_t fileId     = 0;
            std::size_t   wrapBytes  = 0;   // exact emitted bytes of the <f …> wrapper + </f> + its note children
            std::string   notes;            // W3-N2: file notes, PRE-RENDERED so wrapBytes is exact
            std::size_t   entryBegin = 0;   // [entryBegin, entryEnd) rows in `entries`
            std::size_t   entryEnd   = 0;
            std::size_t   liveCount  = 0;   // non-dropped entries (wrapper is dropped when this hits 0)
        };
        struct SigEntry
        {
            std::uint32_t globalRank = 0;   // 1-based global rank — the ladder's only rank input
            std::string   head;             // the exact "<d …>" opening tag
            std::string   doc;              // RAW doc text after the rank tiers ("" ⇒ no <doc> child)
            std::string   sig;              // RAW one-line signature after the rank tiers
            std::string   notes;            // W3-N2: this symbol's note children, PRE-RENDERED (the JSON sibling's shape)
            bool          dropped    = false;
        };
        std::vector<SigFile>  sigFiles;
        std::vector<SigEntry> entries;

        // phase 1 — collect (mirrors the streaming loop byte-for-byte, including the budgetBytes gate)
        for( std::uint32_t f : fileOrder )
        {
            if( used >= budgetBytes )
            {
                break;
            }

            std::FILE* in = std::fopen( diskPath( ing, std::uint32_t( f ) ).c_str(), "rb" );
            if( !in )
            {
                continue; // graceful: file gone
            }
            std::string src;
            char        buf[ 4096 ];
            std::size_t n;
            while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
            {
                src.append( buf, n );
            }
            std::fclose( in );

            std::vector<NodeId>& syms = buckets[f];
            std::sort( syms.begin(), syms.end(), [ & ]( NodeId a, NodeId b )
            { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );

            SigFile sf;
            sf.fileId     = f;
            sf.entryBegin = entries.size();
            {
                // exact wrapper bytes: <f p="…"> [+ layer="…"] + </f>
                sf.wrapBytes = 6 + escapeXml( ing.files[f], esc ).size() + 1 + 1 + 4;
                if( const char* fl = builtinLayer( ing.files[f] ); *fl )
                {
                    sf.wrapBytes += 8 + std::strlen( fl ) + 1;
                }
                sf.notes      = renderNoteChildren( noteIndex, fileNoteTarget( noteIndex, ing.files[f] ), esc );   // W3-N2
                sf.wrapBytes += sf.notes.size();                                                                   //   charged, never trimmed
            }
            for( NodeId id : syms )
            {
                if( used >= budgetBytes )
                {
                    break;
                }
                const Symbol&     s = ing.symbols[id];
                const std::size_t a = s.sigStartByte, b = s.sigEndByte;
                if( a >= src.size() || b > src.size() || a >= b )
                {
                    continue;
                }

                std::string sig = cleanSig( src.data(), a, b, redact );
                if( sig.empty() )
                {
                    continue;
                }

                const std::uint32_t globalRank = globalRankOf[ id ];
                if( globalRank > kForDocExcerptRankCount )
                {
                    truncateUtf8WithEllipsis( sig, kForTailSigBytes );
                }

                const bool  pureSig = pureFromSig( sig, s.lang ) && !( impure && id < impure->size() && (*impure)[id] );
                const char* pure    = pureSig ? " pure=\"1\"" : "";

                char qbuf[ 80 ];  qbuf[ 0 ] = '\0';
                {
                    char* qp = qbuf; char* const qe = qbuf + sizeof( qbuf );
                    const auto appendf = [ & ]( const char* fmt, auto... args )
                    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
                        const int r = std::snprintf( qp, std::size_t( qe - qp ), fmt, args... );
#pragma clang diagnostic pop
                        if( r > 0 )
                        {
                            qp = ( r < qe - qp ) ? qp + r : qe;
                        }
                    };
                    if( churnPerFile && f < churnPerFile->size() && (*churnPerFile)[f] > 0 )
                    {
                        appendf( " churn=\"%u\"", (*churnPerFile)[f] );
                    }
                    if( amp && id < amp->size() && (*amp)[id] > 0 )
                    {
                        appendf( " amp=\"%u\"", (*amp)[id] );
                    }
                    if( cloneMember && id < cloneMember->size() && (*cloneMember)[id] )
                    {
                        appendf( " clone=\"1\"" );
                    }
                    if( tested && id < tested->size() && (*tested)[id] )
                    {
                        appendf( " tested=\"1\"" );
                    }
                }

                std::string head = sigRowHead( ing, id, SigRowFacts{ metrics, fanIn, qbuf, pure }, esc );

                std::string doc = docCommentBefore( src, a );
                redactInPlace( doc, redact );
                if( globalRank > kForDocExcerptRankCount )
                {
                    doc.clear();
                }
                else if( globalRank > kForDocFullRankCount )
                {
                    truncateUtf8WithEllipsis( doc, kForDocExcerptBytes );
                }

                if( !doc.empty() )
                {
                    used += doc.size() + 12; // the same budgetBytes accounting as the streaming path
                }
                used += sig.size() + 16;

                SigEntry e;
                e.globalRank = globalRank;
                e.head       = std::move( head );
                e.doc        = std::move( doc );
                e.sig        = std::move( sig );
                e.notes      = renderNoteChildren( noteIndex, symbolNoteTarget( noteIndex, ing, s ), esc );   // L3/D5 key + W3-N2 pre-render
                entries.push_back( std::move( e ) );
            }
            sf.entryEnd  = entries.size();
            sf.liveCount = sf.entryEnd - sf.entryBegin;
            sigFiles.push_back( sf );
        }

        // exact emitted byte count of the block as collected
        const auto entryCost = [ & ]( const SigEntry& e ) -> std::size_t
        {
            if( e.dropped )
            {
                return 0;
            }
            std::size_t c = e.head.size() + 4;                                       // "<d …>" + "</d>"
            if( !e.doc.empty() )
            {
                c += 11 + escapeXml( e.doc, esc ).size(); // "<doc>" + "</doc>"
            }
            c += escapeXml( e.sig, esc ).size();
            return c + e.notes.size();                                               // W3-N2: notes are pre-rendered, so their
            //   EXACT emitted size is known (jsonSigEntryCost)
        };
        std::size_t total = 6 + 7;                                                   // "<sigs>" + "</sigs>"
        for( const SigFile& sf : sigFiles )
        {
            total += sf.wrapBytes;
        }
        for( const SigEntry& e : entries )
        {
            total += entryCost( e );
        }

        const bool capped = total > payloadBudgetBytes;
        if( capped )
        {
            // the marker itself costs bytes — budget the trimmed state INCLUDING it (guard tiny budgets)
            const std::size_t markerBytes     = sizeof( " capped=\"1\"" ) - 1;
            const std::size_t effectiveBudget = payloadBudgetBytes > markerBytes ? payloadBudgetBytes - markerBytes : 0;

            // one ladder ACTION on one entry, tail-first; every action re-checks the budget so the ladder
            // stops at the first fitting state. Pure function of (global rank, the kFor* constants) — the
            // ladder itself is trimSigLadder() above, shared verbatim with the JSON sibling (§A4a).
            trimSigLadder( entries, sigFiles, total, effectiveBudget, entryCost );
        }

        // phase 2 — emit (identical write shapes to the streaming path)
        //
        // §P8 vocabulary (see src/pageview.h, THE TRUNCATION VOCABULARY, rule 5): this marker used to be
        // payload="capped" — a STRING ENUM, the tool's only one, readable solely by string-matching the
        // literal (packtask.h did exactly that). It is now the same boolean capped= every other truncating
        // element spells, so one parser reads them all. It carries no shown=/total= on purpose: the ladder
        // trims a BYTE budget, and shrinking a signature or dropping a doc excerpt reduces no row count, so
        // there is no honest S<T pair to print here — only "this payload was trimmed". Absent = untrimmed.
        w.write( capped ? "<sigs capped=\"1\">" : "<sigs>" );
        for( const SigFile& sf : sigFiles )
        {
            if( capped && sf.liveCount == 0 && sf.entryEnd > sf.entryBegin )
            {
                continue; // every entry dropped → wrapper too
            }
            w.write( "<f p=\"" );  w.write( escapeXml( ing.files[ sf.fileId ], esc ) );  w.write( "\"" );
            if( const char* fl = builtinLayer( ing.files[ sf.fileId ] ); *fl ) { w.write( " layer=\"" );  w.write( fl );  w.write( "\"" ); }
            w.write( ">" );
            w.write( sf.notes );                                               // L3/D5: file notes on this <f> (rendered in phase 1)
            for( std::size_t k = sf.entryBegin; k < sf.entryEnd; ++k )
            {
                const SigEntry& e = entries[k];
                if( e.dropped )
                {
                    continue;
                }
                w.write( e.head.c_str() );
                if( !e.doc.empty() ) { w.write( "<doc>" );  w.write( escapeXml( e.doc, esc ) );  w.write( "</doc>" ); }
                w.write( escapeXml( e.sig, esc ) );
                w.write( e.notes );                                            // L3: symbol notes on this <d> (inert when null)
                w.write( "</d>" );
            }
            w.write( "</f>" );
        }
        w.write( "</sigs>" );
        w.flush();
        return;
    }

    w.write( "<sigs>" );
    for( std::uint32_t f : fileOrder )
    {
        if( used >= budgetBytes )
        {
            break;
        }

        std::FILE* in = std::fopen( diskPath( ing, std::uint32_t( f ) ).c_str(), "rb" );
        if( !in )
        {
            continue; // graceful: file gone
        }
        std::string src;
        char        buf[ 4096 ];
        std::size_t n;
        while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
        {
            src.append( buf, n );
        }
        std::fclose( in );

        // signatures in source order for readability
        std::vector<NodeId>& syms = buckets[f];
        std::sort( syms.begin(), syms.end(), [ & ]( NodeId a, NodeId b )
        { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );

        w.write( "<f p=\"" );  w.write( escapeXml( ing.files[f], esc ) );  w.write( "\"" );
        if( const char* fl = builtinLayer( ing.files[f] ); *fl ) { w.write( " layer=\"" );  w.write( fl );  w.write( "\"" ); }   // P3
        w.write( ">" );
        {
            const std::string fileNotes = renderNoteChildren( noteIndex, fileNoteTarget( noteIndex, ing.files[f] ), esc );   // L3/D5
            w.write( fileNotes );
            used += fileNotes.size();                                                                   // W3-N2: charged like the JSON wrapBytes
        }
        for( NodeId id : syms )
        {
            if( used >= budgetBytes )
            {
                break;
            }
            const Symbol&     s = ing.symbols[id];
            const std::size_t a = s.sigStartByte, b = s.sigEndByte;
            if( a >= src.size() || b > src.size() || a >= b )
            {
                continue;
            }

            // compact one-line declaration (shared cleaner: stop at '{' or ';', collapse whitespace)
            std::string sig = cleanSig( src.data(), a, b, redact );
            if( sig.empty() )
            {
                continue;
            }

            // B0.3 rank-adaptive payload: a pure function of (global rank, fixed byte limits) — see the
            // kForDoc*/kForTailSig constants. Top ranks are untouched; the tail is signature-only.
            const std::uint32_t globalRank = rankAdaptivePayload ? globalRankOf[ id ] : 0u;
            if( rankAdaptivePayload && globalRank > kForDocExcerptRankCount )
            {
                truncateUtf8WithEllipsis( sig, kForTailSigBytes );
            }

            const bool  pureSig = pureFromSig( sig, s.lang ) && !( impure && id < impure->size() && (*impure)[id] );   // const/non-mutating AND no transitive side-effects
            const char* pure    = pureSig ? " pure=\"1\"" : "";

            // Q3 quality lens — the steering facts folded onto the <d> block (built into a side buffer,
            // appended before pure). Each attr is emitted only when its vector is present AND the value is
            // worth a token (lean output: churn/amp only when >0; clone/tested only when the flag is set).
            // ccx already rides the metrics attrs below — the lens completes it with churn/clone/tested/amp.
            char qbuf[ 80 ];  qbuf[ 0 ] = '\0';
            {
                char* qp = qbuf; char* const qe = qbuf + sizeof( qbuf );
                // A4-F8: clamp qp to qe after each append — an un-clamped `qp += snprintf(...)` overruns on
                // truncation (the next size_t(qe-qp) underflows into an unbounded stack write). See site #1.
                // fmt is always a string literal at every call site below — the non-literal warning is
                // an artifact of routing it through the lambda parameter
                const auto appendf = [ & ]( const char* fmt, auto... args )
                {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
                    const int r = std::snprintf( qp, std::size_t( qe - qp ), fmt, args... );
#pragma clang diagnostic pop
                    if( r > 0 )
                    {
                        qp = ( r < qe - qp ) ? qp + r : qe;
                    }
                };
                if( churnPerFile && f < churnPerFile->size() && (*churnPerFile)[f] > 0 )
                {
                    appendf( " churn=\"%u\"", (*churnPerFile)[f] );
                }
                if( amp && id < amp->size() && (*amp)[id] > 0 )
                {
                    appendf( " amp=\"%u\"", (*amp)[id] );
                }
                if( cloneMember && id < cloneMember->size() && (*cloneMember)[id] )
                {
                    appendf( " clone=\"1\"" );
                }
                if( tested && id < tested->size() && (*tested)[id] )
                {
                    appendf( " tested=\"1\"" );
                }
            }

            // identity (n=/id=) + descriptive facts (cx=complexity, ccx=cognitive, in=reuse-count, Q3 lens, pure)
            w.write( sigRowHead( ing, id, SigRowFacts{ metrics, fanIn, qbuf, pure }, esc ) );
            std::string doc = docCommentBefore( src, a );   // L2: the human-written intent, if any
            redactInPlace( doc, redact );                    // a doc-comment body can hold a pasted secret
            if( rankAdaptivePayload )                        // B0.3: tail entries carry a trimmed excerpt / no doc
            {
                if( globalRank > kForDocExcerptRankCount )
                {
                    doc.clear();
                }
                else if( globalRank > kForDocFullRankCount )
                {
                    truncateUtf8WithEllipsis( doc, kForDocExcerptBytes );
                }
            }
            if( !doc.empty() ) { w.write( "<doc>" );  w.write( escapeXml( doc, esc ) );  w.write( "</doc>" );  used += doc.size() + 12; }
            w.write( escapeXml( sig, esc ) );
            const std::string symNotes = renderNoteChildren( noteIndex, symbolNoteTarget( noteIndex, ing, s ), esc );   // L3/D5
            w.write( symNotes );
            w.write( "</d>" );
            used += sig.size() + 16 + symNotes.size();                                                  // W3-N2: notes are charged, never trimmed
        }
        w.write( "</f>" );
    }
    w.write( "</sigs>" );
    w.flush();
}

// R6 (A4-R6) — --format=candidates: a FLAT, machine-readable top-K export for an EXTERNAL reranker. One
// <cand> row per candidate carrying exactly (rank, score, name, canonical id, kind, file, line, one-line
// signature) — NO lens/quality attrs, NO doc bodies, NO nesting. The research doc's division-of-labor thesis:
// ripwire stays deterministic and offline and hands a reranker precisely the identity + score + signature it
// needs, nothing to strip. Still XML so the G4 xmllint gate holds; the flatness is what makes it cheap.
// Deterministic: (score desc, id asc) — the SAME total order packSignatures/serialize select with. `cap`
// bounds the row count (wired to --top-k); cap<=0 = every symbol. Emits exactly `keep` rows (a symbol whose
// signature span is unreadable still gets a row with an empty <sig/>) so a consumer can trust row-count==cap.
//
// §A4e/§A4f — the RANKING PROVENANCE this export used to carry none of. An external reranker was handed a
// score column with no way to know which ranker produced it (name-exact and subtoken+body BM25 live on
// different score scales — 6.66 vs 29.95 on the same corpus), whether the query's literal mentions were
// anchor-lifted, how much of the corpus the top-k cut away, or that the whole ranking rested on no textual
// evidence at all (the §P5 weak signal was string-spliced into the XML lens header, structurally out of
// reach here — for a nonsense query this exported 200 rows of s="0" as a straight-faced candidate set).
struct CandidateProvenance
{
    const char*   route    = nullptr;   // which ranker ran ("name-exact" / "subtoken+body" / "no-route" / "query"); nullptr ⇒ attribute absent
    std::uint32_t anchored = 0;         // §B8 mention-anchor lifts folded into this rank (0 is a real, emitted value)
    bool          weak     = false;     // §P5: the top raw lexical score is below the confidence threshold
};

// The root element's opening tag. §A4f — what each attribute means, once:
//   count=/total=/capped=  the §P8 shown/total pair: `keep` rows exported out of `corpusCount` ranked
//             candidates, capped="1" ⇔ the top-k cut dropped some. The §P17 path-tier penalty is
//             query-independent and needs no per-run attribute.
//   route=    which ranker produced these scores. name-exact and subtoken+body BM25 do NOT share a score
//             scale (6.66 vs 29.95 on the same corpus), so comparing s= is only meaningful within one route.
//   anchored= how many query-mention anchor lifts (§B8) reshaped this rank. 0 is EMITTED, not omitted:
//             "the anchor ran and moved nothing" and "no anchor at all" must not look alike.
//   weak="1"  §P5: the top raw lexical score is below the confidence threshold — these rows rest on
//             thin-to-no textual evidence. Absent ⇒ the query cleared it (never a fabricated weak="0").
inline std::string candidatesRootTag( std::size_t keep, std::size_t corpusCount, const CandidateProvenance& prov )
{
    std::string tag = "<candidates count=\"" + std::to_string( keep )
                    + "\" total=\"" + std::to_string( corpusCount )
                    + "\" capped=\"" + ( keep < corpusCount ? "1" : "0" ) + "\"";
    if( prov.route ) { tag += " route=\"";  tag += prov.route;  tag += "\""; }
    tag += " anchored=\"" + std::to_string( prov.anchored ) + "\"";
    if( prov.weak )
    {
        tag += " weak=\"1\"";
    }
    return tag + ">";
}

inline void packCandidates( std::FILE* out, const IngestResult& ing, const std::vector<float>& rank, int cap,
                            RedactCounts* redact,                 // §B0/W3-N1: REQUIRED — <sig> is emitted text (nullptr = --no-redact)
                            CandidateProvenance prov = {} )
{
    const std::size_t S = ing.symbols.size();

    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );
    const std::size_t keep = std::min<std::size_t>( cap > 0 ? std::size_t( cap ) : S, S );

    // Per-file content cache: emit in RANK order (r=1..K) but read each needed file at most once. A top-K
    // spanning F files does F file reads, not K.
    HashMap<std::uint32_t, std::string> contents;
    const auto contentOf = [ & ]( std::uint32_t fid ) -> const std::string&
    {
        const auto it = contents.find( fid );
        if( it != contents.end() )
        {
            return it->second;
        }
        std::string s;
        if( fid < ing.files.size() )
        {
            if( std::FILE* in = std::fopen( diskPath( ing, fid ).c_str(), "rb" ) )
            {
                char b[4096];
                std::size_t n;
                while( ( n = std::fread( b, 1, sizeof( b ), in ) ) > 0 )
                {
                    s.append( b, n );
                }
                std::fclose( in );
            }
        }
        return contents.emplace( fid, std::move( s ) ).first->second;
    };

    XmlWriter         w( out );
    std::vector<char> esc;

    // §P8 collision, documented not renamed: on a <cand> row s= is the SCORE and k= the KIND tag — the exact
    // inverse of the ranked map. Neither can move (golden.xml pins one, postingscheck.sh's positional
    // regex pins the other), so the legend states it. G4: no double hyphen inside an XML comment.
    w.write( "<!-- ripwire candidates: flat top K export for an external reranker. r=rank(1 based) s=SCORE "
             "n=name id=canonical k=KIND-tag p=path l=line. Note k= is the kind here and the PageRank score in "
             "the ranked map; on this row the score is s=. Root: count= rows exported of total= RANKED CORPUS "
             "symbols (total is the corpus size, never a match count), capped=\"1\" means the top-k cut dropped "
             "some; route= names the ranker (s= is comparable only within one route); anchored= counts "
             "query-mention lifts (0 = the anchor ran and moved nothing); weak=\"1\" means the top raw lexical "
             "score is below the confidence bar, so these rows rest on thin textual evidence. -->" );
    w.write( candidatesRootTag( keep, S, prov ) );
    for( std::size_t r = 0; r < keep; ++r )
    {
        const NodeId       id  = order[r];
        const Symbol&      s   = ing.symbols[id];
        const std::string& src = contentOf( s.fileId );

        std::string sig;
        if( s.sigStartByte < s.sigEndByte && s.sigEndByte <= src.size() )
        {
            sig = cleanSig( src.data(), s.sigStartByte, s.sigEndByte, redact );
        }
        const std::string canon = canonicalId( ing.files[ s.fileId ], s.scope, s.name );

        char hb[ 96 ];  std::snprintf( hb, sizeof( hb ), "<cand r=\"%zu\" s=\"%.6g\" n=\"", r + 1, double( rank[id] ) );
        w.write( hb );  w.write( escapeXml( s.name, esc ) );
        w.write( "\" id=\"" );  w.write( escapeXml( canon, esc ) );
        w.write( "\" k=\"" );   w.write( symTag( s.kind ) );
        w.write( "\" p=\"" );   w.write( escapeXml( ing.files[ s.fileId ], esc ) );
        char lb[ 24 ];  std::snprintf( lb, sizeof( lb ), "\" l=\"%u\">", s.line );
        w.write( lb );
        w.write( "<sig>" );  w.write( escapeXml( sig, esc ) );  w.write( "</sig></cand>" );
    }
    w.write( "</candidates>" );
    w.flush();
}

// --expand=SYM:START-END (octocode's partial-file idea): pull a SLICE
// of a large def's body instead of the whole thing. Lines are 1-based, relative to the symbol's OWN
// first line (Symbol::line), matching what an agent already sees in --outline/--pack-signatures l=
// output — never a whole-file line number. hasRange=false ⇒ the pre-existing whole-body path (byte-
// identical; this struct's default is inert).
struct LineRange
{
    std::uint32_t startLine = 0;       // 1-based, relative to the symbol's first line; 0 ⇒ unset
    std::uint32_t endLine   = 0;       // 1-based, inclusive; 0 ⇒ unset
    bool          hasRange  = false;   // true ⇒ a --expand=SYM:START-END slice was requested for this node
};

// Slice `body` (the def's full text, [sigStartByte,endByte)) down to 1-based lines [startLine,endLine]
// relative to its own first line. Clamps out-of-range bounds to the def's actual span (never OOB, never
// throws) and UTF-8-safe (never splits a codepoint — same back-off rule as packSource/cleanSig). Returns
// the sliced text plus the CLAMPED [loLine,hiLine] (1-based) and the def's total line count, so the
// caller can emit an honest lines="lo-hi/total" marker. A reversed/malformed range (caught by the CLI
// parse below) never reaches here — but startLine>endLine is still handled defensively by swapping.
struct SlicedBody
{
    std::string   text;
    std::uint32_t loLine = 1;
    std::uint32_t hiLine = 1;
    std::uint32_t total  = 1;
};

inline SlicedBody sliceBodyLines( std::string_view body, std::uint32_t startLine, std::uint32_t endLine )
{
    // split into line spans [begin,end) (end excludes the trailing '\n', if any) — one pass, no copies yet.
    std::vector<std::pair<std::size_t, std::size_t>> lines;
    std::size_t                                      lineStart = 0;
    for( std::size_t i = 0; i < body.size(); ++i )
    {
        if( body[i] == '\n' ) { lines.emplace_back( lineStart, i ); lineStart = i + 1; }
    }
    lines.emplace_back( lineStart, body.size() );   // final line (no trailing '\n', or the text after the last one)

    const std::uint32_t total = std::uint32_t( lines.size() );
    if( startLine > endLine )
    {
        std::swap( startLine, endLine ); // defensive: never emit an inverted slice
    }
    std::uint32_t lo = startLine < 1 ? 1 : startLine;
    std::uint32_t hi = endLine   < 1 ? 1 : endLine;
    if( lo > total )
    {
        lo = total; // clamp — never index past the def's span
    }
    if( hi > total )
    {
        hi = total;
    }
    if( lo > hi )
    {
        lo = hi; // degenerate (empty def) — 1 line, both ends equal
    }

    const std::size_t byteStart = lines[ lo - 1 ].first;
    std::size_t       byteEnd   = lines[ hi - 1 ].second;

    // UTF-8-safe: neither cut point may land mid-codepoint (a continuation byte is 10xxxxxx). Line splits
    // are on '\n' (always a codepoint boundary) so this is normally a no-op; kept as the same defensive
    // back-off used elsewhere (packSource/cleanSig/docCommentBefore) in case of a corrupt/binary body.
    std::size_t bs = byteStart;
    while( bs < body.size() && ( static_cast<unsigned char>( body[bs] ) & 0xC0 ) == 0x80 )
    {
        ++bs;
    }
    while( byteEnd > bs && ( static_cast<unsigned char>( body[byteEnd] ) & 0xC0 ) == 0x80 )
    {
        --byteEnd;
    }

    SlicedBody out;
    out.text   = std::string( body.substr( bs, byteEnd - bs ) );
    out.loLine = lo;
    out.hiLine = hi;
    out.total  = total;
    return out;
}

// ── §H5: THE RECORD OF WHAT packBodies ACTUALLY EMITTED ─────────────────────────────────────────────────
// `--pack-task --json` used to answer "which bodies?" a SECOND time, in a second place, from the same inputs:
// the XML pass handed every candidate to packBodies (which groups by FILE and stops on a BYTE budget), counted
// the resulting <b> elements as bodies_kept, and the JSON tail then re-sliced the first bodies_kept ids in
// RANK order and emitted each one WHOLE. Two answers, one number over both: MEASURED on this repo at
// --token-budget=8000, XML kept {redactInPlace, redactSecrets} while JSON emitted {redactInPlace,
// loadRecallBody} under bodies_kept=2; on `--pack-task="serializeJson runDefaultMap" --token-budget=5000` the
// XML truncated its single body to fit 11 800 B while the JSON shipped 42 200 B against the SAME stated
// ceiling — packBodiesJson had no budgetBytes parameter, no `used`, and no truncation vocabulary at all.
//
// The fix is not a second budget in the JSON emitter (that is how the divergence was born). packBodies is the
// ONE place the decisions live, and it now REPORTS them: which ids it emitted, the exact post-slice /
// post-compress / post-redact bytes it emitted for each, whether it truncated, and the callee rows it showed.
// The JSON dialect renders that record. Same SET, same SELECTION, same TRUNCATION, by construction — a future
// third dialect gets those for free, because there is nothing to keep in step.
//
// NOT the same BYTES, and this comment said otherwise until the wave-2 verifier caught it (F-MED-1). The
// record is taken at the push_back below, i.e. BEFORE `appendCdataSafe`, and that is not an escape — it is a
// LOSSY SCRUB: `xmlSafeByte` maps every C0 byte except \t \n \r to a space, and invalid UTF-8 becomes '?'.
// So a body containing ESC or Latin-1 bytes reaches XML scrubbed and JSON raw (measured: 140 B vs 148 B on a
// fixture whose def holds ESC + Latin-1, at every budget and under --compress/--no-redact). The divergence is
// PRE-EXISTING and base-byte-identical — the wave regressed nothing — but it is real, it is the §B12.7 C0
// dialect divergence appearing in the body payload rather than the task echo, and `bodydialectcheck` cannot
// see it because that gate asserts sets, truncations and omissions, never body bytes. Routed to the wave-3
// lane that owns this file together with §B12.7. Do not restore the unqualified claim without closing it.
//
// The record also removes a latent counting bug: bodies_kept was `countSub( bodiesStr, "<b " )`, and body text
// rides in CDATA verbatim, so any corpus body containing the literal `<b ` (HTML, a markdown table, this
// comment) inflated the count.
struct EmittedBodyCall
{
    std::string   name;
    std::uint32_t line = 0;
    std::string   sig;    // already cleaned + redacted; NOT yet XML/JSON-escaped (each dialect escapes its own way)
};

struct EmittedBody
{
    NodeId                       id          = 0;
    std::string                  text;         // post-slice/compress/redact bytes, taken BEFORE appendCdataSafe's
                                               // xmlSafeByte scrub — so NOT byte-equal to the XML CDATA when the
                                               // body carries C0 or invalid UTF-8 (see the header note, §B12.7)
    std::string                  lineSpan;     // octocode partial-fetch marker value "lo-hi/total"; empty ⇒ whole body
    bool                         isTruncated = false;
    bool                         isXmlScrubbed = false;   // §B12.7/F-MED-1: `text` (this dialect's bytes) differs from
                                                          // the XML CDATA's. Decided from the two byte strings at the
                                                          // emission, carried here so BOTH dialects can disclose it.
    std::vector<EmittedBodyCall> calls;
    std::uint32_t                callsTotal  = 0;   // outOff[id+1]-outOff[id] — the denominator behind calls.size()
};

struct EmittedBodies
{
    std::vector<EmittedBody> kept;
    std::vector<NodeId>      omitted;      // exactly the ids the XML named in a `<!-- body omitted (over budget) -->`
                                           // marker, so the JSON dialect can name the SAME set and no more. A body
                                           // dropped after the budget was fully spent is silent in BOTH dialects and
                                           // is covered by total=/capped= (XML) and bodies_total/bodies_kept (JSON).
    std::size_t              requested = 0; // valid ids handed in: the denominator for total=/capped=
};

// §H5: record an over-budget skip. A free function rather than an inline `if( outEmitted )`, because the one
// call site is packBodies' DEEPEST block (inside for/for/if/else) and a null-check there is the single
// statement that pushed that function's nesting metric over the bar — measured by bisection, not guessed.
inline void noteOmittedBody( EmittedBodies* out, NodeId id )
{
    if( out )
    {
        out->omitted.push_back( id );
    }
}

// The two sinks emitCalleeCallsBlock writes through. A struct rather than two more parameters: the function
// already carries nine, and W3-N1's "REQUIRED redact, no default" discipline survives because this aggregate
// has NO default member initialisers — a caller must spell both fields, including a deliberate `nullptr`.
struct CalleeCallsSink
{
    RedactCounts*                 redact;     // §B0/W3-N1: REQUIRED — the <c> callee sigs are emitted text
    std::vector<EmittedBodyCall>* recorded;   // §H5: nullptr ⇒ do not record (every caller that wants XML only)
};

// §P10.1: the disclosed <calls total=... [shown=... capped="1"]> block
// for one body's 1-hop callee signatures — extracted out of packBodies so the disclosure logic doesn't
// inflate packBodies' own complexity/LOC. `total` is outOff[id+1]-outOff[id] — outTargets is deduped-per-
// source (graph.h:37), so this is exactly what a standalone `--callees=SYM` reports as count= for an
// unambiguous symbol. shown=/capped="1" are added ONLY when the 16-per-body cap or the byte budget
// actually cuts the list (pageview.h THE TRUNCATION VOCABULARY rule 3: capped= always accompanies
// shown=, and both are omitted — never shown="T" capped="0" — when the listing is complete).
template <typename ContentOfFn>
inline void emitCalleeCallsBlock( std::string& out, NodeId id, const std::vector<std::uint32_t>& outOff,
                                  const std::vector<NodeId>& outTargets, const IngestResult& ing,
                                  ContentOfFn&& contentOf, std::vector<char>& esc, std::size_t& used, std::size_t budgetBytes,
                                  const CalleeCallsSink& sink )
{
    RedactCounts* const redact = sink.redact;
    if( id + 1 >= outOff.size() )
    {
        return;
    }
    const std::uint32_t total = outOff[id + 1] - outOff[id];
    if( total == 0 )
    {
        return;
    }

    std::string callsBody;
    int         shown = 0;
    for( std::uint32_t k = outOff[id]; k < outOff[id + 1] && shown < 16 && used < budgetBytes; ++k )
    {
        const NodeId cid = outTargets[k];
        if( cid >= ing.symbols.size() )
        {
            continue;
        }
        const Symbol&      cs   = ing.symbols[cid];
        const std::string& csrc = contentOf( cs.fileId );
        if( cs.sigStartByte >= cs.sigEndByte || cs.sigEndByte > csrc.size() )
        {
            continue;
        }
        const std::string  sig  = cleanSig( csrc.data(), cs.sigStartByte, cs.sigEndByte, redact );
        if( sig.empty() )
        {
            continue;
        }
        char hb[ 32 ];  std::snprintf( hb, sizeof( hb ), "\" l=\"%u\">", cs.line );
        callsBody += "<c n=\"";  callsBody += escapeXml( cs.name, esc );  callsBody += hb;
        callsBody += escapeXml( sig, esc );  callsBody += "</c>";
        used += sig.size() + 24;
        ++shown;
        if( sink.recorded )
        {
            sink.recorded->push_back( EmittedBodyCall { cs.name, cs.line, sig } ); // §H5
        }
    }
    char callsHdr[ 64 ];
    if( static_cast<std::uint32_t>( shown ) < total )
    {
        std::snprintf( callsHdr, sizeof( callsHdr ), "<calls total=\"%u\" shown=\"%d\" capped=\"1\">", total, shown );
    }
    else
    {
        std::snprintf( callsHdr, sizeof( callsHdr ), "<calls total=\"%u\">", total );
    }
    out += callsHdr;
    out += callsBody;
    out += "</calls>";
}

// THE <bodies> DISCLOSURE (§B8.3). This was the one budgeted section element carrying NO attributes at all:
// "kept N of M" lived in the --pack-task header's comment prose while the JSON twin emitted
// bodies_total/bodies_kept, so the two dialects disclosed different amounts of one fact — and
// `truncvocabcheck`'s universal sweep could not even see the element, because every rule it applies is of the
// form "if shown= then …". It now carries the pageview.h rule-1/2/3 triple. `shown` is a RESULT of the budget
// walk rather than an input to it, so the open tag cannot be written until the walk has finished: the children
// are composed into a buffer and the tag is written in front of them. A second, non-emitting decision pass to
// pre-count `shown` was rejected — it would re-run redactInPlace over every body and double the redaction
// tally, which is §B10.2 recreated one file over.
//
// THE BUDGET WALK (§H5 sub-finding, RE-DIAGNOSED BY MEASUREMENT). The audit reported bodies_kept as
// non-monotonic in the budget and named the cause: "packBodies `break`s rather than skipping". It does not.
// The loops already skip-and-continue for a body that does not fit while budget REMAINS (the marker path
// below); the `break` fires only once `used` has reached the budget, when nothing further can fit anyway.
// Converting both breaks to skips and sweeping 8 tasks x 27 budgets (3000..16000 step 500) gives the
// IDENTICAL 5 descending steps at the IDENTICAL budgets — exactly count-neutral.
// CA4 verifier F-LOW-2: count-neutral is NOT marker-neutral, and the sentence above used to stop one word
// short. The two forms disagree on how many `<!-- body omitted (over budget): NAME -->` markers are printed
// for the SAME set of dropped bodies, because a `break` stops writing them while a skip keeps going:
// measured `--token-budget=7000` -> shown=2/6 with ZERO markers, `=8000` -> shown=2/6 with FOUR markers for
// the same four bodies. Nothing is hidden by it — the aggregate `capped="1"` plus shown=/total= carry the
// fact either way, and the JSON `bodies_omitted` key is built from the same set — but a reader diffing two
// budgets sees a marker count move without the body count moving, and is owed the reason here.
//
// The real cause is RANK PRIORITY, and it is not a defect: bodies fill top-rank-first, so a larger budget can
// newly admit a large high-rank body that then consumes the room several smaller low-rank ones had. MEASURED
// `--pack-task="redact secrets from emitted text"`: 5 bodies at --token-budget=6500, 2 at 7000, while the
// delivered bytes went UP (8 687 -> 11 461). Making the count monotone means filling smallest-first, i.e.
// handing an agent four small bodies it did not ask for instead of the one it did. Rank priority is the
// retrieval contract; the count is not a quality measure, and the --pack-task header now SAYS so rather than
// leaving a reader to infer a regression from a falling number.
//
// What the re-diagnosis DID fix: `budgetBytes - used` underflows a size_t whenever `used` has passed the
// budget (appendCdataSafe grows on a `]]>` split, and the callee block and notes are charged after the fit
// test), turning the fit test into "everything fits". The guard happens to mask it today, so the floored form
// is a latent trap defused, not an output change.
//
// --expand (L4 middle ground): emit the FULL definition source [sigStartByte, endByte) for each
// requested symbol — "give me this def's body, not the whole file" (Agentless rung-3 / Serena
// include_body). Grouped under <bodies>, CDATA-safe, budget-capped, self-describing (truncation
// marker). Reads each file once (nodes grouped by file). Emitted AFTER </r>.
// compress=true → strip comments and collapse blank runs (P2-B) before CDATA encoding.
// ranges: optional NodeId→LineRange map (octocode partial-fetch). A node absent from `ranges`, or
// present with hasRange=false, takes the ORIGINAL whole-body path byte-for-byte — no ranges map at
// all (nullptr, the default) is the pre-existing call signature, unchanged.
inline void packBodies( std::FILE* out, const IngestResult& ing, const std::vector<NodeId>& nodes,
                        std::size_t budgetBytes,
                        const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                        bool compress = false, RedactCounts* redact = nullptr,
                        const HashMap<NodeId, LineRange>* ranges = nullptr,
                        const notes::NoteIndex* noteIndex = nullptr,    // L3: field notes — surfaces <note> children on each
                                                                        //   <b> body (canonical-id target). nullptr ⇒ INERT (byte-identical).
                        EmittedBodies* outEmitted = nullptr )           // §H5: what this call actually emitted — see EmittedBodies.
                                                                        //   nullptr ⇒ not recorded (every XML-only caller).
{
    // budgetBytes == 0 ⇒ UNLIMITED (A3-F2): the MCP `exemplar` verb has no byte budget, and 0 must never
    // mean "cap at zero bytes" (the cap fired before the first body and emitted a bare <bodies></bodies>).
    // Matches writeRecall's "0 = no cap" convention; the CLI always passes a real budget (default 64 KB).
    if( budgetBytes == 0 )
    {
        budgetBytes = SIZE_MAX;
    }

    XmlWriter         w( out );
    std::vector<char> esc;
    std::size_t       used = 0;

    // file content cache: each file read once, reused for both the bodies and their callees' signatures.
    HashMap<std::uint32_t, std::string> contents;
    const auto contentOf = [ & ]( std::uint32_t fid ) -> const std::string&
    {
        const auto it = contents.find( fid );
        if( it != contents.end() )
        {
            return it->second;
        }
        std::string s;
        if( fid < ing.files.size() )
        {
            if( std::FILE* in = std::fopen( diskPath( ing, fid ).c_str(), "rb" ) )
            {
                char b[4096];
                std::size_t n;
                while( ( n = std::fread( b, 1, sizeof( b ), in ) ) > 0 )
                {
                    s.append( b, n );
                }
                std::fclose( in );
            }
        }
        return contents.emplace( fid, std::move( s ) ).first->second;
    };

    // group requested nodes by file so each file is read once; keep id order within a file
    HashMap<std::uint32_t, std::vector<NodeId>> byFile;
    std::vector<std::uint32_t>                             fileOrder;
    std::size_t                                            requestedCount = 0;
    for( NodeId id : nodes )
    {
        if( id >= ing.symbols.size() )
        {
            continue;
        }
        ++requestedCount;
        const std::uint32_t f = ing.symbols[id].fileId;
        if( byFile.find( f ) == byFile.end() )
        {
            fileOrder.push_back( f );
        }
        byFile[f].push_back( id );
    }
    if( outEmitted )
    {
        outEmitted->requested = requestedCount;
    }

    std::string children;         // see THE <bodies> DISCLOSURE in the header for why this is buffered, not streamed
    std::size_t shownCount = 0;   // counted at the emission, never by substring-matching `children`
    for( std::uint32_t f : fileOrder )
    {
        if( used >= budgetBytes )
        {
            break;
        }

        if( contentOf( f ).empty() )
        {
            continue; // graceful: file gone / empty
        }

        for( NodeId id : byFile[f] )
        {
            if( used >= budgetBytes )
            {
                break;
            }

            // re-fetch the content EVERY iteration: `contents` is a flat HashMap (values stored
            // contiguously), so the cross-file callee-signature contentOf() below can reallocate the
            // table and dangle any reference held across it — never cache `src` past an insert.
            const std::string& src = contentOf( f );
            const Symbol&      s = ing.symbols[id];
            const std::size_t  a = s.sigStartByte, b = s.endByte;
            if( a >= b || b > src.size() )
            {
                continue;
            }

            std::string body( src.data() + a, b - a );

            // octocode partial-fetch (--expand=SYM:START-END): slice to the requested 1-based lines,
            // relative to the def's own first line, BEFORE the budget/compress/redact pipeline below —
            // everything downstream (truncation, compress, redact, CDATA-escape) then operates on the
            // already-sliced text exactly as it would on a whole small body, so no other code path needs
            // to know a slice happened. A node absent from `ranges` (or hasRange=false) is untouched:
            // `body` is exactly what the pre-range code produced — the whole-body path is byte-identical.
            // §B14 — was `char partAttr[40]`, the third latent site: ` lines=""` is 9 literal bytes and
            // "lo-hi/total" is 3×10 digits + 2 separators = 32 at the u32 ceiling, so 41 B + NUL against a
            // 40-byte buffer. Unreachable (it needs a 10^9-line file) but off by exactly the margin the class
            // is about, so it is composed on std::string rather than left as an arithmetic claim to re-audit.
            std::string partAttr;
            std::string lineSpanValue;   // §H5: the same "lo-hi/total" the XML attribute carries, for the record
            if( ranges )
            {
                if( const auto it = ranges->find( id ); it != ranges->end() && it->second.hasRange )
                {
                    const SlicedBody sliced = sliceBodyLines( body, it->second.startLine, it->second.endLine );
                    body = sliced.text;
                    // lines="lo-hi/total" — an explicit marker so the agent knows this is a SLICE, not the
                    // whole def (octocode's ask: never let a partial fetch masquerade as the complete body).
                    lineSpanValue = std::to_string( sliced.loLine ) + "-" + std::to_string( sliced.hiLine ) + "/" + std::to_string( sliced.total );
                    partAttr = " lines=\"" + lineSpanValue + "\"";
                }
            }

            // the floored remaining budget — see THE BUDGET WALK in this function's header for why it is not
            // `budgetBytes - used`, and for the re-diagnosed non-monotonicity the walk is NOT the cause of.
            const std::size_t remainingBytes = used < budgetBytes ? budgetBytes - used : 0;
            bool              truncated      = false;
            if( body.size() > remainingBytes )                     // doesn't fit the remaining budget
            {
                if( used == 0 && body.size() > budgetBytes )       // a single def larger than the WHOLE budget → truncate it (UTF-8 safe)
                {
                    std::size_t cut = body.rfind( '\n', budgetBytes );
                    if( cut == std::string::npos )
                    {
                        cut = budgetBytes;
                    }
                    while( cut > 0 && ( static_cast<unsigned char>( body[cut] ) & 0xC0 ) == 0x80 )
                    {
                        --cut;
                    }
                    body.resize( cut );
                    truncated = true;
                }
                else                                                // never cut mid-def: skip whole, leave a visible marker
                {
                    // A4-F9: the name rides inside an XML COMMENT, where "--" is ill-formed (and "-->" would
                    // terminate it early). A `--`-bearing name (C++ operator--, a markdown "-- heading") would
                    // break the G4 xmllint gate. W3FIX M3: xmlCommentText above is that collapse plus the two
                    // scrubs a comment also needs (control bytes, invalid UTF-8) — a name is corpus-derived, so
                    // a mis-parse can hand this site any byte sequence at all. Byte-identical on clean names.
                    children += "<!-- body omitted (over budget): ";
                    children += escapeXml( xmlCommentText( s.name ), esc );
                    children += " -->";
                    noteOmittedBody( outEmitted, id );   // §H5: the JSON dialect names the same ones
                    continue;
                }
            }

            // --compress (P2-B): strip comments + collapse blank runs from the body text.
            // Applied AFTER truncation so the budget check above sees the un-compressed size
            // (conservative — compression only makes the output smaller, never larger).
            //
            // anti-growth guard (octocode's rule, Wave 4 #3): compressBody only ever REMOVES bytes
            // (comment spans, excess blank lines), so it cannot grow the payload — but the guard is kept
            // here anyway as the general contract's enforcement point: compare the reduced payload against
            // the pre-compress original (not the wrapper tags) and never emit a "reduction" that lost.
            // Deterministic pure size comparison; compression must never cost tokens.
            if( compress )
            {
                std::string compressed = compressBody( body );
                if( compressed.size() < body.size() )
                {
                    body = std::move( compressed );
                }
            }

            // Redact credential shapes from the def body (a full-body emission seam). After compress /
            // truncation so those size-based decisions see the un-redacted bytes; no-op under --no-redact.
            redactInPlace( body, redact );

            std::string safe;  safe.reserve( body.size() );        // split ]]>; scrub C0 controls (G4) + invalid UTF-8 (A4-F20)
            appendCdataSafe( body, safe );

            // §B12.7 / F-MED-1: appendCdataSafe is not an escape, it is a LOSSY SCRUB — C0 (bar \t\n\r) to a
            // space, invalid UTF-8 to '?'. `body` is what the JSON twin carries, `safe` is what this CDATA
            // carries, and until now nothing said when they differed. Decided from the bytes, not from a
            // predicate re-derivation, so the flag cannot disagree with the scrub that produced them.
            const bool bodyScrubbed = ( safe.size() != body.size() ) || xmlScrubIsLossy( body );

            char hdr[ 64 ];  std::snprintf( hdr, sizeof( hdr ), "<b t=\"%s\" l=\"%u\" p=\"", symTag( s.kind ), s.line );
            children += hdr;  children += escapeXml( ing.files[f], esc );
            children += "\" n=\"";  children += escapeXml( s.name, esc );  children += "\"";
            children += partAttr;                                 // octocode partial-fetch: lines="lo-hi/total" (empty on the whole-body path)
            if( bodyScrubbed )
            {
                children += " scrubbed=\"1\""; // absent = the CDATA is byte-equal to the JSON twin
            }
            children += "><![CDATA[";
            children += safe;
            if( truncated )
            {
                children += "\n<!-- truncated -->";
            }
            children += "]]>";
            used += safe.size();

            ++shownCount;

            // §H5: the record IS the emission — same id, same post-pipeline bytes, same truncation bit, and
            // (filled by emitCalleeCallsBlock below) the same callee rows this body actually showed.
            EmittedBody* record = nullptr;
            if( outEmitted )
            {
                outEmitted->kept.push_back( EmittedBody{ id, body, lineSpanValue, truncated, bodyScrubbed, {},
                                                         ( id + 1 < outOff.size() ) ? outOff[id + 1] - outOff[id] : 0u } );
                record = &outEmitted->kept.back();
            }

            // L4+: the 1-hop callee signatures — a body in isolation is the worst context unit (cAST);
            // its callees' shapes make it a self-contained, composable bundle. §P10.1: the disclosed
            // total=/shown=/capped= block — see emitCalleeCallsBlock above.
            emitCalleeCallsBlock( children, id, outOff, outTargets, ing, contentOf, esc, used, budgetBytes,
                                  CalleeCallsSink{ redact, record ? &record->calls : nullptr } );
            const std::string bodyNotes = renderNoteChildren( noteIndex, symbolNoteTarget( noteIndex, ing, s ), esc );   // L3/D5
            children += bodyNotes;
            used += bodyNotes.size();                                                                   // W3-N2: same charge-never-trim rule
            children += "</b>";
        }
    }

    // §B8.3 / pageview.h THE TRUNCATION VOCABULARY rules 1+2+3: shown= rows printed, total= rows requested,
    // capped= the bit that always rides with shown=. `total` counts the ids the CALLER handed in (invalid ids
    // excluded — they were never a request this function could answer), so capped="1" covers every reason a
    // requested body is absent: the byte budget, an unreadable span, a file that vanished.
    char open[ 96 ];
    std::snprintf( open, sizeof( open ), "<bodies shown=\"%zu\" total=\"%zu\" capped=\"%d\">",
                   shownCount, requestedCount, shownCount < requestedCount ? 1 : 0 );
    w.write( open );
    w.write( children );
    w.write( "</bodies>" );
    w.flush();
}

// ── M6 (density audit 2026-08-08): the WHOLE-FILE form a bare --expand can serve ─────────────────────
// When every requested symbol's own FILE is byte-cheaper than the default bundle (ranked map + <bodies>),
// the cheapest COMPLETE answer is the file itself — measured live at 5.65x bundle-over-file on a small
// file (--expand=pageRankDouble: 27,890 B bundle vs 4,936 B src/pagerank.cpp). This renders that form:
// one <src p= sym=> block per DISTINCT file of the requested nodes (first-appearance order — nodes is
// already deterministic), the file body CDATA-wrapped through the same redact + scrub pipeline
// packSource uses, sym= carrying every requested symbol's name:line anchor, and each symbol's field
// notes still surfaced (L3 — the notes must not vanish just because the serving form changed).
// D2 (audit regressions, 2026-08-08): body-shaping modifiers COMPOSE with this form instead of being
// silently dropped when the serving mode flips —
//   * compress=true strips comments through the SAME compressBody + anti-growth guard packBodies uses,
//     so a --compress caller gets a compressed file, not a silently-uncompressed one (compresscheck);
//   * each requested symbol whose canonical id ADDS an enclosing scope (the S6-C rule — canon != bare
//     name) gets an <s n= id= l=/> anchor row before the CDATA, so the canonical-id surface downstream
//     tooling reads off --expand output (usesselectorcheck resolves NoteIndex::empty through it) does
//     not vanish with the ranked map.
// rawBytes is the Σ of the SERVED body bytes — post-compress when compress is on, the raw on-disk
// bytes otherwise — the number the caller's reason= attribute discloses and compares, so the auto
// choice always weighs SHAPED candidate against SHAPED candidate. The rendered form differs from it
// only by the envelope, anchors and CDATA-safety expansion.
// complete=false (any file unreadable or empty) means this form is NOT a candidate: the caller serves
// the bundle instead — a degraded read must never masquerade as the complete answer.
struct WholeFileRender
{
    std::string xml;              // the <src ...>...</src> blocks, ready to splice inside <ctx>
    std::size_t rawBytes = 0;     // Σ raw file bytes of the distinct files (what reason= compares)
    bool        complete = false; // every file read whole; false => caller falls back to the bundle
};

inline WholeFileRender renderWholeFiles( const IngestResult& ing, const std::vector<NodeId>& nodes,
                                         RedactCounts* redact, const notes::NoteIndex* noteIndex,
                                         bool compress )
{
    WholeFileRender r;
    std::vector<std::uint32_t> fileOrder;
    for( NodeId id : nodes )
    {
        if( id >= ing.symbols.size() )
        {
            continue;
        }
        const std::uint32_t f = ing.symbols[id].fileId;
        if( std::find( fileOrder.begin(), fileOrder.end(), f ) == fileOrder.end() )
        {
            fileOrder.push_back( f );
        }
    }
    if( fileOrder.empty() )
    {
        return r;
    }

    std::vector<char> esc;
    for( std::uint32_t f : fileOrder )
    {
        std::FILE* in = std::fopen( diskPath( ing, f ).c_str(), "rb" );
        if( !in )
        {
            return WholeFileRender{};   // unreadable => not a candidate, never a partial "complete" answer
        }
        std::string body;
        char        buf[ 4096 ];
        std::size_t n = 0;
        while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
        {
            body.append( buf, n );
        }
        std::fclose( in );
        if( body.empty() )
        {
            return WholeFileRender{};   // vanished/empty since ingest => same fallback
        }

        // D2: --compress composes with whole-file serving — the same compressBody + anti-growth guard
        // packBodies applies to a bundle body (never grows, deterministic), applied BEFORE rawBytes is
        // counted so the caller's auto choice compares the compressed file against the compressed bundle.
        if( compress )
        {
            std::string compressed = compressBody( body );
            if( compressed.size() < body.size() )
            {
                body = std::move( compressed );
            }
        }
        r.rawBytes += body.size();

        // sym= anchors (name:line per requested node in this file, request order) + their field notes,
        // plus (D2) an <s n= id= l=/> row per symbol whose canonical id adds an enclosing scope — the
        // exact S6-C emit-only-when-disambiguating rule the map rows follow, so the canonical-id surface
        // survives the serving-mode flip at zero cost for scope-less symbols.
        std::string anchors;
        std::string anchorRows;
        std::string noteStr;
        for( NodeId id : nodes )
        {
            if( id >= ing.symbols.size() || ing.symbols[id].fileId != f )
            {
                continue;
            }
            const Symbol& s = ing.symbols[id];
            if( !anchors.empty() )
            {
                anchors += ',';
            }
            anchors += s.name;
            anchors += ':';
            anchors += std::to_string( s.line );
            const std::string canon = canonicalId( ing.files[f], s.scope, s.name );
            if( canon != s.name )
            {
                anchorRows += "<s n=\"";
                anchorRows += escapeXml( s.name, esc );
                anchorRows += "\" id=\"";
                anchorRows += escapeXml( canon, esc );
                anchorRows += "\" l=\"";
                anchorRows += std::to_string( s.line );
                anchorRows += "\"/>";
            }
            noteStr += renderNoteChildren( noteIndex, symbolNoteTarget( noteIndex, ing, s ), esc );
        }

        redactInPlace( body, redact );          // §B10.1: raw file text is the widest credential seam
        std::string safe;
        safe.reserve( body.size() );
        appendCdataSafe( body, safe );          // split ]]>, scrub C0 controls (G4) + invalid UTF-8

        r.xml += "<src p=\"";
        r.xml += escapeXml( ing.files[f], esc );
        r.xml += "\" sym=\"";
        r.xml += escapeXml( anchors, esc );
        r.xml += "\">";
        r.xml += anchorRows;
        r.xml += noteStr;
        r.xml += "<![CDATA[";
        r.xml += safe;
        r.xml += "]]></src>";
    }
    r.complete = true;
    return r;
}

// --expand est_tokens bugfix: estimate the token cost of the <bodies> block packBodies
// will emit for `nodes`, so serialize()'s header can report header+body (not map-only). Mirrors the
// packBodies byte accounting closely enough for an honest ±15% estimate: per node it reads the def span
// [sigStartByte,endByte), applies the same range slice + optional compress, and adds the 1-hop callee
// signature bytes, all converted to tokens at each symbol's own language B/tok rate (the same calibration
// table the map estimate uses). Deterministic (pure function of the corpus + request). Not the hot path
// (--expand payloads are small vs a warm map), so a second file read here is acceptable.
inline std::size_t estimateExpandBodyTokens( const IngestResult& ing, const std::vector<NodeId>& nodes,
                                             std::size_t budgetBytes,
                                             const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                                             bool compress = false,
                                             const HashMap<NodeId, LineRange>* ranges = nullptr )
{
    if( budgetBytes == 0 )
    {
        budgetBytes = SIZE_MAX;
    }

    // per-file content cache (each def's file read once), mirroring packBodies' contentOf.
    HashMap<std::uint32_t, std::string> contents;
    const auto contentOf = [ & ]( std::uint32_t fid ) -> const std::string&
    {
        const auto it = contents.find( fid );
        if( it != contents.end() )
        {
            return it->second;
        }
        std::string s;
        if( fid < ing.files.size() )
        {
            if( std::FILE* in = std::fopen( diskPath( ing, fid ).c_str(), "rb" ) )
            {
                char b[4096];
                std::size_t n;
                while( ( n = std::fread( b, 1, sizeof( b ), in ) ) > 0 )
                {
                    s.append( b, n );
                }
                std::fclose( in );
            }
        }
        return contents.emplace( fid, std::move( s ) ).first->second;
    };

    // <bodies>…</bodies> envelope + a small per-body markup allowance (<b t= l= p= n=>…</b>), at the
    // mid-band markup rate — informational, so a few bytes of drift between body variants is immaterial.
    double tokensF   = double( 17 ) / kBytesPerTokenDefault;   // "<bodies></bodies>"
    std::size_t used = 0;

    for( NodeId id : nodes )
    {
        if( used >= budgetBytes )
        {
            break;
        }
        if( id >= ing.symbols.size() )
        {
            continue;
        }
        const Symbol&      s   = ing.symbols[id];
        const std::string& src = contentOf( s.fileId );
        const std::size_t  a = s.sigStartByte, b = s.endByte;
        if( a >= b || b > src.size() )
        {
            continue;
        }

        std::string body( src.data() + a, b - a );
        if( ranges )
        {
            if( const auto it = ranges->find( id ); it != ranges->end() && it->second.hasRange )
            {
                body = sliceBodyLines( body, it->second.startLine, it->second.endLine ).text;
            }
        }
        if( compress )
        {
            std::string compressed = compressBody( body );
            if( compressed.size() < body.size() )
            {
                body = std::move( compressed );
            }
        }
        if( body.size() > budgetBytes - used )
        {
            body.resize( budgetBytes - used ); // budget cap (conservative)
        }
        used += body.size();

        // per-body markup (~40 B for the <b …> tag + CDATA wrapper + name/path) at markup rate; body TEXT at
        // the leaner code-body rate (whitespace/braces merge; measured ~3.8 B/tok, not the ~2.46 signature rate).
        tokensF += double( 40 + s.name.size() + ing.files[ s.fileId ].size() ) / kBytesPerTokenDefault;
        tokensF += double( body.size() ) / kBytesPerTokenBody;

        // 1-hop callee signatures packBodies appends (capped 16), estimated from their sig span bytes at
        // each callee's own language rate + ~24 B markup per <c …> tag — the same cap/markup packBodies uses.
        if( id + 1 < outOff.size() )
        {
            int shown = 0;
            for( std::uint32_t k = outOff[id]; k < outOff[id + 1] && shown < 16 && used < budgetBytes; ++k )
            {
                const NodeId cid = outTargets[k];
                if( cid >= ing.symbols.size() )
                {
                    continue;
                }
                const Symbol&      cs   = ing.symbols[cid];
                const std::string& csrc = contentOf( cs.fileId );
                if( cs.sigStartByte >= cs.sigEndByte || cs.sigEndByte > csrc.size() )
                {
                    continue;
                }
                const std::size_t sigBytes = cs.sigEndByte - cs.sigStartByte;
                tokensF += double( 24 + cs.name.size() ) / kBytesPerTokenDefault + double( sigBytes ) / bytesPerTokenFor( cs.lang );
                used += sigBytes + 24;
                ++shown;
            }
        }
    }
    return std::size_t( tokensF + 0.5 );
}

// --outline (L3 scoped snippet): the def's control-flow SHAPE — signature + top-level body
// statements + control headers (brace depth ≤ 1), with nested block bodies (depth ≥ 2) collapsed to
// "...". Between a signature (L1) and the full body (L4): you see the logic structure, not the leaf
// code. Depth-based (no AST needed); brace-in-string is a rare, accepted imprecision for a sketch.
// compress=true → strip comments and collapse blank runs (P2-B) before CDATA encoding.
// §B10.1: `redact` is REQUIRED — no default (see packSource). `compress` loses its default with it, because
// C++ defaults must be trailing; both call sites already spell both.
inline void packOutline( std::FILE* out, const IngestResult& ing, const std::vector<NodeId>& nodes, std::size_t budgetBytes, bool compress, RedactCounts* redact )
{
    XmlWriter         w( out );
    std::vector<char> esc;
    std::size_t       used = 0;

    HashMap<std::uint32_t, std::vector<NodeId>> byFile;
    std::vector<std::uint32_t>                  fileOrder;
    for( NodeId id : nodes )
    {
        if( id >= ing.symbols.size() )
        {
            continue;
        }
        const std::uint32_t f = ing.symbols[id].fileId;
        if( byFile.find( f ) == byFile.end() )
        {
            fileOrder.push_back( f );
        }
        byFile[f].push_back( id );
    }

    w.write( "<outline>" );
    for( std::uint32_t f : fileOrder )
    {
        if( used >= budgetBytes )
        {
            break;
        }
        std::FILE* in = std::fopen( diskPath( ing, std::uint32_t( f ) ).c_str(), "rb" );
        if( !in )
        {
            continue;
        }
        std::string src;  char buf[ 4096 ];  std::size_t n;
        while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
        {
            src.append( buf, n );
        }
        std::fclose( in );

        for( NodeId id : byFile[f] )
        {
            if( used >= budgetBytes )
            {
                break;
            }
            const Symbol&     s = ing.symbols[id];
            const std::size_t a = s.sigStartByte, b = s.endByte;
            if( a >= b || b > src.size() )
            {
                continue;
            }

            std::string sk;                                            // build the depth-collapsed skeleton
            int         depth     = 0;
            bool        collapsed = false;
            std::size_t i = a;
            while( i < b )
            {
                std::size_t eol = src.find( '\n', i );
                if( eol == std::string::npos || eol > b )
                {
                    eol = b;
                }
                const int startD = depth;
                for( std::size_t k = i; k < eol; ++k )
                {
                    const char c = src[k];
                    if( c == '{' ) { ++depth; }
                    else if( c == '}' )
                    {
                        --depth;
                    }
                }
                if( std::min( startD, depth ) <= 1 ) { sk.append( src, i, eol - i ); sk.push_back( '\n' ); collapsed = false; }
                else if( !collapsed ) { sk += "  ...\n"; collapsed = true; }
                i = ( eol < b ) ? eol + 1 : b;
            }
            if( sk.empty() )
            {
                continue;
            }

            // --compress (P2-B): strip comments + collapse blank runs from the skeleton text.
            if( compress )
            {
                sk = compressBody( sk );
            }
            if( sk.empty() )
            {
                continue;
            }

            // anti-growth guard (octocode's rule, Wave 4 #3): the whole POINT of an outline is fewer
            // bytes than the real definition — a "..."-collapse can occasionally cost MORE than the few
            // short lines it replaces (e.g. a 4-byte "  ;\n" collapsed to a 6-byte "  ...\n"). Compare
            // the PAYLOAD only (skeleton text vs the original [a,b) def span), never the wrapper tags —
            // if the reduced form is not strictly smaller, emit the original bytes instead. Deterministic,
            // pure size comparison: compression must never cost tokens.
            if( sk.size() >= ( b - a ) )
            {
                sk.assign( src, a, b - a );
            }

            // Redact credential shapes from the control-flow skeleton (a body-emission seam — the
            // skeleton keeps depth≤1 source lines verbatim, which can include a secret literal). --no-redact = no-op.
            redactInPlace( sk, redact );
            if( sk.empty() )
            {
                continue;
            }

            std::string safe;  safe.reserve( sk.size() );              // split ]]>; scrub C0 controls (G4) + invalid UTF-8 (A4-F20)
            appendCdataSafe( sk, safe );
            char hdr[ 64 ];  std::snprintf( hdr, sizeof( hdr ), "<o t=\"%s\" l=\"%u\" p=\"", symTag( s.kind ), s.line );
            w.write( hdr );  w.write( escapeXml( ing.files[f], esc ) );
            w.write( "\" n=\"" );  w.write( escapeXml( s.name, esc ) );  w.write( "\"><![CDATA[" );
            w.write( safe );  w.write( "]]></o>" );
            used += safe.size();
        }
    }
    w.write( "</outline>" );
    w.flush();
}

// S5-E HAS-A composition view: for a set of relevant symbols, emit the member-variable type edges
// (owner → member-type, rel="creates"|"uses") as a <compose> block. ONLY called from --for and
// --around (NOT from the default map). composeEdges are OUTSIDE the call graph (PageRank unchanged).
// relevantIds: the set of symbol ids in scope (from --for lens or --around ego-graph); we emit
// compose edges where the ownerSym is in the relevant set OR the typeSym is in the relevant set.
inline void packCompose( std::FILE* out, const IngestResult& ing,
                         const std::vector<ComposeEdge>& composeEdges,
                         const std::vector<NodeId>& relevantIds )
{
    if( composeEdges.empty() || relevantIds.empty() )
    {
        return;
    }

    // build a quick membership set for O(log N) lookup
    std::vector<NodeId> relevant( relevantIds );
    std::sort( relevant.begin(), relevant.end() );

    const auto inSet = [ &relevant ]( NodeId id ) noexcept -> bool
    {
        const auto it = std::lower_bound( relevant.begin(), relevant.end(), id );
        return it != relevant.end() && *it == id;
    };

    XmlWriter         w( out );
    std::vector<char> esc;
    bool              open = false;

    for( const ComposeEdge& ce : composeEdges )
    {
        if( !inSet( ce.ownerSym ) && !inSet( ce.typeSym ) )
        {
            continue;
        }
        if( ce.ownerSym >= ing.symbols.size() )
        {
            continue;
        }
        if( !open ) { w.write( "<compose>" );  open = true; }
        w.write( "<field name=\"" );  w.write( escapeXml( ce.fieldName, esc ) );
        w.write( "\" type=\"" );      w.write( escapeXml( ce.typeName, esc ) );
        w.write( "\" owner=\"" );     w.write( escapeXml( ce.ownerName, esc ) );
        w.write( "\" rel=\"" );       w.write( ce.rel );  w.write( "\"/>" );
    }
    if( open ) { w.write( "</compose>" );  w.flush(); }
}

// B6.3 HTTP-route cross-service view: for a set of relevant symbols, emit the synthesized route USE→DEF
// edges (client call → server handler) as a <routes> block. ONLY called from --for and --around (NOT the
// default map) — see model.h RouteEdge / graph.h buildGraph's B6.3 section for how these are matched.
// relevantIds: the set of symbol ids in scope; we emit a route where fromSym is in the set OR toSym is.
inline void packRoutes( std::FILE* out, const IngestResult& ing,
                        const std::vector<RouteEdge>& routeEdges,
                        const std::vector<NodeId>& relevantIds )
{
    if( routeEdges.empty() || relevantIds.empty() )
    {
        return;
    }

    std::vector<NodeId> relevant( relevantIds );
    std::sort( relevant.begin(), relevant.end() );

    const auto inSet = [ &relevant ]( NodeId id ) noexcept -> bool
    {
        const auto it = std::lower_bound( relevant.begin(), relevant.end(), id );
        return it != relevant.end() && *it == id;
    };

    XmlWriter         w( out );
    std::vector<char> esc;
    bool              open = false;

    for( const RouteEdge& re : routeEdges )
    {
        if( !inSet( re.fromSym ) && !inSet( re.toSym ) )
        {
            continue;
        }
        if( !open ) { w.write( "<routes>" );  open = true; }
        w.write( "<route method=\"" );  w.write( httpMethodTag( re.method ) );
        w.write( "\" path=\"" );        w.write( escapeXml( re.path, esc ) );
        w.write( "\" from=\"" );        w.write( escapeXml( re.fromName, esc ) );
        w.write( "\" to=\"" );          w.write( escapeXml( re.toName, esc ) );  w.write( "\"/>" );
    }
    if( open ) { w.write( "</routes>" );  w.flush(); }
}

// R8: --with-graph — a compact MERMAID flowchart of the bundle's anchor
// neighborhood, appended right before </ctx> when passed alongside --for/--pack-task. Reuses the SAME
// mermaid syntax the --mermaid module-dependency view emits (flowchart direction, quoted labels, `"`→`'`
// safety) instead of inventing a second emitter. Nodes = the top-N (N<=kWithGraphNodeCap) ranked symbols,
// labelled "name (file:line)"; edges = 1-hop call edges where BOTH ends are in that same top-N set (the
// neighborhood, not the whole graph). Deterministic ordering: rank order (rank desc, id asc — the same
// key every other pack* view sorts by) for nodes, then ascending target id (CSR order) for edges. Callers
// opt in explicitly (G5: additive) — a rendered diagram costs more tokens than the sigs it sits beside,
// worth it only when the reading agent renders mermaid natively.
inline constexpr std::size_t kWithGraphNodeCap = 8;

inline void packGraphBlock( std::FILE* out, const IngestResult& ing, const std::vector<float>& rank,
                            const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets )
{
    const std::size_t S = ing.symbols.size();
    if( S == 0 )
    {
        return;
    }

    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );
    const std::size_t keep = std::min( kWithGraphNodeCap, S );
    const std::vector<NodeId> nodes( order.begin(), order.begin() + keep );   // rank order, id 0..keep-1 index

    const auto indexOf = [ & ]( NodeId id ) -> std::size_t   // linear scan is fine at keep<=8
    {
        for( std::size_t j = 0; j < nodes.size(); ++j )
        {
            if( nodes[j] == id )
            {
                return j;
            }
        }
        return std::size_t( -1 );
    };
    const auto sanitize = []( std::string s ) -> std::string
    {
        for( char& ch : s )
        {
            if( ch == '"' )
            {
                ch = '\''; // mermaid label safety (same rule as --mermaid)
            }
        }
        return s;
    };

    std::string body = "flowchart LR\n";
    for( std::size_t i = 0; i < keep; ++i )
    {
        const Symbol& s = ing.symbols[ nodes[i] ];
        const std::string file = s.fileId < ing.files.size() ? ing.files[ s.fileId ] : std::string();
        // §B14 site 6 — composed on std::string. This one lives inside appendCdataSafe so it never breached
        // G4; a char[512] instead produced a WELL-FORMED document that says something FALSE: the truncation
        // deleted the closing `"]` AND the trailing '\n', gluing the next node declaration onto the cut label
        // (measured on base at a 600-byte path: 8 node lines collapsed into ONE 4097-byte line that also
        // swallowed the first edge). "sanitize" only swaps '"' for '\'' — a same-width scrub, so the cut still
        // landed inside markup. See the FIXED-BUFFER RULE above escapeXml.
        body += "n";  body += std::to_string( i );
        body += "[\"";
        body += sanitize( s.name );
        body += " (";  body += sanitize( file );
        body += ":";   body += std::to_string( s.line );
        body += ")\"]\n";
    }
    for( std::size_t i = 0; i < keep; ++i )
    {
        const NodeId u = nodes[i];
        if( outOff.empty() || u + 1 >= outOff.size() )
        {
            continue;
        }
        for( std::uint32_t k = outOff[u]; k < outOff[u + 1]; ++k )     // outTargets is deduped, ascending per source (CSR order)
        {
            const std::size_t j = indexOf( outTargets[k] );
            if( j == std::size_t( -1 ) )
            {
                continue; // 1-hop among the top-N only — not the whole graph
            }
            char eb[ 32 ];
            std::snprintf( eb, sizeof( eb ), "n%zu --> n%zu\n", i, j );
            body += eb;
        }
    }

    std::string safe;  safe.reserve( body.size() );
    appendCdataSafe( body, safe );   // splits any "]]>" so hostile names/paths can't break the CDATA (G4)

    XmlWriter w( out );
    w.write( "<graph fmt=\"mermaid\"><![CDATA[" );
    w.write( safe );
    w.write( "]]></graph>" );
    w.flush();
}

// The interface method-CONTRACT (<m>) is only emitted where the language captures interface members
// as real method symbols with a signature span the tags query pins correctly. Measured: C++/ObjC in-class
// methods are captured soundly (SymKind::Method, correct sigStartByte/sigEndByte). For TS/Java/Rust the
// interface's OWN members are NOT captured as method symbols the same way — scanning the iface span there
// grabs the interface's own declaration line and emits garbage (`<m>interface Animal</m>`). Declarative
// allow-list (not a scattered if): emit <m> only for langs where the surface is correct; suppress it (emit
// the <impl> list alone) elsewhere. A correct empty contract beats a broad wrong one.
inline bool legoMethodContractSound( Lang lang ) noexcept
{
    return lang == Lang::Cpp || lang == Lang::ObjC;
}

// §A9.4 — the suppression above, SAID OUT LOUD on the targeted verb. A Rust `trait Vehicle` with two
// methods emitted nothing while the C++ `Shape` beside it emitted its contract, so a caller who named ONE
// type read the silence as "this interface declares no methods" — a false zero. Suppression stays (a
// correct empty contract beats a broad wrong one); it now carries a tell. RANKED (--for) mode is left
// byte-identical: it emits a taste of many interfaces rather than an answer about one, so there is no
// single absence for a reader to misread.
//
// The returned literal is spliced INSIDE the <iface> attribute list, between the still-open n=/p= quote and
// the `" implementors="` tail — hence the leading quote and the missing trailing one.
inline const char* legoContractCaveat( bool isContractExtracted, bool isTargeted ) noexcept
{
    return ( isTargeted && !isContractExtracted ) ? "\" methods=\"0\" caveat=\"not-extracted-for-lang" : "";
}

// §P3 SCOPE (bundle embeddings only). packLego's ranked mode treats "has implementors" as "is an interface",
// so scoping THAT map is the filter: this returns a view of `implementors` in which every interface the task
// did not reach has an EMPTY implementor list — packLego then ranks and emits only what is left, and emits no
// <lego> element at all when nothing is (its own ifaces.empty() early return). Reached = the interface, or one
// of its implementors, is on the caller's RESOLVED SURFACE: the top-N ranked ids the bundle already selected,
// plus the files those ids live in (an interface declared in a file the task actually opened is on-topic even
// when the interface symbol itself missed the cut).
//
// Why it exists: ranking alone never REMOVED anything, so `--for="cache invalidation"` answered with ten
// unrelated test-fixture interfaces (Shape, Animal, IGreeter, …). Ten irrelevant interfaces are worse than
// none, and absence is the honest shape — there is nothing to disclose. The standalone --lego=TYPE verb is
// never scoped: the caller named the type.
inline std::vector<std::vector<NodeId>> legoImplementorsOnSurface( const IngestResult& ing,
                                                                   const std::vector<std::vector<NodeId>>& implementors,
                                                                   const std::vector<NodeId>& surfaceIds )
{
    std::vector<char>            onSurface( ing.symbols.size(), 0 );
    HashMap<std::uint32_t, char> surfaceFiles;
    for( NodeId s : surfaceIds )
    {
        if( s < onSurface.size() ) { onSurface[s] = 1;  surfaceFiles.emplace( ing.symbols[s].fileId, char( 1 ) ); }
    }

    const auto isOnSurface = [ & ]( NodeId n ) { return n < onSurface.size() && ( onSurface[n] || surfaceFiles.find( ing.symbols[n].fileId ) != surfaceFiles.end() ); };

    std::vector<std::vector<NodeId>> scoped( implementors.size() );          // empty lists = "not an interface" to packLego
    for( NodeId id = 0; id < implementors.size(); ++id )
    {
        if( implementors[id].empty() )
        {
            continue;
        }
        bool isReached = isOnSurface( id );
        for( NodeId im : implementors[id] )
        {
            isReached = isReached || isOnSurface( im );
        }
        if( isReached )
        {
            scoped[id] = implementors[id];
        }
    }
    return scoped;
}

// §P3 follow-through, exposed by §P4's tier down-weight: <sigs> is budget-TRIMMED after the lego scope was
// computed from the cap-N lens surface, so a lego row could carry a p= the rendered sigs no longer shows —
// an identity the reader cannot tie back to the bundle's own surface (legobundlecheck rule 2; latent before
// §P4 because the fixture files that host most interfaces also used to dominate the sigs head). Narrow
// `legoScoped` to files literally present in the RENDERED sigs (its `<f p="…"` rows, compared in escaped
// form exactly as serialized — the same naive scan the gate applies, so the two always agree): an interface
// whose own file was trimmed is dropped (packLego's name-dedup then falls to the next-ranked same-named
// interface, if any survives), and an implementor row in a trimmed file leaves its list. Returns true when
// anything narrowed — the caller re-renders the lego block, a byte-SUBSET of what the sigs budget already
// accounted for, so the bundle can only shrink.
inline bool narrowLegoToRenderedSigs( const IngestResult& ing, std::vector<std::vector<NodeId>>& legoScoped,
                                      std::string_view sigsRendered )
{
    HashMap<std::string, char> renderedFilePaths;
    for( std::size_t at = sigsRendered.find( "<f p=\"" ); at != std::string_view::npos; at = sigsRendered.find( "<f p=\"", at + 6 ) )
    {
        const std::size_t open  = at + 6;
        const std::size_t close = sigsRendered.find( '"', open );
        if( close == std::string_view::npos )
        {
            break; // torn attribute at end-of-buffer → stop scanning
        }
        renderedFilePaths.emplace( std::string( sigsRendered.substr( open, close - open ) ), char( 1 ) );
        at = close;
    }

    // per-file verdict memo: escape each candidate file once, not once per row
    std::vector<signed char> fileVerdict( ing.files.size(), -1 );        // -1 unknown, 0 trimmed, 1 rendered
    std::vector<char>        esc;
    const auto isRenderedFile = [ & ]( std::uint32_t f ) -> bool
    {
        if( f >= ing.files.size() )
        {
            return false;
        }
        if( fileVerdict[f] < 0 )
        {
            const std::string_view escaped = escapeXml( ing.files[f], esc );
            fileVerdict[f] = renderedFilePaths.find( std::string( escaped ) ) != renderedFilePaths.end() ? 1 : 0;
        }
        return fileVerdict[f] == 1;
    };

    bool narrowed = false;
    for( NodeId id = 0; id < legoScoped.size(); ++id )
    {
        if( legoScoped[id].empty() )
        {
            continue;
        }
        if( !isRenderedFile( ing.symbols[id].fileId ) ) { legoScoped[id].clear();  narrowed = true;  continue; }

        std::vector<NodeId> kept;
        kept.reserve( legoScoped[id].size() );
        for( NodeId im : legoScoped[id] )
        {
            if( im < ing.symbols.size() && isRenderedFile( ing.symbols[im].fileId ) )
            {
                kept.push_back( im );
            }
            else
            {
                narrowed = true;
            }
        }
        if( kept.size() != legoScoped[id].size() )
        {
            legoScoped[id] = std::move( kept ); // empty ⇒ packLego drops the iface
        }
    }
    return narrowed;
}

// the Lego view: for the top relevant interfaces/base-classes (those with implementors), emit the
// concrete implementations — the socket → interchangeable bricks. Descriptive (no pattern labels);
// steers an agent to snap a new brick into the socket instead of reimplementing. Emitted in --for.
//
// Two modes, one schema (<lego><iface><m><impl>): the RANKED set (--for) caps interfaces at topN, impls
// at 16, and omits paths for brevity; the TARGETED variant (--lego=TYPE) passes focusId != kNoNode to emit
// exactly that ONE interface, uncapped impls, the full contract, and withPaths=true so p= file paths ride
// along on <iface>/<impl> (the agent can open them). Reuses the same writer + contract logic for both.
//
// §P3: the bundle embeddings pass withPaths=true as well — the bundle form of a verb must never carry less
// identity than its standalone form, and without p= this repo's two different `Circle`s render as one
// duplicated row. They also pass an implementors map pre-scoped to the task (legoImplementorsOnSurface).
inline void packLego( std::FILE* out, const IngestResult& ing, const std::vector<std::vector<NodeId>>& implementors,
                      const std::vector<float>& rank, int topN,
                      RedactCounts* redact,                       // §B0/W3-N1: REQUIRED — the <m> contract sigs are emitted text
                      const std::vector<char>* impure = nullptr,
                      NodeId focusId = kNoNode, bool withPaths = false )
{
    std::vector<NodeId> ifaces;
    if( focusId != kNoNode )
    {
        // targeted: ALWAYS emit the requested interface, even with ZERO implementors (D8 fix). The caller
        // already resolved a real symbol (resolveFocus succeeded) — a bare `<lego></lego>` here is
        // indistinguishable from the "type not found" case, so emit the contract with implementors="0"
        // instead of silently nothing. The RANKED (--for) path below keeps the has-implementors gate: it
        // exists to select which interfaces are worth surfacing, not to detect "not found".
        ifaces.push_back( focusId );
    }
    else
    {
        for( NodeId i = 0; i < ing.symbols.size(); ++i )
        {
            if( i < implementors.size() && !implementors[i].empty() )
            {
                ifaces.push_back( i );
            }
        }
    }
    if( ifaces.empty() )
    {
        return;
    }

    sortutil::radixSortByScoreDescId( ifaces, rank );

    // dedup same-named interfaces (fwd-decl + definition collisions), keeping the highest-ranked. In the
    // targeted (focusId) path there is exactly one entry, so the dedup is a no-op that keeps it.
    HashMap<std::string, char> seenName;
    std::vector<NodeId>        uniq;
    for( NodeId id : ifaces )
    {
        if( seenName.emplace( ing.symbols[id].name, char( 1 ) ).second )
        {
            uniq.push_back( id );
        }
    }
    ifaces.swap( uniq );

    const std::size_t keep = std::min<std::size_t>( topN > 0 ? std::size_t( topN ) : ifaces.size(), ifaces.size() );

    XmlWriter         w( out );
    std::vector<char> esc;
    std::string       src;
    std::uint32_t     loadedFile = 0xFFFFFFFFu;
    w.write( "<lego>" );
    for( std::size_t k = 0; k < keep; ++k )
    {
        const NodeId  id   = ifaces[k];
        const Symbol& isym = ing.symbols[id];

        const bool  isContractExtracted = legoMethodContractSound( isym.lang );
        const char* caveatAttr          = legoContractCaveat( isContractExtracted, focusId != kNoNode );   // §A9.4
        char hdr[ 48 ];  std::snprintf( hdr, sizeof( hdr ), "\" implementors=\"%zu\">", implementors[id].size() );
        w.write( "<iface n=\"" );  w.write( escapeXml( isym.name, esc ) );
        if( withPaths ) { w.write( "\" p=\"" );  w.write( escapeXml( ing.files[ isym.fileId ], esc ) ); }
        w.write( caveatAttr );
        w.write( hdr );

        // contract: the interface's own method signatures (what a brick must implement) — only where the
        // language captures them soundly (see legoMethodContractSound). Read the iface's file once; emit
        // up to a few method sigs whose span sits inside the class span (or ALL of them for --lego=TYPE).
        if( isContractExtracted )
        {
            if( isym.fileId != loadedFile )
            {
                src.clear();  loadedFile = isym.fileId;
                std::FILE* in = std::fopen( diskPath( ing, isym.fileId ).c_str(), "rb" );
                if( in )
                {
                    char buf[4096];
                    std::size_t n;
                    while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
                    {
                        src.append( buf, n );
                    }
                    std::fclose( in );
                }
            }
            const int maxMethods = ( focusId != kNoNode ) ? 64 : 6;   // targeted verb = full contract; --for = a taste
            int shown = 0;
            for( const Symbol& m : ing.symbols )
            {
                if( m.kind != SymKind::Method || m.fileId != isym.fileId || m.id == id )
                {
                    continue;
                }
                if( m.sigStartByte < isym.sigStartByte || m.sigStartByte >= isym.endByte )
                {
                    continue; // inside the class span
                }
                // FIX #2 (nested-class over-list): span-containment alone lists a method of a class NESTED
                // inside the iface (that method's span sits within the iface's span too). Require the method's
                // OWN nearest class-like scope to BE the iface — Symbol::scope carries exactly that (the nearest
                // enclosing class/struct name; enclosingScopeOf in ingest). scope==name ⇒ the iface owns it;
                // Outer::Nested::nestedMethod (scope "Nested") is correctly excluded from Outer's contract.
                if( m.scope != isym.name )
                {
                    continue;
                }
                if( m.sigEndByte <= m.sigStartByte || m.sigEndByte > src.size() )
                {
                    continue;
                }
                if( ++shown > maxMethods ) { w.write( "<!-- +more methods -->" ); break; }
                const std::string sig = cleanSig( src.data(), m.sigStartByte, m.sigEndByte, redact );
                if( !sig.empty() )
                {
                    const bool mp = pureFromSig( sig, m.lang ) && !( impure && m.id < impure->size() && (*impure)[m.id] );
                    w.write( mp ? "<m pure=\"1\">" : "<m>" );  w.write( escapeXml( sig, esc ) );  w.write( "</m>" );
                }
            }
        }

        const std::vector<NodeId>& impls = implementors[id];
        const std::size_t          cap   = ( focusId != kNoNode ) ? impls.size()               // targeted: uncapped
                                                                  : ( impls.size() < 16 ? impls.size() : 16 );
        for( std::size_t j = 0; j < cap; ++j )
        {
            const Symbol& im = ing.symbols[ impls[j] ];
            w.write( "<impl n=\"" );  w.write( escapeXml( im.name, esc ) );
            if( withPaths ) { w.write( "\" p=\"" );  w.write( escapeXml( ing.files[ im.fileId ], esc ) ); }
            w.write( "\"/>" );
        }
        if( impls.size() > cap )
        {
            w.write( "<!-- +more -->" );
        }
        w.write( "</iface>" );
    }
    w.write( "</lego>" );
    w.flush();
}

// --deps: the file→file physical dependency view. Files ranked by include count (heaviest first =
// the "pulls in 100 headers to do something simple" detector); each lists its #include/import
// targets. Descriptive — names the number so the agent can choose a lighter path.
inline void packDeps( std::FILE* out, const IngestResult& ing, int topN,
                      const std::vector<std::vector<std::uint32_t>>& cycles,
                      const std::vector<std::uint32_t>& transitive, const std::vector<std::uint32_t>& afferent,
                      const std::vector<std::vector<std::uint32_t>>& adj,
                      std::uint64_t ccd, double acd, double nccd,
                      // T2: pagination of the per-file dependency LIST (the high-cardinality tail). limit<=0 =
                      // unbounded (the historic topN cap still applies); >0 overrides topN. offset skips the first
                      // M files of the sorted order. The health/godfiles/stabledeps/cycles PREAMBLE is unpaginated
                      // (it's a small fixed summary). Default args keep every existing caller byte-identical.
                      int pageLimit = 0, int pageOffset = 0 )
{
    const std::size_t F = ing.files.size();
    // §P9.4: dep_files= denominator (see graph.h::restrictDependencyHealth) — derived from `ing`, already a param.
    const auto        depCapableMask = dependencyCapableMask( ing );
    const std::size_t depFiles       = std::size_t( std::count( depCapableMask.begin(), depCapableMask.end(), char( 1 ) ) );
    std::vector<std::vector<std::uint32_t>> byFile( F );   // file → indices into ing.includes
    for( std::uint32_t i = 0; i < ing.includes.size(); ++i )
    {
        if( ing.includes[i].fileId < F )
        {
            byFile[ing.includes[i].fileId].push_back( i );
        }
    }

    std::vector<std::uint32_t> order;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( !byFile[f].empty() )
        {
            order.push_back( f );
        }
    }
    const auto trans = [ & ]( std::uint32_t f ) { return f < transitive.size() ? transitive[f] : std::uint32_t( byFile[f].size() ); };
    std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b )   // heaviest TRANSITIVE cone first
    { return trans( a ) != trans( b ) ? trans( a ) > trans( b ) : a < b; } );
    // T2 + §P8 G1: window the sorted per-file list. --limit overrides the historic topN cap; --offset skips
    // files; both default to the pre-T2 behavior (offset 0, cap = topN). This block used to hand-roll its own
    // ` offset= limit=` pair — the SECOND paging vocabulary main.cpp's pageAttr() also spoke, and the reason
    // a loop over --deps could cut rows correctly and still never terminate (no total=, no has_more=). It
    // uses pageview's window + disclosure now, like every other paging verb.
    const int         depLimit = rw::effectiveRowCap( pageLimit, topN > 0 ? topN : int( order.size() ) );
    const rw::PageWindow depPage = rw::pageWindow( order.size(), depLimit, pageOffset );
    const std::size_t begin    = depPage.begin;
    const std::size_t end      = depPage.end;

    XmlWriter         w( out );
    std::vector<char> esc;
    // §A10.11: three files=-family counts, one legend (the DEPTH-collision --owners already discloses for
    // its own files=, same idea here across an element and its child instead of a fold).
    w.write( "<!-- ripwire deps: file-to-file #include/import view, heaviest transitive cone first. files= (root) = files with "
             "at least one dependency edge (this listing's own denominator); health files= = the whole indexed corpus; "
             "health dep_files= = the dependency-CAPABLE subset of it (the ccd/acd/nccd denominator). "
             "raise the default cap with limit=N (offset=M pages). -->" );

    // discloseCap=TRUE, and this is the one un-paginated byte-shape change here: --deps caps the listing at
    // --pack-top-n (default 40) while files= counted every file with an include — 40 rows under files="179"
    // with nothing saying so is bug 2 verbatim (src/pageview.h, THE TRUNCATION VOCABULARY, rules 1-3). The
    // paging half still appears only when --limit/--offset is active.
    {
        char db[ 64 + rw::kPageDisclosureCap ], pd[ rw::kPageDisclosureCap ];
        std::snprintf( db, sizeof( db ), "<deps files=\"%zu\"%s>", order.size(),
                       rw::pageDisclosure( pd, sizeof( pd ), end - begin, order.size(), end, pageLimit, pageOffset, true ) );
        w.write( db );
    }

    // whole-codebase dependency health (Lakos): NCCD<1 horizontal/flat/good, >1 vertical, >2 tangled.
    // §P9.4: files=corpus size, dep_files=the ccd/acd/nccd/shape denominator (dependency-capable only).
    char hb[ 176 ];
    std::snprintf( hb, sizeof( hb ), "<health files=\"%zu\" dep_files=\"%zu\" ccd=\"%llu\" acd=\"%.1f\" nccd=\"%.2f\" shape=\"%s\"/>",
                   ing.files.size(), depFiles, static_cast<unsigned long long>( ccd ), acd, nccd,
                   nccd < 1.0 ? "horizontal" : ( nccd > 2.0 ? "tangled" : "vertical" ) );
    w.write( hb );

    // most depended-ON (afferent coupling Ca) = highest blast radius: changing these recompiles the most.
    // The complement of the transitive-cone ranking below (efferent, "pulls in 100 headers").
    {
        std::vector<std::uint32_t> byAff;
        for( std::uint32_t f = 0; f < F; ++f )
        {
            if( f < afferent.size() && afferent[f] > 0 )
            {
                byAff.push_back( f );
            }
        }
        std::sort( byAff.begin(), byAff.end(), [ & ]( std::uint32_t a, std::uint32_t b )
                   { return afferent[a] != afferent[b] ? afferent[a] > afferent[b] : ing.files[a] < ing.files[b]; } );
        const std::size_t capG = byAff.size() < 12 ? byAff.size() : 12;
        if( capG )
        {
            // §P9 N6: this listing used to emit exactly 12 rows with no total/cap disclosure while
            // --report's own god-files section (main.cpp) says "showing N of M" for the SAME population —
            // src/pageview.h, THE TRUNCATION VOCABULARY, rules 1-3, applied here too.
            char gfb[ 64 ];
            std::snprintf( gfb, sizeof( gfb ), "<godfiles total=\"%zu\" shown=\"%zu\" capped=\"%d\">",
                           byAff.size(), capG, capG < byAff.size() ? 1 : 0 );
            w.write( gfb );   // ranked by afferent = # files that #include this one
            for( std::size_t i = 0; i < capG; ++i )
            {
                char gb[ 48 ];  std::snprintf( gb, sizeof( gb ), "\" afferent=\"%u\"/>", afferent[ byAff[i] ] );
                w.write( "<f p=\"" );  w.write( escapeXml( ing.files[ byAff[i] ], esc ) );  w.write( gb );
            }
            w.write( "</godfiles>" );
        }
    }

    // Stable-Dependencies Principle (Martin): instability I = Ce/(Ca+Ce) must only DECREASE along an edge.
    // Ce = efferent (# files this one includes), Ca = afferent. An edge f→g with I(f) < I(g) means you
    // depend on something MORE volatile than yourself — flag the worst (ranked by the instability gap).
    {
        const auto instab = [ & ]( std::uint32_t f ) -> double
        {
            const double ce = f < adj.size() ? double( adj[f].size() ) : 0.0;
            const double ca = f < afferent.size() ? double( afferent[f] ) : 0.0;
            return ( ca + ce ) > 0.0 ? ce / ( ca + ce ) : 0.0;
        };
        struct SV { std::uint32_t from, to; double gap; };
        std::vector<SV> sv;
        for( std::uint32_t f = 0; f < adj.size(); ++f )
        {
            for( std::uint32_t g : adj[f] )
            {
                if( const double gap = instab( g ) - instab( f ); gap > 0.05 )
                {
                    sv.push_back( { f, g, gap } );
                }
            }
        }
        std::sort( sv.begin(), sv.end(), [ & ]( const SV& a, const SV& b )
                   { return a.gap != b.gap ? a.gap > b.gap
                            : ( ing.files[a.from] != ing.files[b.from] ? ing.files[a.from] < ing.files[b.from] : ing.files[a.to] < ing.files[b.to] ); } );
        const std::size_t capS = sv.size() < 12 ? sv.size() : 12;
        if( capS )
        {
            char sh[ 56 ];  std::snprintf( sh, sizeof( sh ), "<stabledeps violations=\"%zu\">", sv.size() );
            w.write( sh );
            for( std::size_t i = 0; i < capS; ++i )
            {
                char vb[ 32 ];  std::snprintf( vb, sizeof( vb ), "\" gap=\"%.2f\"/>", sv[i].gap );
                w.write( "<v from=\"" );  w.write( escapeXml( ing.files[ sv[i].from ], esc ) );
                w.write( "\" to=\"" );    w.write( escapeXml( ing.files[ sv[i].to ], esc ) );  w.write( vb );
            }
            w.write( "</stabledeps>" );
        }
    }

    if( !cycles.empty() )   // Lakos's cardinal sin: cyclic physical dependencies (must build/test as one unit)
    {
        w.write( "<cycles>" );
        const std::size_t capC = cycles.size() < 20 ? cycles.size() : 20;
        for( std::size_t c = 0; c < capC; ++c )
        {
            char cb[ 56 ];   // cost = k² = this cycle's contribution to CCD (Lakos: a k-cycle costs k²)
            std::snprintf( cb, sizeof( cb ), "<cycle size=\"%zu\" cost=\"%zu\"", cycles[c].size(), cycles[c].size() * cycles[c].size() );
            w.write( cb );

            // weakest-link cut suggestion: among the cycle's INTERNAL edges (both endpoints members of
            // this SCC), pick the one with the fewest crossings — weight = how many times src includes
            // dst (adj is un-deduped: a repeated #include pushes a duplicate entry, so occurrence count
            // is an honest, already-available proxy for "how load-bearing is this one dependency"). Any
            // single edge removed breaks a strongly-connected component's cyclicality along that walk, so
            // the min-weight edge is the cheapest cut. Ties broken lexicographically by (srcPath,dstPath)
            // for determinism (adj traversal order is file-id order, not necessarily path order).
            {
                HashMap<std::uint64_t, std::uint32_t> weight;                 // (srcIdx<<32|dstIdx) → occurrence count
                std::vector<std::uint32_t>            memberOf( cycles[c].begin(), cycles[c].end() );
                std::sort( memberOf.begin(), memberOf.end() );
                const auto isMember = [ & ]( std::uint32_t f )
                { return std::binary_search( memberOf.begin(), memberOf.end(), f ); };
                for( std::uint32_t src : cycles[c] )
                {
                    if( src >= adj.size() )
                    {
                        continue;
                    }
                    for( std::uint32_t dst : adj[src] )
                    {
                        if( dst != src && isMember( dst ) )
                        {
                            ++weight[ ( std::uint64_t( src ) << 32 ) | dst ];
                        }
                    }
                }
                bool haveCut = false;  std::uint32_t bestSrc = 0, bestDst = 0, bestW = 0;
                for( const auto& [ key, w_ ] : weight )
                {
                    const std::uint32_t s = std::uint32_t( key >> 32 ), d = std::uint32_t( key );
                    const bool better = !haveCut || w_ < bestW
                        || ( w_ == bestW && ( ing.files[s] != ing.files[bestSrc] ? ing.files[s] < ing.files[bestSrc]
                                                                                  : ing.files[d] < ing.files[bestDst] ) );
                    if( better ) { haveCut = true;  bestSrc = s;  bestDst = d;  bestW = w_; }
                }
                if( haveCut )   // degrade path: an SCC always has >=1 internal edge, but never assert it — just skip the attr
                {
                    w.write( " cut=\"" );  w.write( escapeXml( ing.files[bestSrc], esc ) );
                    w.write( " -&gt; " );  w.write( escapeXml( ing.files[bestDst], esc ) );
                    // §B14 — was `char rb[24]`, correct by EXACTLY one byte (`" cutrefs=""` is 12 literal bytes
                    // + 10 digits at UINT32_MAX = 22, +NUL = 23 ≤ 24). A one-byte margin on a buffer nobody
                    // re-derives is the class's own precondition, so it is composed instead.
                    w.write( "\" cutrefs=\"" );  w.write( std::to_string( bestW ) );  w.write( "\"" );
                }
            }
            w.write( ">" );

            const std::size_t capN = cycles[c].size() < 12 ? cycles[c].size() : 12;
            for( std::size_t j = 0; j < capN; ++j )
            { w.write( "<f p=\"" );  w.write( escapeXml( ing.files[ cycles[c][j] ], esc ) );  w.write( "\"/>" ); }
            w.write( "</cycle>" );
        }
        w.write( "</cycles>" );
    }

    for( std::size_t k = begin; k < end; ++k )
    {
        const std::uint32_t f = order[k];
        // §P9.2: Ce here MUST be the same project-only resolved graph (adj) the <stabledeps> violation
        // scan above uses (its own `instab` lambda, line ~2405) — not byFile[f].size(), which counts every
        // #include STATEMENT textually found (system/third-party headers included). Martin's I is defined
        // over component (project) dependencies; using the raw statement count here produced a SECOND,
        // different number under the same `instab=` name, so recomputing a printed <stabledeps gap=> from
        // the printed <f instab=> failed (0.52ish claimed vs 0.25ish from project-only Ce). `includes=`
        // below stays the raw statement count on purpose — that is a corpus fact, not an instability input.
        const double ce_ = f < adj.size() ? double( adj[f].size() ) : 0.0, ca_ = f < afferent.size() ? double( afferent[f] ) : 0.0;
        const double inst = ( ce_ + ca_ ) > 0.0 ? ce_ / ( ce_ + ca_ ) : 0.0;   // instability I = Ce/(Ca+Ce), project-only
        char hdr[ 112 ];  std::snprintf( hdr, sizeof( hdr ), "\" includes=\"%zu\" afferent=\"%u\" instab=\"%.2f\" transitive=\"%u\">",
                                        byFile[f].size(), f < afferent.size() ? afferent[f] : 0u, inst, trans( f ) );
        w.write( "<f p=\"" );  w.write( escapeXml( ing.files[f], esc ) );  w.write( hdr );
        const std::size_t cap = byFile[f].size() < 40 ? byFile[f].size() : 40;
        for( std::size_t j = 0; j < cap; ++j )
        { w.write( "<inc t=\"" );  w.write( escapeXml( ing.includes[ byFile[f][j] ].target, esc ) );  w.write( "\"/>" ); }
        if( byFile[f].size() > cap )
        {
            w.write( "<!-- +more -->" );
        }
        w.write( "</f>" );
    }
    w.write( "</deps>" );
    w.flush();
}

// ── L2: --json output mode ──────────────────────────────────────────────────────────────────────────
// A sibling JSON emitter for the CORE/CI verbs (default map, --for, --pack-task, --callers/--callees/
// --impact, --quality-delta, --test-gate) — NOT a string-replace over the XML. Keys mirror the XML attr
// names 1:1 so the two docs (README/--help) transfer without a second vocabulary. Determinism contract
// is identical to the XML: stable key EMISSION order (== the XML attr order), the same float-formatting
// path (bytesPerTokenFor / "%.4f" / estimateTokens — never a second counter), 2-run byte-diff clean.
// Escaping reuses the ONE canonical JSON core (jsonesc.h) at the same posture as mcp.h's stdio JSON-RPC
// output (escapeMcp): no <>& hardening (this is a CLI stdout stream, never re-embedded in HTML/markup),
// UTF-8-validated with raw U+FFFD bytes on an invalid sequence — see jsonesc.h's posture rationale.
//
// Scope note (documented, not a silent gap): the --for/--pack-task JSON ranking section applies the
// SAME rank-tier doc/sig trimming as the XML (kForDocFullRankCount/kForDocExcerptRankCount/kForTailSigBytes)
// but does NOT run the XML's H1 global-budget LADDER (serialize.h kForPayloadBudgetBytes) — that ladder
// exists to fit an XML-byte budget and re-deriving it against a second (JSON) byte model would be a
// second source of truth for the same decision. In the ordinary case (result fits under budget without
// the ladder engaging) the two are byte-for-byte the same SET of entries; only a bundle so large the XML
// ladder had to trim further can diverge, and only in how AGGRESSIVELY the tail is cut, never in what the
// top ranks show. --pack-task's callers/notes/tests sections reuse the XML path's OWN kept-count (the
// packTaskListSection budget decision) so the two outputs report the same truncation, just re-shaped.

// Reused JSON writer: XmlWriter is a generic 64 KB streaming byte buffer (no XML-specific behaviour
// beyond flush-on-cap) — safe to reuse verbatim for a JSON stream.
using JsonWriter = XmlWriter;

// Escape `s` into `scratch` (jsonesc.h's canonical core, mcp posture) and write it as a quoted JSON
// string literal, INCLUDING the surrounding quotes. `scratch` is caller-owned/reused (same pattern as
// escapeXml's `esc` scratch vector) so a hot loop over many symbols allocates once, not per string.
inline void writeJsonStr( JsonWriter& w, std::string_view s, std::string& scratch )
{
    scratch.clear();
    jsonesc::escapeInto( s, scratch, /*escapeAngleAmp=*/false, /*validateUtf8=*/true, /*replacementAsTextEscape=*/false );
    w.write( "\"" );
    w.write( scratch );
    w.write( "\"" );
}

// Same escape, allocating — for the small flat-list verbs (--callers/--callees/--impact/--quality-delta/
// --test-gate) that already build their rows with std::printf rather than an XmlWriter; returns the
// escaped text WITHOUT the surrounding quotes (call sites printf `"%s"` around it, mirroring how those
// verbs already call ex()/escapeXml today). A --quality-delta pass flagged the hand-rolled body this used
// to have as a clone of jsonesc::escapeMcp (same core, same flags — it IS that posture); delegates now
// instead of carrying a second copy.
inline std::string jsonStr( std::string_view s )
{
    return jsonesc::escapeMcp( s );
}

// The `--metrics` run on one JSON map row (loc/params/nest/cbo/lcom4/amp/tested/in/out/cx/ccx/role). Every
// member is absent-unless-measured — an omitted key means "not measured", NEVER a fabricated 0 that would
// read as "nobody calls this". Its own function so serializeJson's row loop stays a list of facts rather
// than a nest of optional-metric branches.
struct JsonQMetrics
{
    const Symbol&                     sym;
    NodeId                            id;
    std::uint32_t                     outDegree;
    const std::vector<std::uint32_t>* fanIn;
    const std::vector<std::uint32_t>* cbo;
    const std::vector<std::uint8_t>*  tested;
    const std::vector<std::uint32_t>* lcom4;
    const std::vector<std::uint32_t>* amp;
};

inline void writeJsonQMetrics( JsonWriter& w, const JsonQMetrics& q )
{
    const Symbol& s = q.sym;
    char          num[ 96 ];

    if( s.loc > 0 ) { std::snprintf( num, sizeof( num ), ",\"loc\":%u", s.loc );  w.write( num ); }
    if( s.kind == SymKind::Function || s.kind == SymKind::Method )
    {
        std::snprintf( num, sizeof( num ), ",\"params\":%u,\"nest\":%u", unsigned( s.params ), unsigned( s.maxNest ) );
        w.write( num );
        // Phase 1 (local-variable-indexing, PLAN.md 2026-08-06 evening): the JSON sibling of the XML
        // locals=/locals_floor= pair — omitted key (never a fabricated 0) outside model.h's
        // localsCountedLang (MVP: C/C++ only). "locals_floor" mirrors the XML boolean-flag convention
        // as JSON `true`, matching how `tested` is spelled two lines below.
        if( localsCountedLang( s.lang ) )
        {
            std::snprintf( num, sizeof( num ), ",\"locals\":%u,\"locals_floor\":true", s.locals );
            w.write( num );
        }
        // ppalt disclosure — the JSON sibling of the XML ppalt= attribute (model.h Symbol::ppAlt):
        // omitted key when 0, mirroring locals/tested (absent-unless-measured).
        if( s.ppAlt > 0 )
        {
            std::snprintf( num, sizeof( num ), ",\"ppalt\":%u", unsigned( s.ppAlt ) );
            w.write( num );
        }
        // The JSON sibling of the XML humps=/deep=/deep_floor= triple — same omission rule (absent exactly
        // when nest < quality::kNestBar), same floor flag spelled as JSON `true`. Unlike locals, this is
        // NOT language-gated: cc_walk computes nesting for every grammar.
        if( s.humps > 0 )
        {
            std::snprintf( num, sizeof( num ), ",\"humps\":%u,\"deep\":%u,\"deep_floor\":true", unsigned( s.humps ), unsigned( s.deepLoc ) );
            w.write( num );
        }
        // The JSON sibling of the XML ev=/ev_floor=/ev_why= triple — same omission rule (absent means
        // exactly 1 on a cx row; evCountedLang keeps an uncovered language absent, never a fabricated
        // number), floor spelled as JSON true like deep_floor/locals_floor. Composed on std::string via
        // the shared evWhyString formatter — no fixed buffer and no new format call for fixedbufsweep to classify.
        if( evCountedLang( s.lang ) && s.ev >= 2u )
        {
            w.write( ",\"ev\":" );
            w.write( std::to_string( s.ev ) );
            w.write( ",\"ev_floor\":true,\"ev_why\":\"" );
            w.write( evWhyString( s ) );
            w.write( "\"" );
        }
    }
    if( q.cbo && q.id < q.cbo->size() ) { std::snprintf( num, sizeof( num ), ",\"cbo\":%u", (*q.cbo)[q.id] );  w.write( num ); }
    if( q.lcom4 && q.id < q.lcom4->size() && (*q.lcom4)[q.id] != 0xFFFFFFFFu )   // 0xFFFFFFFF = kLcom4NA (graph.h) ⇒ omit
    { std::snprintf( num, sizeof( num ), ",\"lcom4\":%u", (*q.lcom4)[q.id] );  w.write( num ); }
    if( q.amp && q.id < q.amp->size() ) { std::snprintf( num, sizeof( num ), ",\"amp\":%u", (*q.amp)[q.id] );  w.write( num ); }
    if( q.tested && q.id < q.tested->size() && ( *q.tested )[q.id] )
    {
        w.write( ",\"tested\":true" );
    }
    if( !q.fanIn )
    {
        return;
    }

    const std::uint32_t in = ( q.id < q.fanIn->size() ) ? (*q.fanIn)[q.id] : 0u;
    std::snprintf( num, sizeof( num ), ",\"in\":%u,\"out\":%u,\"cx\":%u,\"ccx\":%u", in, q.outDegree, s.cx, s.ccx );
    w.write( num );
    if( in >= 8 )
    {
        w.write( ",\"role\":\"hub\"" );
    }
}

// The default map's JSON header — the gauge block plus the two prologues that ride on it, in one place so
// "which gauge, in which order, on which condition" is stated once rather than smeared through the emitter.
// The XML sibling states the same set through its `stats` snprintf + the <root> prologue in serialize().
struct JsonMapHeader
{
    const IngestResult&              ing;
    std::size_t                      symbolCount;
    std::size_t                      edgeCount;
    std::size_t                      shownCount;
    std::size_t                      estTokens;
    std::size_t                      ambiguousCount;
    std::size_t                      unresolvedCount;
    const char*                      orderAttr;
    const std::vector<std::uint8_t>* outProv;      // nullptr ⇒ no precise= (nothing was measured)
    const MapAnnotations*            ann;          // §B1.2: how THIS map was produced — the same at/rank_by/window
                                                   // stamp the XML `<r>` element carries. nullptr ⇒ no stamp emitted.
};

// §B1.2: the PROVENANCE stamp — the JSON half of the XML `<r at= rank_by= window=>` attributes. Without it
// `--rank-by=churn --json` and `--rank-by=pagerank --json` emitted keyset-identical headers while every `k`
// underneath meant something different (a git change-frequency prior vs call-graph importance), against
// --help's explicit promise that churn "stamps its own map … so it cannot pass for the structural one".
// Same absent-unless-produced rule as the XML: a default map passes no annotations ⇒ zero bytes, byte-
// identical output. `changed` (--map-diff) has no arm here on purpose — see the coverage note above
// serializeJson: jsonUnsupportedVerb refuses --map-diff before this emitter is ever reached.
inline void writeJsonMapStamp( JsonWriter& w, std::string& esc, const MapAnnotations* ann )
{
    if( !ann )
    {
        return;
    }

    // §B12.6 (CA4): `at`'s ABSENCE had two meanings inside one dialect. Five JSON emitters (quality-delta,
    // test-gate, cochange, plan-lanes, the MCP quality_delta twin) write `"at":null` when the root has no
    // HEAD to anchor to — "we tried, there is nothing" — while this one OMITTED the key in the same state,
    // so `--rank-by=churn --json` on a non-git root produced a stamped map (rank_by=, window=) with no `at`
    // key at all. A schema-holding consumer breaks on one form; a presence-keying consumer gets opposite
    // answers from two JSON surfaces of the SAME binary in the SAME state.
    //
    // The rule, now uniform across the dialect: the key is PRESENT exactly when the run attempted an anchor,
    // and `null` means the attempt found no HEAD. A run that anchors nothing (the plain map — no map-diff,
    // no churn ranking) emits no key, which is also what the XML does, so the 1:1 attr/key correspondence
    // holds in every state. The windowless rank_by= stamps (authority/hub/rrf) attempt no anchor and are
    // deliberately outside the predicate, exactly as they are on the XML side.
    const bool didAttemptAtStamp = ( ann->changedCount != nullptr ) || ( ann->churnWindow != nullptr );
    if( didAttemptAtStamp )
    {
        w.write( ",\"at\":" );
        if( ann->atStamp != nullptr && !ann->atStamp->empty() )
        {
            writeJsonStr( w, *ann->atStamp, esc );
        }
        else
        {
            w.write( "null" );
        }
    }
    if( ann->churnWindow != nullptr )
    {
        w.write( ",\"rank_by\":\"churn\",\"window\":" );
        writeJsonStr( w, *ann->churnWindow, esc );
    }
    // §B2.1: authority/hub/rrf carry no window, so they stamp rank_by alone — the JSON half of the XML arm
    // above, symmetric with it, so the two dialects still cannot disagree about how a map was produced.
    else if( ann->rankByLabel != nullptr )
    {
        w.write( ",\"rank_by\":" );
        writeJsonStr( w, std::string_view( ann->rankByLabel ), esc );
    }

    // §C4 — the --max-tokens fit, in the dialect that was missing it. `--max-tokens=N --json` shaped the map and
    // then said NOTHING about the shaping: no max_tokens=, no fit_bytes=, no over_ceiling — the XML sibling's
    // three attributes, on a surface whose whole audience is machines. `--help` already described this state
    // accurately ("XML only: the --json map carries no max_tokens=/fit_bytes= keys yet"), so the choice here was
    // between a precise description of a gap and closing the gap; the data was already in this function's own
    // `ann` parameter, so the gap closes.
    //
    // fit_measured_in= is the one key with no XML twin, and it is required rather than decorative: the top-K
    // binary search that chose this map measures the XML rendering (main.cpp's measureMapBytes calls
    // serialize()), and the JSON encoding of the same map is materially smaller — MEASURED on src/
    // --max-tokens=1200: fit_bytes=2548, XML 2464 B, JSON 1775 B. Emitting fit_bytes into a JSON document
    // without naming the dialect it was measured against would replace one silence with a false implication.
    // The XML needs no such key because the XML is the measured dialect. Fixing the SEARCH to measure the
    // emitted dialect is a main.cpp change and is recorded as a residual, not smuggled in here.
    if( ann->maxTokensFit != nullptr )
    {
        char fit[ 160 ];
        std::snprintf( fit, sizeof( fit ), ",\"max_tokens\":%zu,\"fit_bytes\":%zu,\"fit_measured_in\":\"xml\"%s",
                       ann->maxTokensFit->askedTokens, ann->maxTokensFit->ceilingBytes,
                       ann->maxTokensFit->isOverCeiling ? ",\"over_ceiling\":true" : "" );
        w.write( fit );
    }
}

inline void writeJsonMapHeader( JsonWriter& w, std::string& esc, const JsonMapHeader& h )
{
    char hdr[ 256 ];   // the gauge line has 7 size_t fields — wider than the per-symbol scratch
    std::snprintf( hdr, sizeof( hdr ), "{\"files\":%zu,\"symbols\":%zu,\"edges\":%zu,\"shown\":%zu,\"est_tokens\":%zu,\"ambiguous\":%zu,\"unresolved\":%zu,",
                   h.ing.files.size(), h.symbolCount, h.edgeCount, h.shownCount, h.estTokens, h.ambiguousCount, h.unresolvedCount );
    w.write( hdr );

    // §P0.5d, JSON lane: the size-ceiling disclosure must reach --json consumers too — the XML header
    // gained skipped_oversize= and a JSON reader (MCP clients most of all) must not be the one audience
    // still shown the survivors as if they were the corpus. Same absent-when-zero rule as the XML side.
    if( !h.ing.skippedOversize.empty() )
    {
        std::snprintf( hdr, sizeof( hdr ), "\"skipped_oversize\":%zu,", h.ing.skippedOversize.size() );
        w.write( hdr );
    }
    // §A4d: `precise=N` — how many out-edges the SCIP overlay / an FFI binding actually pinned.
    // Emitted ONLY when a provenance vector was supplied, exactly like the XML attribute (absent ⇒ nothing
    // was measured, never a fabricated 0 that would read as "no edge is precise").
    if( h.outProv )
    {
        std::size_t preciseTotal = 0;
        for( std::uint8_t v : *h.outProv )
        {
            preciseTotal += ( v ? 1u : 0u );
        }
        std::snprintf( hdr, sizeof( hdr ), "\"precise\":%zu,", preciseTotal );
        w.write( hdr );
    }
    w.write( "\"order\":" );
    writeJsonStr( w, h.orderAttr, esc );

    writeJsonMapStamp( w, esc, h.ann );   // §B1.2 — see its header

    // §A4b: the multi-root prologue (A13) — `roots_count` joins the header gauges and a
    // `roots` table maps each label to its root path, ONLY when N≥2 (single-root output byte-unchanged).
    // Without it every `"p"` in the payload is an unresolvable root-relative fragment.
    if( h.ing.rootLabels.size() < 2 )
    {
        return;
    }

    std::snprintf( hdr, sizeof( hdr ), ",\"roots_count\":%zu,\"roots\":[", h.ing.rootLabels.size() );
    w.write( hdr );
    for( std::size_t r = 0; r < h.ing.rootLabels.size(); ++r )
    {
        if( r )
        {
            w.write( "," );
        }
        w.write( "{\"label\":" );  writeJsonStr( w, h.ing.rootLabels[r], esc );
        // V1-6: "p", not "path" — the XML sibling is <root label= p=/> and --help promises keys mirror attrs 1:1.
        w.write( ",\"p\":" );      writeJsonStr( w, r < h.ing.rootPaths.size() ? h.ing.rootPaths[r] : std::string(), esc );
        w.write( "}" );
    }
    w.write( "]" );
}

// The default-map JSON sibling of serialize() — same rank/order/bucket logic (kept a deliberate, mechanical
// duplication per the L2 seam decision: a sibling emitter, not a shared-emission refactor of the XML path,
// so the G5 byte-identical-default contract carries zero risk from this addition). Scope: the common single-
// root invocation (metrics, fan-in, ambiguity, cbo/tested/lcom4/amp Q-metrics, stable/most-important-last/
// auto-order, bind labels, est_tokens, per-edge provenance, the multi-root prologue, and — §B1.2 — the
// at/rank_by/window PROVENANCE STAMP a churn-ranked map carries. NOT covered (documented gap, refused
// upstream by jsonUnsupportedVerb before this is ever reached in those combinations): --map-diff
// (changed=), --expand's appended <bodies> token math (extraBodyTokens).
//
// §B1.2 — churn was the third XML-only honesty fact this sibling dropped, and the enumeration above used to
// omit it entirely: it read as a complete coverage statement while `--rank-by=churn --json` and
// `--rank-by=pagerank --json` emitted keyset-identical headers. serializeJson now takes the same
// `MapAnnotations` the XML path takes and emits `at`/`rank_by`/`window` from it (writeJsonMapHeader).
//
// §A4b/§A4d closed three XML-only honesty attributes that this sibling used to drop SILENTLY:
//   * multi-root: the header comment above claimed the combination was "refused upstream by
//     jsonUnsupportedVerb" — it never was (no roots-count arm exists there), so a JSON consumer got
//     `"p":"src/./svector.h"` with no label→path table and no signal the graph spanned several roots.
//     `"roots"`/`"roots_count"` now mirror the XML `roots=` + `<root label= p=/>` prologue exactly.
//   * overloads: this emitter never called collapseOverloadRows(), so a const/non-const pair printed TWO
//     byte-identical rows and a consumer keying on "id" silently lost one. Collapsed here as in the XML,
//     with the same `"overloads":N` (>1 only) discriminator.
//   * prov/precise: an edge the SCIP overlay or an FFI binding actually PINNED read identical to a
//     name-guessed one. Same absent-unless-present rule as the XML attribute.
inline void serializeJson( std::FILE* out, const IngestResult& ing, const std::vector<float>& rank,
                           const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                           int topK, bool mostImportantLast, bool metrics,
                           const std::vector<std::uint32_t>* fanIn, const std::vector<std::uint32_t>* ambOut,
                           bool stable,
                           const std::vector<std::uint32_t>* cbo, const std::vector<std::uint8_t>* tested,
                           const std::vector<std::uint32_t>* lcom4, const std::vector<std::uint32_t>* amp,
                           const std::vector<std::uint32_t>* unresolvedOut,
                           const std::vector<std::string>* bind,
                           bool autoOrder, std::size_t* outEstTokens,
                           const std::vector<std::uint8_t>* outProv = nullptr,
                           const MapAnnotations& ann = {} )     // §B1.2: same value the XML serialize() takes;
                                                                // defaulted ⇒ every field null ⇒ no stamp keys.
{
    const std::size_t S = ing.symbols.size();

    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );

    const std::size_t keep = std::min<std::size_t>( topK > 0 ? std::size_t( topK ) : S, S );

    std::vector<std::vector<NodeId>> buckets( ing.files.size() );
    std::vector<std::uint32_t>       fileOrder;
    std::vector<char>                seen( ing.files.size(), 0 );
    for( std::size_t k = 0; k < keep; ++k )
    {
        const NodeId        id = order[k];
        const std::uint32_t f  = ing.symbols[id].fileId;
        if( !seen[f] ) { seen[f] = 1;  fileOrder.push_back( f ); }
        buckets[f].push_back( id );
    }

    // T1/§H7: SAME byte-model the XML sibling uses, in the same two roles — the fill-order oracle and the
    // rate source. The REPORTED est_tokens is measured from the emitted bytes in PHASE 2 below, exactly as
    // in serialize(): a defect fixed in one serialization and not the other is how the §H5 dialect
    // divergences are born, and this emitter had the identical --metrics under-report (MEASURED: 1780 B
    // reported as est_tokens=507, 3.51 B/tok).
    const TokenEstimate mapEst      = estimateTokens( ing, order, keep, outOff, outTargets );
    const std::size_t   mapEstTokens = mapEst.tokens;

    const bool autoFlip         = autoOrder && !stable && !mostImportantLast && mapEstTokens > kFillOrderThreshold;
    const bool effImportantLast = mostImportantLast || autoFlip;
    if( stable )
    {
        std::sort( fileOrder.begin(), fileOrder.end(),
                   [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
        for( std::vector<NodeId>& b : buckets )
        {
            std::sort( b.begin(), b.end() );
        }
    }
    else if( effImportantLast )
    {
        std::reverse( fileOrder.begin(), fileOrder.end() );
        for( std::vector<NodeId>& b : buckets )
        {
            std::reverse( b.begin(), b.end() );
        }
    }

    std::size_t ambTotal = 0;
    if( ambOut )
    {
        for( std::uint32_t v : *ambOut )
        {
            ambTotal += v;
        }
    }
    std::size_t unresolvedTotal = 0;
    if( unresolvedOut )
    {
        for( std::uint32_t v : *unresolvedOut )
        {
            unresolvedTotal += v;
        }
    }
    const char* orderAttr = stable ? "stable"
                          : mostImportantLast ? "important-last"
                          : autoFlip ? "important-last(auto:fill)"
                          : "important-first";

    // ── PHASE 1: render the "r" array into a buffer (§H7 — see serialize()'s PHASE 1 for the full reasoning:
    // measure, decide, then write). DEGRADE: an open_memstream failure emits the header FIRST with the
    // MODELLED estimate (the pre-§H7 number, never a fabricated one) and streams the array behind it.
    char*       rowsBuf = nullptr;
    std::size_t rowsSz  = 0;
    std::FILE*  rowsMem = openChargeBuffer( &rowsBuf, &rowsSz );
    if( !rowsMem )
    {
        DEGRADED_PATH_ALERT( "serializeJson: open_memstream failed — est_tokens reports the MODELLED bytes, not the emitted ones" );
    }

    // ONE header emitter, used by the degrade write, the size probe and the real write, so the three can
    // never disagree on the header's shape.
    std::string esc;
    const auto  emitHeader = [ & ]( std::FILE* dst, std::size_t estTokens )
    {
        JsonWriter hw( dst );
        writeJsonMapHeader( hw, esc, JsonMapHeader{ ing, S, outTargets.size(), keep, estTokens, ambTotal,
                                                    unresolvedTotal, orderAttr, outProv, &ann } );
        hw.write( ",\"r\":[" );
    };

    if( !rowsMem )
    {
        emitHeader( out, mapEstTokens ); // degrade: nothing to measure, so the model stands
    }

    JsonWriter w( rowsMem ? rowsMem : out );
    char       num[ 64 ];

    bool firstFile = true;
    for( std::uint32_t f : fileOrder )
    {
        if( !firstFile )
        {
            w.write( "," );
        }
        firstFile = false;
        w.write( "{\"p\":" );  writeJsonStr( w, ing.files[f], esc );
        if( const char* fl = builtinLayer( ing.files[f] ); *fl ) { w.write( ",\"layer\":" );  writeJsonStr( w, fl, esc ); }
        w.write( ",\"s\":[" );

        // §P6.3 / §A4d: const/non-const overloads canonicalize to the SAME id, so a bucket straight from
        // `order` printed two byte-identical JSON objects and a consumer keying on "id" silently dropped
        // one. Same collapse the XML path runs (collapseOverloadRows above), same "overloads" count.
        const OverloadRows rows = collapseOverloadRows( ing, buckets[f] );

        bool firstSym = true;
        for( std::size_t rowIndex = 0; rowIndex < rows.id.size(); ++rowIndex )
        {
            const NodeId id = rows.id[ rowIndex ];
            if( !firstSym )
            {
                w.write( "," );
            }
            firstSym = false;
            const Symbol&       s   = ing.symbols[id];
            const std::uint32_t out2= outOff[id + 1] - outOff[id];

            w.write( "{\"t\":" );  writeJsonStr( w, symTag( s.kind ), esc );
            w.write( ",\"n\":" );  writeJsonStr( w, s.name, esc );

            const std::string canon = canonicalId( ing.files[ s.fileId ], s.scope, s.name );
            if( canon != s.name ) { w.write( ",\"id\":" );  writeJsonStr( w, canon, esc ); }

            if( rows.overloads[ rowIndex ] > 1 )
            { std::snprintf( num, sizeof( num ), ",\"overloads\":%u", rows.overloads[ rowIndex ] );  w.write( num ); }

            if( bind && id < bind->size() && !(*bind)[id].empty() )
            { w.write( ",\"bind\":" );  writeJsonStr( w, (*bind)[id], esc ); }

            if( ambOut && id < ambOut->size() && ( *ambOut )[id] > 0 )
            { std::snprintf( num, sizeof( num ), ",\"amb\":%u", ( *ambOut )[id] );  w.write( num ); }

            if( !stable )
            { std::snprintf( num, sizeof( num ), ",\"k\":%.4f", double( rank[id] ) );  w.write( num ); }

            if( metrics )
            {
                writeJsonQMetrics( w, JsonQMetrics{ s, id, out2, fanIn, cbo, tested, lcom4, amp } );
            }

            w.write( ",\"c\":[" );
            bool firstC = true;
            for( std::uint32_t e = outOff[id]; e < outOff[id + 1]; ++e )
            {
                if( !firstC )
                {
                    w.write( "," );
                }
                firstC = false;
                w.write( "{\"n\":" );  writeJsonStr( w, ing.symbols[ outTargets[e] ].name, esc );
                // §A4d: prov mirrors the XML attribute 1:1 — "scip" for a SCIP-pinned edge, "binding" for a
                // decoded FFI binding. outProv parallels outTargets exactly, so index `e` is the same edge.
                if( outProv && e < outProv->size() && (*outProv)[e] )
                { w.write( ",\"prov\":" );  writeJsonStr( w, (*outProv)[e] == 2u ? "binding" : "scip", esc ); }
                w.write( "}" );
            }
            w.write( "]}" );
        }
        w.write( "]}" );
    }
    w.write( "]}" );
    w.flush();

    // ── PHASE 2: measure, decide, then write ────────────────────────────────────────────────────────────
    if( !rowsMem )
    {
        if( outEstTokens )
        {
            *outEstTokens = mapEstTokens;
        }
        return;
    }
    std::fflush( rowsMem );
    std::fclose( rowsMem );
    std::string rowsStr;
    if( rowsBuf ) { rowsStr.assign( rowsBuf, rowsSz );  std::free( rowsBuf ); }

    // The header STATES est_tokens and its own bytes are part of what est_tokens covers, so its size is
    // probed with the modelled number first. Unlike the XML sibling — whose head is a plain std::string and
    // can therefore be rebuilt free of charge inside a fixpoint — this header is written through a
    // JsonWriter to a FILE*, so iterating it would mean a memstream per pass. The ONLY thing a pass changes
    // is the width of one digit string, so that is priced by a fixed reserve instead (the same technique the
    // --for lens uses for its own est_tokens attribute): kEstTokensFieldReserve bytes ≈ 3 tokens, well
    // inside the estimate's own band. A probe failure falls back to the model's envelope allowance rather
    // than dropping the header's bytes from the charge.
    std::size_t headerBytes = kEnvelopeBytes;
    {
        char*       pbuf = nullptr;
        std::size_t psz  = 0;
        if( std::FILE* pm = openChargeBuffer( &pbuf, &psz ) )
        {
            emitHeader( pm, mapEstTokens );
            std::fflush( pm );  std::fclose( pm );
            headerBytes = psz;
            std::free( pbuf );
        }
        else
        {
            DEGRADED_PATH_ALERT( "serializeJson: open_memstream failed for the header size probe — est_tokens charges the modelled envelope instead" );
        }
    }

    const std::size_t estTokens = tokensForEmittedBytes( headerBytes + kEstTokensFieldReserve + rowsStr.size(),
                                                         mapEst.bytesPerToken() );
    if( outEstTokens )
    {
        *outEstTokens = estTokens;
    }
    emitHeader( out, estTokens );
    std::fwrite( rowsStr.data(), 1, rowsStr.size(), out );
}

// ── §A4a: the JSON signature bundle's collected form ────────────────────────────────────────────────────
// The JSON <sigs> sibling now runs the SAME two-phase collect-then-trim emission the XML path runs, over the
// SAME ladder (trimSigLadder above — one ladder, two serializations). These are its row structs; the member
// NAMES are the ladder's duck-typed contract (globalRank/doc/sig/dropped and wrapBytes/entryBegin/entryEnd/
// liveCount), so they deliberately match the XML path's local structs field for field.
struct JsonSigFile
{
    std::uint32_t fileId     = 0;
    std::size_t   wrapBytes  = 0;   // exact emitted bytes of the {"p":…,"symbols":[…]} wrapper (+ its separating comma)
    std::size_t   entryBegin = 0;   // [entryBegin, entryEnd) rows in the entries vector
    std::size_t   entryEnd   = 0;
    std::size_t   liveCount  = 0;   // non-dropped entries (the wrapper is dropped when this hits 0)
    std::string   notes;            // §B1.3: the rendered `,"notes":[…]` for FILE-level notes ("" ⇒ none)
    std::size_t   noteCount = 0;    //         how many notes that array holds (the countable fact)
};
struct JsonSigEntry
{
    std::uint32_t globalRank = 0;   // 1-based global rank — the ladder's only rank input
    std::string   head;             // the exact `{"l":…,"n":…` prefix through the flag fields
    std::string   doc;              // RAW doc text after the rank tiers ("" ⇒ no "doc" key)
    std::string   sig;              // RAW one-line signature after the rank tiers
    std::string   notes;            // §B1.3: the rendered `,"notes":[…]` for SYMBOL-level notes ("" ⇒ none)
    std::size_t   noteCount = 0;    //         how many notes that array holds
    bool          dropped    = false;
};

// §B1.3: how many notes this array-emitter matched, and how many survived the ladder — the caller pairs
// them into the `notes_total`/`notes_kept` keys --pack-task --json already established. Kept as ONE value
// rather than two out-params so the pair can never be filled in half.
struct JsonSigNoteCounts
{
    std::size_t total = 0;   // notes matching any COLLECTED file/symbol (before the byte ladder)
    std::size_t kept  = 0;   // notes actually EMITTED (after it)
};

// §B1.3: the JSON rendering of a note list — the sibling of appendOneNote/renderNoteChildren on the XML
// side, and shaped like --pack-task --json's note objects (`d` + `text`), with the same absent-unless-
// recorded rule for the provenance pair (`sha`/`branch` omitted entirely on a legacy unstamped note, never
// emitted empty). Returns the number of notes rendered; appends NOTHING when there are none, so a tree
// with no NoteIndex keeps the pre-feature bytes exactly (the L3 inertness contract).
inline std::size_t appendJsonNoteArray( std::string& out, const notes::NoteIndex* ni, const std::string& target )
{
    if( !ni )
    {
        return 0;
    }
    const std::vector<std::uint32_t>* hits = ni->find( target );
    if( !hits || hits->empty() )
    {
        return 0;
    }

    out += ",\"notes\":[";
    for( std::size_t i = 0; i < hits->size(); ++i )
    {
        const notes::Note& n = ni->notes[ (*hits)[i] ];
        if( i )
        {
            out += ",";
        }
        appendJsonStrField( out, "{\"d\":", n.date );
        if( !n.sha.empty() )
        {
            appendJsonStrField( out, ",\"sha\":", notes::shortSha( n.sha ) );
            if( !n.branch.empty() )
            {
                appendJsonStrField( out, ",\"branch\":", n.branch );
            }
        }
        appendJsonStrField( out, ",\"text\":", n.text );
        out += "}";
    }
    out += "]";
    return hits->size();
}

// The per-symbol quality/identity lens, gathered once so both the collector's signature and its body stay
// readable (the XML sibling spells the same set as SigRowFacts + the qbuf lens string).
struct JsonSigLens
{
    bool                              metrics             = false;
    const std::vector<std::uint32_t>* fanIn               = nullptr;
    const std::vector<char>*          impure              = nullptr;
    const std::vector<std::uint32_t>* churnPerFile        = nullptr;
    const std::vector<std::uint8_t>*  cloneMember         = nullptr;
    const std::vector<std::uint8_t>*  tested              = nullptr;
    const std::vector<std::uint32_t>* amp                 = nullptr;
    bool                              rankAdaptivePayload = false;
    const notes::NoteIndex*           noteIndex           = nullptr;   // §B1.3: L3 field notes — surfaces a
                                                                       // `notes` array on the row/file the XML
                                                                       // sibling hangs <note> children on.
                                                                       // nullptr ⇒ INERT (byte-identical).
};

// One row's `{"l":…` opening through its flag fields — everything EXCEPT doc/sig, which the ladder mutates
// and phase 2 appends. Mirrors sigRowHead()'s role on the XML side.
inline std::string jsonSigRowHead( const IngestResult& ing, NodeId id, std::uint32_t fileId,
                                   const JsonSigLens& lens, bool pureSig )
{
    const Symbol& s = ing.symbols[id];
    char          num[ 64 ];
    std::string   head;

    std::snprintf( num, sizeof( num ), "{\"l\":%u", s.line );
    head += num;
    // P2.3: the chain key — "n" always, "id" only when the canonical form adds an enclosing scope
    // (the XML sibling's rule, scopedCanonicalId above), so a JSON consumer can chain onward too.
    appendJsonStrField( head, ",\"n\":", s.name );
    if( const std::string canon = scopedCanonicalId( ing, s ); !canon.empty() )
    {
        appendJsonStrField( head, ",\"id\":", canon );
    }
    if( lens.metrics )
    {
        appendJsonMetricFields( head, s, id, lens.fanIn );
    }
    if( lens.churnPerFile && fileId < lens.churnPerFile->size() && (*lens.churnPerFile)[fileId] > 0 )
    { std::snprintf( num, sizeof( num ), ",\"churn\":%u", (*lens.churnPerFile)[fileId] );  head += num; }
    if( lens.amp && id < lens.amp->size() && (*lens.amp)[id] > 0 )
    { std::snprintf( num, sizeof( num ), ",\"amp\":%u", (*lens.amp)[id] );  head += num; }
    if( lens.cloneMember && id < lens.cloneMember->size() && ( *lens.cloneMember )[id] )
    {
        head += ",\"clone\":true";
    }
    if( lens.tested && id < lens.tested->size() && ( *lens.tested )[id] )
    {
        head += ",\"tested\":true";
    }
    if( pureSig )
    {
        head += ",\"pure\":true";
    }
    return head;
}

// The exact emitted byte cost of one collected row. `,"doc":"` + closing quote = 9 bytes of key framing,
// likewise `,"sig":"`; +1 for the row's own separating comma (charged to EVERY row, so a file's first row
// over-reports by one byte — the budget stays conservative, never optimistic).
inline std::size_t jsonSigEntryCost( const JsonSigEntry& e )
{
    if( e.dropped )
    {
        return 0;
    }
    std::size_t c = 1 + e.head.size() + 1;                                   // `,` … `}`
    if( !e.doc.empty() )
    {
        c += 9 + jsonStr( e.doc ).size();
    }
    return c + 9 + jsonStr( e.sig ).size() + e.notes.size();                 // §B1.3: notes are pre-rendered, so
                                                                             // their EXACT emitted size is known
}

// §B1.3: the note DENOMINATOR — everything the collector matched, counted BEFORE the ladder runs, so
// `notes_total` stays a fact about the tree while `notes_kept` is a fact about this budget.
inline std::size_t collectedJsonNoteTotal( const std::vector<JsonSigFile>& files, const std::vector<JsonSigEntry>& entries )
{
    std::size_t total = 0;
    for( const JsonSigFile& sf : files )
    {
        total += sf.noteCount;
    }
    for( const JsonSigEntry& e : entries )
    {
        total += e.noteCount;
    }
    return total;
}

// Phase 2's per-file symbol array, as ONE string: the live rows of `sf`, comma-joined, in collection order.
// Returns "" when every row was skipped or dropped, which is the signal phase 2 uses to spend no file
// wrapper and no separating comma. `outKeptNotes` accumulates the notes that survived onto those rows.
inline std::string renderJsonSigRows( const std::vector<JsonSigEntry>& entries, const JsonSigFile& sf, std::size_t& outKeptNotes )
{
    std::string rows;
    for( std::size_t k = sf.entryBegin; k < sf.entryEnd; ++k )
    {
        const JsonSigEntry& e = entries[k];
        if( e.dropped )
        {
            continue;
        }
        if( !rows.empty() )
        {
            rows += ",";
        }
        rows += e.head;
        if( !e.doc.empty() )
        {
            appendJsonStrField( rows, ",\"doc\":", e.doc );
        }
        appendJsonStrField( rows, ",\"sig\":", e.sig );
        rows         += e.notes;      // §B1.3: pre-rendered, after `sig` — the XML order of <d>'s children
        outKeptNotes += e.noteCount;
        rows += "}";
    }
    return rows;
}

// Phase 1 — derive every row exactly as the pre-§A4a streaming loop did (same skip gates, same rank tiers,
// same budgetBytes accounting), into memory. Per-file emission is a variable-skip loop (an unreadable span
// or an empty cleaned signature drops a symbol entirely), so whether a file contributes anything is only
// known AFTER walking its symbols — collecting first is what lets phase 2 keep every comma unconditionally
// correct AND gives the ladder an exact byte total to trim against.
//
// §B0: `redact` carries NO default here (nor on packSignaturesJson / packBodiesJson below), unlike the XML
// siblings — that is the whole lesson of the finding. This emitter and packBodiesJson were written as the
// JSON twins of packSignatures/packBodies and simply never passed one, so `--for --json` / `--pack-task
// --json` shipped the raw credentials their XML siblings redact, on the surface most likely to be piped
// into logs/CI/model context. A REQUIRED parameter turns the next twin's omission into a compile error
// instead of a silent leak. Pass nullptr for --no-redact (the same convention redactInPlace already has).
inline void collectJsonSigEntries( const IngestResult& ing, const std::vector<std::uint32_t>& fileOrder,
                                   std::vector<std::vector<NodeId>>& buckets,
                                   const std::vector<std::uint32_t>& globalRankOf,
                                   const JsonSigLens& lens, RedactCounts* redact, std::size_t budgetBytes,
                                   std::vector<JsonSigFile>& outFiles, std::vector<JsonSigEntry>& outEntries )
{
    std::size_t used = 0;
    for( std::uint32_t f : fileOrder )
    {
        if( used >= budgetBytes )
        {
            break;
        }

        std::FILE* in = std::fopen( diskPath( ing, f ).c_str(), "rb" );
        if( !in )
        {
            continue; // graceful: file gone
        }
        std::string src;
        char        buf[ 4096 ];
        std::size_t n;
        while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
        {
            src.append( buf, n );
        }
        std::fclose( in );

        std::vector<NodeId>& syms = buckets[f];
        std::sort( syms.begin(), syms.end(), [ & ]( NodeId a, NodeId b )
        { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );

        JsonSigFile sf;
        sf.fileId     = f;
        sf.entryBegin = outEntries.size();
        // exact wrapper bytes: `,` + `{"p":"…"` [+ `,"layer":"…"`] + `,"symbols":[` + `]}`
        sf.wrapBytes  = 1 + 6 + jsonStr( ing.files[f] ).size() + 1 + 12 + 2;
        if( const char* fl = builtinLayer( ing.files[f] ); *fl )
        {
            sf.wrapBytes += 10 + std::strlen( fl ) + 1;
        }
        // §B1.3: FILE-level notes ride the wrapper, exactly as the XML <f> child does — rendered here so the
        // wrapper's byte cost stays EXACT (the ladder trims against these numbers).
        sf.noteCount  = appendJsonNoteArray( sf.notes, lens.noteIndex, fileNoteTarget( lens.noteIndex, ing.files[f] ) );
        sf.wrapBytes += sf.notes.size();

        for( NodeId id : syms )
        {
            if( used >= budgetBytes )
            {
                break;
            }
            const Symbol&     s = ing.symbols[id];
            const std::size_t a = s.sigStartByte, b = s.sigEndByte;
            if( a >= src.size() || b > src.size() || a >= b )
            {
                continue;
            }
            std::string sig = cleanSig( src.data(), a, b, redact );
            if( sig.empty() )
            {
                continue;
            }

            const std::uint32_t globalRank = lens.rankAdaptivePayload ? globalRankOf[ id ] : 0u;
            if( lens.rankAdaptivePayload && globalRank > kForDocExcerptRankCount )
            {
                truncateUtf8WithEllipsis( sig, kForTailSigBytes );
            }
            const bool pureSig = pureFromSig( sig, s.lang ) && !( lens.impure && id < lens.impure->size() && (*lens.impure)[id] );

            std::string doc = docCommentBefore( src, a );
            redactInPlace( doc, redact );                   // §B0: same seam, same order as the XML sibling (:1586)
            if( lens.rankAdaptivePayload )
            {
                if( globalRank > kForDocExcerptRankCount )
                {
                    doc.clear();
                }
                else if( globalRank > kForDocFullRankCount )
                {
                    truncateUtf8WithEllipsis( doc, kForDocExcerptBytes );
                }
            }

            if( !doc.empty() )
            {
                used += doc.size() + 12; // the same budgetBytes accounting as the XML path
            }
            used += sig.size() + 16;

            JsonSigEntry e;
            e.globalRank = globalRank;
            e.head       = jsonSigRowHead( ing, id, f, lens, pureSig );
            e.doc        = std::move( doc );
            e.sig        = std::move( sig );
            e.noteCount  = appendJsonNoteArray( e.notes, lens.noteIndex, symbolNoteTarget( lens.noteIndex, ing, s ) );   // §B1.3
            outEntries.push_back( std::move( e ) );
        }
        sf.entryEnd  = outEntries.size();
        sf.liveCount = sf.entryEnd - sf.entryBegin;
        outFiles.push_back( sf );
    }
}

// The --for/--pack-task JSON ranking sibling of packSignatures. Writes JUST the array value
// `[ {...}, ... ]` (the caller supplies the key name, e.g. `"sigs":` or `"ranking":`, so the same array
// shape composes into either bundle).
//
// §A4a: it used to run NO budget at all — `--for --json` was byte-identical at --token-budget=1000 and
// 20000 while the XML sibling shrank 12,780 → 2,707 bytes, so the audience that most needs a size control
// (MCP/JSON consumers) had none, and the old comment here ("never claims capped, since it never runs the
// ladder") documented the hole instead of closing it. It reports the outcome through `outCapped` so the
// caller can emit the `"capped"` key next to its own `"est_tokens"`. budgetBytes/payloadBudgetBytes are 0
// (⇒ unlimited / no ladder) for callers that supply no budget, which keeps their bytes identical.
// The eight per-symbol lens pointers travel as ONE `JsonSigLens` rather than eight positional parameters:
// they are one cohesive thing (the quality lens the row carries), the old flat form was a 12-parameter
// signature where three adjacent `const std::vector<std::uint8_t>*` arguments could be transposed with no
// diagnostic, and adding the budget as three more would have made it fifteen.
inline void packSignaturesJson( std::FILE* out, const IngestResult& ing, const std::vector<float>& rank,
                                int topN, const JsonSigLens& lens,
                                RedactCounts* redact,                      // §B0: REQUIRED (no default) — see collectJsonSigEntries; nullptr = --no-redact
                                std::size_t budgetBytes        = 0,        // per-entry streaming budget (cfg.packBudgetBytes); 0 = unlimited
                                std::size_t payloadBudgetBytes = 0,        // H1 global payload budget for this array; 0 = no ladder
                                bool*       outCapped          = nullptr,  // set true iff the ladder trimmed something
                                JsonSigNoteCounts* outNotes    = nullptr ) // §B1.3: matched vs emitted note counts
{
    const bool rankAdaptivePayload = lens.rankAdaptivePayload;
    if( outCapped )
    {
        *outCapped = false;
    }
    if( outNotes )
    {
        *outNotes = JsonSigNoteCounts {};
    }
    if( budgetBytes == 0 )
    {
        budgetBytes = SIZE_MAX; // A3-F1 convention, same as packSignatures
    }

    const std::size_t S = ing.symbols.size();
    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );
    const std::size_t keep = std::min<std::size_t>( topN > 0 ? std::size_t( topN ) : S, S );

    std::vector<std::vector<NodeId>> buckets( ing.files.size() );
    std::vector<std::uint32_t>       fileOrder;
    std::vector<char>                seen( ing.files.size(), 0 );
    std::vector<std::uint32_t>       globalRankOf;
    if( rankAdaptivePayload )
    {
        globalRankOf.assign( S, 0 );
    }
    for( std::size_t k = 0; k < keep; ++k )
    {
        const std::uint32_t f = ing.symbols[ order[k] ].fileId;
        if( !seen[f] ) { seen[f] = 1; fileOrder.push_back( f ); }
        buckets[f].push_back( order[k] );
        if( rankAdaptivePayload )
        {
            globalRankOf[order[k]] = std::uint32_t( k + 1 );
        }
    }

    // phase 1 — collect (collectJsonSigEntries above), then the exact emitted byte total of the array as
    // collected, then the ladder. Phase 2 splices a file wrapper only when that file still has a live entry.
    std::vector<JsonSigFile>  sigFiles;
    std::vector<JsonSigEntry> entries;
    collectJsonSigEntries( ing, fileOrder, buckets, globalRankOf, lens, redact, budgetBytes, sigFiles, entries );

    std::size_t total = 2;                                                       // "[" + "]"
    for( const JsonSigFile& sf : sigFiles )
    {
        total += sf.wrapBytes;
    }
    for( const JsonSigEntry& e : entries )
    {
        total += jsonSigEntryCost( e );
    }

    const bool capped = payloadBudgetBytes > 0 && total > payloadBudgetBytes;
    if( capped )
    {
        trimSigLadder( entries, sigFiles, total, payloadBudgetBytes, jsonSigEntryCost );
    }
    if( outCapped )
    {
        *outCapped = capped;
    }

    if( outNotes )
    {
        outNotes->total = collectedJsonNoteTotal( sigFiles, entries ); // §B1.3 — see its header
    }

    // phase 2 — emit (identical write shapes to the pre-§A4a streaming path)
    JsonWriter  w( out );
    std::string esc;
    w.write( "[" );
    bool firstFile = true;
    for( const JsonSigFile& sf : sigFiles )
    {
        std::size_t       fileKeptNotes = 0;
        const std::string fileSyms      = renderJsonSigRows( entries, sf, fileKeptNotes );
        if( fileSyms.empty() )
        {
            continue; // every symbol in this file skipped/dropped — no wrapper, no comma spent
        }

        if( !firstFile )
        {
            w.write( "," );
        }
        firstFile = false;
        w.write( "{\"p\":" );  writeJsonStr( w, ing.files[ sf.fileId ], esc );
        if( const char* fl = builtinLayer( ing.files[ sf.fileId ] ); *fl ) { w.write( ",\"layer\":" );  writeJsonStr( w, fl, esc ); }
        w.write( sf.notes );               // §B1.3: file-level notes, where the XML puts them on <f>
        w.write( ",\"symbols\":[" );  w.write( fileSyms );  w.write( "]}" );
        if( outNotes )
        {
            outNotes->kept += sf.noteCount + fileKeptNotes;
        }
    }
    w.write( "]" );
    w.flush();
}

// The --pack-task JSON sibling of packBodies — now a pure RE-SERIALIZATION of what packBodies emitted, not a
// second selection pass (§H5). It takes the EmittedBodies record and writes JUST the array value.
//
// What this deletes, deliberately: the old form took `nodes` + `outOff`/`outTargets` + `redact` and re-derived
// everything — it re-read every file, re-sliced every body from source, re-ran redactInPlace (double-charging
// the shared tally, §B10.2), re-walked the callee edges, and applied NO byte budget of any kind, because it
// had no budgetBytes parameter to apply. Every one of those was a chance to disagree with the XML, and all of
// them took it. There is nothing left here that can decide differently, because there is nothing left here
// that decides.
//
// §B0 note: there is no `redact` parameter and that is not an opt-out — `record` holds text packBodies ALREADY
// redacted, at the one seam packBodies already defines. Adding a second redaction pass here is what created the over-count.
inline void packBodiesJson( std::FILE* out, const IngestResult& ing, const EmittedBodies& record )
{
    JsonWriter  w( out );
    std::string esc;
    char        num[ 64 ];

    w.write( "[" );
    bool first = true;
    for( const EmittedBody& e : record.kept )
    {
        if( e.id >= ing.symbols.size() )
        {
            continue;
        }
        const Symbol& s = ing.symbols[ e.id ];

        if( !first )
        {
            w.write( "," );
        }
        first = false;

        w.write( "{\"t\":" );  writeJsonStr( w, symTag( s.kind ), esc );
        std::snprintf( num, sizeof( num ), ",\"l\":%u,", s.line );
        w.write( num );
        w.write( "\"p\":" );  writeJsonStr( w, ing.files[ s.fileId ], esc );
        w.write( ",\"n\":" );  writeJsonStr( w, s.name, esc );
        // the octocode partial-fetch marker, where the XML writes lines="lo-hi/total" — absent on a whole body,
        // exactly as the attribute is.
        if( !e.lineSpan.empty() ) { w.write( ",\"lines\":" );  writeJsonStr( w, e.lineSpan, esc ); }
        w.write( ",\"body\":" );  writeJsonStr( w, e.text, esc );
        // §H5: the per-body truncation vocabulary this dialect had NONE of. The XML appends
        // `\n<!-- truncated -->` inside the CDATA; a JSON consumer gets a boolean it can branch on. Emitted
        // only when true, matching the tool's silence-means-nothing-happened convention.
        if( e.isTruncated )
        {
            w.write( ",\"truncated\":true" );
        }
        // §B12.7/F-MED-1: THIS dialect's `body` is the faithful one, and the XML CDATA for the same def is
        // NOT byte-equal to it — appendCdataSafe's scrub mapped a C0 byte to a space or an invalid UTF-8
        // sequence to '?'. Emitted here as well as on the XML <b scrubbed="1"> because a consumer diffing the
        // two dialects must be able to learn it from whichever one it happens to hold. Absent = byte-equal.
        if( e.isXmlScrubbed )
        {
            w.write( ",\"xml_scrubbed\":true" );
        }

        // calls: the rows the XML <calls> block actually printed, with its own total= as the denominator.
        // calls_capped is pageview.h rule 3 in this dialect — the bit that always rides with a shown count.
        std::snprintf( num, sizeof( num ), ",\"calls_total\":%u,\"calls_capped\":%s,\"calls\":[",
                       e.callsTotal, ( e.calls.size() < std::size_t( e.callsTotal ) ) ? "true" : "false" );
        w.write( num );
        bool firstC = true;
        for( const EmittedBodyCall& c : e.calls )
        {
            if( !firstC )
            {
                w.write( "," );
            }
            firstC = false;
            w.write( "{\"n\":" );  writeJsonStr( w, c.name, esc );
            std::snprintf( num, sizeof( num ), ",\"l\":%u", c.line );
            w.write( num );
            w.write( ",\"sig\":" );  writeJsonStr( w, c.sig, esc );
            w.write( "}" );
        }
        w.write( "]}" );
    }
    w.write( "]" );
    w.flush();
}

}   // namespace rw
