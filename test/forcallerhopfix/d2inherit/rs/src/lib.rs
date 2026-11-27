pub struct Ledger;

impl Ledger {
    pub fn post_entry(&self, e: i32) -> i32 {
        e
    }
}

pub fn proven_hop(led: &Ledger) -> i32 {
    led.post_entry(1)
}

pub fn name_hop(x: Box<dyn std::any::Any>) -> i32 {
    let v = x.downcast::<Ledger>().unwrap();
    v.post_entry(2)
}

pub struct Svc;

impl Svc {
    pub fn relay(&self, led: &Ledger) -> i32 {
        led.post_entry(3)
    }
}

pub fn only_by_name() -> i32 {
    name_hop(Box::new(Ledger))
}

pub fn both_paths() -> i32 {
    proven_hop(&Ledger) + name_hop(Box::new(Ledger))
}

pub fn by_name_edge(s: Box<dyn std::any::Any>) -> i32 {
    s.relay(&Ledger)
}
