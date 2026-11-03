// A same-named trait in another module: its implementor is NOT one of render::Renderer's.
pub trait Renderer {
    fn render(&self, n: u32) -> u32;
}

pub struct Foreign;

impl Renderer for Foreign {
    fn render(&self, n: u32) -> u32 {
        n * 7
    }
}
