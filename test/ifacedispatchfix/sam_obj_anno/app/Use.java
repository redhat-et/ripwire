package app;
public class Use {
    public static int run(Hasher h) { return h.hash("a"); }
    public static int lam() { return run(String::length); }
}
