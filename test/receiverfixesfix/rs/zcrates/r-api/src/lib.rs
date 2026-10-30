pub trait Renderer {
    fn name(&self) -> &str;
    fn render(&self, x: u32) -> u32;
}
