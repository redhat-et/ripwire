use crate::cmd::Command;
pub struct Twin;
impl Command for Twin {
    fn run(&self, x: i32) -> i32 { x + 20 }
}
