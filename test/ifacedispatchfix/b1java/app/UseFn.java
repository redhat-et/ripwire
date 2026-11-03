package app;
public class UseFn {
  static int runFn(Fn f) { return f.apply(1); }
  static int main() { return runFn(new FnImpl()) + runFn(x -> x * 2); }
}
