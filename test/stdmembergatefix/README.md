# stdmembergatefix — the C++ standard-member gate (test/stdmembergatecheck.sh)

`lib/vec.h` defines in-tree classes whose members are named like standard container and string members:
`Vec<T>` (two `push_back` overloads, `size`, `empty`, `clear`, `data`, `grow`), `Pool` (`size`, `empty`, `clear`),
`Solo` (the tree's ONLY `append`) and a free `size( const Bag& )`. `lib/alias.h` adds `SmallV<T>`, an alias of `Vec<T>`,
and `StdMap`, an alias of a standard map.

`app/use.cpp` calls those names two ways:

- through receivers a rule types (a typed local, parameter, pointer, member field, smart-pointer `->`, `this->`, an
  implicit-this call inside `Vec`, a local declared with the in-tree alias): the edge must stay exactly as before;
- through receivers nothing types or that are written in `std` (`std::vector` locals and parameters, `auto`, a call
  result, a `std::string`, a field written in `std`, a local declared with the standard-map alias): the call must be
  declined and disclosed (declined_calls=, the callees answer's `<stdm>` line), never bound to an in-tree namesake.

Controls: a name outside the table (`grow`) gates nothing by its name (lane std-namesake: its receiver is a written
`std::vector`, so no in-tree `Vec::grow` is a candidate either); a bare call `size( b )` reaches the free function; `c/`
holds a C function-pointer call (C has no member functions, so no gate); `gogate/` holds a Go `f().Len()` (Go's row is
empty, so the ladder is unchanged).

`rsgate/` (with the older `rs/`) is the Rust row: `Stack<T>` (`push`, `len`, `frobnicate`), `Holder` (a field written
`Stack<i32>`) and `Book` (its own `iter`). `v.push()` / `v.iter()` on Vec parameters and a parameter of a type the tree does
not define are declined with a `<stdm>` line; `self.iter()` inside `Book` stays proven; a name outside the table
(`frobnicate`) and a name with no in-tree definition (`insert`) are untouched; a parameter, local or field written as the
in-tree `Stack` / `Book` binds that type's method (lane rust-receivers), and a generic bounded by an in-tree trait
(`P: Pushable`) is the stated floor (declined: lane L6). `far/` calls `w.empty()` where no namesake is in
reach, so the ladder itself declines it (tier 3), and the `<stdm>` line still names it.

`sib/` holds the field and expression receivers: a field written as the in-tree `Vec` (`this->items_`, `b.items_` on a
`Box& b`) keeps the hedge, a field written in `std` is declined, a subscript of a `std::vector<Vec<int>>` reads its element
type and keeps the hedge, and a dereference, a range-for `auto` and a template parameter are the stated floor (declined even
where the element is `Vec`).

`elem/` holds the element receivers: one element access (`c[ k ]`, `c.at( k )`, `c.front()`, `c.back()`) of a container whose
recorded written type is a std sequence container or map of `EvalString` — through a class-scoped typedef'd map field on a
`std::unique_ptr` local, a std map/vector field, a local, a const parameter, an unordered_map, a typedef and a typedef of it,
an extern map, a bare and a `this->` field — keeps the ladder's hedge on `EvalString::empty` and `Piece::empty`; an element
written in std, an element class with no `empty`, and the container's own member stay declined; two element accesses, an
iterator's `->second` and a range-for `auto` are the stated floor.

`wrap/` holds the written types Rule 2's tables do not carry: `ns::List` (the tree's only `size`/`find`/`front`) reached
through `std::unique_ptr`/`std::shared_ptr`/`std::optional`, an in-tree `SP<T>` with its own `operator->`, Qt and boost
pointers, a smart-pointer root one field hop off, namespace-scope, file-static and extern variables, and `typedef` /
`using` aliases of a std smart pointer or of an undefined wrapper (`list.h` tail) — each keeps the ladder's hedge — beside
the near-misses that stay declined (a smart pointer of `std::string`, raw pointers to std containers or to an alias of one,
`.` on `std::vector<ns::List>`, an in-tree class with no `operator->`, a std-written global, a global hidden by a local or a
field) and the stated floor (call results, an iterator, an unqualified template's arguments, a `std::optional` member
field, a typedef inside a function body).
