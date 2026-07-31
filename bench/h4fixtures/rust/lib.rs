// Rust call-form fixture.
pub struct Widget { n: u32 }
impl Widget {
    pub fn new() -> Widget { Widget { n: 0 } }
    pub fn bump(&mut self) { self.n += 1; Self::helper(); }
    fn helper() {}
}
pub mod util {
    pub fn tool() {}
    pub mod deep { pub fn deepfn() {} }
}
pub fn free() {}
pub fn generic<T>(v: T) -> T { v }
macro_rules! mymac { () => {}; }

pub fn caller() {
    free();                        // 1. bare call
    let mut w = Widget::new();     // 2. Type::assoc (scoped, 2-seg)
    w.bump();                      // 3. method call
    util::tool();                  // 4. module::fn (scoped, 2-seg)
    util::deep::deepfn();          // 5. 3-segment scoped
    Widget::bump(&mut w);          // 6. UFCS method-as-assoc call
    generic::<u32>(1);             // 7. turbofish on bare fn
    Vec::<u32>::new();             // 8. turbofish on scoped path
    mymac!();                      // 9. macro invocation
    std::mem::drop(w);             // 10. external 3-segment
}
