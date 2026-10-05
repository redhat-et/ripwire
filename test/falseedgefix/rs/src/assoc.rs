use crate::history::History;

impl History {
    pub fn new() -> History { History { lines: Vec::new() } }
    fn count(&self) -> usize { Self::width() + 1 }
    fn width() -> usize { 3 }
}

pub fn build() -> usize {
    let h = History::new();
    History::render(&h)
}
