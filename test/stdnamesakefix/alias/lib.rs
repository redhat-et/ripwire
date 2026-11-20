// arm (N8) CR706-STD-ALIAS-SHADOW: an import that takes a standard name for another item. Each `touch()` receiver below is
// written as a std name the file has re-bound, so nothing is proven and the name tier stands (hedged); plain.rs's controls,
// whose std names are the standard types, stay proven (no in-tree row).
pub mod widget;
pub mod wrapper;
pub mod text;
pub mod boxed_alias;
pub mod wrap_alias;
pub mod str_alias;
pub mod plain;
