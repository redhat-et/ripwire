pub struct Spy(u32);
impl crate::Renderer for Spy {
    fn render(&self, x: u32) -> u32 { self.0 * x }
}
