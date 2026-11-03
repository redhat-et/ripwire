package app;
public class Use { static int runSub(Sub s) { return s.a(1); } static int lam() { return runSub(x -> x * 2); } }
