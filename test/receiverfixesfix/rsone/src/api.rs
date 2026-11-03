pub trait Renderer {
    fn render(&self, x: u32) -> u32;
    fn name(&self) -> u32 { 0 }
}
