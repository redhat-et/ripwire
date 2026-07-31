#!/usr/bin/env python3
# make_index.py — generate a minimal, VALID SCIP index (index.scip) for the scipfix fixture, by
# hand-rolling protobuf wire encoding (stdlib only — no scip-clang, no protobuf library). This is the
# ground-truth the --scip overlay consumes: it pins the ambiguous `handler()` call in caller.cpp to
# alpha.cpp's `handler`, so ripwire collapses the name-based split edge to one precise edge.
#
# SCIP proto field numbers (verified against sourcegraph/scip scip.proto):
#   Index.documents = 2
#   Document.relative_path = 1, occurrences = 2, symbols = 3
#   Occurrence.range = 1 (packed repeated int32 [startLine,startChar,endChar]), symbol = 2, symbol_roles = 3
#   SymbolInformation.symbol = 1, display_name = 6
#   SymbolRole.Definition = 0x1 (bit 0)
# Ranges are 0-BASED. ripwire Symbol.line is 1-based, so line N (1-based def) is encoded as N-1 here.
#
# Usage: python3 test/scipfix/make_index.py            # writes test/scipfix/index.scip next to this file
#        python3 test/scipfix/make_index.py OUT.scip   # writes to OUT.scip

import os
import sys

ROLE_DEFINITION = 0x1

# ---- protobuf wire primitives ----------------------------------------------------------------------

def varint(n: int) -> bytes:
    if n < 0:
        raise ValueError("varint must be non-negative")
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)

def tag(field: int, wire: int) -> bytes:
    return varint((field << 3) | wire)

def field_varint(field: int, value: int) -> bytes:
    return tag(field, 0) + varint(value)

def field_bytes(field: int, data: bytes) -> bytes:
    return tag(field, 2) + varint(len(data)) + data

def field_string(field: int, s: str) -> bytes:
    return field_bytes(field, s.encode("utf-8"))

def field_message(field: int, msg: bytes) -> bytes:
    return field_bytes(field, msg)

def packed_int32(field: int, ints) -> bytes:
    payload = b"".join(varint(i) for i in ints)   # all non-negative here (line/char offsets)
    return field_bytes(field, payload)

# ---- SCIP messages ---------------------------------------------------------------------------------

def occurrence(range_ints, symbol: str, roles: int) -> bytes:
    m = b""
    m += packed_int32(1, range_ints)          # range
    m += field_string(2, symbol)              # symbol
    if roles:
        m += field_varint(3, roles)           # symbol_roles
    return m

def symbol_information(symbol: str, display_name: str) -> bytes:
    m = b""
    m += field_string(1, symbol)              # symbol
    if display_name:
        m += field_string(6, display_name)    # display_name
    return m

def document(relative_path: str, occurrences, symbols) -> bytes:
    m = b""
    m += field_string(1, relative_path)                   # relative_path
    for occ in occurrences:
        m += field_message(2, occ)                        # occurrences (repeated)
    for si in symbols:
        m += field_message(3, si)                         # symbols (repeated)
    return m

def index(documents) -> bytes:
    m = b""
    for doc in documents:
        m += field_message(2, doc)                        # documents (repeated)
    return m

# ---- the fixture index -----------------------------------------------------------------------------
# The SCIP symbol string that identifies alpha.cpp's `handler`. The exact string is opaque to ripwire —
# it only needs the SAME string to appear on the definition (in alpha.cpp) and the reference (in
# caller.cpp) so they link. We use a SCIP-shaped string; any stable string works.
SYM_HANDLER_ALPHA = "scip-clang cxx . `alpha.cpp`/handler()."

def build(stale: bool = False, external: bool = False) -> bytes:
    # `stale=False` → the FRESH, correct index (the gate's positive case).
    #
    # `stale=True` simulates an index built from an OLDER commit, engineered to expose the S5 mis-attribution
    # hazard sharply — the DEF stays correct (so the ref target is a known def and NOTHING but the S5 gate
    # can stop the edge), but the caller's REFERENCE line is stale:
    #   * alpha's `handler` DEFINITION stays at 0-based line 10 (== 1-based line 11) → it maps fine.
    #   * caller's reference to `handler` is recorded at 0-based line 7 (== 1-based line 8) — one line OFF
    #     the real `handler();` call (line 9, 0-based 8), as if a line were inserted since the index was cut.
    #     ripwire parsed NO `handler` call at caller.cpp line 8. Under the OLD "greatest def line ≤ occ line"
    #     line-scan the stale line still resolves to run() (run def at line 7) and pins run→handler with
    #     prov="scip" — it TRUSTS the stale line with no cross-check (the silent partial-staleness hazard).
    #     The S5 gate finds no ripwire reference at (caller.cpp, line 8) → it DROPS the occurrence: run
    #     reverts to the honest name-based ambiguous split. Fewer-but-correct, never a wrong precise edge.
    # Result: a stale index yields ZERO precise edges, and the match-ratio note fires showing 0/1
    # occurrences pinned — the honest older-commit signal.
    if stale:
        alpha = document(
            "alpha.cpp",
            occurrences=[
                occurrence([10, 5, 12], SYM_HANDLER_ALPHA, ROLE_DEFINITION),   # def: still correct (line 11)
            ],
            symbols=[symbol_information(SYM_HANDLER_ALPHA, "handler")],
        )
        caller = document(
            "caller.cpp",
            occurrences=[
                occurrence([7, 4, 11], SYM_HANDLER_ALPHA, 0),                  # STALE ref: line 8, real call is line 9
            ],
            symbols=[],
        )
        return index([alpha, caller])

    # alpha.cpp: DEFINITION of handler at 0-based line 10 (== 1-based line 11 in alpha.cpp).
    alpha = document(
        "alpha.cpp",
        occurrences=[
            occurrence([10, 5, 12], SYM_HANDLER_ALPHA, ROLE_DEFINITION),
        ],
        symbols=[symbol_information(SYM_HANDLER_ALPHA, "handler")],
    )
    # caller.cpp: a REFERENCE to alpha's handler at 0-based line 8 (== the `handler();` call on line 9),
    # inside run()'s span (run def at 1-based line 7). roles = 0 → a reference, not a definition.
    caller_occs = [
        occurrence([8, 4, 11], SYM_HANDLER_ALPHA, 0),
    ]
    if external:
        # A4-F21 gate fixture: one EXTERNAL reference occurrence — a symbol string that never appears in
        # any document's `symbols` (never a def anywhere in this index), the way a real SCIP indexer
        # records every `std::`/library reference it sees even though ripwire (and the index itself) never
        # defines those symbols in-tree. `dit == scipDef.end()` for this one regardless of which line it
        # sits on, so its exact position is irrelevant — it exists purely to inflate ov.refOccurrences
        # (the OLD, wrong S5 denominator) without being matchable, which is exactly the deflation this
        # fixture proves is fixed: internalOccurrences (the NEW denominator) must exclude it.
        SYM_EXTERNAL = "scip-clang cxx . `<stdlib>`/std::string#"
        caller_occs.append(occurrence([8, 20, 30], SYM_EXTERNAL, 0))
    caller = document("caller.cpp", occurrences=caller_occs, symbols=[])
    return index([alpha, caller])

def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    args = [a for a in sys.argv[1:] if a not in ("--stale", "--external")]
    stale = "--stale" in sys.argv[1:]                 # --stale → an older-commit index (def ok, ref stale/mis-placed)
    external = "--external" in sys.argv[1:]           # --external → adds one unmatchable (std::) ref occurrence (A4-F21)
    out = args[0] if args else os.path.join(here, "index.scip")
    data = build(stale, external)
    with open(out, "wb") as f:
        f.write(data)
    sys.stderr.write("wrote %s (%d bytes, stale=%s)\n" % (out, len(data), stale))

if __name__ == "__main__":
    main()
