public class Outer {
    public static class Inner {
        public static String makeFn(Object value) { return String.valueOf(value); }
        public static String nestedInnerFn(Object value) { return String.valueOf(value); }
        public static String leadingShadowFn(Object value) { return String.valueOf(value); }
    }
}
