pub struct Inner { pub f: fn() }
pub struct Outer { pub inner: Inner, pub f: fn() }
impl Outer {
    pub fn go_inner(&self) { (self.inner.f)() }
}
pub fn in_t() {}
pub fn out_t() {}
pub fn mk() -> Outer { Outer { inner: Inner { f: in_t }, f: out_t } }
