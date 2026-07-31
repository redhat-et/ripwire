// FIX #1 repro (Rust): a GENERIC impl of a trait for a generic type. The impl's `type:` field
// is `Wrapper<T>` — the `<...>` type arguments must be stripped so the DERIVED name stashed in
// `qualifier` is `Wrapper` and resolves by name, making `--lego=Draw` surface Wrapper.
// (Trait/type names Draw/Wrapper are unique to this file.)
trait Draw
{
    fn draw( &self );
}

struct Wrapper<T>
{
    inner: T,
}

impl<T> Draw for Wrapper<T>
{
    fn draw( &self ) {}
}
