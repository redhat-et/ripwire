use crate::api::Renderer;
pub struct Spy(pub u32);
impl Renderer for Spy {
    fn render(&self, x: u32) -> u32 { self.0 + x }
}
