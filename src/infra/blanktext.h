#pragma once

// blanktext.h — THE ONE PREDICATE for "this value is PRESENT but carries NOTHING".
//
// WHY IT IS ITS OWN HEADER. The rule below was born in src/mcp.h, at the
// MCP edit verbs' payload check, because that is where a blank value DELETES a definition. But "does this
// UTF-8 text occupy any visible column" is not an MCP question — it is a text question, and the same
// question was being answered a THIRD time, differently, one file over: `--note-add` decided it with
// notes::sanitizeField (which maps only \t \n \r to space and trims ASCII spaces) plus `.empty()`, so an
// ASCII-blank note was refused while NBSP, ZWSP, BOM, U+2800 BRAILLE PATTERN BLANK, a bidi RLO and a raw
// VT (0x0B) were all ACCEPTED and committed straight into the notes file — a text file the tool tells
// users to commit. Six of six blank classes through.
//
// The fix for a duplicated rule is not a third copy of it, so the table and the two walks moved HERE, where
// a caller that is not an MCP server can reach them without including a JSON-RPC server. mcp.h and notes.h
// now read the SAME table: the surface a fourth caller joins is this header, and the derivation script that
// re-derives the table (test/derive_blankcodepoints.py) reads this file.
//
// It carries no index/graph dependency on purpose — jsonesc.h (utf8SeqLen) is the whole of it — so
// it stays includable from any layer, which is the property that let it be duplicated in the first place.

#include "jsonesc.h"       // utf8SeqLen — fully validating, the decoder both walks below are built on

#include <algorithm>       // std::upper_bound — the binary search over kBlankRanges
#include <cstdint>
#include <cstdio>          // std::snprintf — blankPayloadSpelling's U+XXXX rendering
#include <string>
#include <string_view>
#include <utility>         // std::pair — blankPayloadSpelling's return

namespace rw
{

// ── THE RULING, and why the set is DERIVED rather than listed ────────────────────────────────────────────
//
// A payload carries content iff it has at least ONE code point that occupies a visible column. An INVALID
// UTF-8 byte counts as CONTENT, and so does an unassigned (Cn) code point: garbage bytes are a different
// problem with a different fix. The asymmetry is deliberate and it has a direction — over-refusing costs a
// rejected write the caller sees in a named refusal and can retry; under-refusing deletes a definition (or,
// at --note-add, commits an invisible line into a shared file) and reports success.
//
// The MCP-side ruling this grew out of, and its edit-verb SCOPE, stay in src/mcp.h beside the verbs they
// bind; what follows is the part that is about the TABLE.
//
// ── WAVE-1 VERIFIER (F2, MED): the "closed 23-entry table" was not closed ────────────────────────────────
//
// The ruling above shipped as ASCII `<= 0x20 || == 0x7F` plus a hand-picked, "closed, sorted" 23-entry list of
// Zs / zero-width / format code points — included because NBSP and the BOM are what a copy-paste out of a
// browser or a word processor produces, so they are an ACCIDENT class exactly like a stray space and not
// merely an adversarial input. That rationale still stands; the LIST did not. The verifier found 19 further
// payload shapes that carried no visible column, DELETED the definition and reported {"applied":…}, on stdio
// AND over HTTP with --allow-remote-edits. The two that indict the METHOD rather than the entries: the list
// carried U+200B/200C/200D and U+2060 and skipped **U+200E LRM / U+200F RLM**, which is exactly what the
// ruling's own browser-copy-paste rationale produces off any page with RTL text; and the ASCII group stopped
// at 0x7F, so every **C1 control U+0080-U+009F** — including U+0085 NEL, a line separator — counted as a
// definition. Also missed: U+00AD, U+180E, U+2800, the Hangul fillers U+3164/U+115F/U+FFA0, U+FE00-FE0F, the
// Trojan-Source bidi set U+202A-202E / U+2066-2069 / U+061C, U+17B4, U+FFF9, the U+E0000 tag plane, and any
// MIX of an in-list code point with an out-of-list one.
//
// So the list is GONE and the question is answered from Unicode PROPERTIES instead — a derived rule cannot
// have a 24th entry someone forgot. A payload carries no content iff EVERY one of its code points lies in the
// union of: **Cc** (all C0 and C1 controls) · **Zs/Zl/Zp + White_Space** · **Cf** (all format characters) ·
// **Default_Ignorable_Code_Point** (which adds the CGJ, the Hangul and Khmer fillers, and the variation
// selectors) · plus **U+2800 BRAILLE PATTERN BLANK**, the one glyph that is empty by design while no property
// says so. That is `kBlankRanges` below: 30 ranges, machine-derived, with `test/derive_blankcodepoints.py`
// re-deriving them from `unicodedata` and `--check` failing on drift — so the next round CHECKS the table
// instead of trusting it, and every judgement call (why ALL of Cf and not DI's PCM-subtracted form, why Mn and
// Cn are content) is argued in that script's header. Extending a LIST is what failed here: if a code point is
// missing now, the fix belongs in the derivation, not in a 31st hand-written row.
//
// ── WAVE-1 VERIFIER (F3, MED): this comment used to CONTAIN the NUL it talks about ───────────────────────
//
// The `U+0000` above was written as a literal 0x00 byte, and it made this file — the largest MCP source in the
// tree — BINARY to the search tools this project's whole working method rests on: `grep -rn` answered "Binary
// file src/mcp.h matches" with zero locations at rc=0, and `rg` the same, while `grep -c` on the file counted 6
// real matches. `git grep`/`git diff` sample only the first 8000 bytes and the NUL sat at 18573, so it was
// invisible to the review path and visible only to the search path. test/nulbytecheck.sh now scans every
// tracked non-binary file for embedded NULs, so a prose byte cannot silently un-searchable a source file again.
//

// A half-open-in-neither-direction code-point range: BOTH ends are members. Ranges rather than points because
// the derived set is 4291 code points in 30 runs — a point list would be 4291 rows nobody can read or check.
struct BlankCodePointRange
{
    std::uint32_t lo;     // first code point IN the range
    std::uint32_t hi;     // last code point IN the range (inclusive)
};

static_assert( sizeof( BlankCodePointRange ) == 8, "BlankCodePointRange must stay two packed u32s" );

// The code points that CANNOT carry a definition — Cc · Zs/Zl/Zp + White_Space · Cf ·
// Default_Ignorable_Code_Point · U+2800, derived from **Unicode 16.0.0**. See the F2 block at the top of
// this file for why this is derived rather than hand-picked, and `test/derive_blankcodepoints.py` for the
// derivation itself (`python3 test/derive_blankcodepoints.py --check` diffs this literal against a fresh
// derivation and exits 1 on drift; it also pins the F2 witnesses so a range cannot regress silently).
//
// SORTED, non-overlapping and MERGED (no two rows are adjacent) — all three asserted below, because the lookup
// is a binary search and any of the three failing would make it silently stop matching somewhere in the middle
// of a range, which at this seam means deleting a definition.
inline constexpr BlankCodePointRange kBlankRanges[] = {
    { 0x0000, 0x0020 },  { 0x007F, 0x00A0 },  { 0x00AD, 0x00AD },  { 0x034F, 0x034F },
    { 0x0600, 0x0605 },  { 0x061C, 0x061C },  { 0x06DD, 0x06DD },  { 0x070F, 0x070F },
    { 0x0890, 0x0891 },  { 0x08E2, 0x08E2 },  { 0x115F, 0x1160 },  { 0x1680, 0x1680 },
    { 0x17B4, 0x17B5 },  { 0x180B, 0x180F },  { 0x2000, 0x200F },  { 0x2028, 0x202F },
    { 0x205F, 0x206F },  { 0x2800, 0x2800 },  { 0x3000, 0x3000 },  { 0x3164, 0x3164 },
    { 0xFE00, 0xFE0F },  { 0xFEFF, 0xFEFF },  { 0xFFA0, 0xFFA0 },  { 0xFFF0, 0xFFFB },
    { 0x110BD, 0x110BD }, { 0x110CD, 0x110CD }, { 0x13430, 0x1343F }, { 0x1BCA0, 0x1BCA3 },
    { 0x1D173, 0x1D17A }, { 0xE0000, 0xE0FFF },
};

// is kBlankRanges sorted, well-formed, non-overlapping and canonically merged? A `consteval` walk rather than
// three std::is_sorted-style spellings because "merged" is the property a careless edit actually breaks (two
// adjacent rows still binary-search correctly, so nothing would fail — the table would just stop being the
// canonical form the derivation emits, and the next `--check` diff would report a phantom drift).
consteval bool blankRangesAreCanonical() noexcept
{
    for( std::size_t rangeIndex = 0; rangeIndex < std::size( kBlankRanges ); ++rangeIndex )
    {
        if( kBlankRanges[rangeIndex].lo > kBlankRanges[rangeIndex].hi )
        {
            return false;
        }
        if( rangeIndex > 0 && kBlankRanges[rangeIndex].lo <= kBlankRanges[rangeIndex - 1].hi + 1 )
        {
            return false;
        }
    }
    return true;
}

static_assert( blankRangesAreCanonical(),
               "kBlankRanges must stay sorted, non-overlapping and MERGED — hasVisibleContent binary-searches "
               "it; re-derive with test/derive_blankcodepoints.py rather than hand-editing rows" );

// does this code point render as nothing? (binary search over the merged ranges above)
inline bool isBlankCodePoint( std::uint32_t codePoint ) noexcept
{
    // the first row whose `lo` is ABOVE codePoint; the candidate is therefore the row before it.
    const BlankCodePointRange* above = std::upper_bound(
        std::begin( kBlankRanges ), std::end( kBlankRanges ), codePoint,
        []( std::uint32_t probe, const BlankCodePointRange& row ) noexcept { return probe < row.lo; } );

    return above != std::begin( kBlankRanges ) && codePoint <= ( above - 1 )->hi;
}

// One decoded UTF-8 scalar. `seqLength == 0` means the bytes at that offset are NOT valid UTF-8 — the caller
// decides what that means (hasVisibleContent rules it CONTENT), which is why this returns the fact rather than
// substituting U+FFFD.
struct DecodedCodePoint
{
    std::uint32_t codePoint;   // the scalar value; meaningless when seqLength == 0
    int           seqLength;   // 1..4 bytes consumed, or 0 ⇒ invalid
};

// decode the UTF-8 sequence starting at `byteOffset`. Factored out because TWO walks below need it (the
// predicate and the refusal's spelling), and a duplicated shift-and-mask decoder is precisely the Type-2 clone
// family §H3 had to unpick in mcpjson.h — on a scan that decides what a request MEANS.
inline DecodedCodePoint decodeUtf8At( std::string_view text, std::size_t byteOffset ) noexcept
{
    // utf8SeqLen is fully validating (0 on a bad continuation, an overlong form, a surrogate half or a tail
    // truncated by the buffer end), so everything below it is a well-formed U+0000..U+10FFFF scalar value.
    const int seqLength = jsonesc::utf8SeqLen( text.data(), byteOffset, text.size() );
    if( seqLength == 0 )
    {
        return { 0, 0 };
    }

    const unsigned char lead = static_cast<unsigned char>( text[ byteOffset ] );
    std::uint32_t codePoint = seqLength == 1 ? std::uint32_t( lead )
                                             : std::uint32_t( lead & ( 0xFF >> ( seqLength + 1 ) ) );
    for( int continuationIndex = 1; continuationIndex < seqLength; ++continuationIndex )
    {
        codePoint = ( codePoint << 6 )
                  | std::uint32_t( static_cast<unsigned char>( text[ byteOffset + std::size_t( continuationIndex ) ] ) & 0x3F );
    }

    return { codePoint, seqLength };
}

// does `payload` contain at least one code point that occupies a visible column? (See THE RULING at the top
// of this file for the derived "no content" set and why the line is drawn where it is; src/mcp.h's ITEM A block
// has the edit-verb ruling this grew out of, and its SCOPE.)
inline bool hasVisibleContent( std::string_view payload ) noexcept
{
    for( std::size_t byteOffset = 0; byteOffset < payload.size(); )
    {
        const DecodedCodePoint decoded = decodeUtf8At( payload, byteOffset );
        if( decoded.seqLength == 0 )
        {
            return true; // invalid UTF-8 — content, by the ruling
        }
        if( !isBlankCodePoint( decoded.codePoint ) )
        {
            return true; // a code point that renders — content
        }

        byteOffset += std::size_t( decoded.seqLength );
    }
    return false;
}

// how many code points does this all-blank payload have, and how do they SPELL? — the got-clause for the
// refusal, and the reason it is a spelling and not an echo: every code point in here renders as nothing or is a
// raw control, so echoing the bytes would paste a C1 control or a bidi override into a client-facing message
// (§B4's defect, and the F3 byte one screen up in this file). `U+200E` is a caller can grep for; the character
// itself is not. Capped at kBlankSpellingMaxCodePoints so a multi-megabyte blank payload cannot mint a
// multi-megabyte refusal frame — the amplification cappedEcho exists to prevent, on the same path.
//
// Returns { 0, "" } for an EMPTY payload: an omitted argument and `new_body:""` were ruled the SAME refusal in
// §H2 and stay byte-identical, so nothing is appended for them. Only a payload that was actually SENT and
// carries nothing gains the clause — because for that one, "missing required field" alone reads as "you sent
// no new_body", which is false and sends the caller back to re-paste the same invisible bytes.
inline constexpr std::size_t kBlankSpellingMaxCodePoints = 8;

inline std::pair<std::size_t, std::string> blankPayloadSpelling( std::string_view payload )
{
    std::size_t codePointCount = 0;
    std::string spelling;

    for( std::size_t byteOffset = 0; byteOffset < payload.size(); )
    {
        const DecodedCodePoint decoded = decodeUtf8At( payload, byteOffset );
        if( decoded.seqLength == 0 )
        {
            return { 0, {} }; // not an all-blank payload at all — caller's guard failed
        }

        if( codePointCount < kBlankSpellingMaxCodePoints )
        {
            char hex[16] = {};
            std::snprintf( hex, sizeof( hex ), "U+%04X", decoded.codePoint );
            if( !spelling.empty() )
            {
                spelling += ' ';
            }
            spelling += hex;
        }
        ++codePointCount;
        byteOffset += std::size_t( decoded.seqLength );
    }

    if( codePointCount > kBlankSpellingMaxCodePoints )
    {
        spelling += " …";
    }
    return { codePointCount, spelling };
}

}   // namespace rw
