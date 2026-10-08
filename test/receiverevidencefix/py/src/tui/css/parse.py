def parse(css):
    """The module function the stylesheet imports."""
    return [rule.strip() for rule in css.split(";") if rule.strip()]
