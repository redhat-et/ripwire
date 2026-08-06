// Every PLACE a Rust `use` can be written that is not a crate-root item, plus the `mod x;` control that
// must NOT regress: a body-LESS `mod` declares a sibling FILE and is emitted as `mod:x`, and the walk
// descends into `mod x { … }` for its inner `use`s — the same node kind has to do both, so a descent
// that swallowed the node instead of also reading it would silently drop every module-file declaration.
//
// `#[cfg(unix)] mod plat { … }` is the Rust spelling of a platform guard: exactly the C `#ifdef` shape,
// and its contents were invisible for the same reason.
//
// ONE DISTINCT MODULE NAME PER ARM, and one arm per node kind in the Rust container table — an entry
// with no arm here is an untested claim, so the table and this file are kept in lockstep.

use std::fmt;                                   // CONTROL — a crate-root use, captured before and after

pub mod sibling_decl;                           // CONTROL — body-LESS `mod` → emitted as `mod:sibling_decl`

#[cfg(unix)]
mod plat                                        // mod_item → declaration_list
{
    use crate::unix_inner;

    mod deeper                                  // nested mod_item → declaration_list
    {
        use crate::deeper_inner;
    }

    pub fn platform_fn() {}
}

extern "C"                                      // foreign_mod_item → declaration_list
{
    use crate::foreign_inner;
    pub fn c_fn();
}

fn free_fn()                                    // function_item → block
{
    use crate::fn_local;
    let _ = fn_local::VALUE;
}

struct Thing;

impl Thing                                      // impl_item → declaration_list → function_item → block
{
    fn method( &self )
    {
        use crate::impl_local;
        let _ = impl_local::VALUE;
    }
}

trait Shape                                     // trait_item → declaration_list → function_item → block
{
    fn area( &self ) -> f64
    {
        use crate::trait_default_local;
        trait_default_local::AREA
    }
}

fn control_flow( n: i32 ) -> i32
{
    if n > 0                                    // if_expression → block
    {
        use crate::if_local;
        return if_local::VALUE;
    }
    else                                        // else_clause → block
    {
        use crate::else_local;
        return else_local::VALUE;
    }
}

fn loops()
{
    loop                                        // loop_expression → block
    {
        use crate::loop_local;
        let _ = loop_local::VALUE;
        break;
    }
    while false                                 // while_expression → block
    {
        use crate::while_local;
        let _ = while_local::VALUE;
    }
    for _ in 0..1                               // for_expression → block
    {
        use crate::for_local;
        let _ = for_local::VALUE;
    }
}

fn matching( n: i32 ) -> i32
{
    match n                                     // match_expression → match_block → match_arm → block
    {
        0 =>
        {
            use crate::match_local;
            match_local::VALUE
        }
        _ => 1,
    }
}

fn blocks()
{
    unsafe                                      // unsafe_block → block
    {
        use crate::unsafe_local;
        let _ = unsafe_local::VALUE;
    }
    let _fut = async                            // async_block → block
    {
        use crate::async_local;
        let _ = async_local::VALUE;
    };
}
