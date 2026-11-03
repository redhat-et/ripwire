use crate::t::{Foo, Bar};
use std::io::Write;
pub fn via_ext(x: &dyn Foo) -> u32 { x.helper() }
pub fn via_inherent(x: &dyn Foo) -> u32 { x.only_inherent() }
pub fn via_std(w: &mut dyn Write) { w.write_all(b"x").unwrap(); }
pub fn via_std_q(w: &mut dyn std::io::Write) { w.write_all(b"x").unwrap(); }
pub fn via_two<T: Foo + Bar>(x: &T) -> u32 { x.b() }
pub fn via_box(x: Box<dyn Foo>) -> u32 { x.a() }
