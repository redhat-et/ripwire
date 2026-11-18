pub struct TestClient { pub n: u32 }
impl TestClient {
    pub fn new(n: u32) -> Self { TestClient { n } }
    pub fn again(&self) -> Self { Self::new(self.n) }
}
pub struct Holder<T> { pub t: Option<T> }
impl<T> Holder<T> {
    pub fn new() -> Self { Holder { t: None } }
}
