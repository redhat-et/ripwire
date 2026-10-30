pub struct Dyn { g: std::sync::Arc<dyn Fn()> }
impl Dyn { pub fn go(&self) { (self.g)() } }
pub fn arc_t() {}
pub fn mk() -> Dyn { Dyn { g: std::sync::Arc::new(arc_t) } }
