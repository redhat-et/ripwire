pub struct Cfg { pub cb: fn() }
impl Cfg {
    pub fn local_go(&self) { (self.cb)() }
}
pub fn fc_local() {}
pub fn fc_qualified() {}
pub fn mk_local() -> Cfg { Cfg { cb: fc_local } }
pub fn mk_qualified() -> crate::a::Cfg { crate::a::Cfg { cb: fc_qualified } }
