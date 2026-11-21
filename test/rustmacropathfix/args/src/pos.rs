// Calls written inside macro arguments: each is a call of the enclosing function.
use crate::{any, arm_helper, block_helper, ghost_call, late_line, nested_helper, probe, render, wrap, Engine, Shape};

pub fn in_assert() {
    assert_eq!(probe(), 1);
}

pub fn in_format() -> String {
    format!("{}", render())
}

pub fn in_late_line() {
    assert_eq!(
        1,
        late_line()
    );
}

impl Engine {
    pub fn route(self, path: &str) -> Self {
        tap!(self, mut this => {
            block_helper();
            checked!(this.inner.route_inner(path));
        })
    }

    pub fn rebuilt(self) -> Engine {
        remap!(self, this => Engine { inner: arm_helper(this.inner) })
    }

    pub fn own_len(&self) -> usize {
        0
    }

    pub fn in_self_call(&self) {
        assert_eq!(self.own_len(), 0);
    }
}

pub fn in_nested() {
    assert!(matches!(wrap(1), Some(_)) && nested_helper());
}

pub fn in_vec() -> Vec<u32> {
    vec![probe(), 2]
}

pub fn live_control() {
    assert_eq!(ghost_call(1), 1);
}

pub fn any_control() {
    assert!(any(true, false));
}

pub fn shape_control() -> Shape {
    Shape(1)
}
