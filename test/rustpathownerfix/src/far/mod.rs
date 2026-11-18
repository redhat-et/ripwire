// callers in a directory of no candidate: no locality rung picks for them
use crate::mypath::PathBuf;
pub fn far_tree_from() -> u32 { let p = PathBuf::from("x"); p.s }
pub fn far_std_from() { let _p = std::path::PathBuf::from("x"); }
