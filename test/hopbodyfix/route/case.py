import re


def camel_to_snake(name, _re=re.compile("[a-z][A-Z]")):
    def repl(m):
        lower, upper = m.group()
        return f"{lower}_{upper.lower()}"

    return _re.sub(repl, name).lower()
