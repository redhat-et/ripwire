from pkg.widgetparsers import WidgetError


def load(text):
    try:
        return text.split(",")
    except WidgetError:
        return []


def main():
    return load("a,b") + load("c")


def run():
    return main() + main()
