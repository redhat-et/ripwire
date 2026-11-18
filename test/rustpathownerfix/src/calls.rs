pub mod one_use {
    use crate::test_helpers::TestClient;
    pub fn one_use() -> u32 { let c = TestClient::new(1); c.n }
}
pub mod other_use {
    use crate::other_helpers::TestClient;
    pub fn other_use() { let _c = TestClient::new(1); }
}
pub fn written() -> u32 { let c = crate::test_helpers::TestClient::new(1); c.n }
pub fn written_other() { let _c = crate::other_helpers::TestClient::new(1); }
pub mod std_use {
    use std::path::PathBuf;
    pub fn std_new() { let _p = PathBuf::new(); }
    pub fn std_from() { let _p = PathBuf::from("x"); }
}
pub fn std_written() -> bool { std::path::PathBuf::new().as_os_str().is_empty() }
pub fn std_written_from() { let _p = std::path::PathBuf::from("x"); }
pub mod tree_use {
    use crate::mypath::PathBuf;
    pub fn tree_new() -> u32 { let p = PathBuf::new(); p.s }
    pub fn tree_from() -> u32 { let p = PathBuf::from("x"); p.s }
}
pub fn tree_written() -> u32 { let p = crate::mypath::PathBuf::from("x"); p.s }
pub mod bare_from {
    use crate::mypath::PathBuf;
    pub fn bare_from() -> PathBuf { From::from("x") }
}
pub mod turbo_use {
    use crate::test_helpers::Holder;
    pub fn turbo() { let _h = Holder::<u32>::new(); }
}
pub fn io_error() { let _e = std::io::Error::from(std::io::ErrorKind::Other); }
pub fn trait_next(it: &mut crate::errs::Iterator) -> Option<u32> { std::iter::Iterator::next(it) }
pub mod std_proc {
    use std::process::Command;
    pub fn std_command() { let _c = Command::new("x"); }
}
