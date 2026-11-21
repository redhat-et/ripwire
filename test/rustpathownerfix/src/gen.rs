// a type the index holds no class for: a macro makes it (zed's extension_api: a wit-bindgen `Command`)
macro_rules! make_command { () => { pub struct Command { pub program: u32 } }; }
make_command!();
