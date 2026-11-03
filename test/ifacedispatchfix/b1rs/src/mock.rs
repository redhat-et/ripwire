// envoy's dynamic-module SDK shape: mockall's attribute writes `impl Filter for MockFilter`, an implementor no source holds.
#[cfg_attr(any(test, feature = "mock"), automock)]
pub trait Filter {
    fn send_response(&self, code: u32) -> u32;
}

pub struct FilterImpl;

impl Filter for FilterImpl {
    fn send_response(&self, code: u32) -> u32 {
        code
    }
}

pub fn send_500<F: Filter>(f: &F) -> u32 {
    f.send_response(500)
}
