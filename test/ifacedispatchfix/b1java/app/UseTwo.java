package app;
public class UseTwo {
  static void runTwo(Two t) { t.first(); }
  static void main() {
    runTwo(new TwoImpl());
    runTwo(new Two() { public void first() { System.err.println("anon"); } public void second() { } });
  }
}
