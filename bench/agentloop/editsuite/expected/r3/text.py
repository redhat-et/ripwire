"""Text helpers used by the report module."""

import re


def slugify(title, sep="-"):
    return re.sub(r"[^a-z0-9]+", sep, title.lower()).strip(sep)


def word_count(text):
    return len(text.split())


def title_case(text):
    return " ".join(w.capitalize() for w in text.split())
