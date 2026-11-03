use crate::Render;

pub struct Circle;

impl Render for Circle {
    fn draw(&self) -> i32 {
        1
    }
}
