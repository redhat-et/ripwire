// The other precise-capturing spellings: lifetimes and type parameters in the list, `impl use<..> + Trait`, a trait
// method declaration, and a bound split across lines.
pub struct Buffer<'a> {
    text: &'a str,
}

impl<'a> Buffer<'a> {
    pub fn edit<T: Clone>(&self, value: T) -> impl Iterator<Item = T> + use<'a, T> {
        std::iter::repeat(value).take(self.text.len())
    }

    pub fn chars_of(&self) -> impl use<'a> + Iterator<Item = char> {
        self.text.chars()
    }

    pub fn lines_of(&self) -> impl Iterator<Item = &'a str>
        + use<'a>
    {
        self.text.lines()
    }
}

pub trait Source {
    fn items(&self) -> impl Iterator<Item = u8> + use<Self>;
}

impl Source for Buffer<'_> {
    fn items(&self) -> impl Iterator<Item = u8> + use<'_> {
        self.text.bytes().collect::<Vec<_>>().into_iter()
    }
}
