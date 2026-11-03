use crate::Render;

pub fn go(r: &dyn Render) -> i32 {
    r.draw()
}
