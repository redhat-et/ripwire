pub fn amb_t() {}
pub fn amb_bare_t() {}
pub fn mk() -> crate::p::Amb { crate::p::Amb { f: amb_t } }
pub fn mk_bare() { let _x = Amb { f: amb_bare_t }; }
