use self::Kind::*;
pub enum Kind { A, B }
pub fn self_glob_t() {}
pub fn mk() { let _k = A; let _a = Gh { hcb: self_glob_t }; }
