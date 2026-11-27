// `Box` here is the tree's Wrap: `b.touch()` is Wrap::touch
use crate::wrapper::Wrap as Box;
pub fn via_wrap(b: Box<Vec<u8>>) -> u32 {
    b.touch()
}
