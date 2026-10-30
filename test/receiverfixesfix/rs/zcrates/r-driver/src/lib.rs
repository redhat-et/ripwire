use r_api::Renderer;
pub struct Markdown;
impl Renderer for Markdown {
    fn name(&self) -> &str { "md" }
    fn render(&self, x: u32) -> u32 { x + 2 }
}
pub struct Book;
impl Book {
    pub fn execute(&self, renderer: &dyn Renderer) -> u32 {
        renderer.render(1)
    }
    pub fn boxed(&self, renderer: Box<dyn Renderer>) -> u32 {
        renderer.render(2)
    }
    pub fn check(&self) -> u32 {
        struct TestRenderer;
        impl Renderer for TestRenderer {
            fn name(&self) -> &str { "test" }
            fn render(&self, _: u32) -> u32 { 0 }
        }
        self.execute(&TestRenderer)
    }
}
