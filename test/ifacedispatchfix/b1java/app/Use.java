package app;
public class Use {
  static void run(Handler h) { h.handle("x"); }
  static void main() {
    run(new LogHandler());
    run(s -> System.err.println(s));
    run(new Handler() { public void handle(String s) { System.err.println("anon" + s); } });
  }
}
