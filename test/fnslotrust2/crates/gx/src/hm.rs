pub struct Gm { pub mcb: fn() }
impl Gm { pub fn fire_gm(&self) { (self.mcb)() } }
