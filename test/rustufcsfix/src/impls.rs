use crate::cmd::{Command, Shape};
pub struct Where;
impl Command for Where {
    fn run(&self, x: i32) -> i32 { x + 1 }
}
impl Where {
    pub fn helper(&self) -> i32 { 3 }
}
pub struct Other;
impl Command for Other {
    fn run(&self, x: i32) -> i32 { x + 2 }
}
pub struct Sq;
impl Shape for Sq {
    fn area(&self) -> i32 { 4 }
}
pub struct Ci;
impl Shape for Ci {
    fn area(&self) -> i32 { 5 }
}
// a namesake `run` that implements no trait: no `<T as Command>::run` may reach it
pub struct Runner;
impl Runner {
    pub fn run(&self, x: i32) -> i32 { x }
}
