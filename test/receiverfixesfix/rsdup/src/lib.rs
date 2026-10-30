pub mod a;
pub mod b;
pub trait Renderer {
    fn render(&self, x: u32) -> u32;
}
pub struct Book;
impl Book {
    pub fn execute(&self, renderer: &dyn Renderer) -> u32 {
        renderer.render(1)
    }
    pub fn check(&self) -> u32 {
        struct TestRenderer;
        impl Renderer for TestRenderer {
            fn render(&self, _: u32) -> u32 { 0 }
        }
        self.execute(&TestRenderer)
    }
}
