pub struct Stack { n: usize }
impl Stack {
    pub fn push(&mut self, x: i32) { }
}
pub struct Queue { n: usize }
impl Queue {
    pub fn push(&mut self, x: i32) { }
}
pub fn std_vec() { let mut v = Vec::new(); v.push(1); }
pub fn typed_local() { let mut s = Stack { n: 0 }; s.push(2); }
