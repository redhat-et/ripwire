pub trait Solo {
    fn solo_step(&self) -> u32;
}

pub struct OnlySolo;

impl Solo for OnlySolo {
    fn solo_step(&self) -> u32 {
        42
    }
}
