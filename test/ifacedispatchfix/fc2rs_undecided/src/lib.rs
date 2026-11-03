pub mod a;
pub mod b;
pub mod run;

pub trait Render {
    fn draw(&self) -> i32;
}
