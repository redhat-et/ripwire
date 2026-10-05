mod history;

use history::History;
use termkit::render;

// render is the outside crate's free function: a bare call never reaches History::render.
pub fn draw(rows: usize) -> usize {
    render(rows)
}

fn helper(n: usize) -> usize {
    n + 1
}

// True edges: a same-module free function called bare, and the method through a receiver.
pub fn paint(h: &History) -> usize {
    helper(h.render())
}
mod assoc;
mod ufcs;
