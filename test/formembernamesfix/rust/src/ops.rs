//! BookDriver's methods, in an impl block of their own file.
use crate::model::{BookDriver, Renderer};

impl BookDriver {
    pub fn load(root: &str) -> BookDriver {
        BookDriver { root: root.to_string() }
    }

    pub fn execute_build(&self, renderer: &dyn Renderer) -> usize {
        renderer.name().len()
    }

    pub fn source_dir(&self) -> String {
        self.root.clone()
    }

    pub fn theme_dir(&self) -> String {
        format!("{}/theme", self.root)
    }

    pub fn build_dir_for(&self, backend: &str) -> String {
        format!("{}/{}", self.root, backend)
    }
}
