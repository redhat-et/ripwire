// an in-tree PathBuf (nushell crates/nu-path/src/path.rs's shape): its members are ITS own, never std's
pub struct PathBuf { pub s: u32 }
impl PathBuf {
    pub fn new() -> Self { PathBuf { s: 0 } }
}
impl From<&str> for PathBuf {
    fn from(s: &str) -> Self { PathBuf { s: s.len() as u32 } }
}
