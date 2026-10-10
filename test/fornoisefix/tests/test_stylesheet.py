"""Tests: how is CSS parsed and applied to widgets?"""

from src.textual.css.stylesheet import Stylesheet, Widget, parse


def test_css_parsed_and_applied_to_widgets() -> None:
    """How is CSS parsed and applied to widgets: parse then apply."""
    sheet = Stylesheet()
    sheet.add_source("Widget { color: red; }")
    sheet.parse()
    widget = Widget()
    sheet.apply(widget)
    assert widget.styles["color"] == "red"


def test_parse_css_rules() -> None:
    rules = parse("Widget { color: red; }")
    assert rules[0].selector == "Widget"
