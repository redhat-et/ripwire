from json import dumps as stringify
from json import dumps


def render(obj):
    """`stringify` and `dumps` here are json.dumps (an outside from-import), never jsonutil's functions."""
    return stringify(obj) + dumps(obj)
