#[cfg(feature = "a")]
pub use crate::other::Config;

#[cfg(not(feature = "a"))]
pub use crate::model::Config;
