// a second trait of the same name: impl blocks are keyed by NAME, so the open-list rule answers nothing here
pub trait Renderer {
    fn render(&self, x: u32) -> u32;
}
pub struct Spy(u32);
impl Renderer for Spy {
    fn render(&self, x: u32) -> u32 { self.0 + x }
}
