# Same-named classes in a DIFFERENT language than the C++ owner in widget.cpp. This file sorts
# BEFORE widget.cpp, so its symbols get LOWER ids — a language-blind compose resolver binds the
# C++ member `Foo m_foo;` here first (and `Bar` has NO C++ definition at all).


class Foo:
    def bark(self):
        return 1


class Bar:
    def meow(self):
        return 2
