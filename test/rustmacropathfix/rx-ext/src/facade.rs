#[cfg(feature = "external")]
pub use external_crate::Config;

#[cfg(not(feature = "external"))]
pub use crate::model::Config;
