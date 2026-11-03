pub struct Cfg { pub cb: fn() }
impl Cfg {
    pub fn go(&self) { (self.cb)() }
}
pub fn fa() {}
pub fn mka() -> Cfg { Cfg { cb: fa } }
