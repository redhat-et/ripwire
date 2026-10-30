use super::eval::{eval_block, eval_block_generic, CallEval};

pub fn closure_eval(block: &str) -> usize {
    let mut ce = CallEval::new(1, eval_block);
    ce.run(block)
}

pub fn closure_eval_generic(block: &str) -> usize {
    let mut ce = CallEval::new(2, eval_block_generic::<u8>);
    ce.run(block)
}

pub fn crate_tier_target(block: &str) -> usize {
    block.len() + 11
}

// a store in ANOTHER file of the crate: CallEval is this crate's (crates/twin has its own), keyed by the crate tier
pub fn closure_direct() -> CallEval {
    CallEval { stack: 9, eval: crate_tier_target }
}
