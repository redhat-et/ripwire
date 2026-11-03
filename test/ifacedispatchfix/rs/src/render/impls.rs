use super::Renderer;

pub struct Html;
pub struct Markdown;
pub struct Pdf;
pub struct Epub;
pub struct Text;

impl Renderer for Html {
    fn render(&self, n: u32) -> u32 {
        n + 1
    }
}

impl Renderer for Markdown {
    fn render(&self, n: u32) -> u32 {
        n + 2
    }
}

impl Renderer for Pdf {
    fn render(&self, n: u32) -> u32 {
        n + 3
    }
}

impl Renderer for Epub {
    fn render(&self, n: u32) -> u32 {
        n + 4
    }
    fn label(&self) -> String {
        String::from("epub")
    }
}

impl Renderer for Text {
    fn render(&self, n: u32) -> u32 {
        n + 5
    }
}

#[cfg(test)]
mod tests {
    use super::super::Renderer;

    struct FakeRenderer;

    impl Renderer for FakeRenderer {
        fn render(&self, n: u32) -> u32 {
            n
        }
    }

    #[test]
    fn fake_renders() {
        assert_eq!(FakeRenderer.render(1), 1);
    }
}
