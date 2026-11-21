// `str` here is the tree's Text (an item shadows the primitive): `s.touch()` is Text::touch
use crate::text::Text as str;
pub fn via_str(s: &str) -> u32 {
    s.touch()
}
