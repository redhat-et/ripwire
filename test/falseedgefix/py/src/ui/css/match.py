"""Selector matching: the module-level function the widget imports."""


def match(selector_sets, node) -> bool:
    return any(node in s for s in selector_sets)
