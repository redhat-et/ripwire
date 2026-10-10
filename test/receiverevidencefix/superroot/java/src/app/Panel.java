package app;

import outside.Factory;

public class Panel extends Base {
    public String typed() {
        Widget base = new Widget();
        return base.render();
    }

    public String untyped() {
        var base = Factory.make();
        return base.render();
    }

    public String realSuper() {
        return super.render();
    }
}
