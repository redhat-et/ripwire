package app;

public class Buffer {
    protected StringBuilder data = new StringBuilder();

    public void flush() {
        data.setLength(0);
    }

    public void write(String s) {
        data.append(s);
        flush();
    }
}
