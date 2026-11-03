pub mod impls;

pub trait Renderer {
    fn render(&self, n: u32) -> u32;
    fn label(&self) -> String {
        String::from("renderer")
    }
}

pub trait Lonely {
    fn lonely_call(&self) -> u32;
}

pub struct Plain;

impl Plain {
    pub fn lonely_call(&self) -> u32 {
        1
    }
}

pub struct Other2;

impl Other2 {
    pub fn lonely_call(&self) -> u32 {
        2
    }
}
