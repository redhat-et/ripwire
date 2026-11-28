// RUST-PATH-KEYWORD fixture, crate `one`: a src/lib.rs crate root the module layout knows.
pub mod b;
pub mod a;

pub fn rootfn() {}

pub struct Widget;
impl Widget {
    // a METHOD named like a root item: `crate::paint()` can never mean it
    pub fn paint(&self) {}
}
