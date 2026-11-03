package app;
public class LenCmp implements Cmp {
    public int compare(String a, String b) { return a.length() - b.length(); }
}
