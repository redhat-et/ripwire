// An inherent method and the trait's method share a name: through `&dyn Step` only the trait impl's can run.
pub trait Step {
    fn go(&self) -> u32;
}

pub struct Z;

impl Z {
    pub fn go(&self) -> u32 {
        1
    }
}

impl Step for Z {
    fn go(&self) -> u32 {
        2
    }
}

pub fn via_dup(z: &dyn Step) -> u32 {
    z.go()
}

impl Z {
    pub fn len(&self) -> usize {
        0
    }
}

pub fn std_len(v: &Vec<u32>) -> usize {
    v.len()
}
