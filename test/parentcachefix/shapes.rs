mod shapes {
    pub struct S;
    impl S {
        pub fn make(a: i32) -> S { let _ = a; S }
        pub fn grow(&self, b: i32) -> i32 { b }
    }
    pub mod deeper {
        pub fn reach() -> i32 { super::S::make(1).grow(2) }
    }
}
fn run() -> i32 { shapes::S::make(3); shapes::deeper::reach() }
