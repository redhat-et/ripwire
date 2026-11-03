package app;

public class UserF {
    private final Handler anon = new Handler() { public void run() { } };
    public int viaField() {
        anon.run();
        return Handler.of(2);
    }
}
