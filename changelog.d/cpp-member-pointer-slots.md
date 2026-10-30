### Added — C++ pointers to member functions and C class tables with macro-cast receivers are joined to the calls through their fields (`--callers`, `--callees`, `--for`)

A C++ pointer to a member function stored in a struct field (`{ "browse", …, &NinjaMain::ToolBrowse }` in a table of a struct
this file defines, a field assignment, an argument) is now a value reference to that class's method — its definition with a
body, else its declaration, never a same-named method of another class — and a call through a member pointer held in a field,
`( ninja.*options.tool->func )( … )`, is a call through that field (typed by the root's declared struct, as `x->f( … )` is). In
C, a designated initializer nested in an untyped braced member (`.super = { .writeField = f }` in a `ProcessClass` literal)
keys the field path from the enclosing literal's type (`ProcessClass.super` is a `RowClass`), and a call whose receiver is a
function-like macro whose whole body is one pointer cast (`#define As_Row( x ) ( ( const RowClass* )( … ) )`,
`As_Row( this )->writeField( … )`) is typed by the cast's type; any other call receiver (`f( x )->g( … )`, a macro of another
shape) joins by the field name only (`via="slot-name"`, `~` on `--for`). Not joined (floors): `&a::Twin::Go` when the repo
defines two classes of that name (a symbol carries no namespace), a namespace function `&ns::f`, a member pointer in a plain
variable, `->*` and an inline member-pointer field declarator `R ( C::*f )( … )` (both parse as an ERROR node: use a typedef, as
ninja's `ToolFunc` does), table entries inside an `#ifdef` within the initializer list (an ERROR node), `std::function` members (a call result or lambda is no value), and an inherited method whose base is
declared outside the tree (the store is dropped, and the slot lists the targets it does have). A pointer to a virtual method is a
candidate SET: the declaring class's definition and every override in a class derived from the pointer's class (a non-virtual
method a derived class hides is listed too: a hedge, never a pin), and a pure virtual's bodyless declaration is never a target when
an override has one (with no in-tree override, the pure declaration is the target). A template's dependent base written as a template parameter (`template <class B> struct M : B`) names no in-tree class, even one called `B`. An inherited or CRTP-base method (`&D::inh` defined in a base) names the nearest base's definition (two bases
at one level: none). An overloaded name lists every overload, so `targets=` counts definitions, not stored values. A qualified
spelling must match the namespace the in-tree class sits in (`&grpc::Server::start` is no `mine::Server`; neither is a bare
`&Server::start` under `using grpc::Server;` or `using namespace grpc;` written outside `mine`; a bare `&Server::start` written INSIDE `namespace grpc { … }`, where an external `grpc::Server` hides an in-tree GLOBAL `Server`, still binds the global class: a floor). A call site whose typed
tier hides name-only stores says `slot_name_also=K` on its `<vs>`, and `--for` `slot_fields=` keeps the fields a caller calls
through when its cap of 4 cuts.
Nothing here is a proven call: count= and reaches= never move.
