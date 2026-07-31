// H4 W3 Rust qualified-call fixture — file 2 of 3, in a DIFFERENT DIRECTORY from src/lib.rs.
//
// This file exists for the case W1-MEASURE proved a pattern-only widening cannot handle: TWO types defining
// `new` in DIFFERENT directories. Under bare-name spray the two candidates are neither same-file nor
// same-dir, so §2a's tier-3 "unique global or DROP" rule kills BOTH edges — and SILENTLY: no `amb=`, no
// `unresolved=` movement, nothing a reader could notice. With the canonical tier extended to Rust, each
// `Type::new()` keys `Type::new` and lands on its OWN impl.

pub struct Gadget { n: u32 }

impl Gadget {
    pub fn new() -> Gadget { Gadget { n: 0 } }   // cross-directory collision partner of Widget::new
    fn helper() {}                                // cross-directory collision partner of Widget::helper

    pub fn spin(&mut self) {
        self.n += 1;
        Self::helper();            // Self:: here must reach Gadget::helper past the SAME-FILE GDecoy::helper
    }
}

pub struct GDecoy;
impl GDecoy {
    fn helper() {}
}

// ── V3 M-6: the CROSS-DIRECTORY half of the discriminating Self:: pair (see the note in src/lib.rs) ──
// A SECOND `impl Widget` block, for the type declared over in src/lib.rs — legal Rust and common in real
// crates. `Widget::bump` (in lib.rs) calls `Self::detached()`; because this target is neither same-file nor
// same-dir with that caller, and `Detacher::detached` below is a same-named decoy, a BARE `detached()` there
// hits tier-3 with two candidates and DROPS. Only Self -> Widget keying reaches it.
impl crate::Widget {
    pub fn detached(&self) {}
}

pub struct Detacher;
impl Detacher {
    pub fn detached(&self) {}
}

// A FILE-module function: the module path `crate::gadget` comes from the DIRECTORY LAYOUT, and no AST node in
// this file spells "gadget", so this def carries scope="". graph.h::rustFileModuleOf maps the path back to
// "gadget", which is what lets `crate::gadget::gadget_free()` resolve without the guard keeping every
// scope-less def in the tree (V3 M-2).
pub fn gadget_free() {}

pub fn crossdir_caller() {
    let _w = crate::Widget::new();  // cross-directory, 3-seg -> Widget::new  CANONICAL, its own impl
    let _g = Gadget::new();         // same-file,       2-seg -> Gadget::new  CANONICAL, its own impl
}

// V3 M-3 REPRO, kept permanently — the round's headline failure class, reproduced INSIDE the round's own fix.
// `Thing::run` is a canonical key with TWO defs (dup_a/dup_b in src/lib.rs), and this caller is in ANOTHER
// DIRECTORY. Before the fix the canonical tier matched both, then tier-3's unique-or-DROP swallowed the
// result: no edge, no amb=, no unresolved= movement, map byte-identical. §3 tested cross-dir with UNIQUE
// keys and §6 tested ambiguity SAME-FILE; their intersection was untested, and broken.
pub fn crossdir_amb(t: &crate::dup_a::Thing) {
    Thing::run(t);                  // -> BOTH dup_a::Thing::run and dup_b::Thing::run, ACROSS a directory
}
