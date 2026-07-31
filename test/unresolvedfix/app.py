# Python app: calls render() — a name defined ONLY in C++ (lib.cpp). The C++ def is
# language-filtered away for a Python call, so this is the HIGH-signal "plausibly
# internal but missed" case the unresolved gauge must count.
def run():
    render()                 # cross-language miss → in-repo name, all defs lang-filtered → COUNTED
    totally_external_fn()    # no in-repo def anywhere (site A, genuine external) → NOT counted
    helper()                 # same-language Python call → resolves cleanly (not unresolved)

def helper():
    return 1
