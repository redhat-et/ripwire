package app;

public class UserM {
    public int inMethod() {
        Handler h = new Handler() { public void run() { } };
        h.run();
        return Handler.of(1);
    }
}
