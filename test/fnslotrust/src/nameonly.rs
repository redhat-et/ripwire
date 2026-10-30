// FN-SLOT S2 fixture (test/fnslotcheck.sh L4): a Rust typed slot beside a name-only store of the same field.
pub struct SnHold { pub snfn: fn(u32) -> u32 }
pub fn sn_typed(x: u32) -> u32 { x }
pub fn sn_loose(x: u32) -> u32 { x + 1 }
impl SnHold {
    pub fn new() -> SnHold { SnHold { snfn: sn_typed } }
    pub fn fire(&self) -> u32 { (self.snfn)(1) }
}
pub fn sn_stray() { let mut v = sn_unknown_make(); v.snfn = sn_loose; }
