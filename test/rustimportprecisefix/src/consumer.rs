use crate::geo::helper;
use crate::util::utilfn;
use std::collections::HashMap;

pub fn use_crate_helper() -> i32 {
    helper()
}

pub fn use_crate_util() -> i32 {
    utilfn()
}

pub fn use_std() -> HashMap<i32, i32> {
    HashMap::new()
}
