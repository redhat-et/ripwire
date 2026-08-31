// The C++ owner. Five members, four different resolution fates under the compose lang guard:
//   m_foo               -> Foo    defined BOTH here (C++) and in alpha.py (Python)  => binds to the C++ Foo only
//   m_bar               -> Bar    defined ONLY in alpha.py (Python)                 => no compose edge at all
//   m_gadget            -> Gadget defined ONLY in gadget.c (C, bridged to C++)      => compose edge kept
//   m_thing / m_other   -> Thing  defined TWICE in C++ (here and theta.cpp)         => ONE row per field, not
//                                  one per candidate definition (a field has one declared type)
class Foo
{
public:
    int ping() { return 3; }
};

struct Thing
{
    int y;
};

class Widget
{
public:
    Foo    m_foo;
    Bar*   m_bar;
    Gadget m_gadget;
    Thing  m_thing;
    Thing  m_other;
    int go() { return m_foo.ping(); }
};
