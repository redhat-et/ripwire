package app;

// An unrelated class that happens to define flush() and render().
public class Exporter {
    public void flush() {
        System.out.println("exporter flush");
    }

    public String render(String s) {
        return "<" + s + ">";
    }
}
