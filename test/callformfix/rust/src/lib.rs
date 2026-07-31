// RUST CALL-FORM MATRIX fixture — one line per call SPELLING the grammar distinguishes.
// Every callee has a UNIQUE name so `--uses=<name>` is a per-spelling assertion; expected counts
// are literals read off this file. ABSENT rows are asserted at 0 and fence an honest reject.

pub struct Widget { n: u32 }

pub trait Spin { fn trait_fn(&self); }

impl Spin for Widget { fn trait_fn(&self) {} }

impl Widget {
    pub fn assoc_fn() -> Widget { Widget { n: 0 } }
    pub fn method_fn(&mut self) { self.n += 1; }
    pub fn ufcs_fn(_w: &Widget) {}
    pub fn self_fn() {}
    pub fn calls_self() { Self::self_fn(); }          // 6. Self:: — resolves to THIS impl's type
}

pub struct Holder<T> { v: T }

impl<T: Default> Holder<T> {
    pub fn turbo_scoped() -> u32 { 7 }
}

pub mod util {
    pub fn mod_fn() {}
    pub mod deep { pub fn deep_fn() {} }
}

pub fn bare_fn() {}

pub fn turbo_bare<T>(v: T) -> T { v }

macro_rules! mymac { () => {}; }

pub fn caller() {
    bare_fn();                          // 1. bare call
    let mut w = Widget::assoc_fn();     // 3. Type::assoc (scoped, 2 segments)
    w.method_fn();                      // 2. method call
    util::mod_fn();                     // 4. module::fn (scoped, 2 segments)
    util::deep::deep_fn();              // 5. module::module::fn (3 segments)
    Widget::ufcs_fn(&w);                // 7. UFCS — method spelled as an associated fn
    turbo_bare::<u32>(1);               // 8. turbofish on a bare fn (generic_function)
    Holder::<u32>::turbo_scoped();      // 9. turbofish on a scoped path
    w.trait_fn();                       // 10. trait method through the receiver
    mymac!();                           // 11. macro invocation
    crate::plainmod::file_mod_fn();     // 13. file-module call (src/plainmod.rs)
}

pub fn caller_ufcs_cast() {
    // 12. NOT-CHECKED in the survey: `<T as Trait>::method()`, the UFCS-with-cast form.
    let w = Widget::assoc_fn();
    <Widget as Spin>::trait_fn(&w);
    mymac!();
}
