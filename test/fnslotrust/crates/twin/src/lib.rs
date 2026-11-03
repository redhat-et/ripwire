// a second crate with a same-named struct: its slot is another type (part-2 type key, crate tier)
pub struct CallEval {
    eval: fn(&str) -> usize,
}

impl CallEval {
    pub fn new(eval: fn(&str) -> usize) -> Self {
        CallEval { eval: eval }
    }
    pub fn twin_run(&self, s: &str) -> usize {
        (self.eval)(s)
    }
}

pub fn twin_target(s: &str) -> usize {
    s.len() + 3
}

pub fn twin_make() -> CallEval {
    CallEval::new(twin_target)
}

pub enum Msg {
    Fire { eval: fn(&str) -> usize },
}

pub fn variant_target(s: &str) -> usize {
    s.len() + 4
}

pub fn make_variant() -> Msg {
    Msg::Fire { eval: variant_target }
}

pub struct Loose {
    pub cb: fn(&str) -> usize,
}

pub fn loose_target(s: &str) -> usize {
    s.len() + 5
}

pub fn set_loose(x: &mut Loose) {
    x.cb = loose_target;
}

pub fn call_loose(y: &Loose) -> usize {
    (y.cb)("z")
}

pub struct Reg {
    pub h: fn(&str) -> usize,
}

impl Reg {
    pub fn set(&mut self, h: fn(&str) -> usize) {
        self.h = h;
    }
    pub fn go(&self) -> usize {
        (self.h)("q")
    }
}

pub fn method_reg_target(s: &str) -> usize {
    s.len() + 6
}

pub fn use_method_reg(r: &mut Reg) {
    r.set(method_reg_target);
}

pub fn path_reg_target(s: &str) -> usize {
    s.len() + 8
}

pub fn use_path_reg(r: &mut Reg) {
    Reg::set(r, path_reg_target);
}
