pub struct Gw { pub wcb: fn() }
impl Gw { pub fn fire_ga(&self) { (self.wcb)() } }
pub struct Gother;
