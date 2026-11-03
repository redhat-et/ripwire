pub struct Amb { pub f: fn() }
impl Amb { pub fn go_q(&self) { (self.f)() } }
