use extcrate::*;
pub struct Gm { pub mcb: fn() }
impl Gm { pub fn fire_gm_local(&self) { (self.mcb)() } }
pub fn glob_loc_t() {}
pub fn mk() { let _a = Gm { mcb: glob_loc_t }; }
