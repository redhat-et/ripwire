// [N] two globs both bring a TestClient: no `use` chooses one
use crate::test_helpers::*;
use crate::other_helpers::*;
pub fn two_globs() { let _c = TestClient::new(1); }
