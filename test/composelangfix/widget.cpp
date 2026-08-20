// The C++ owner. Three members, three different resolution fates under the compose lang guard:
//   m_foo    -> Foo    defined BOTH here (C++) and in alpha.py (Python)  => binds to the C++ Foo only
//   m_bar    -> Bar    defined ONLY in alpha.py (Python)                 => no compose edge at all
//   m_gadget -> Gadget defined ONLY in gadget.c (C, bridged to C++)      => compose edge kept
class Foo
{
public:
    int ping() { return 3; }
};

class Widget
{
public:
    Foo    m_foo;
    Bar*   m_bar;
    Gadget m_gadget;
    int go() { return m_foo.ping(); }
};
