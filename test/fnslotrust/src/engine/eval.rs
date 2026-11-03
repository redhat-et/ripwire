pub type EvalFn = fn(&str) -> usize;

pub struct CallEval {
    stack: usize,
    eval: EvalFn,
}

impl CallEval {
    pub fn new(stack: usize, eval: EvalFn) -> Self {
        Self { stack, eval }
    }

    pub fn run(&mut self, block: &str) -> usize {
        (self.eval)(block) + self.stack
    }
}

pub fn eval_block(block: &str) -> usize {
    block.len()
}

pub fn eval_block_generic<D>(block: &str) -> usize {
    block.len() * 2
}

pub fn direct_eval(block: &str) -> usize {
    block.len() + 1
}

pub fn make_direct() -> CallEval {
    CallEval { stack: 0, eval: direct_eval }
}
