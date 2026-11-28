// crate `two` has its own root `rootfn`: crate `one`'s `crate::rootfn()` must never reach it
pub fn rootfn() {}
