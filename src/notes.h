#pragma once

// notes.h — L3 repo field notes: a committed, human-reviewable write-side
// MEMORY keyed to symbols/files, surfaced at retrieval. `--recall` reads docs; this is the missing write
// path keyed to a symbol. The most expensive thing an agent rebuilds across sessions is gotchas (this
// round pinned four), not structure — a note pins one to the symbol it belongs to.
//
// STORE: `.ripwire_notes` at the repo root — a committed, sorted, merge-friendly text file (the B10 sorted-
// acks precedent: two sessions each appending a DIFFERENT note produce two pure, non-overlapping insertions
// a 3-way text merge resolves cleanly). One line per note, in ONE of two shapes:
//     <canonical-id or path>\t<ISO-date>\t<text, no tabs/newlines>                              (legacy, 3 fields)
//     <canonical-id or path>\t<ISO-date>\t<text, no tabs/newlines>\t<HEAD sha>\t<branch>          (provenance-stamped, 5 fields)
// `target` is either a canonical id (path::scope::name, exactly as serialization emits `id=`) or a file path.
//
// PROVENANCE STAMP (the day's costliest lesson: a "done" claim with nothing anchoring it to a commit is
// worthless the moment the tree moves on). --note-add now stamps the writing repo's HEAD sha + branch onto
// every NEW note (main.cpp's --note-add handler resolves them via quality::gitHeadSha / `rev-parse
// --abbrev-ref HEAD` and hands them to addNote). BACKWARD COMPATIBILITY is load-bearing — `.ripwire_notes`
// is a COMMITTED file in real repos, so the format must extend, never break:
//   - `text` itself can never contain a tab (sanitizeField strips them on write), so any tab appearing AFTER
//     the third field is unambiguously the start of the sha/branch suffix — a 3-field legacy line (no such
//     tab) and a 5-field stamped line (two more) coexist in the SAME file and both parse correctly.
//   - a line is only ever WRITTEN with 5 fields when a real sha was resolved; a non-git root or an
//     unresolvable HEAD writes the plain 3-field legacy shape — "no sha shown rather than a wrong one".
//   - `sha`/`branch` default-construct empty, so every existing call site that builds a Note with 3
//     initializers still compiles (aggregate init zero-fills the trailing fields).
//
// PORTABILITY (D5 fix): the path component of `target` is stored ROOT-RELATIVE, never absolute — a note
// committed alongside the repo must resolve on any other checkout, whose crawl root lands somewhere else on
// disk. normalizeNoteTarget() is the ONE seam that enforces this: it canonicalizes an absolute in-root target
// to root-relative on WRITE (see runNotes' --note-add handler in main.cpp) and refuses an outside-root target
// loudly rather than silently writing an entry that can never match anywhere. readNotesRelative() is the READ
// half — it re-normalizes on load so a LEGACY .ripwire_notes written before this fix (absolute targets) keeps
// surfacing correctly without a rewrite. A bare-name SYM target (no scope, e.g. a free function — canonicalId
// degrades to just `name`) has no path component at all and passes through both untouched.
//
// INERTNESS CONTRACT: an absent OR empty notes file yields an empty NoteIndex → surfacing emits ZERO bytes,
// so every verb's output is byte-identical to the pre-feature output (gated by cmp). Notes are DATA, never
// instructions — the retrieval-time emitter (serialize.h::renderNoteChildren) escapes them and never
// interprets them.
//
// Deterministic + degrade-don't-throw: readNotes tolerates anything a sorted-write does not itself guarantee
// (out-of-order lines from a hand edit or an older-revision merge, CRLF from a Windows checkout, blank/comment
// lines) and self-heals to canonical order on the next write; a malformed line degrades+skips, never throws.

#include "model.h"         // HashMap<> — the flat, cache-friendly lookup index (never std::unordered_map)
#include "infra/Diagnostics.h"   // DEGRADED_PATH_ALERT — the degrade path for a malformed line / unwritable file
#include "arch.h"          // D5: relForHash — the SAME lexical, no-I/O root-relative strip the baseline sidecars use
#include "infra/blanktext.h"     // §S3: rw::hasVisibleContent — the ONE "present but carries nothing" predicate

#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw::notes
{

// the committed store, at the repo root — mirrors quality.h's kAcksFile convention.
inline const char* kNotesFile = ".ripwire_notes";

// one field note. POD-ish; owns its strings (a note file is small, so simplicity beats SoA here).
struct Note
{
    std::string target;   // a canonical id (path::scope::name) or a file path — matched verbatim at surfacing
    std::string date;     // ISO short date (YYYY-MM-DD): git's committer clock at add time, NOT wall time
    std::string text;     // the note body — no tabs / newlines (stripped on add); may hold XML metachars
    std::string sha;      // provenance: the writing repo's HEAD sha at add time, full 40/64-hex ("" = legacy/unstamped — never a WRONG sha, only an absent one)
    std::string branch;   // provenance: `rev-parse --abbrev-ref HEAD` at add time ("HEAD" on a detached checkout; "" alongside an empty sha)
};

// canonical total order: (target, date, text, sha, branch) ascending — a sort has no tolerance band, so it
// must be a TOTAL order for byte-stable output (the det-gate discipline). Matches the acks file's
// merge-friendly write. sha/branch are the LAST tie-breakers so a legacy (unstamped) and a provenance-stamped
// note that otherwise share (target,date,text) sort deterministically regardless of read/insertion order —
// empty sha/branch sort first (a legacy entry precedes a stamped duplicate of the same content).
inline bool noteLess( const Note& a, const Note& b ) noexcept
{
    if( a.target != b.target )
    {
        return a.target < b.target;
    }
    if( a.date != b.date )
    {
        return a.date < b.date;
    }
    if( a.text != b.text )
    {
        return a.text < b.text;
    }
    if( a.sha != b.sha )
    {
        return a.sha < b.sha;
    }
    return a.branch < b.branch;
}

inline void sortNotes( std::vector<Note>& notes )
{
    std::stable_sort( notes.begin(), notes.end(), noteLess );
}

// root + "/" + kNotesFile — the notes file lives ALONGSIDE the analyzed tree (its targets are root-relative
// canonical ids), so it is keyed off the ingest root exactly as invoked.
inline std::string notesPath( const std::string& root )
{
    std::string p = root;
    if( !p.empty() && p.back() != '/' )
    {
        p += '/';
    }
    p += kNotesFile;
    return p;
}

// collapse a raw field to a single tab/newline-free, edge-trimmed line — enforces the format invariant at the
// write seam so a pasted multi-line note can never corrupt the tab-delimited file.
//
// This function is about the FILE FORMAT (no tabs, no newlines, no edge spaces) and nothing else. It is NOT
// the "does this field carry anything" predicate — see sanitizeNoteField below for why the two were confused
// and what it cost.
inline std::string sanitizeField( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( char c : s )
    {
        out += ( c == '\t' || c == '\n' || c == '\r' ) ? ' ' : c;
    }
    const std::size_t a = out.find_first_not_of( ' ' );
    if( a == std::string::npos )
    {
        return {};
    }
    const std::size_t b = out.find_last_not_of( ' ' );
    return out.substr( a, b - a + 1 );
}

// ── §S3 (capture-audit-4, 2026-07-30) — sanitize AND decide, in one call ──────────────────────────────────
//
// `--note-add` used to sanitize a field and then ask `.empty()` about the result. That pair is a THIRD
// spelling of "present but carries nothing", and it is the weakest of the three: sanitizeField maps only
// \t \n \r to a space and trims ASCII spaces, so an ASCII-blank note was refused while **6 of 6** other
// blank classes were accepted and COMMITTED into `.ripwire_notes` — NBSP, ZWSP, BOM, U+2800 BRAILLE PATTERN
// BLANK, a bidi RLO, and a raw VT (0x0B) written verbatim into a text file this tool tells users to commit
// and merge. Same equivalence class the MCP edit verbs' §H2/ITEM A ruling already closed, one file over.
//
// So the verdict comes from `rw::hasVisibleContent` — the ONE derived predicate (src/infra/blanktext.h), which
// mcp.h's edit payloads read too — and it is returned TOGETHER with the sanitized text rather than left for
// the caller to ask separately. A caller cannot sanitize a note field without being handed the answer to
// "is there anything in it", which is exactly the step the old two-call shape let a call site skip.
//
// Deliberately NOT applied to the branch name (main.cpp sanitizes that with the plain sanitizeField): a
// branch is provenance the tool resolved itself, never user payload, and an empty one already means "no
// stamp" by design.
struct NoteField
{
    std::string text;                 // the sanitized, single-line, tab-free, edge-trimmed field
    bool        hasContent = false;   // rw::hasVisibleContent( text ) — false ⇒ nothing a reader could see
};

inline NoteField sanitizeNoteField( std::string_view raw )
{
    NoteField field{ sanitizeField( raw ), false };
    field.hasContent = rw::hasVisibleContent( field.text );
    return field;
}

// ── R6: decision-shaped note heuristic (write-side, interactive nudge only) ────────────────────────────
//
// A note that names WHAT was decided and WHY retrieves better than plain description — "chose refcount
// over raw pointer because the arena outlives the handle" tells a future reader what to do differently;
// "watch the lifetime here" does not. This table is a NUDGE trigger, never a gate: --note-add always
// writes whatever text it's given, unconditionally. isDecisionShaped() only decides whether runNotes'
// --note-add handler (main.cpp) prints a one-line stderr tip alongside the write — pure substring match,
// no locale/case-folding, so the same text always yields the same verdict on any machine (determinism
// contract). This function has no I/O and never touches stdout, so it cannot contaminate --note-add's
// printed line or any later --for/--expand/default-map XML emission.
inline constexpr std::array<std::string_view, 8> kDecisionMarkers = {
    "because", "chose", "over", "instead", "broke", "->", "vs", "due to"
};

inline bool isDecisionShaped( std::string_view text )
{
    for( std::string_view marker : kDecisionMarkers )
    {
        if( text.find( marker ) != std::string_view::npos )
        {
            return true;
        }
    }
    return false;
}

// ── D5: root-relative target normalization (the portable-notes seam) ───────────────────────────────────
//
// A target is either a bare file path (no "::") or a canonical id `path::scope::name`. A file path never
// contains a literal "::" (only '/' separators), so splitting on the FIRST "::" cleanly isolates the path
// prefix from the scope::name suffix regardless of how many "::"-joined scope segments follow (nested
// namespaces/classes). A bare-name SYM target (canonicalId degrades to just `name` when scope is empty) has
// no "::" and no leading '/' either, so it round-trips through relForHash unchanged.
//
// Sets `outsideRoot` when an ABSOLUTE path target does not resolve under `root` — the write-time caller
// refuses the add loudly rather than silently committing an entry no checkout could ever match. A relative
// target that lexically climbs above the root (`../…`) is refused the same way. Pure, no I/O — mirrors
// relForHash's determinism contract exactly (arch.h §S2).
inline std::string normalizeNoteTarget( std::string_view target, std::string_view root, bool& outsideRoot )
{
    outsideRoot = false;
    const std::size_t      sep      = target.find( "::" );
    const std::string_view pathPart = ( sep == std::string_view::npos ) ? target : target.substr( 0, sep );
    const std::string_view rest     = ( sep == std::string_view::npos ) ? std::string_view{} : target.substr( sep );   // includes the leading "::"

    if( pathPart.empty() )
    {
        return std::string( target ); // degenerate target — pass through untouched, never throw
    }

    if( pathPart.front() == '/' )
    {
        // absolute — must land UNDER root (same root-trim + whole-component compare as relForHash) or refuse.
        std::string_view rootTrim = root;
        while( rootTrim.size() > 1 && rootTrim.back() == '/' )
        {
            rootTrim.remove_suffix( 1 );
        }
        const bool underRoot = !rootTrim.empty() && rootTrim != "." && rootTrim.front() == '/'
            && pathPart.size() >= rootTrim.size() && pathPart.compare( 0, rootTrim.size(), rootTrim ) == 0
            && ( pathPart.size() == rootTrim.size() || pathPart[ rootTrim.size() ] == '/' );
        if( !underRoot ) { outsideRoot = true; return std::string( target ); }
    }

    // (copy-init, not `Type rel( expr );` — the latter's a single-call-expression "parameter" that tree-sitter's
    // C++ grammar mis-shapes as a function declarator, spuriously indexing a symbol named `rel`.)
    std::string rel = std::string( relForHash( pathPart, root ) );
    // a RELATIVE target that lexically escapes upward past the root is also "outside" — refuse rather than
    // store a path a different checkout can't resolve (relForHash never touches ".." — only a prefix strip).
    if( rel == ".." || ( rel.size() >= 3 && rel.compare( 0, 3, "../" ) == 0 ) ) { outsideRoot = true; return std::string( target ); }

    rel.append( rest );
    return rel;
}

// abbreviate a stored sha for TERSE display at surfacing sites (--notes, <note sha="…">, the MCP notes
// array) — the file always stores the FULL sha (unambiguous, `git show`-able); only the presentation layer
// shortens it. 7 hex chars matches git's own default --abbrev; shorter input passes through unchanged.
inline std::string shortSha( std::string_view sha )
{
    return std::string( sha.size() > 7 ? sha.substr( 0, 7 ) : sha );
}

// split the tab-delimited remainder AFTER a line's (target,date) prefix into (text,sha,branch) — the ONE
// decision behind both shapes readNotes accepts. `rest` is never tab-free by accident: sanitizeField strips
// every tab from `text` on write, so a tab found HERE is unambiguously the start of the provenance suffix a
// stamped write appended — never mistaken text. No third tab ⇒ the legacy 3-field shape (sha/branch stay
// empty); a third but no fourth ⇒ a hand-edited 4-field oddity (sha only, degrade rather than reject).
inline void splitNoteTail( std::string_view rest, std::string& text, std::string& sha, std::string& branch )
{
    const std::size_t t3 = rest.find( '\t' );
    if( t3 == std::string_view::npos ) { text = std::string( rest ); return; }
    text = std::string( rest.substr( 0, t3 ) );
    const std::string_view tail = rest.substr( t3 + 1 );
    const std::size_t t4 = tail.find( '\t' );
    if( t4 == std::string_view::npos ) { sha = std::string( tail ); return; }
    sha    = std::string( tail.substr( 0, t4 ) );
    branch = std::string( tail.substr( t4 + 1 ) );
}

// tolerant read (readAckRecords precedent): skip blank/'#'/CRLF; a line missing either of the first two tabs
// degrades+skips. splitNoteTail (above) owns the legacy-vs-stamped decision for everything after them.
inline std::vector<Note> readNotes( const std::string& path )
{
    std::vector<Note> notes;
    std::ifstream f( path );
    if( !f )
    {
        return notes;
    }
    std::string line;
    while( std::getline( f, line ) )
    {
        while( !line.empty() && ( line.back() == '\r' || line.back() == '\n' ) )
        {
            line.pop_back(); // CRLF tolerance
        }
        if( line.empty() || line[0] == '#' )
        {
            continue;
        }
        const std::size_t t1 = line.find( '\t' );
        const std::size_t t2 = ( t1 == std::string::npos ) ? std::string::npos : line.find( '\t', t1 + 1 );
        if( t1 == std::string::npos || t2 == std::string::npos )
        { DEGRADED_PATH_ALERT( "notes: malformed line skipped (want <target>\\t<date>\\t<text>)" ); continue; }
        Note n;
        n.target = line.substr( 0, t1 );
        n.date   = line.substr( t1 + 1, t2 - t1 - 1 );
        splitNoteTail( std::string_view( line ).substr( t2 + 1 ), n.text, n.sha, n.branch );
        if( n.target.empty() ) { DEGRADED_PATH_ALERT( "notes: empty-target line skipped" ); continue; }
        notes.push_back( std::move( n ) );
    }
    return notes;
}

// D5 read-side normalization: re-relativize every target against `root` on load. This is what keeps a
// LEGACY .ripwire_notes (absolute targets, written before this fix or hand-edited) surfacing correctly on
// the current checkout without a rewrite. Best-effort like the rest of this file: an out-of-root absolute
// target degrades to itself unchanged (normalizeNoteTarget's outsideRoot signal is ignored here — a read
// never fails; the entry simply stays dangling, which --notes already reports).
inline std::vector<Note> readNotesRelative( const std::string& path, const std::string& root )
{
    std::vector<Note> notes = readNotes( path );
    for( Note& n : notes )
    {
        bool outsideRoot = false;
        n.target = normalizeNoteTarget( n.target, root, outsideRoot );
    }
    return notes;
}

// the exact data line writeNotes emits for one Note — shared by writeNotes (per-line) and addNote (the
// printed confirmation), so the two can never drift apart. A note with an empty sha writes the plain
// LEGACY 3-field shape (never a hollow "\t\t" suffix); a stamped one (sha non-empty) always writes both
// trailing fields, even when branch itself is empty (a resolvable HEAD with an unresolvable branch name
// — rare, but the sha alone is still honest provenance worth keeping).
inline std::string noteLine( const Note& n )
{
    std::string line = n.target + "\t" + n.date + "\t" + n.text;
    if( !n.sha.empty() )
    {
        line += "\t" + n.sha + "\t" + n.branch;
    }
    return line;
}

// write SORTED (self-healing: canonical order regardless of the on-disk shape read). The leading '#' header is
// constant across every version (identical in a merge → never a conflict) and is skipped by readNotes.
inline bool writeNotes( const std::string& path, std::vector<Note> notes )
{
    sortNotes( notes );
    std::ofstream f( path, std::ios::trunc );
    if( !f ) { DEGRADED_PATH_ALERT( "notes: cannot write notes file" ); return false; }
    f << "# ripwire field notes v1 — one per line: <canonical-id or path> <TAB> <ISO-date> <TAB> <text> [<TAB> <HEAD sha> <TAB> <branch>]. Kept SORTED (merge-friendly union); dates are git committer-clock, not wall time; the trailing sha/branch pair is present only on provenance-stamped notes.\n";
    for( const Note& n : notes )
    {
        f << noteLine( n ) << '\n';
    }
    return bool( f );
}

// append (target,date,text[,sha,branch]), re-sort, write; return the EXACT written data line so --note-add
// can print precisely what it wrote, or "" on a write failure. Idempotent: an identical (target,date,text,
// sha,branch) is not duplicated (re-running the same add is a no-op line, still printed) — sha/branch are
// part of the identity so a legacy unstamped entry and a later re-add of the SAME text from a real commit
// are both kept (they are genuinely different provenance claims, not a duplicate).
inline std::string addNote( const std::string& path, std::string_view target, std::string_view date, std::string_view text,
                            std::string_view sha = {}, std::string_view branch = {} )
{
    std::vector<Note> notes = readNotes( path );
    Note n{ std::string( target ), std::string( date ), std::string( text ), std::string( sha ), std::string( branch ) };
    bool dup = false;
    for( const Note& e : notes )
    {
        if( e.target == n.target && e.date == n.date && e.text == n.text && e.sha == n.sha && e.branch == n.branch )
        {
            dup = true;
            break;
        }
    }
    if( !dup )
    {
        notes.push_back( n );
    }
    if( !writeNotes( path, std::move( notes ) ) )
    {
        return {};
    }
    return noteLine( n );
}

// ── retrieval-time surfacing index ───────────────────────────────────────────────────────────────────────
// target-string → the notes on it (in sorted/file order). Built once per run from the notes file; looked up
// by canonical id (a symbol) and by path (a file) as the emitter walks each surfaced element. `notes` here
// are ALREADY root-relative (readNotesRelative, called by loadNoteIndex) — `root` is carried alongside so a
// surfacing site holding a CRAWL-ROOT-PREFIXED path (ing.files[...], spelled `<root>/<relative>` verbatim —
// see arch.h §S2) can relativize it the same way (relForHash(rawPath, ni->root)) before calling find().
struct NoteIndex
{
    std::string                                      root;       // D5: the ingest root this index was loaded for
    std::vector<Note>                                notes;      // owns storage, sorted (byte-stable emit order)
    HashMap<std::string, std::vector<std::uint32_t>> byTarget;   // target → indices into `notes`

    bool empty() const noexcept { return notes.empty(); }

    // nullptr ⇒ no notes on this target (the INERT common case) → the emitter writes zero bytes.
    const std::vector<std::uint32_t>* find( const std::string& target ) const
    {
        const auto it = byTarget.find( target );
        return it == byTarget.end() ? nullptr : &it->second;
    }
};

inline NoteIndex buildNoteIndex( std::vector<Note> notes, std::string root = {} )
{
    sortNotes( notes );
    NoteIndex idx;
    idx.root = std::move( root );
    idx.notes = std::move( notes );
    idx.byTarget.reserve( idx.notes.size() );   // reserve to expected size — skip the ankerl rehash cascade
    for( std::uint32_t i = 0; i < idx.notes.size(); ++i )
    {
        idx.byTarget[idx.notes[i].target].push_back( i );
    }
    return idx;
}

inline NoteIndex loadNoteIndex( const std::string& root )
{
    return buildNoteIndex( readNotesRelative( notesPath( root ), root ), root );
}

}   // namespace rw::notes
