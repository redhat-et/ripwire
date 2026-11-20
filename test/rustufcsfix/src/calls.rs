use crate::cmd::{Command, Shape};
use crate::impls::Where;
// (a) Where's impl of Command::run, one row, no via=name
pub fn cast_call() -> i32 {
    <Where as Command>::run(&Where, 1)
}
// (b) Where's inherent helper, one row, no via=name
pub fn inherent_call() -> i32 {
    <Where>::helper(&Where)
}
// (c) negative: Twin names two types; the call splits over both, never every `run`
pub fn twin_call(t: &dyn Command) -> i32 {
    <Twin as Command>::run(t, 2)
}
// (d) negative: String is no type of the tree; the call is declined, no row
pub fn external_call() -> String {
    <String as Clone>::clone(&String::new())
}
// (e) negative: through a trait object, the trait's implementors, hedged (via=name), never Runner::run
pub fn dyn_call(s: &dyn Shape) -> i32 {
    <dyn Shape>::area(s)
}
// (f) negative: T is a type parameter; Command's implementors, hedged, never Runner::run
pub fn generic_call<T: Command>(t: &T) -> i32 {
    <T as Command>::run(t, 1)
}
