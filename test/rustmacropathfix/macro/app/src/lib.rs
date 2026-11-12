use thing_core::__define_thing as define_thing;

pub fn app_alias() {
    define_thing!(Eta);
}

pub fn app_path() {
    thing_core::__define_thing!(Theta);
}

pub fn app_ext() -> u32 {
    serde_json::json!(3);
    0
}

define_thing! { Iota }
