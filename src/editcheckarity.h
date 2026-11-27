#pragma once
// editcheckarity.h — the ARITY RANGE one definition accepts, behind --edit-check's incompatible= (editcheck.h
// editCheckIncompatibleFlags): the family shape plus the explicit language layer for C, C++, Rust and Go.
//
// The field report (verb-audit2, 2026-11-27): after a REQUIRED parameter was added — params_was="3" params_now="4" — the
// answer read incompatible="0" on C (jq), Rust (zed) and Go (cockroach) beside 9, 7 and 4 callers that still pass the old
// count, while TypeScript flagged 36/36. The arity test was not missing; its INPUT was. ingest's call-comparable arity
// (Symbol::arityExact, ingest_metrics.h cc_paramShape) is gated to the languages whose default/variadic forms it reads off
// the parse tree, and C, Rust and Go are not among them, so every definition there was a wildcard. A C++ definition that
// already carried a default was one too: arityExact 0 means "a range", and nothing said which range.
//
// THE FAMILY SHAPE: per overload, the [min, max] arguments a call may pass (max = kEditCheckNoMaxArity for a variadic),
// plus how a receiver shifts that range for one call form. A call is flagged only when NO overload's range accepts its
// counted argument count (editcheck.h editCheckIncompatibleFlags) — the one-sided rule every language already follows.
//
// THE LANGUAGE LAYER (editCheckArityFromSignature): the parameter list is read off the definition's SOURCE TEXT
// (comment-blanked, editcheckdecl.h EditCheckSources), the way the C/C++ declaration identity reads parameter types — no
// new ingest fact, so no cache, graph-edge or ranking change. Per language:
//   * C    — `(void)` is 0; a trailing `...` is variadic; `()` declares NO prototype (C17), so any count compiles: no
//            bound. A K&R list (`f( a, b ) int a; …`) counts its identifiers. A member call (`s->f( … )`) goes through a
//            field, never to this function.
//   * C++  — read only where ingest's arityExact is 0 (an exact list keeps ingest's answer byte for byte): each `= v`
//            default lowers min by one, a `...` or a pack (`Args... a`) lifts max. Declaration-side defaults come from
//            editcheckdecl.h editCheckMinArity, as for an exact list.
//   * Rust — no defaults or overloads; a first `self` / `&self` / `&mut self` / `self: T` entry is the RECEIVER: a method
//            call `x.m( a )` omits it, a path call `T::m( &x, a )` writes it. A function without one is never reached by
//            a method call.
//   * Go   — no defaults or overloads; `a, b int` is two parameters in one declaration (the cross-check below counts
//            declarations); `xs ...T` is variadic; a METHOD (`func ( r *T ) M( … )`) may also be called through a method
//            expression `T.M( r, … )`, one argument more.
// NEVER A GUESS: a list the reader cannot hold to the indexed parameter count (Symbol::params), a list that does not close,
// a macro standing where parameters belong (`f( ARGS )`), an unreadable file, or a signature past kEditCheckSigCap is
// UNREAD — the answer discloses it (arity_unknown=) and the definition stays a wildcard, so no caller is flagged against a
// count nobody read, and incompatible="0" beside it is not a "compatible".
// RESIDUAL, stated: Go's indexed params counts a method's RECEIVER list (ingest_metrics.h countParams takes the first
// parameter list), so a Go method's list is cross-checked on its receiver alone.

#include "model.h"
#include "langfacts.h"          // langFacts(l).arityReader: which reader below a language takes
#include "editcheckdecl.h"     // EditCheckSources / kEditCheckSigCap / isDefinitionNotDeclaration
#include "cppscopechain.h"     // editCheckParamOpen / editCheckSplitParams — the one parameter-list opener and splitter
#include "infra/namesplit.h"   // namesplit::isIdentChar
#include "infra/shellword.h"   // shellword::trimView

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::uint16_t kEditCheckNoMaxArity = 0xFFFF;

// How a receiver moves the accepted count for one call form. The METHOD form is a member call written on a receiver with
// no explicit scope (Reference::memberCall, qualifier empty: `x.m( a )`, `s->f( a )`); a path call (`S::m( &x, a )`) carries
// its scope in Reference::qualifier and writes every argument — Rust records memberCall on both shapes.
enum class EditCheckReceiver : std::uint8_t
{
    None,           // the list is the call's argument list for every form
    RustSelf,       // the list's first entry is `self`: the method form passes one fewer
    GoMethod,       // a method: a method expression `T.M( r, … )` passes one more
    FreeFunction,   // a C / Rust function: the method form `x.f()` / `s->f()` calls something else
};

struct EditCheckArity
{
    std::uint16_t     min      = 0;
    std::uint16_t     max      = kEditCheckNoMaxArity;
    EditCheckReceiver receiver = EditCheckReceiver::None;
    bool              known    = false;   // false: a wildcard — accepts every call
    bool              unread   = false;   // a C/C++/Rust/Go list this layer could not read: disclosed as arity_unknown=
};

// Does a call passing `argCount` arguments, in the method form or not (see EditCheckReceiver), fit this range?
inline bool editCheckArityRangeAccepts( const EditCheckArity& a, std::uint16_t argCount, bool methodForm ) noexcept
{
    if( !a.known || ( a.receiver == EditCheckReceiver::FreeFunction && methodForm ) )
    {
        return true;
    }
    std::uint32_t lo = a.min, hi = a.max;
    if( a.receiver == EditCheckReceiver::RustSelf && methodForm )
    {
        lo = lo > 0 ? lo - 1 : 0;
        hi = ( hi == kEditCheckNoMaxArity || hi == 0 ) ? hi : hi - 1;
    }
    if( a.receiver == EditCheckReceiver::GoMethod && hi != kEditCheckNoMaxArity )
    {
        ++hi;
    }
    return lo <= argCount && argCount <= hi;
}

// The languages this layer reads (langfacts.h arityReader). Every other language keeps ingest's arityExact answer.
inline bool editCheckArityLayerLang( Lang l ) noexcept
{
    return langFacts( l ).arityReader != ArityReader::None;
}

namespace arity_detail
{
using rw::shellword::trimView;   // the one both-ends ASCII whitespace trim

inline bool isIdentifier( std::string_view s ) noexcept
{
    if( s.empty() || ( s[0] >= '0' && s[0] <= '9' ) )
    {
        return false;
    }
    for( const char c : s )
    {
        if( !namesplit::isIdentChar( c ) )
        {
            return false;
        }
    }
    return true;
}

// `ARGS` or `PARAMS( x )`: an ALL-CAPS identifier standing where a parameter belongs — it may expand to any number of them.
inline bool isMacroEntry( std::string_view e ) noexcept
{
    const std::size_t      open = e.find( '(' );
    const std::string_view head = trimView( open == std::string_view::npos ? e : e.substr( 0, open ) );
    if( !isIdentifier( head ) || ( open != std::string_view::npos && e.back() != ')' ) )
    {
        return false;
    }
    bool letter = false;
    for( const char c : head )
    {
        if( c >= 'a' && c <= 'z' )
        {
            return false;
        }
        letter = letter || ( c >= 'A' && c <= 'Z' );
    }
    return letter;
}

// Rust: `self`, `mut self`, `&self`, `&mut self`, `&'a self`, `&'a mut self`, `self: Box<Self>`, `mut self: T`.
inline bool isRustSelf( std::string_view e ) noexcept
{
    std::string_view s = trimView( e.substr( 0, e.find( ':' ) ) );
    if( !s.empty() && s.front() == '&' )
    {
        s = trimView( s.substr( 1 ) );
        if( !s.empty() && s.front() == '\'' )
        {
            const std::size_t sp = s.find_first_of( " \t\r\n" );
            s = ( sp == std::string_view::npos ) ? std::string_view() : trimView( s.substr( sp ) );
        }
    }
    if( s.size() > 4 && s.substr( 0, 3 ) == "mut" && !namesplit::isIdentChar( s[3] ) )
    {
        s = trimView( s.substr( 3 ) );
    }
    return s == "self";
}

// The trimmed entries of the list opening at `open`; `ok` is false when it does not close or holds an empty entry
// (a trailing comma, legal in Rust and Go, is dropped first). `defaulted` counts the `= v` entries.
struct ParamEntries
{
    std::vector<std::string_view> entries;
    std::uint32_t                 defaulted = 0;
    bool                          ok        = false;
};

inline ParamEntries splitEntries( std::string_view text, std::size_t open )
{
    ParamEntries             out;
    const EditCheckRawParams raw = editCheckSplitParams( text, open );
    if( !raw.closed )
    {
        return out;
    }
    for( std::size_t k = 0; k < raw.text.size(); ++k )
    {
        out.entries.push_back( trimView( raw.text[k] ) );
        out.defaulted += raw.defaulted[k] ? 1u : 0u;
    }
    if( out.entries.size() > 1 && out.entries.back().empty() )
    {
        out.entries.pop_back();   // `( a: i32, b: i32, )`
    }
    if( out.entries.size() == 1 && out.entries[0].empty() )
    {
        out.entries.clear();      // `()`
    }
    out.ok = std::none_of( out.entries.begin(), out.entries.end(), []( std::string_view e ) { return e.empty(); } );
    return out;
}

// Go: does the entry start with a parameter NAME (`a int`, `xs ...T`) rather than a type (`int`, `chan int`, `func()`)?
inline bool goNamedEntry( std::string_view e ) noexcept
{
    std::size_t i = 0;
    while( i < e.size() && namesplit::isIdentChar( e[i] ) )
    {
        ++i;
    }
    const std::string_view head = e.substr( 0, i );
    const bool keyword = head == "chan" || head == "func" || head == "map" || head == "struct" || head == "interface";
    return i > 0 && i < e.size() && ( e[i] == ' ' || e[i] == '\t' || e[i] == '\n' || e[i] == '\r' ) && !keyword;
}

// Go counts DECLARATIONS for params: in a named list a bare-name entry (`a` of `a, b int`) shares the next entry's type.
inline std::uint32_t goDeclarations( const std::vector<std::string_view>& entries ) noexcept
{
    const bool named = std::any_of( entries.begin(), entries.end(), goNamedEntry );
    std::uint32_t decls = 0;
    for( const std::string_view e : entries )
    {
        decls += ( named && isIdentifier( e ) ) ? 0u : 1u;
    }
    return decls;
}

// Go: is the text before the name `func (` — a receiver list, i.e. a method? `recvOpen` gets that list's '('.
inline bool goMethod( std::string_view text, std::size_t nameAt, std::size_t& recvOpen ) noexcept
{
    const std::size_t fn = text.find( "func" );
    if( fn == std::string_view::npos || fn >= nameAt )
    {
        return false;
    }
    recvOpen = text.find_first_not_of( " \t\r\n", fn + 4 );
    return recvOpen != std::string_view::npos && recvOpen < nameAt && text[ recvOpen ] == '(';
}

inline std::uint32_t variadicEntries( const std::vector<std::string_view>& entries ) noexcept
{
    return std::uint32_t( std::count_if( entries.begin(), entries.end(), []( std::string_view e ) { return e.find( "..." ) != std::string_view::npos; } ) );
}

inline EditCheckArity rangeOf( std::uint32_t n, std::uint32_t optional, bool variadic, EditCheckReceiver receiver ) noexcept
{
    EditCheckArity a{};
    a.min      = std::uint16_t( n > optional ? n - optional : 0 );
    a.max      = variadic ? kEditCheckNoMaxArity : std::uint16_t( n );
    a.receiver = receiver;
    a.known    = n < kEditCheckNoMaxArity;
    a.unread   = !a.known;
    return a;
}
// ── THE LANGUAGE LAYER ─────────────────────────────────────────────────────────────────────────────────────────
// One reader per language over the definition's split parameter list (`list`, `text` the signature it was read from,
// `open` where the list opens); each returns the accepted range or an UNREAD arity (the header's NEVER A GUESS).
struct ArityInput
{
    const Symbol&       sym;
    const ParamEntries& list;
    std::string_view    text;
    std::size_t         open;
    std::uint16_t       declMin;   // editCheckMinArity: params less the defaults a C++ declaration of it carries
};

inline EditCheckArity unreadArity() noexcept
{
    EditCheckArity a{};
    a.unread = true;
    return a;
}

inline bool isVoidList( const std::vector<std::string_view>& e ) noexcept
{
    return e.size() == 1 && e[0] == "void";
}

inline EditCheckArity cArity( const ArityInput& in )
{
    const std::vector<std::string_view>& e = in.list.entries;
    if( e.empty() )
    {
        return EditCheckArity{};   // `f()`: no prototype — any argument count compiles (a wildcard, not unread)
    }
    if( isVoidList( e ) )
    {
        return rangeOf( 0, 0, false, EditCheckReceiver::FreeFunction );
    }
    if( std::any_of( e.begin(), e.end(), isMacroEntry ) || in.list.defaulted > 0 || e.size() != in.sym.params )
    {
        return unreadArity();
    }
    const std::uint32_t variadic = variadicEntries( e );
    return rangeOf( std::uint32_t( e.size() ), variadic, variadic > 0, EditCheckReceiver::FreeFunction );
}

// Read only where ingest called the list a RANGE (arityExact 0): one with neither a default nor a variadic disagrees — unread.
inline EditCheckArity cppArity( const ArityInput& in )
{
    const std::vector<std::string_view>& e        = in.list.entries;
    const std::uint32_t                  variadic = variadicEntries( e );
    if( std::any_of( e.begin(), e.end(), isMacroEntry ) || e.size() != in.sym.params || ( in.list.defaulted == 0 && variadic == 0 ) )
    {
        return unreadArity();
    }
    const std::uint32_t declDefaults = in.sym.params > in.declMin ? std::uint32_t( in.sym.params - in.declMin ) : 0u;
    return rangeOf( std::uint32_t( e.size() ), in.list.defaulted + variadic + declDefaults, variadic > 0, EditCheckReceiver::None );
}

inline EditCheckArity rustArity( const ArityInput& in )
{
    const std::vector<std::string_view>& e = in.list.entries;
    if( in.list.defaulted > 0 || e.size() != in.sym.params )
    {
        return unreadArity();
    }
    const std::uint32_t variadic = variadicEntries( e );   // `...` only in an extern "C" declaration
    const bool          self     = !e.empty() && isRustSelf( e[0] );
    return rangeOf( std::uint32_t( e.size() ), variadic, variadic > 0, self ? EditCheckReceiver::RustSelf : EditCheckReceiver::FreeFunction );
}

// The cross-check: a method's indexed params is its RECEIVER list's (the header's RESIDUAL), a function's its own.
inline EditCheckArity goArity( const ArityInput& in )
{
    const std::vector<std::string_view>& e        = in.list.entries;
    std::size_t                          recvOpen = 0;
    const bool                           method   = goMethod( in.text, in.open, recvOpen );
    const ParamEntries                   recv     = method ? splitEntries( in.text, recvOpen ) : ParamEntries{};
    const std::uint32_t                  checked  = method ? ( recv.ok ? goDeclarations( recv.entries ) : 0u ) : goDeclarations( e );
    const std::uint32_t                  variadic = variadicEntries( e );
    if( in.list.defaulted > 0 || checked != in.sym.params || variadic > 1 )
    {
        return unreadArity();
    }
    return rangeOf( std::uint32_t( e.size() ), variadic, variadic > 0, method ? EditCheckReceiver::GoMethod : EditCheckReceiver::None );
}

// The signature text of `s` (definition: up to its body; declaration: the whole span), "" when it cannot be read whole.
// Go's channel direction `<-` is blanked: it is not an angle the splitter should nest.
inline std::string signatureText( EditCheckSources& sources, const Symbol& s )
{
    const EditCheckFileText& source = sources.text( s.fileId );
    const std::uint32_t      end    = std::min<std::uint32_t>( isDefinitionNotDeclaration( s ) ? s.sigEndByte : s.endByte, std::uint32_t( source.body.size() ) );
    if( !source.whole || end <= s.sigStartByte || end - s.sigStartByte > kEditCheckSigCap )
    {
        return {};
    }
    std::string text = source.body.substr( s.sigStartByte, end - s.sigStartByte );
    for( std::size_t at = langFacts( s.lang ).arityReader == ArityReader::Go ? text.find( "<-" ) : std::string::npos; at != std::string::npos; at = text.find( "<-", at ) )
    {
        text.replace( at, 2, "  " );
    }
    return text;
}
}   // namespace arity_detail

// THE LANGUAGE LAYER's entry: the accepted range of one C/C++/Rust/Go definition, read off its signature text.
inline EditCheckArity editCheckArityFromSignature( EditCheckSources& sources, const Symbol& s, std::uint16_t declMin )
{
    using namespace arity_detail;
    const std::string  text = signatureText( sources, s );
    const std::size_t  open = text.empty() ? std::string::npos : editCheckParamOpen( text, s.name, /*skipGenerics=*/true ).second;
    const ParamEntries list = ( open == std::string::npos ) ? ParamEntries{} : splitEntries( text, open );
    if( !list.ok )
    {
        return unreadArity();
    }
    const ArityInput in{ s, list, text, open, declMin };
    switch( langFacts( s.lang ).arityReader )
    {
        case ArityReader::C:    return cArity( in );
        case ArityReader::Cpp:  return cppArity( in );
        case ArityReader::Rust: return rustArity( in );
        case ArityReader::Go:   return goArity( in );
        case ArityReader::None: break;
    }
    return unreadArity();
}

}   // namespace rw
