from pkg.shapes import Base, Widget, make_base


class Panel(Base):
    def typed(self):
        base = Widget()
        return base.render()

    def untyped(self):
        base = make_base()
        return base.render()

    def shadowed(self):
        super = make_base()
        return super.render()

    def real_super(self):
        return super().render()
