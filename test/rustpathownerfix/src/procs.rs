pub use crate::gen::Command;

impl Command {
    pub fn new(program: &str) -> Self { Command { program: program.len() as u32 } }
}
