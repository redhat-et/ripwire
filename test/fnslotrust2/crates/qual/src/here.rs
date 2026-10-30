pub struct S { f: fn() }
impl S { pub fn new(f: fn()) -> Self { S { f } } pub fn go(&self) { (self.f)() } }
pub fn target() {}
pub fn register(f: fn()) -> S { S { f } }
pub fn local_t() {}
pub fn qual_t() {}
pub fn uses() {
    let _a = S::new(crate::other::target);
    let _b = crate::other::register(qual_t);
    let _c = register(local_t);
}
