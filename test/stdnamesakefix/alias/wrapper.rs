pub struct Wrap<T>(pub T);
impl<T> Wrap<T> {
    pub fn touch(&self) -> u32 {
        5
    }
}
