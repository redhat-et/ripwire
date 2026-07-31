// FIX #1 repro (Java): a class extending a GENERIC base. The base clause hands back a
// `generic_type` node whose text is `Base<String>` — the `<...>` type arguments must be
// stripped so the recorded base name is `Base` and `--lego=Base` surfaces the implementor D.
// (Single-language type names — Base/D — unique to this file so no cross-fixture collision.)
public class Base<T>
{
    public T get() { return null; }
}

class D extends Base<String>
{
    public String get() { return ""; }
}
