// outside-crate macro paths: never bound to the in-tree namesake
use serde_json::json as sj;

pub fn ext_path() -> u32 {
    serde_json::json!(1);
    0
}

pub fn ext_alias() -> u32 {
    sj!(2);
    0
}

pub fn ext_other() {
    other_crate::__define_thing!(Zeta);
}
