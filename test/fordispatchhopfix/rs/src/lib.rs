pub mod pick;

pub trait Renderer {
    fn name(&self) -> &str;
    fn render(&self, out: &mut String);
}

pub struct Html;

impl Renderer for Html {
    fn name(&self) -> &str {
        "html"
    }
    fn render(&self, out: &mut String) {
        out.push_str("<html/>");
    }
}

pub fn build_book(r: &dyn Renderer) -> String {
    let mut text = String::with_capacity(64);
    r.render(&mut text);
    text.push('\n');
    text
}
