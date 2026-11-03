use crate::{a::{self}};
pub struct Sa { pub acb: fn() }
impl Sa { pub fn fire_sa_local(&self) { (self.acb)() } }
pub fn self_short_t() {}
pub fn mk() { let _y = a::Sa { acb: self_short_t }; }
