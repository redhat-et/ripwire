use crate::{Html, Renderer};

pub struct Cmd {
    cmd: String,
}

impl Cmd {
    pub fn new(cmd: String) -> Cmd {
        Cmd { cmd }
    }
}

impl Renderer for Cmd {
    fn name(&self) -> &str {
        &self.cmd
    }
    fn render(&self, out: &mut String) {
        out.push_str(&self.cmd);
    }
}

pub fn pick_renderers(custom: Option<String>) -> Vec<Box<dyn Renderer>> {
    let mut out: Vec<Box<dyn Renderer>> = Vec::new();
    match custom {
        Some(c) => out.push(Box::new(Cmd::new(c))),
        None => out.push(Box::new(Html)),
    }
    out
}
