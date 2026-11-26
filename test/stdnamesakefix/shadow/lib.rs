// arm (N6): a tree that DEFINES `Option` — a written `Option<T>` may be this one, so nothing is proven
pub struct Option<T> {
    pub v: T,
}
impl<T> Option<T> {
    pub fn map(&self) -> u32 {
        1
    }
}
pub struct Other;
impl Other {
    pub fn map(&self) -> u32 {
        2
    }
}
pub fn shadowed(o: &Option<u32>) -> u32 {
    o.map()
}
pub struct Holder {
    pub o: Option<u32>,
}
impl Holder {
    pub fn field(&self) -> u32 {
        self.o.map()
    }
}
