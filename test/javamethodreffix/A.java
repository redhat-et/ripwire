import java.util.List;
import java.util.function.Function;
import java.util.function.Supplier;

public class A extends Base {
    public List<String> lambdaForm(List<Object> in) {
        return in.stream().map(item -> Widget.makeFn(item)).toList();
    }

    public List<String> typeMethod(List<Object> in) {
        return in.stream().map(Widget::makeFn).toList();
    }

    public List<String> nestedTypeMethod(List<Object> in) {
        return in.stream().map(Outer.Inner::makeFn).toList();
    }

    public List<String> genericTypeMethod(List<Object> in) {
        return in.stream().map(Widget::<Object>makeFn).toList();
    }

    public Function<Object, String> instanceMethod(Widget widget) {
        return widget::instanceFn;
    }

    public Function<Object, String> instanceSameName(Widget widget) {
        return widget::makeFn;
    }

    public Function<Object, String> shadowedTypeName(Widget Widget) {
        return Widget::instanceFn;
    }

    public Function<Object, String> localShadowedTypeName() {
        Widget Widget = null;
        return Widget::localShadowFn;
    }

    public Function<Object, String> localDeclaredAfter() {
        Function<Object, String> ref = Widget::afterLocalFn;
        Widget Widget = null;
        return ref;
    }

    public Function<Object, String> siblingBlockLocal() {
        if (true) {
            Widget Widget = null;
        }
        return Widget::siblingFn;
    }

    public List<String> packageQualified(List<Object> in) {
        return in.stream().map(com.example.Widget::pkgFn).toList();
    }

    public List<String> nestedInnerLocal(List<Object> in) {
        Object Inner = null;
        return in.stream().map(Outer.Inner::nestedInnerFn).toList();
    }

    public List<String> nestedLeadingShadow(List<Object> in) {
        Outer Outer = null;
        return in.stream().map(Outer.Inner::leadingShadowFn).toList();
    }

    public Function<Object, String> inferredLambdaParam() {
        Function<Object, String> ignore = Widget -> Widget::lambdaInfFn;
        return ignore;
    }

    public Function<Object, String> inferredParenLambdaParam() {
        Function<Object, String> ignore = (Widget) -> Widget::lambdaParenFn;
        return ignore;
    }

    public Function<Object, String> thisMethod() {
        return this::thisFn;
    }

    public Function<Object, String> thisSameName() {
        return this::makeFn;
    }

    public Function<Object, String> superMethod() {
        return super::superFn;
    }

    public Function<Object, String> superSameName() {
        return super::makeFn;
    }

    public Supplier<Widget> typeNew() {
        return Widget::new;
    }

    public String makeFn(Object value) { return String.valueOf(value); }
    public String thisFn(Object value) { return String.valueOf(value); }
}

class Base {
    public String makeFn(Object value) { return String.valueOf(value); }
    public String superFn(Object value) { return String.valueOf(value); }
}

class FieldShadowHost {
    Widget Widget;
    public Function<Object, String> fieldShadowedTypeName() {
        return Widget::fieldShadowFn;
    }
}
