// `mystery_crate` is a registry dependency Cargo.toml declares: this Render is DECIDED outside the tree, so Square implements
// no in-tree trait and the one in-tree implementor (Circle) is proven.
use mystery_crate::Render;

pub struct Square;

impl Render for Square {
    fn draw(&self) -> i32 {
        2
    }
}
