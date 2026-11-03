package app;
public class Use {
    public static int run(Cmp c) { return c.compare("a", "b"); }
    public static int lam() { return run((a, b) -> a.compareTo(b)); }
}
