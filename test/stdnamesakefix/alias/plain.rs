// controls: the std names ARE the standard types (an import of the item as itself, the prelude, `use std::str;` the module)
use std::str;
use std::vec::Vec;
pub fn plain_vec(v: Vec<u8>) -> u32 {
    v.touch()
}
pub fn plain_box(b: Box<Vec<u8>>) -> u32 {
    b.touch()
}
pub fn plain_str(s: &str) -> u32 {
    let _ = str::from_utf8(&[]);
    s.touch()
}
