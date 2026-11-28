// A user macro with a block arm (axum's `tap_inner!` shape), and one that takes an expression.
macro_rules! tap {
    ( $owner:ident, mut $this:ident => { $($body:tt)* } ) => {{
        let mut $this = $owner;
        $($body)*
        $this
    }};
}

// axum's `map_inner!` shape: the arm body is a struct expression, not a block.
macro_rules! remap {
    ( $owner:ident, $this:ident => $body:expr ) => {{
        let $this = $owner;
        $body
    }};
}

macro_rules! checked {
    ( $value:expr ) => {
        $value
    };
}

// N5: a definition site. `$value.ghost_method()` and `ghost_call( $value )` are the transcriber's tokens: never calls of an enclosing
// function (the macro-args re-read), only the macro's own (BX2 FIX 5, a role="macro" row of def_site).
macro_rules! def_site {
    ( $value:expr ) => {
        assert!($value.ghost_method());
        crate::ghost_call($value)
    };
}

macro_rules! sql {
    ( $($tokens:tt)* ) => {
        ()
    };
}

macro_rules! quote {
    ( $($tokens:tt)* ) => {
        ()
    };
}
