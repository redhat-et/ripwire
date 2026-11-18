// RUST-MACRO-ARGS fixture (test/rustmacropathcheck.sh, the A arms): the definitions the call sites in pos.rs and neg.rs name.
#[macro_use]
mod macros;
pub mod neg;
pub mod pos;

pub struct Inner;

impl Inner {
    pub fn route_inner(&self, path: &str) -> usize {
        path.len()
    }
}

pub struct Engine {
    pub inner: Inner,
}

pub struct Shape(pub u32);

pub fn probe() -> u32 {
    1
}

pub fn render() -> String {
    String::new()
}

pub fn late_line() -> u32 {
    1
}

pub fn block_helper() {}

pub fn arm_helper(inner: Inner) -> Inner {
    inner
}

pub fn nested_helper() -> bool {
    true
}

pub fn wrap(value: u32) -> Option<Shape> {
    Some(Shape(value))
}

pub fn ghost_call(value: u32) -> u32 {
    value
}

pub fn any(left: bool, right: bool) -> bool {
    left || right
}
