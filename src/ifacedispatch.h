#pragma once
// ifacedispatch.h — lane L6: a call through an INTERFACE-, TRAIT- or ABSTRACT-typed receiver names the implementors' methods
// that can run there (test/ifacedispatchcheck.sh; reports/gap-ideas.md "L6 iface-typed dispatch rows").
//
// A programmer facing `pkg.Package( info, f )` on an interface value lists the implementors and opens the ones that can run.
// The resolver's name tiers answered by NAME instead: every in-tree definition called `Package`, including a same-named
// interface's implementor elsewhere and an overload of another arity. This tier sits in buildGraph's resolve loop after the
// receiver rules and before the name tiers. When the receiver's recorded type T (ReceiverEvidence::dispatchReceiverOf) is an
// interface or trait, or a class declaring the callee without a body, the candidates are the bodied methods of that name the
// types implementing T own (the extends / implements / `impl T for X` edges, walked down to every depth), plus T's own bodied
// default. One candidate reached through proven edges only is an edge, rendered via="impl" — the only implementor in the tree
// (one outside it, or one a macro other than a mock attribute writes, may exist); otherwise the call is DECLINED with exactly that list (DeclinedSiteKind::Iface, gate="iface").
// No candidate: the tier stays out of the way, and the name tiers answer as before.
//
// EXACT OR NO ROW (fix round 1, reports/dispatch-classes.md §(a) 4 and 5). The one-candidate edge needs the WHOLE in-tree set:
//   * a list some implementor can join with no clause the map reads is OPEN, and the tier steps aside (graph.h implementorsOpen):
//     a Java / Kotlin anonymous class or object expression, a Kotlin `fun interface`, a Rust trait under a mock attribute (all
//     ImplBlock records with no implementor name), and a Java interface with one abstract method, which a lambda implements;
//   * a language that types structurally (TypeScript: an object literal or a matching class conforms unnamed) never proves one
//     candidate; two or more still decline, and cands=K is then a floor (the legend says so);
//   * Rust: an implementor's candidate sits inside its `impl T for X` block (an ImplBlock record's span); an inherent method of
//     X is never one, and a supertrait's method, whose impl block is another trait's, finds none here (the name tiers answer).
//
// The rule reads only the implementors map and the receiver's type, so it is language-neutral; what each language supplies
// is the receiver typing (receiverevidence.h) and, for Rust, the langfacts.h column saying its trait signatures are not
// indexed. C++ keeps its own class identity (resolve.h IdentityNarrower's dispatch split), which graph.h hands to the same
// decision.

#include "model.h"
#include "filter.h"   // isTestSymbol — a declined list names the non-test implementors first
#include "langfacts.h"
#include "receiverevidence.h"
#include "smallvec.h"

#include <algorithm>
#include <cstdint>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// lane lego-transitive fix 1: how an extends/implements edge base→derived was bound (Graph::implementorBound).
//   Proven — the language's own lookup names THIS base: a same-file declaration the clause's enclosing scopes declare
//            (ingest_relations.h localBaseBinding), the file an import binds the name (or its qualifier) to, an included
//            C-family header, the package directory (Java/Kotlin/Go), Ruby's constant scope (RubyBaseScope).
//   ByName — no such evidence, or it named two candidates: the edge rests on the spelling alone.
//   Other  — the evidence names a DIFFERENT same-named type: this edge is the name collision, not a subtype.
// The values order the merge of two references drawing the same edge: the smaller wins (a proven site proves the edge).
enum class BaseBound : std::uint8_t { Proven = 0, ByName = 1, Other = 2 };

// One tier answer: the candidates (ascending ids) and whether a single one is PROVEN (every implements edge to its owner proven).
struct IfaceDispatchAnswer
{
    bool                fired  = false;
    bool                proven = false;
    bool                open   = false;   // the list is what the tree shows of an implementors list it cannot close (openTraitAnswer): never a proof
    std::vector<NodeId> cand;
};

// the lambda-conversion count of lambdaImplements, apart from the tier: per class IDENTITY (the index knows a base by NAME only), the
// abstract (bodyless) member names a class declares, and every class of a lambda-convertible language under its name
class SamCounter
{
public:
    SamCounter( const IngestResult& ing, const ReceiverEvidence& recvEv ) : ing_( ing ), recvEv_( recvEv ) {}

    void addClass( const Symbol& s ) { classesByName_[ s.name ].push_back( s.id ); }   // the identities one name stands for (a package apart)

    // a bodyless member `s` of class `owner`
    void addMember( NodeId owner, const Symbol& s )
    {
        mergeAbstract( abstractNames_[ owner ], AbstractMember{ s.name, std::int32_t( s.params ) }, true );
    }

    // the one class-like symbol of a lambda-convertible language called `name`; kNoNode when none or several share it
    NodeId soleClassNamed( std::string_view name ) const
    {
        const auto it = classesByName_.find( name );
        return it != classesByName_.end() && it->second.size() == 1 ? it->second[ 0 ] : kNoNode;
    }

    // a bodyless member: its name and parameter count (kOverloaded: the class declares the name bodyless more than once)
    static constexpr std::int32_t kOverloaded = -1;
    struct AbstractMember
    {
        std::string_view name;
        std::int32_t     params = 0;
    };

    // the count of distinct abstract member names and what the index cannot vouch for: `doubted`: the count may be BELOW the truth
    // (a base it cannot see adds names; a name a body overrides is dropped by name, an overload it cannot tell apart); `hidden`: a
    // class that may re-declare a name WITH A BODY is out of sight, so the count may also be ABOVE the truth (even a 2 proves nothing)
    struct AbstractCount
    {
        std::size_t n       = 0;
        std::size_t ownN    = 0;   // of n, the class's OWN abstract names: no base's body can override one (the class re-declares it)
        bool        doubted = false;
        bool        hidden  = false;
    };

    // what the walk below the receiver gathered: the abstract names of the classes it named exactly (and their identities)
    struct BaseWalk
    {
        std::vector<AbstractMember>   names;
        std::vector<NodeId>           walked;
        bool                          doubted = false;
        bool                          hidden  = false;
    };

    // does class `cls` own a member of abstract member `m`'s name WITH a body (a Kotlin interface's default, a Java `default` method, an
    // override), and is it exactly the one `m` declares: ONE such body of the same parameter count and `m` not overloaded (an
    // overload by type the index cannot see stays unseen: that is a name match, which `doubted` records)
    struct BodyMatch
    {
        bool any   = false;
        bool exact = false;
    };
    BodyMatch bodyOf( NodeId cls, const AbstractMember& m ) const
    {
        recvEv_.found.clear();
        recvEv_.collectMethods( ing_.symbols[ cls ].name, m.name, cls );
        return BodyMatch{ !recvEv_.found.empty(),
                          recvEv_.found.size() == 1 && m.params != kOverloaded && ing_.symbols[ recvEv_.found[ 0 ] ].params == m.params };
    }

    // add `m` to `into`, one entry per name; a name seen again keeps one entry, its arity `kOverloaded` when the two cannot be told
    // apart (the same class bodyless twice, or two classes with different parameter counts)
    static void mergeAbstract( std::vector<AbstractMember>& into, const AbstractMember& m, bool sameClass )
    {
        if( const auto seen = std::ranges::find( into, m.name, &AbstractMember::name ); seen == into.end() )
        {
            into.push_back( m );
        }
        else if( sameClass || seen->params != m.params )
        {
            seen->params = kOverloaded;
        }
    }

    // append the distinct abstract members of class `id` to `names`
    void addOwnAbstract( NodeId id, std::vector<AbstractMember>& names ) const
    {
        if( const auto it = abstractNames_.find( id ); it != abstractNames_.end() )
        {
            for( const AbstractMember& m : it->second )
            {
                mergeAbstract( names, m, false );
            }
        }
    }

    // breadth-first through ALL the bases the index names exactly (no early stop: a class below may give a name a body), adding their
    // abstract names and identities. A base that is not exactly one class in the tree (a shared name, or none) or a walk the cap cut
    // short leaves the names only a lower bound (`doubted`); one that may be a class hiding an override is `hidden`: a name shared by
    // several classes, or the cap (a name no class in the tree bears is external, and no external type extends an in-tree one)
    void walkAbstractBases( std::vector<std::string_view>& frontier, BaseWalk& w ) const
    {
        std::size_t i = 0;
        for( ; i < frontier.size() && i < ReceiverEvidence::kWalkCap; ++i )
        {
            recvEv_.forEachBase( frontier[ i ], [ & ]( std::string_view base )
            {
                const NodeId only = soleClassNamed( base );
                if( only == kNoNode )
                {
                    w.doubted = true;
                    w.hidden  = w.hidden || classesByName_.contains( base );
                }
                else if( std::ranges::find( frontier, base ) == frontier.end() )
                {
                    frontier.push_back( base );
                    w.walked.push_back( only );
                    addOwnAbstract( only, w.names );
                }
            } );
        }
        if( i < frontier.size() )
        {
            w.doubted = w.hidden = true;
        }
    }

    // the classes of the walk that declare an abstract member of this name
    std::vector<NodeId> declarersOf( std::string_view name, const BaseWalk& w ) const
    {
        std::vector<NodeId> out;
        for( NodeId k : w.walked )
        {
            if( const auto it = abstractNames_.find( k ); it != abstractNames_.end() && std::ranges::contains( it->second, name, &AbstractMember::name ) )
            {
                out.push_back( k );
            }
        }
        return out;
    }

    // a body of abstract member `m` in a class of the walk AT OR BELOW a class declaring it (nearer to the receiver): a body ABOVE the
    // re-declaring class (Base { ap() = 0 } above Mid { override ap( x ): Int }) never runs for it. Below only SOME of the declaring
    // classes (a diamond) cannot be told exact: a loose drop
    BodyMatch bodyBelowDeclarer( const AbstractMember& m, const BaseWalk& w ) const
    {
        const std::vector<NodeId> decl = declarersOf( m.name, w );
        for( NodeId k : w.walked )
        {
            const auto below = [ & ]( NodeId d ) { return recvEv_.inCone( ing_.symbols[ k ].name, ing_.symbols[ d ].name ); };
            if( BodyMatch hit = bodyOf( k, m ); hit.any && std::ranges::any_of( decl, below ) )
            {
                hit.exact = hit.exact && std::ranges::all_of( decl, below );
                return hit;
            }
        }
        return {};
    }

    // the distinct abstract member names of class `c`: its own, plus those of the bases the index names exactly, minus a base's name
    // that some class of the walk gives a body (a sub-interface's or middle interface's `override fun m() = …`, a Java `default`
    // method) AT OR BELOW a class declaring the name, nearer to `c` (a body ABOVE the re-declaring class never runs for it): that name
    // is no abstract member of `c` (matched by NAME, an overload the index cannot tell apart is dropped too, so a drop is `doubted`).
    // `c`'s own abstract name stays (an abstract re-declaration) unless `c` has a bodied member of it too.
    // `exactBases`: false when c's own name is shared, so its base names cannot be told apart per identity (doubted, not walked;
    // hidden when c names any base at all).
    AbstractCount abstractCount( NodeId c, bool exactBases ) const
    {
        BaseWalk                      w;
        std::vector<std::string_view> frontier{ ing_.symbols[ c ].name };
        if( exactBases )
        {
            walkAbstractBases( frontier, w );
        }
        else
        {
            w.doubted = true;
            recvEv_.forEachBase( frontier[ 0 ], [ & ]( std::string_view ) { w.hidden = true; } );
        }
        std::vector<AbstractMember> own;
        addOwnAbstract( c, own );
        AbstractCount ac;
        ac.hidden = w.hidden;
        bool exactDrop = false;   // a body matched an abstract name exactly (name, parameter count, not overloaded)
        bool looseDrop = false;   // a body matched by name only: an overload may remain abstract
        std::vector<AbstractMember> names;
        const auto                  overridden = [ & ]( const AbstractMember& m, bool ownName )
        {
            BodyMatch hit = bodyOf( c, m );
            if( !ownName && !hit.any )
            {
                hit = bodyBelowDeclarer( m, w );
            }
            exactDrop = exactDrop || ( hit.any && hit.exact );
            looseDrop = looseDrop || ( hit.any && !hit.exact );
            return hit.any;
        };
        std::ranges::copy_if( own, std::back_inserter( names ), [ & ]( const AbstractMember& m ) { return !overridden( m, true ); } );
        ac.ownN = names.size();
        std::ranges::copy_if( w.names, std::back_inserter( names ), [ & ]( const AbstractMember& m )
                              { return !std::ranges::contains( own, m.name, &AbstractMember::name ) && !overridden( m, false ); } );
        ac.n = names.size();
        // A base the index cannot see (an external type, a same-named class of another language) may add an abstract name: the count is
        // only a lower bound. But a type that gives a body to names it inherits, every one of them exactly, is far likelier a concrete
        // implementor than an interface left with one external SAM base: such a lower bound is not a doubt (the walk saw what it
        // overrides). A shared base name, the cap and a loose match stay doubts.
        ac.doubted = looseDrop || w.hidden || ( w.doubted && !exactDrop );
        return ac;
    }

private:
    const IngestResult&                            ing_;
    const ReceiverEvidence&                        recvEv_;
    HashMap<NodeId, std::vector<AbstractMember>>   abstractNames_;   // class id → its bodyless members' distinct names
    HashMap<std::string_view, std::vector<NodeId>> classesByName_;   // name → every class-like symbol so named
};

class IfaceDispatch
{
public:
    IfaceDispatch( const IngestResult& ing, const ReceiverEvidence& recvEv, const std::vector<std::vector<NodeId>>& implementors,
                   const std::vector<std::vector<std::uint8_t>>& bound, const std::vector<char>& open )
        : ing_( ing ), recvEv_( recvEv ), implementors_( implementors ), bound_( bound ), open_( open ), sam_( ing, recvEv )
    {
        EXPECTS( bound.empty() || bound.size() == implementors.size(), "buildGraph sizes the bound map with the implementors map" );
        for( const Symbol& s : ing.symbols )
        {
            indexSymbol( s );
        }
        for( const Binding& b : ing.bindings )   // a trait impl block's span, keyed "T\x1fX" (model.h LocalBindKind::ImplBlock)
        {
            if( b.kind == LocalBindKind::ImplBlock && !b.typeName.empty() )
            {
                key_.assign( b.var ).push_back( '\x1f' );
                implBlocks_[ key_.append( b.typeName ) ].push_back( &b );
                traitBlocks_[ b.var ].push_back( &b );
            }
        }
        for( const Symbol& s : ing.symbols )   // RUST-DYN-NAMESAKE: the bodied callables of a trait-impl-block language, by name
        {
            if( langFacts( s.lang ).traitImplBlocks && ReceiverEvidence::callableKind( s.kind ) && s.endByte > s.sigEndByte )
            {
                blockCallables_[ s.name ].push_back( s.id );
            }
        }
    }

    // The tier's answer for a call named `callee` on a receiver typed `type`: fired = false when T is no dispatch type for
    // the callee or no candidate is in the tree.
    IfaceDispatchAnswer answer( NodeId type, std::string_view callee ) const
    {
        IfaceDispatchAnswer out;
        if( type == kNoNode || type >= ing_.symbols.size() || !dispatchesThrough( type, callee ) )
        {
            return out;
        }
        const std::vector<Row>& rows   = closureOf( type );
        const auto              opened = [ & ]( NodeId t ) { return ( t < open_.size() && open_[ t ] != 0 ) || lambdaImplements( t ); };
        if( opened( type ) || std::ranges::any_of( rows, [ & ]( const Row& row ) { return opened( row.id ); } ) )
        {
            return openTraitAnswer( type, callee );   // one the map cannot list: Rust reads the impl blocks, else the name tiers answer
        }
        if( rows.empty() )
        {
            return out;   // no implementor in the tree: the name tiers answer, as before
        }
        bool provenAll = true;
        collect( type, callee, out.cand );   // T's own bodied default runs for every implementor without an override
        const bool hasDefault = !out.cand.empty();
        const bool implBlocks = langFacts( ing_.symbols[ type ].lang ).traitImplBlocks;
        for( const Row& row : rows )
        {
            const std::size_t before = out.cand.size();
            collect( row.id, callee, out.cand );
            if( implBlocks )
            {
                keepInImplBlock( type, row.id, out.cand, before );   // Rust: X's methods for T, never an inherent one
            }
            // a concrete implementor owning no body of the callee, with no default above it, holds one the index cannot see
            // (a macro-made override, a mock): the list is not the whole of what runs, so one candidate proves nothing
            const bool unseen = !hasDefault && out.cand.size() == before && ( row.id >= implementors_.size() || implementors_[ row.id ].empty() );
            provenAll = provenAll && row.proven && !unseen;
        }
        settle( out );
        out.proven = provenAll && !langFacts( ing_.symbols[ type ].lang ).structuralTyping;   // structural: the list is a floor
        return out;
    }

private:
    // the candidates once, ascending, then the non-test ones first (filter.h isTestSymbol; each part keeps id order): the list a
    // <dc gate="iface"> row names leads with what production code runs (RUST-DYN-NAMESAKE: mdbook's renderers before the
    // testsuite's Spy). Order only: the set, its count and the one-candidate proof are unchanged.
    void settle( IfaceDispatchAnswer& out ) const
    {
        std::sort( out.cand.begin(), out.cand.end() );
        out.cand.erase( std::unique( out.cand.begin(), out.cand.end() ), out.cand.end() );
        std::stable_partition( out.cand.begin(), out.cand.end(), [ & ]( NodeId c ) { return !isTestSymbol( ing_, c ); } );
        out.fired = !out.cand.empty();
    }

    // lane receiver-fixes (RUST-DYN-NAMESAKE; dispatch classes #5 candidate-set completeness, #11 name-keyed identity): a trait
    // whose implementors list the map cannot list (an implementor two same-named types share — mdbook's tests hold two `Spy`
    // structs —, `impl T for &X`, a blanket impl). Before, the tier stepped aside, and the name tiers bound a `&dyn T` call by
    // name to the one same-file impl (mdbook execute_build_process → TestRenderer::render). A language whose trait methods sit in
    // `impl T for X` blocks (langfacts.h traitImplBlocks) still knows every in-tree body of the callee written for T: the bodied
    // callables of that name inside one of T's ImplBlock spans, plus T's own default. That list is the decline (never a proof:
    // a mock attribute's or macro's impl writes no body the index sees); a trait name another in-tree type shares answers
    // nothing (the blocks are keyed by name), and every other language keeps the name tiers.
    IfaceDispatchAnswer openTraitAnswer( NodeId type, std::string_view callee ) const
    {
        IfaceDispatchAnswer out;
        const Symbol&       t = ing_.symbols[ type ];
        if( !langFacts( t.lang ).traitImplBlocks || t.kind != SymKind::Interface || recvEv_.types.sameNamedClasses( type ) != 1 )
        {
            return out;
        }
        const auto blocks = traitBlocks_.find( std::string_view( t.name ) );
        const auto named  = blockCallables_.find( callee );
        if( blocks == traitBlocks_.end() || named == blockCallables_.end() )
        {
            return out;
        }
        collect( type, callee, out.cand );   // T's own bodied default
        for( NodeId c : named->second )
        {
            const Symbol& m = ing_.symbols[ c ];
            if( std::ranges::any_of( blocks->second, [ & ]( const Binding* b )
                { return b->fileId == m.fileId && b->spanStart <= m.sigStartByte && m.endByte <= b->spanEnd && !recvEv_.types.rustPathProvablyOutside( b->fileId, b->startByte, b->importedName ); } ) )
            {
                out.cand.push_back( c );
            }
        }
        settle( out );
        out.open = out.fired;
        return out;
    }

    // the bodyless members are an interface's or abstract class's contract; in a lambda-convertible language (langfacts.h) they are
    // also counted per owning class identity, and every class is listed under its name
    void indexSymbol( const Symbol& s )
    {
        const LangFacts& lf      = langFacts( s.lang );
        const bool       samLang = lf.samLambdas || lf.samFromJavaLambdas;
        javaInTree_              = javaInTree_ || lf.samLambdas;
        if( samLang && ReceiverEvidence::classLike( s.kind ) )
        {
            sam_.addClass( s );
        }
        if( !ReceiverEvidence::callableKind( s.kind ) || s.endByte > s.sigEndByte || s.id >= recvEv_.ownerClass.size() || recvEv_.ownerClass[ s.id ].empty() )
        {
            return;
        }
        contract_.try_emplace( recvEv_.ownerClass[ s.id ] + "::" + s.name, char( 1 ) );
        if( !samLang || std::ranges::contains( lf.samIgnoredMembers, std::string_view( s.name ) ) )
        {
            return;
        }
        if( const NodeId owner = recvEv_.classAt( s.fileId, s.sigStartByte, s.endByte, s.id ); owner != kNoNode )
        {
            sam_.addMember( owner, s );   // per class IDENTITY, not per name: the SAM count
        }
    }

    struct Row
    {
        NodeId id     = kNoNode;
        bool   proven = false;   // every implements edge from T down to it is proven
    };

    // T dispatches a call of `callee`: an interface / trait whose contract (its members, or a base's) names the callee — or
    // any trait of a language whose trait signatures are not indexed — or a class whose contract declares it without a body
    bool dispatchesThrough( NodeId type, std::string_view callee ) const
    {
        const Symbol& t = ing_.symbols[ type ];
        if( t.kind == SymKind::Interface && langFacts( t.lang ).contractSignaturesUnindexed )
        {
            return true;
        }
        if( !ReceiverEvidence::classLike( t.kind ) )
        {
            return false;
        }
        const bool iface = t.kind == SymKind::Interface;
        return recvEv_.walkBaseLevels( t.name, [ & ]( const std::vector<std::string_view>& level, std::size_t )
        {
            for( std::string_view c : level )
            {
                key_.assign( c ).append( "::" ).append( callee );
                if( contract_.contains( key_ ) || ( iface && recvEv_.methodsByType.contains( key_ ) ) )
                {
                    return true;
                }
            }
            return false;
        } );
    }

    // the bodied methods named `callee` class `cls` owns (ReceiverEvidence::collectMethods: by name, then ownership); the
    // caller keeps those of the call's language and root, as for every candidate list
    void collect( NodeId cls, std::string_view callee, std::vector<NodeId>& out ) const
    {
        recvEv_.found.clear();
        recvEv_.collectMethods( ing_.symbols[ cls ].name, callee, cls );
        out.insert( out.end(), recvEv_.found.begin(), recvEv_.found.end() );
    }

    // Rust: keep, of the candidates from `first` on (implementor `impl`'s methods named the callee), those inside one of its
    // `impl T for X` blocks (ImplBlock spans, by T's and X's names, as the inherit reference names them)
    void keepInImplBlock( NodeId type, NodeId impl, std::vector<NodeId>& cand, std::size_t first ) const
    {
        key_.assign( ing_.symbols[ type ].name ).push_back( '\x1f' );
        key_.append( ing_.symbols[ impl ].name );
        const auto hit = implBlocks_.find( key_ );
        const auto out = std::remove_if( cand.begin() + std::ptrdiff_t( first ), cand.end(), [ & ]( NodeId c )
        {
            const Symbol& m = ing_.symbols[ c ];
            return hit == implBlocks_.end() || std::none_of( hit->second.begin(), hit->second.end(), [ & ]( const Binding* b )
                   { return b->fileId == m.fileId && b->spanStart <= m.sigStartByte && m.endByte <= b->spanEnd; } );
        } );
        cand.erase( out, cand.end() );
    }

    // A lambda or a method reference implements an interface with exactly one abstract method (JLS 9.8), with no class the index
    // keeps, so such an interface's implementors list is open (langfacts.h samLambdas: Java; samFromJavaLambdas: Kotlin, when the
    // tree holds Java). EXACT OR NO ROW: every doubt opens the list. The count is per class IDENTITY (the index knows a base by
    // NAME only, and `a.Handler` and `b.Handler` are two interfaces): T's own members, plus those of the bases it names exactly.
    bool lambdaImplements( NodeId t ) const
    {
        const Symbol&    s  = ing_.symbols[ t ];
        const LangFacts& lf = langFacts( s.lang );
        // Kotlin's extractor reads an interface as a class (interfaceReadsAsClass), so there a class with no abstract member of
        // its own or above is a plain class, never an interface: the count must be exactly one
        if( !samConvertible( s.lang ) || !( s.kind == SymKind::Interface || ( lf.interfaceReadsAsClass && s.kind == SymKind::Class ) ) )
        {
            return false;
        }
        if( const auto hit = samMemo_.find( t ); hit != samMemo_.end() )
        {
            return hit->second != 0;
        }
        const SamCounter::AbstractCount ac = sam_.abstractCount( t, sam_.soleClassNamed( s.name ) != kNoNode );
        // a doubted 0 is a LOWER bound, never a certain 0: Kotlin's "exactly one" holds only for a count the index is sure of; and a
        // count with a class the walk cannot see (`hidden`: it may re-declare a name with a body) is no certain 2 either: it opens,
        // unless T's own members alone are two (a base's body never overrides a name T itself declares)
        const bool sam = ac.ownN < 2 && ( ac.hidden || ( ac.n <= 1 && ( !lf.interfaceReadsAsClass || ac.n == 1 || ac.doubted ) ) );
        samMemo_.emplace( t, char( sam ? 1 : 0 ) );
        return sam;
    }

    // a lambda can implement this language's interfaces: Java's always, Kotlin's when a Java file in the tree can pass the lambda
    bool samConvertible( Lang l ) const
    {
        const LangFacts& lf = langFacts( l );
        return lf.samLambdas || ( lf.samFromJavaLambdas && javaInTree_ );
    }

    // breadth-first down the implementors map from T, each type once (a cycle or a diamond is walked once): an Other edge (the
    // evidence names a different same-named type) is not followed; a ByName one is, its row and everything below it unproven
    const std::vector<Row>& closureOf( NodeId type ) const
    {
        if( const auto hit = memo_.find( type ); hit != memo_.end() )
        {
            return hit->second;
        }
        std::vector<Row>        rows;
        HashMap<NodeId, char>   seen;
        seen.emplace( type, char( 1 ) );
        const auto expand = [ & ]( NodeId parent, bool provenSoFar )
        {
            if( parent >= implementors_.size() )
            {
                return;
            }
            for( std::size_t k = 0; k < implementors_[ parent ].size(); ++k )
            {
                const BaseBound b = bound_.empty() ? BaseBound::ByName : BaseBound( bound_[ parent ][ k ] );
                if( b == BaseBound::Other )
                {
                    continue;
                }
                const NodeId child = implementors_[ parent ][ k ];
                if( seen.emplace( child, char( 1 ) ).second )
                {
                    rows.push_back( Row{ child, provenSoFar && b == BaseBound::Proven } );
                }
            }
        };
        expand( type, true );
        for( std::size_t i = 0; i < rows.size(); ++i )   // rows grow inside the loop: index, never iterate by reference
        {
            expand( rows[ i ].id, rows[ i ].proven );
        }
        return memo_.emplace( type, std::move( rows ) ).first->second;
    }

    const IngestResult&                           ing_;
    const ReceiverEvidence&                       recvEv_;
    const std::vector<std::vector<NodeId>>&       implementors_;
    const std::vector<std::vector<std::uint8_t>>& bound_;
    HashMap<std::string_view, std::vector<const Binding*>> traitBlocks_;      // RUST-DYN-NAMESAKE: a trait name → its ImplBlock records
    HashMap<std::string_view, std::vector<NodeId>>         blockCallables_;   // … and a callable name → its bodied definitions (traitImplBlocks languages)
    const std::vector<char>&                      open_;       // graph.h implementorsOpen: a clause names an implementor the map cannot list
    HashMap<std::string, char>                    contract_;   // "Owner::name" of every bodyless member
    SamCounter                                          sam_;   // the SAM count: abstract members per class identity
    bool                                                javaInTree_ = false;   // a samLambdas-language symbol exists (a Kotlin SAM can take its lambda)
    HashMap<std::string, std::vector<const Binding*>>   implBlocks_;      // "T\x1fX" → the `impl T for X` blocks (ImplBlock)
    mutable HashMap<NodeId, std::vector<Row>>     memo_;       // T → its closure
    mutable HashMap<NodeId, char>                 samMemo_;    // T → lambdaImplements( T )
    mutable std::string                           key_;
};

}   // namespace rw
