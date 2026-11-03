use r_api::Renderer;
pub struct Spy(u32);
impl Renderer for Spy {
    fn name(&self) -> &str { "spy" }
    fn render(&self, x: u32) -> u32 { self.0 + x }
}
