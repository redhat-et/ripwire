pub struct Amb { pub f: fn() }
impl Amb { pub fn go_p(&self) { (self.f)() } }
