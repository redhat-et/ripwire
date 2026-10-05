// A method spelled like the outside crate's free function.
pub struct History {
    pub lines: Vec<String>,
}

impl History {
    pub fn render(&self) -> usize {
        self.lines.len()
    }
}
