// `Vec` here is std's Box: `v.touch()` is Widget::touch through the box's deref
use crate::widget::Widget;
use std::boxed::Box as Vec;
pub fn via_box(v: Vec<Widget>) -> u32 {
    v.touch()
}
