// arm (N5): names this file does not import from std prove nothing, and a foreign glob hides the prelude
use foreign_crate::prelude::*;
use other_maps::HashMap;

use crate::Shelf;

pub fn foreign_map(m: &HashMap<String, u32>, s: &Shelf) -> u32 {
    let _ = s;
    *m.get("k").unwrap()
}
pub fn glob_option(o: Option<u32>) -> Option<u32> {
    o.map(|x| x + 1)
}
pub fn unimported(d: Duration) -> u32 {
    d.source()
}

pub struct Rack;
impl Rack {
    pub fn get(&self, _k: &str) -> u32 {
        4
    }
    pub fn map(&self) -> u32 {
        5
    }
    pub fn source(&self) -> u32 {
        6
    }
}
