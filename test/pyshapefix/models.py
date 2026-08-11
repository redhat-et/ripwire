"""Typed-surface fixture — every shape here was measured against django@7d75c0b and
pydantic@2e5f0e2 on 2026-08-04; see test/pyshapecheck.sh for the counts."""

from dataclasses import dataclass
from enum import Enum, IntEnum
from typing import ClassVar, NamedTuple, TypedDict

from vendor_enums import EnumLike, TextChoices


@dataclass
class RetryPolicy:
    backoff_ms: float
    max_attempts: int = 3
    registry: ClassVar[dict] = {}

    def next_delay(self, attempt_index):
        return self.backoff_ms * attempt_index


class WireFormat(TypedDict):
    frame_kind: str
    payload_len: int


class Endpoint(NamedTuple):
    host_name: str
    port_num: int = 443


class Color(Enum):
    CRIMSON = 1
    TEAL = 2

    def css_name(self):
        return self.name.lower()


class Precedence(IntEnum):
    URGENT_FIRST = 10
    BULK_LAST = 90


class Rank(TextChoices):
    GOLD_TIER = "g"
    SILVER_TIER = "s"


class Custom(EnumLike):
    HIDDEN_VAL = 1


class NotAnEnum:
    plain_slot = "data"
    formatter = lambda self, raw: raw.strip()
