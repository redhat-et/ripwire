pub struct Foreign;
impl other_crate::Renderer for Foreign {
    fn render(&self, x: u32) -> u32 { x * 7 }
}
