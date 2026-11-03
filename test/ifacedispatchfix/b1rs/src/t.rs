pub trait Ext {
    fn helper(&self) -> u32 { 7 }
}
pub trait Foo: Ext {
    fn a(&self) -> u32;
}
pub struct X;
impl X {
    pub fn helper(&self) -> u32 { 1 }
    pub fn only_inherent(&self) -> u32 { 2 }
}
impl Ext for X {}
impl Foo for X {
    fn a(&self) -> u32 { 3 }
}
pub trait Write {
    fn write_all(&mut self, b: &[u8]);
}
pub struct Sink;
impl Write for Sink {
    fn write_all(&mut self, _b: &[u8]) {}
}
pub trait Bar { fn b(&self) -> u32; }
pub struct Y;
impl Bar for Y { fn b(&self) -> u32 { 4 } }

impl Ext for Y {}
