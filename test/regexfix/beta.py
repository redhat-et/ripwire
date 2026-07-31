# beta.py — more tricky content, different language (python) for cross-file matches.

import sys

class Widget:                 # same CamelCase name as alpha.cpp → multi-file [A-Z]\w+
    def open(self):           # 'open' / 'close' for the alternation test
        return 1

    def close(self):
        return 0


def compute(n):               # 'compute' appears in alpha.cpp too (multi-file literal)
    return n - 1


# a Foo ... Bar spanning case where Foo and Bar are far apart (still one line)
FooThenALongGapUntilBar = "Foo .......................... Bar"

# NOT an anchored-int line: this starts with whitespace then 'int' inside a string
indent = "    int not_anchored_here"
