// A clean Rust file: no error bytes, so no re-parse is attempted.
pub struct Editor {
    text: String,
}

impl Editor {
    pub fn backspace(&mut self) {
        self.text.pop();
    }

    pub fn chars_of(&self) -> impl Iterator<Item = char> + '_ {
        self.text.chars()
    }
}
