pub struct Spy(u32);
impl Spy {
    pub fn run(&self) -> u32 { self.0 }
}
