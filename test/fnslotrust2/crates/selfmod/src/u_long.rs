use crate::workspace_settings_module::{self, Other};
pub struct Ws { pub scb: fn() }
impl Ws { pub fn fire_ws_local(&self) { (self.scb)() } }
pub fn self_long_t() {}
pub fn mk( _o: Other ) { let _y = workspace_settings_module::Ws { scb: self_long_t }; }
