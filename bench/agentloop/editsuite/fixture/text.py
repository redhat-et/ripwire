"""Text helpers used by the report module."""

import re


def slugify(title):
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")


def word_count(text):
    return len(text.split())


def title_case(text):
    return " ".join(w.capitalize() for w in text.split())
