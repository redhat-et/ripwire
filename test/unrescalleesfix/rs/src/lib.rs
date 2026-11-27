mod key;
pub mod api {
    pub use crate::key::{read_key, KEY_LEN};
}

pub fn load() -> usize {
    api::read_key() + 1
}
