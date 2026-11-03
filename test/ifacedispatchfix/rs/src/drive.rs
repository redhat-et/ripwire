use crate::render::{Lonely, Renderer};
use crate::solo::Solo;

pub struct Host {
    pub boxed: Box<dyn Renderer>,
}

impl Host {
    pub fn host_field(&self) -> u32 {
        self.boxed.render(1)
    }
}

pub fn dyn_ref(r: &dyn Renderer) -> u32 {
    r.render(2)
}

pub fn dyn_box(r: Box<dyn Renderer>) -> u32 {
    r.render(3)
}

pub fn impl_param(r: impl Renderer) -> u32 {
    r.render(4)
}

pub fn impl_ref(r: &impl Renderer) -> u32 {
    r.render(5)
}

pub fn bound_generic<R: Renderer>(r: &R) -> u32 {
    r.render(6)
}

pub fn where_generic<R>(r: &R) -> u32
where
    R: Renderer,
{
    r.render(7)
}

pub fn let_dyn(h: &Host) -> u32 {
    let r: &dyn Renderer = h.boxed.as_ref();
    r.render(8)
}

pub fn default_label(r: &dyn Renderer) -> String {
    r.label()
}

pub fn solo_dyn(s: &dyn Solo) -> u32 {
    s.solo_step()
}

pub fn lonely_dyn(l: &dyn Lonely) -> u32 {
    l.lonely_call()
}
