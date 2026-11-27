pub fn make() -> crate::facade::Config {
    crate::model::Config
}

pub fn use_it() -> u32 {
    let c = make();
    c.get()
}
