from ui.css.match import match


class Widget:
    def prune_children(self, selector_sets, children):
        # match is the imported module function, not a method of FuzzyIndex or Scorer
        return [child for child in children if match(selector_sets, child)]


def run_all(items):
    # process is no function anywhere: a bare call can never reach Worker.process
    return [process(item) for item in items]


def read_config(path):
    # open is the builtin: a bare call can never reach Worker.open
    with open(path) as fh:
        return fh.read()
