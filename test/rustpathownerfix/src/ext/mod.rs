// an in-tree trait impl FOR std's PathBuf (its `PathBuf` is the `use`d one): `PathBuf::from( w )` reaches it only when w is a
// Wrap, and the call's argument is not read, so a std PathBuf path call hedges it; it lives below src/, out of the callers' directory
use std::path::PathBuf;
pub struct Wrap;
impl From<Wrap> for PathBuf {
    fn from(w: Wrap) -> Self { PathBuf::new() }
}
