from pkg.cache import cache_get
from pkg.gizmoloader import load_gizmo
from pkg.sinkwriter import write_sink
from pkg.widgetparsers import WidgetError
from pkg.widgetstore import open_widget_store


def load(text):
    try:
        return [load_gizmo(text), cache_get(text), open_widget_store(text), write_sink(text)]
    except WidgetError:
        return []


def main():
    return load("a,b") + load("c")


def run():
    return main() + main()
