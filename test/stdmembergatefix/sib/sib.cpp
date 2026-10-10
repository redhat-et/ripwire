#include "../lib/vec.h"
#include <vector>

// Field receivers: a field whose written type is the in-tree Vec keeps the ladder's hedge (the type may be that
// container); a field written in std is declined.
struct Box
{
    Vec<int>         items_;
    std::vector<int> raw_;
    void thisField() { this->items_.push_back( 1 ); }
    void thisRaw() { this->raw_.push_back( 2 ); }
};
void fieldOfVar( Box& b ) { b.items_.push_back( 3 ); }
void fieldOfVarRaw( Box& b ) { b.raw_.push_back( 4 ); }

// STATED FLOORS: a receiver the resolver reads no written type for — a dereference, a subscript, a range-for `auto`, a
// template parameter — is declined even where the element is the in-tree Vec.
void derefPtr( Vec<int>* p ) { ( *p ).push_back( 5 ); }
void subscript( std::vector<Vec<int>>& vs ) { vs[ 0 ].push_back( 6 ); }
void rangeFor( std::vector<Vec<int>>& vs ) { for( auto& v : vs ) { v.push_back( 7 ); } }
template<class C> void tmplParam( C& c ) { c.push_back( 8 ); }
