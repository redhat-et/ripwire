class Screen:
    def refresh(self):
        return True

    def collect(self, nodes):
        """A local alias of a list's bound append beside another class's nested add_widget."""
        widgets = []
        add_widget = widgets.append
        for node in nodes:
            add_widget(node)
        return widgets
