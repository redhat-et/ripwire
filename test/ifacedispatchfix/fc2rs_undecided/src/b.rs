// `mystery_crate` is no module of this tree, no std sibling and no Cargo dependency: the tree cannot say whether this Render is
// the one lib.rs defines (a re-export it did not see), so Square is neither listed as an implementor nor ruled out.
use mystery_crate::Render;

pub struct Square;

impl Render for Square {
    fn draw(&self) -> i32 {
        2
    }
}
