pub struct Buffer;
impl Buffer {
    pub fn edit(x: i32) -> i32 { rs_my_edit_helper(x) }
}
fn rs_my_edit_helper(x: i32) -> i32 { x }
pub fn grow(x: i32) -> i32 { rs_free_grow_helper(x) }
fn rs_free_grow_helper(x: i32) -> i32 { x }
fn rs_local_helper() {}
pub fn outer_fn() {
    fn local_fn() { rs_local_helper(); }
    local_fn();
}
