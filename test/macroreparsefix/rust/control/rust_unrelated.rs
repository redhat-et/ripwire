// An error blanking cannot reduce: the bound spelling appears only in a comment (`+ use<>`), a string and a raw
// string, and as the raw identifier r#use, so the scanner names nothing and the first tree is KEPT.
pub struct Editor {
    text: String,
}

impl Editor {
    pub fn backspace(&mut self) {
        let note = "+ use<> is a bound";
        let raw = r#"impl use<'a> + Sized"#;
        let r#use = note.len() + raw.len();
        self.text.truncate(r#use);
    }

    pub fn broken(&self) -> u32 {
        let x = ;
        7
    }
}
