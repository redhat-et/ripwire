pub struct Ws { pub scb: fn() }
impl Ws { pub fn fire_ws(&self) { (self.scb)() } }
pub struct Other;
