// CodeRabbit #633: a renamed FUNCTION import beside a macro of the alias's name. Rust keeps macros apart from functions, so
// `local_mac!()` names the `macro_rules!` below and `exported_mac!()` the #[macro_export] one in macros.rs: neither names the function.
use crate::things::helper_fn as local_mac;
use crate::things::shared_fn as exported_mac;

macro_rules! local_mac {
    () => {};
}

pub fn calls_local() {
    local_mac!();
}

pub fn calls_exported() {
    exported_mac!();
}
