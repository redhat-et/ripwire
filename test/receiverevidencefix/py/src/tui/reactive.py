from .content import Content


def watch(watchers, name, node, callback):
    """list.append / str.split on plain values, in a file that imports Content."""
    watcher_list = watchers.setdefault(name, [])
    watcher_list.append((node, callback))


def toggle(obj, toggle_class: str):
    obj.set_class(True, *toggle_class.split())


def label() -> Content:
    return Content("label")
