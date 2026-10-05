use crate::history::History;

pub trait Render {
    fn render_all(&self) -> usize;
}

impl Render for History {
    fn render_all(&self) -> usize {
        self.lines.len()
    }
}

// A fully qualified (UFCS) path call: `<History as Render>::render_all( &h )` reaches the trait method — a true edge.
pub fn draw_all(h: &History) -> usize {
    <History as Render>::render_all(h)
}
