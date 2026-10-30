pub struct Gh { pub hcb: fn() }
impl Gh { pub fn fire_gh(&self) { (self.hcb)() } }
