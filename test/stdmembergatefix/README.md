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

Controls: a name outside the table (`grow`) keeps the ladder; a bare call `size( b )` reaches the free function; `c/`
holds a C function-pointer call (C has no member functions, so no gate); `rs/` is the Rust stated scope (no declared
receiver types there yet), whose by-name split must stay unchanged. `far/` calls `w.empty()` where no namesake is in
reach, so the ladder itself declines it (tier 3), and the `<stdm>` line still names it.

`sib/` holds the field and expression receivers: a field written as the in-tree `Vec` (`this->items_`, `b.items_` on a
`Box& b`) keeps the hedge, a field written in `std` is declined, and a dereference, a subscript, a range-for `auto` and
a template parameter are the stated floor (declined even where the element is `Vec`).
