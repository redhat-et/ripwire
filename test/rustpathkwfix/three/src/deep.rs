pub mod leaf;

pub fn deep_item() {}
pub fn caller_manifest_crate() { crate::manifest_root(); }
pub fn caller_manifest_super() { super::manifest_root(); }
pub fn caller_manifest_self() { self::deep_item(); }
// precision: `crate::` is three.rs, so deep.rs's own deep_item answers nothing
pub fn caller_manifest_wrong() { crate::deep_item(); }
