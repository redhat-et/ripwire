pub struct Sa { pub acb: fn() }
impl Sa { pub fn fire_sa(&self) { (self.acb)() } }
