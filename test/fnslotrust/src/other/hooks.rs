pub struct Hooks {
    eval: Box<dyn Fn(&str) -> usize>,
}

impl Hooks {
    pub fn new(eval: fn(&str) -> usize) -> Self {
        Hooks { eval: Box::new(eval) }
    }

    pub fn fire(&self, s: &str) -> usize {
        (self.eval)(s)
    }
}

pub fn hook_target(s: &str) -> usize {
    s.len() + 7
}

pub fn make_hooks() -> Hooks {
    Hooks { eval: Box::new(hook_target) }
}

pub fn shadowed(s: &str) -> usize {
    s.len() + 9
}

pub fn uses_local(s: &str) -> usize {
    let shadowed = |x: &str| x.len();
    let ce = crate::engine::eval::CallEval::new(3, shadowed);
    0
}
