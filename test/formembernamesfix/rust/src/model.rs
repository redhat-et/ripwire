//! The book driver: loads a book and hands it to each renderer backend.

pub trait Renderer {
    fn name(&self) -> &str;

    fn supports(&self, format: &str) -> bool {
        format == self.name()
    }
}

pub struct BookDriver {
    root: String,
}

pub fn run_renderers(driver: &BookDriver) -> usize {
    driver.root.len()
}
