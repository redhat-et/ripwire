use crate::__define_thing as define_thing;

pub fn gamma() {
    __define_thing!(Gamma);
}

pub fn alpha() {
    define_thing!(Alpha);
}

pub fn beta() {
    crate::__define_thing!(Beta);
}

pub fn delta() {
    wrap_thing!(Delta);
}

define_thing! { Epsilon }
