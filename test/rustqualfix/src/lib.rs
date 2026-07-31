// H4 W3 Rust qualified-call fixture — file 1 of 3 (src/gadget/mod.rs and src/plainmod.rs are the others).
//
// PLAN_h4QualifiedCalls_2026-07-30.md §3.2 / §6. Every call SPELLING Rust offers gets exactly one site, in a
// function that isolates it, so a per-spelling assertion is possible at all. test/rustqualcheck.sh states its
// expected counts as LITERALS read off these files — never derived the way the query derives them (§7 trap 1).

pub mod gadget;      // DIRECTORY-form file module: src/gadget/mod.rs
pub mod plainmod;    // FILE-form file module:      src/plainmod.rs

pub struct Widget { n: u32 }

impl Widget {
    // cross-DIRECTORY collision partner: src/gadget/mod.rs also defines `new` and `helper`.
    pub fn new() -> Widget { Widget { n: 0 } }

    pub fn bump(&mut self) {
        self.n += 1;
        Self::helper();            // Self:: — same-file target (see the DISCRIMINATION note below)
        Self::detached();          // Self:: — CROSS-DIRECTORY target: the arm that actually discriminates
    }

    fn helper() {}
}

// ── V3 M-6: what it takes to make a `Self::` arm DISCRIMINATE ────────────────────────────────
// V3 was right that the original arms were vacuous — rewriting `Self::helper()` as a bare `helper()` left
// them green. It proposed a same-named decoy in the OTHER file; measured, that is not enough either, and
// neither is this same-file `Decoy::helper`. The reason is worth recording: with Rust def scopes now
// populated, B2.1 CHA-lite ALREADY narrows a bare in-method call using the caller's enclosing scope
// (`receiverStaticType` → "Widget"), and it drops every candidate outside Widget's inheritance cone. Two
// independent mechanisms therefore agree on the same-file shape, so no same-file decoy can separate them.
//
// What separates them is DISTANCE, not naming: `Widget::detached` lives in a SECOND `impl Widget` block in
// src/gadget/mod.rs (legal Rust, and common in real crates), with a same-named `Detacher::detached` decoy
// beside it. Neither is same-file or same-dir with this caller, so a BARE `detached()` cannot be answered by
// tier-1/tier-2 and CHA-lite cannot reach it either; what DOES answer is Rule 3 (lib.rs's `mod gadget;` is an
// include edge, and both defs live in that one included file), which narrows to the FILE — i.e. to BOTH.
// MEASURED, by rewriting the call and re-running:
//   bare `detached()`  → --callees=bump count=3, and bump carries amb="1"   (the decoy is picked up too)
//   `Self::detached()` → --callees=bump count=2, and bump carries NO amb=   (canonical `Widget::detached`)
// The gate asserts the second pair, so the arm goes red the moment `Self::` stops being resolved.
pub struct Decoy;
impl Decoy {
    fn helper() {}
}

pub trait Shape {
    fn area(&self) -> u32;
}

impl Shape for Widget {
    // trait-impl method. The impl header's `type:` is Widget, so this scopes to Widget (not Shape).
    fn area(&self) -> u32 { self.n }
}

pub mod util {
    pub fn tool() {}
    pub mod deep {
        pub fn deepfn() {}
    }
}

pub fn free() {}

pub fn generic<T>(v: T) -> T { v }

// V3 M-2 REPRO, kept permanently. A TOP-LEVEL fn carries scope="" — and in Rust that is true of EVERY
// top-level fn in EVERY file, not only of file-module members. The guard's first version kept every
// scope-less candidate, so this `new` answered the EXTERNAL `Vec::<u32>::new()` below: a confident false
// edge, count 0 -> 1, with no amb= and no ambiguous= movement. It must never be a callee of external_caller.
pub fn new() {}

// ── the spelling matrix ──────────────────────────────────────────────────────────────────────
// 9 calls, 9 DISTINCT targets, so every callee row is attributable to exactly one spelling.
pub fn caller() {
    free();                        // 1. bare                        -> free
    let mut w = Widget::new();     // 2. Type::assoc, 2-seg          -> Widget::new   CANONICAL
    w.bump();                      // 3. method call                 -> Widget::bump
    util::tool();                  // 4. mod::fn, 2-seg              -> util::tool    CANONICAL
    util::deep::deepfn();          // 5. mod::mod::fn, 3-seg         -> deep::deepfn  CANONICAL
    generic::<u32>(1);             // 6. turbofish on a BARE fn      -> generic
    let _a = Shape::area(&w);      // 7. TRAIT-qualified             -> Widget::area  (via chaUp)
    crate::gadget::gadget_free();  // 8. file module, DIRECTORY form -> gadget_free   (file-module rule)
    crate::plainmod::plainfn();    // 9. file module, FILE form      -> plainfn       (file-module rule)
}

// ── the EXTERNAL turbofish, isolated ─────────────────────────────────────────────────────────
// `Vec` is not defined in this tree. Isolating this call in its own function is what makes a false edge
// observable at all (the graph collapses duplicate (from,to) pairs, so a shared caller would hide it).
pub fn external_caller() {
    let _v = Vec::<u32>::new();    // -> NOTHING. Not Widget::new, not Gadget::new, and NOT the top-level new.
}

// ── the DELIBERATE ambiguity, engineered ─────────────────────────────────────────────────────
// Canonical keying makes the honest cases precise, so the `amb=` path is exercised on purpose (plan §6):
// TWO modules in ONE file each holding `impl Thing`, so the canonical key `Thing::run` has TWO definitions.
pub mod dup_a {
    pub struct Thing;
    impl Thing { pub fn run(&self) {} }
}
pub mod dup_b {
    pub struct Thing;
    impl Thing { pub fn run(&self) {} }
}

pub fn amb_caller(t: &dup_a::Thing) {
    Thing::run(t);                 // -> BOTH dup_a::Thing::run and dup_b::Thing::run, with amb=
}
