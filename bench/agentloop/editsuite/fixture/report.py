"""Builds a one-line report from the helpers."""

from stats import describe
from text import slugify, word_count


def build_report(title, values, body):
    d = describe(values)
    return "%s: mean=%.2f median=%.2f words=%d" % (slugify(title), d["mean"], d["median"], word_count(body))
