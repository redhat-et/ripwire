#pragma once

// unmodelled.h — the cases the model must REFUSE to number instead of guessing. Each one changes the
// real ABI in a way a lexical field walk cannot see, so the verb has to say so.

// Bitfields: the allocation unit and the bit packing order are implementation-defined.
struct BitfieldCase
{
    unsigned int lo : 3;
    unsigned int hi : 5;
};

// A virtual member introduces a vtable pointer the source text never spells.
struct VirtualCase
{
    virtual ~VirtualCase();
    int   n;
    float f;
};

// A base class contributes a subobject whose size and placement are not in this declaration.
struct DerivedCase : public BitfieldCase
{
    int extra;
};

// An unsized field type: everything AFTER it has an unknown offset too.
struct UnknownTypeCase
{
    int               known;
    SomeTypeNotInTree opaque;
    int               after;
};

// §P6.12 (2026-07-28 output audit): TWO unmodelable fields of the SAME caveat kind ("unknown-type") — the
// dedup in addCaveat keeps one <caveat> ROW per kind, but it must disclose that TWO sites hit it (count="2"),
// not silently drop the second one with no trace it ever existed. Mirrors the real bug found on Symbol
// (src/model.h): name/scope, both std::string, both "unknown-type", one caveat.
struct DoubleUnknownTypeCase
{
    AnotherTypeNotInTree first;
    YetAnotherTypeNotInTree second;
};

// §P6.11 (2026-07-28 output audit): a SCOPED enum's head contains the word "class" too — must refuse with
// "this is an enum, --layout models structs" instead of silently degrading to a confident modeled="1"
// zero-field struct. `enum struct` is the same idiom with "struct" instead of "class"; `enum` with neither
// keyword is the unscoped form.
enum class EnumClassCase
{
    First,
    Second
};

enum struct EnumStructCase
{
    Alpha,
    Beta
};

enum PlainEnumCase
{
    Left,
    Right
};
