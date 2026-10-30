pub struct Spy(pub u32);
impl crate::api::Renderer for Spy {
    fn render(&self, x: u32) -> u32 { x * 2 }
}
