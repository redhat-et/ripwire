package app;

// Inherited: a bare flush() reaches Buffer.flush through the class cone.
public class FileBuffer extends Buffer {
    public void sync() {
        flush();
    }

    public void drain() {
        super.flush();
    }
}
