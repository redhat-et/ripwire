// RUST-MACRO-PATH fixture (test/rustmacropathcheck.sh): exported macros reached through a path or a `use … as` alias
#[macro_export]
macro_rules! __define_thing {
    ($name:ident) => {
        pub struct $name;
    };
}

#[macro_export]
macro_rules! other_thing {
    ($name:ident) => {
        pub struct $name;
    };
}

// a transcriber that invokes a sibling through `$crate::`
#[macro_export]
macro_rules! wrap_thing {
    ($name:ident) => {
        $crate::other_thing!($name);
    };
}

// an in-tree namesake of an outside crate's macro (`serde_json::json!`)
#[macro_export]
macro_rules! json {
    ($e:tt) => {
        0
    };
}
