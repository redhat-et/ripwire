from typing import overload

GATE_DEFAULT: int

class SchemaGate:
    poll_interval: float = 0.5

    def validate_frame(self, data: bytes) -> bool: ...

def build_gate(cfg: dict) -> SchemaGate: ...
