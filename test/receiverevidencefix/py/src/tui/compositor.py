class Compositor:
    def arrange_root(self, root):
        placed = []

        def add_widget(widget):
            placed.append(widget)

        for child in root:
            add_widget(child)
        return placed
