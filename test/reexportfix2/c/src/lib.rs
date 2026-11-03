pub mod m;
pub mod inner;
pub mod x;
pub mod private { pub use crate::m::Xray; }
pub(crate) use inner::Hidden;
pub struct Widget;
mod scoped { use crate::inner as m; }
pub use m::Zed;
