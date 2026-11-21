// test/stdmembergatecheck.sh arm (N), lane std-namesake: receivers WRITTEN as a standard type (C++).
// Handle is the in-tree namesake: get / value / count / reset are std member names too, and none is in the name table.
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

struct Handle
{
    int get() const { return 1; }
    int value() const { return 3; }
    int count() const { return 4; }
    int reset() { return 5; }
};

struct Owner
{
    std::unique_ptr<int>    ptr_;
    std::unique_ptr<Handle> handlePtr_;
    std::vector<int>        vec_;
    std::map<int, int>      map_;
    std::string             name_;
    Handle                  handle_;
    // (N1) a field written in std
    int fieldSmart() { return *ptr_.get(); }   // STATED FLOOR: a smart pointer of a builtin records no field type (arm N3)
    int fieldSmartOfHandle() { return handlePtr_.get() != nullptr; }
    int fieldMap() { return (int)map_.count( 1 ); }
    int fieldString() { return (int)name_.count(); }
    int fieldThis() { return (int)this->map_.count( 1 ); }
    // (N2) an in-tree field keeps its edge; a `->` through the smart pointer reaches Handle
    int fieldHandle() { return handle_.get(); }
    int fieldArrow() { return handlePtr_->get(); }
};

// (N1) a local or parameter written in std
int localSmart()
{
    std::unique_ptr<int> p;
    return *p.get();
}
int paramSmart( const std::shared_ptr<int>& p )
{
    return *p.get();
}
int localOptional()
{
    std::optional<int> o;
    return o.value();
}
int paramMap( const std::map<int, int>& m )
{
    return (int)m.count( 1 );
}
int hopField( Owner& o )
{
    return o.handlePtr_.get() != nullptr;
}

// (N2) NEGATIVES: an in-tree receiver keeps its edge
int inRepo( Handle& h )
{
    return h.get() + h.value();
}

// (N3) NEGATIVES: no declaration proves a std receiver: the name tier stands
template<class T> int untyped( T& t )
{
    return t.get();
}
struct Holder
{
    std::vector<Handle>::value_type item_;
    std::vector<Handle>             items_;
    int nested() { return item_.get(); }
    int element() { return items_[ 0 ].get(); }
};
int nestedLocal()
{
    std::vector<Handle>::value_type h;
    return h.get();
}
int transformLocal()
{
    std::remove_reference_t<Handle&> h;
    return h.get();
}
int shadowAuto( bool b )
{
    std::unique_ptr<int> p;
    if( b )
    {
        auto p = Handle{};
        return p.get();
    }
    return 0;
}
int shadowTyped( bool b )
{
    std::unique_ptr<int> p;
    if( b )
    {
        Handle p;
        return p.get();
    }
    return 0;
}
int paramShadowed( const std::shared_ptr<int>& p, bool b )
{
    if( b )
    {
        auto p = Handle{};
        return p.get();
    }
    return 0;
}
