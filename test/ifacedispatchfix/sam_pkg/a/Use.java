package a;
public class Use {
    public static void run(Handler h) { h.handle("x"); }
    public static void lam() { run(s -> {}); }
}
