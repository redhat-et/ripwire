// the namesake: same directory as every caller
pub struct TestClient;
impl TestClient {
    pub fn new(n: u32) -> Self { TestClient }
}
pub fn helper_glob() -> u32 { 0 }
pub struct Holder<T> { pub t: Option<T> }
impl<T> Holder<T> {
    pub fn new() -> Self { Holder { t: None } }
}
