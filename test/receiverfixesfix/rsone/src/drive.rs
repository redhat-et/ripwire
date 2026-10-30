use crate::api::Renderer;
pub struct Local;
impl Local {
    pub fn name(&self) -> u32 { 5 }
}
pub fn by_name(r: &dyn Renderer) -> u32 { r.name() }
pub fn by_render(r: &dyn Renderer) -> u32 { r.render(1) }
