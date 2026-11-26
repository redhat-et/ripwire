// test/rustqualcheck.sh §5b RUST-PATH-OWNER: a Rust path call `T::m( .. )` names the ONE type T resolves to where it is written.
// Two in-tree types share the name TestClient (test_helpers/test_client.rs, other_helpers.rs), one shares std's PathBuf
// (mypath.rs), and procs.rs's `impl Command` is for a type only a `use` into the tree names (gen.rs makes it in a macro).
// Every caller sits in src/, the directory of the wrong namesake, so a locality pick lands on it.
pub mod test_helpers;
pub mod other_helpers;
pub mod mypath;
pub mod ext;
pub mod calls;
pub mod globs;
pub mod far;
pub mod errs;
pub mod gen;
pub mod procs;
