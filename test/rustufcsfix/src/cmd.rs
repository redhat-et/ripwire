pub trait Command {
    fn run(&self, x: i32) -> i32;
}
pub trait Shape {
    fn area(&self) -> i32;
}
