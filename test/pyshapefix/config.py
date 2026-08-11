"""Module-level binding fixture: one guard level deep is in scope, two is pinned OUT."""

import sys
from typing import TYPE_CHECKING, Final

SESSION_LIMIT = 32
cache_dir = "/tmp/rw"
RATE_TABLE: Final = {"burst": 8}

if sys.platform == "win32":
    LOCK_MODE = "exclusive"
    spool_path = "C:/spool"
elif sys.platform == "darwin":
    LOCK_MODE = "kqueue"
else:
    LOCK_MODE = "shared"

if TYPE_CHECKING:
    TypeHintAlias = dict

try:
    import ujson as _fastjson
    HAS_FAST_JSON = True
except ImportError:
    HAS_FAST_JSON = False
else:
    JSON_BACKEND = "ujson"
finally:
    JSON_PROBED = True

MAJOR_VER, MINOR_VER = 2, 7
first_low, second_low = 1, 2

if sys.maxsize > 2**32:
    if sys.platform != "win32":
        DOUBLE_NESTED = "two guard levels deep"


def helper_fn(flag):
    LOCAL_CONST = 5
    if flag:
        GUARDED_LOCAL = 6
        return GUARDED_LOCAL
    return LOCAL_CONST
