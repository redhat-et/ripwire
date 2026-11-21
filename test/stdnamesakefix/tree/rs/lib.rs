// test/stdmembergatecheck.sh arm (N), lane std-namesake: receivers WRITTEN as a standard type (Rust).
// Shelf is the in-tree namesake: it defines get / map / clone / text / source, names the standard types define too.
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

pub struct Shelf {
    pub items: Vec<u32>,
}

impl Shelf {
    pub fn get(&self, i: usize) -> u32 {
        self.items[i]
    }
    pub fn map(&self) -> u32 {
        1
    }
    pub fn clone(&self) -> Shelf {
        Shelf { items: Vec::new() }
    }
    pub fn text(&self) -> u32 {
        2
    }
    pub fn source(&self) -> u32 {
        3
    }
}

pub struct Store {
    pub opt: Option<u32>,
    pub names: Vec<String>,
    pub table: HashMap<String, u32>,
    pub inner: Shelf,
    pub shared: Arc<Shelf>,
}

pub struct Deep {
    pub store: Store,
}

fn make_shelf() -> Shelf {
    Shelf { items: Vec::new() }
}

// ── (N1) POSITIVES: the receiver is written as a standard type; Shelf's namesake is no callee ──────────────
pub fn local_map() -> u32 {
    let m: HashMap<String, u32> = HashMap::new();
    *m.get("k").unwrap()
}
pub fn param_map(m: &HashMap<String, u32>) -> u32 {
    *m.get("k").unwrap()
}
pub fn param_vec(v: &Vec<Shelf>) -> usize {
    v.clone().len()
}
pub fn param_string(t: String) -> usize {
    t.clone().len()
}
pub fn param_str(s: &str) -> usize {
    s.text().len()
}
pub fn param_slice(xs: &[u32]) -> Option<&u32> {
    xs.get(0)
}
pub fn param_option(o: Option<u32>) -> Option<u32> {
    o.map(|x| x + 1)
}
pub fn param_arc_mutex(a: Arc<Mutex<u32>>) -> Arc<Mutex<u32>> {
    a.clone()
}
pub fn qualified_path(m: std::collections::BTreeMap<String, u32>) -> Option<u32> {
    m.get("k").copied()
}
impl Store {
    pub fn field_opt(&self) -> Option<u32> {
        self.opt.map(|x| x + 1)
    }
    pub fn field_vec(&self) -> Option<&String> {
        self.names.get(0)
    }
    pub fn field_table(&self) -> Option<&u32> {
        self.table.get("k")
    }
}
impl Deep {
    pub fn two_hop(&self) -> Option<&u32> {
        self.store.table.get("k")
    }
}
pub fn field_of_local(s: &Store) -> Option<&u32> {
    s.table.get("k")
}
pub fn payload_some(o: Option<Vec<u32>>) -> usize {
    if let Some(x) = &o {
        return x.clone().len();
    }
    0
}
pub fn payload_err(r: Result<u32, String>) -> usize {
    if let Err(e) = r {
        return e.clone().len();
    }
    0
}

// ── (N2) NEGATIVES: an in-tree receiver keeps its edge ──────────────────────────────────────────────────────
pub fn in_repo_param(s: &Shelf) -> u32 {
    s.map()
}
impl Store {
    pub fn field_inner(&self) -> u32 {
        self.inner.map()
    }
}
impl Deep {
    pub fn two_hop_inner(&self) -> u32 {
        self.store.inner.map()
    }
}

// ── (N3) NEGATIVES: the receiver is not the std binding itself, or its type is not written: the name tier stands ──
pub fn untyped_local() -> u32 {
    let y = make_untyped();
    y.map()
}
fn make_untyped() -> impl Sized {
    make_shelf()
}
pub fn index_elem(v: &Vec<Shelf>) -> u32 {
    v[0].map()
}
pub fn try_payload(o: Option<Shelf>) -> Option<u32> {
    Some(o?.map())
}
pub fn unwrap_payload(o: Option<Shelf>) -> u32 {
    o.unwrap().map()
}
pub fn arc_deref(a: Arc<Shelf>) -> u32 {
    a.map()
}
pub fn box_deref(a: Box<Shelf>) -> u32 {
    a.map()
}
pub fn arc_field(s: &Store) -> u32 {
    s.shared.map()
}
pub fn shadow_inner(m: &HashMap<String, u32>, f: impl Fn() -> Shelf) -> u32 {
    {
        let m = f();
        m.map()
    }
}
pub fn closure_shadow(m: &HashMap<String, u32>, shelves: &[Shelf]) -> u32 {
    shelves.iter().map(|m| m.text()).sum::<u32>() + m.len() as u32
}
pub fn payload_intree(o: Option<Shelf>) -> u32 {
    if let Some(x) = o {
        return x.map();
    }
    0
}
pub fn payload_shadowed(o: Option<Vec<u32>>) -> u32 {
    let o = Some(make_shelf());
    if let Some(x) = o {
        return x.map();
    }
    0
}
pub fn payload_ok_of_err(r: Result<Shelf, String>) -> u32 {
    if let Ok(x) = r {
        return x.map();
    }
    0
}
pub fn generic_named_like_std<Vec: Sized>(v: Vec, s: &Shelf) -> u32 {
    let _ = v;
    s.text()
}

// ── (N4) the way back: a TRAIT reaches a standard receiver; a struct's namesake does not ───────────────────────
pub trait VecExt {
    fn total(&self) -> u32;
    fn source(&self) -> u32 {
        7
    }
}
impl VecExt for Vec<u32> {
    fn total(&self) -> u32 {
        self.iter().sum()
    }
}
pub type Table = HashMap<String, u32>;
pub trait TableExt {
    fn text(&self) -> u32;
}
impl TableExt for Table {
    fn text(&self) -> u32 {
        9
    }
}
pub fn ext_call(v: &Vec<u32>) -> u32 {
    v.total() + v.source()
}
pub fn alias_impl_call(m: &HashMap<String, u32>) -> u32 {
    m.text()
}
