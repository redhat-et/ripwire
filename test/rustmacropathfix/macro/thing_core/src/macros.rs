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

// CodeRabbit #627: what the transcriber scan must read as one literal or comment. `ghost` is only ever spelled inside them, so no
// macro below calls it; each also makes one real `$crate::other_thing!` call AFTER the literal, which the scan must still reach.
#[macro_export]
macro_rules! ghost {
    () => {};
}

// a raw string: the embedded `"` does not close it
#[macro_export]
macro_rules! raw_quiet {
    ($name:ident) => {
        const _: &str = r#"a " $crate::ghost!() b"#;
        $crate::other_thing!($name);
    };
}

// a nested block comment: the inner `*/` does not close the outer one
#[macro_export]
macro_rules! nest_quiet {
    ($name:ident) => {
        /* outer /* inner */ $crate::ghost!(); */
        $crate::other_thing!($name);
    };
}

// a char literal `'"'` opens no string, so the real call after it is read
#[macro_export]
macro_rules! char_quiet {
    ($name:ident) => {
        const _: char = '"';
        $crate::other_thing!($name);
    };
}

// CodeRabbit #633: the macro shadow.rs's `exported_mac!()` names, though a function import there is renamed `exported_mac`
#[macro_export]
macro_rules! exported_mac {
    () => {};
}
