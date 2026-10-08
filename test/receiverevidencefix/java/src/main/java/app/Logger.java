package app;

import static org.markup.Html.render;

// A bare call is this.method() or a static import: Logger inherits flush() from an OUTSIDE class and
// imports render() from an outside package; Exporter and Buffer are unrelated.
public class Logger extends java.io.Writer {
    public String line(String s) {
        return render(s);
    }

    public void close() {
        flush();
        reset();
    }

    private void reset() {
        System.out.println("logger reset");
    }
}
