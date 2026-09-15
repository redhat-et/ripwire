public class Widget {
    public Widget() {}
    public static String makeFn(Object value) { return String.valueOf(value); }
    public static String pkgFn(Object value) { return String.valueOf(value); }
    public static String afterLocalFn(Object value) { return String.valueOf(value); }
    public static String siblingFn(Object value) { return String.valueOf(value); }
    public String instanceFn(Object value) { return String.valueOf(value); }
    public String localShadowFn(Object value) { return String.valueOf(value); }
    public String fieldShadowFn(Object value) { return String.valueOf(value); }
    public String lambdaInfFn(Object value) { return String.valueOf(value); }
    public String lambdaParenFn(Object value) { return String.valueOf(value); }
}
