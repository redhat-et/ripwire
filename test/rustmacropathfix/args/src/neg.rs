// Tokens that are not an expression of the enclosing function: nothing here is a call.
use crate::{wrap, Shape};

pub fn dsl_quote() {
    let _tokens = quote! {
        fn generated() {
            ghost_call(1)
        }
    };
}

pub fn dsl_sql_block() {
    sql! { SELECT name FROM users WHERE id = ghost_call(1) }
}

pub fn dsl_sql_paren() {
    sql!(SELECT ghost_call(id) FROM users);
}

pub fn dsl_sql_list() {
    sql!(SELECT name, ghost_call(id), other FROM users);
}

pub fn dsl_stringify() -> &'static str {
    stringify!(ghost_call(1))
}

pub fn in_cfg() -> bool {
    cfg!(any(unix, windows))
}

pub fn in_pattern() -> bool {
    matches!(wrap(1), Some(Shape(1)))
}
