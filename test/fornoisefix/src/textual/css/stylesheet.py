"""Stylesheet: parses CSS sources into rule sets and applies them to widgets."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class RuleSet:
    selector: str
    declarations: dict[str, str] = field(default_factory=dict)
    specificity: int = 0


def tokenize(css: str) -> list[str]:
    """Split CSS text into tokens."""
    tokens: list[str] = []
    current = ""
    for ch in css:
        if ch in "{}:;":
            if current.strip():
                tokens.append(current.strip())
            tokens.append(ch)
            current = ""
        else:
            current += ch
    if current.strip():
        tokens.append(current.strip())
    return tokens


def parse(css: str) -> list[RuleSet]:
    """Parse CSS text into rule sets (parse_selectors + parse_declarations)."""
    rules: list[RuleSet] = []
    tokens = tokenize(css)
    i = 0
    while i < len(tokens):
        selector = tokens[i]
        i += 1
        if i < len(tokens) and tokens[i] == "{":
            i += 1
            declarations: dict[str, str] = {}
            while i < len(tokens) and tokens[i] != "}":
                name = tokens[i]
                if i + 2 < len(tokens) and tokens[i + 1] == ":":
                    declarations[name] = tokens[i + 2]
                    i += 3
                else:
                    i += 1
                if i < len(tokens) and tokens[i] == ";":
                    i += 1
            i += 1
            rules.append(RuleSet(selector, declarations, specificity=len(selector)))
    return rules


class Stylesheet:
    """Holds the rules parsed from every CSS source and applies them to widgets."""

    def __init__(self) -> None:
        self.rules: list[RuleSet] = []
        self.sources: list[str] = []

    def add_source(self, css: str) -> None:
        self.sources.append(css)

    def parse(self) -> None:
        self.rules = []
        for source in self.sources:
            self.rules.extend(parse(source))

    def apply(self, widget: Widget) -> None:
        """Apply the parsed rules to one widget: match selectors, order by specificity, set styles."""
        matched = [rule for rule in self.rules if self._check_rule(rule, widget)]
        matched.sort(key=lambda rule: rule.specificity)
        for rule in matched:
            for name, value in rule.declarations.items():
                widget.styles[name] = value
        widget.refresh()

    def _check_rule(self, rule: RuleSet, widget: Widget) -> bool:
        return rule.selector == widget.css_type or rule.selector in widget.classes

    def update_nodes(self, widgets: list[Widget]) -> None:
        for widget in widgets:
            self.apply(widget)


class Widget:
    css_type = "Widget"

    def __init__(self) -> None:
        self.styles: dict[str, str] = {}
        self.classes: set[str] = set()

    def refresh(self) -> None:
        pass
