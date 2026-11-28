pub fn caller_crate() { crate::rootfn(); }
pub fn caller_super() { super::rootfn(); }
pub fn sibling() {}
pub fn caller_self() { self::sibling(); }
pub fn caller_nested() { crate::a::af(); }

// precision: `crate::` names the ROOT module, so a def only `a` holds answers nothing
pub fn caller_wrong_module() { crate::only_in_a(); }
// precision: `self::` is module `b`, so the root's rootfn answers nothing
pub fn caller_wrong_self() { self::rootfn(); }
// precision: a method is no module item
pub fn caller_method_name() { crate::paint(); }

pub mod inner {
    pub fn inner_helper() {}
    pub fn caller_inner_self() { self::inner_helper(); }
    pub fn caller_inner_super() { super::sibling(); }
    pub fn caller_inner_super2() { super::super::rootfn(); }
}
