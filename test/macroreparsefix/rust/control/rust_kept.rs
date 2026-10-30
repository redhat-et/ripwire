// A `+ use<>` the first parse recovers with a zero-width MISSING node, next to an unrelated error blanking cannot
// reduce: the scanner names the bound, the re-parse holds the SAME error bytes, so the first tree is KEPT.
pub struct Editor {
    text: String,
}

impl Editor {
    pub fn chars_of(&self) -> impl Iterator<Item = char> + use<> {
        self.text.clone().into_chars()
    }

    pub fn broken(&self) -> u32 {
        let x = ;
        7
    }
}
