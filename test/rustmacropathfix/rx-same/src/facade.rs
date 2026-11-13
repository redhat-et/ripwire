#[cfg(feature = "a")]
pub use crate::model::Config;

#[cfg(not(feature = "a"))]
pub use crate::model::Config;
