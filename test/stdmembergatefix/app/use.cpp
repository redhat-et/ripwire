#include "../lib/alias.h"
#include "../lib/vec.h"
#include <memory>
#include <string>
#include <vector>

// ---- receivers a rule types: every edge stays ----
void typedLocal() { Vec<int> v; v.push_back( 1 ); }
void typedParam( Vec<int>& v ) { v.push_back( 2 ); }
void typedPtr( Vec<int>* p ) { p->push_back( 3 ); }
struct Holder
{
    Vec<int>                  items_;
    std::unique_ptr<Vec<int>> owned_;
    std::vector<int>          raw_;
    void add() { items_.push_back( 4 ); }
    void addOwned() { owned_->push_back( 5 ); }
    void addRaw() { raw_.push_back( 6 ); }
};
void soloTyped() { Solo so; so.append( 7 ); }
void poolTyped( Pool& p ) { p.clear(); }
void aliasTyped() { SmallV<int> a; a.push_back( 8 ); }

// ---- receivers nothing types, or written in std: declined, disclosed ----
void stdLocal() { std::vector<int> v; v.push_back( 9 ); }
void stdParam( std::vector<char>& out, const std::string& s ) { out.push_back( 'x' ); out.reserve( s.size() ); out.clear(); }
void autoLocal() { auto v = std::vector<int>(); v.push_back( 10 ); }
std::vector<int>& getV();
void chained() { getV().push_back( 11 ); }
void stdAppend( std::string& s ) { s.append( "x" ); }
void stdEmpty( const std::vector<int>& w ) { if( w.empty() ) { return; } }
void stdAliasClear( StdMap& m ) { m.clear(); }

// ---- controls ----
void notInTable( std::vector<int>& v ) { v.grow(); }
std::size_t bareFree( const Bag& b ) { return size( b ); }
