import Outside

class Panel: Base {
    func typed() -> String {
        let base = Widget()
        return base.render()
    }

    func untyped() -> String {
        let base = makeAny()
        return base.render()
    }

    func realSuper() -> String {
        return super.render()
    }
}
