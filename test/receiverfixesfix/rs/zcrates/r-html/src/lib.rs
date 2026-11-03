use r_api::Renderer;
pub struct Html;
impl Renderer for Html {
    fn name(&self) -> &str { "html" }
    fn render(&self, x: u32) -> u32 { x + 1 }
}
