// in-tree types named like std's, each implementing a std trait: `impl std::error::Error for Error` is no member of std::io::Error,
// while `impl std::iter::Iterator for Iterator` is one the trait path `std::iter::Iterator::next( &mut it )` may run
use std::fmt;
pub struct Error;
impl fmt::Debug for Error { fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { Ok(()) } }
impl fmt::Display for Error { fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { Ok(()) } }
impl std::error::Error for Error {}
impl From<u32> for Error {
    fn from(n: u32) -> Self { Error }
}
pub struct Iterator;
impl std::iter::Iterator for Iterator {
    type Item = u32;
    fn next(&mut self) -> Option<u32> { None }
}
