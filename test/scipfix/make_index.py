#!/usr/bin/env python3
# make_index.py — generate a minimal, VALID SCIP index (index.scip) for the scipfix fixture, by
# hand-rolling protobuf wire encoding (stdlib only — no scip-clang, no protobuf library). This is the
# ground-truth the --scip overlay consumes: it pins the ambiguous `handler()` call in caller.cpp to
# alpha.cpp's `handler`, so ripwire collapses the name-based split edge to one precise edge.
#
# SCIP proto field numbers (verified against sourcegraph/scip scip.proto):
#   Index.documents = 2
#   Document.relative_path = 1, occurrences = 2, symbols = 3
#   Occurrence.range = 1 (packed repeated int32 [startLine,startChar,endChar], DEPRECATED), symbol = 2,
#                symbol_roles = 3, typed_range oneof = single_line_range 8 | multi_line_range 9
#   SingleLineRange.line = 1, start_character = 2, end_character = 3
#   MultiLineRange.start_line = 1, start_character = 2, end_line = 3, end_character = 4
#   SymbolInformation.symbol = 1, display_name = 6
#   SymbolRole.Definition = 0x1 (bit 0)
# When an Occurrence carries both `range` and a typed_range, scip.proto requires typed_range to win.
# Ranges are 0-BASED. ripwire Symbol.line is 1-based, so line N (1-based def) is encoded as N-1 here.
#
# Usage: python3 test/scipfix/make_index.py                     # writes test/scipfix/index.scip next to this file
#        python3 test/scipfix/make_index.py OUT.scip            # writes to OUT.scip
#        python3 test/scipfix/make_index.py --typed OUT.scip    # the same fixture encoded with typed_range
#        python3 test/scipfix/make_index.py --typed --blind OUT.scip   # --typed with the typed_range fields removed

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

def single_line_range(line: int, start_char: int, end_char: int) -> bytes:
    m = field_varint(1, line) + field_varint(2, start_char) + field_varint(3, end_char)
    return field_message(8, m)                # Occurrence.single_line_range

def multi_line_range(start_line: int, start_char: int, end_line: int, end_char: int) -> bytes:
    m = field_varint(1, start_line) + field_varint(2, start_char)
    m += field_varint(3, end_line) + field_varint(4, end_char)
    return field_message(9, m)                # Occurrence.multi_line_range

def deprecated_range(range_ints) -> bytes:
    return packed_int32(1, range_ints)        # Occurrence.range

def occurrence_ranges(range_fields, symbol: str, roles: int) -> bytes:
    # `range_fields` are already-encoded range fields, emitted in the given ORDER. Protobuf permits any
    # field order on the wire, so an occurrence carrying both a deprecated and a typed range can put
    # either first; a reader that honours the spec resolves to the typed one regardless.
    m = b"".join(range_fields)
    m += field_string(2, symbol)              # symbol
    if roles:
        m += field_varint(3, roles)           # symbol_roles
    return m

def occurrence(range_ints, symbol: str, roles: int) -> bytes:
    return occurrence_ranges([deprecated_range(range_ints)], symbol, roles)

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
# alpha.cpp's `helperAlpha`, defined at 1-based line 6 and called from `handler`'s body at 1-based line 13.
# The typed-range arm needs a second def/ref pair so the three range encodings can each carry a distinct,
# independently observable occurrence.
SYM_HELPER_ALPHA = "scip-clang cxx . `alpha.cpp`/helperAlpha()."

# A line past the end of both fixture files: ripwire parses no reference there, so the S5 gate drops any
# occurrence that resolves to it. Whenever this is the DEPRECATED half of a both-forms occurrence, the
# precise edge survives if and only if the typed half won.
BOGUS_LINE = 99

def build_typed(blind: bool = False) -> bytes:
    # The typed_range arm. Same fixture semantics as the fresh index — alpha.cpp's `handler` is the target
    # of caller.cpp's bare `handler()` call — re-encoded so every range arrives in the typed form that
    # scip-java (and every current SCIP producer) emits:
    #   * `handler` DEF          -> multi_line_range, alone
    #   * `helperAlpha` DEF      -> single_line_range, alone
    #   * `helperAlpha` REF      -> BOTH forms, deprecated field FIRST
    #   * `handler` REF          -> BOTH forms, typed field FIRST
    # Each both-forms occurrence puts a BOGUS_LINE in its deprecated half, so it pins only if the typed
    # half won; using one ordering each way leaves neither wire order untested.
    #
    # `blind=True` re-emits the identical index with the typed_range fields REMOVED — exactly the view a
    # reader that knows only `Occurrence.range` has of it. It is the arm's discrimination check: the defs
    # lose their range entirely and the refs keep only BOGUS_LINE, so it must yield ZERO precise edges.
    def ranges(typed, deprecated=None, typed_first=True):
        if blind:
            return [] if deprecated is None else [deprecated]
        if deprecated is None:
            return [typed]
        return [typed, deprecated] if typed_first else [deprecated, typed]

    alpha = document(
        "alpha.cpp",
        occurrences=[
            # DEF of handler at 0-based line 10 (== 1-based 11), as a multi_line_range spanning the whole
            # definition down to its closing brace. start_line and end_line deliberately DIFFER: a reader
            # that took MultiLineRange.end_line (field 3) for the start would bind this def to 1-based line
            # 14, where no `handler` is defined, and surface as a def unmatched.
            occurrence_ranges(ranges(multi_line_range(10, 5, 13, 1)), SYM_HANDLER_ALPHA, ROLE_DEFINITION),
            # DEF of helperAlpha at 0-based line 5 (== 1-based 6), as a single_line_range.
            occurrence_ranges(ranges(single_line_range(5, 4, 15)), SYM_HELPER_ALPHA, ROLE_DEFINITION),
            # REF to helperAlpha at 0-based line 12 (== the `helperAlpha( 41 );` call on line 13), carrying
            # both forms with the DEPRECATED field first.
            occurrence_ranges(ranges(single_line_range(12, 4, 15), deprecated_range([BOGUS_LINE, 4, 15]),
                                     typed_first=False), SYM_HELPER_ALPHA, 0),
        ],
        symbols=[symbol_information(SYM_HANDLER_ALPHA, "handler"),
                 symbol_information(SYM_HELPER_ALPHA, "helperAlpha")],
    )
    # REF to alpha's handler at 0-based line 8 (== the `handler();` call on line 9), carrying both forms
    # with the TYPED field first.
    caller = document(
        "caller.cpp",
        occurrences=[
            occurrence_ranges(ranges(single_line_range(8, 4, 11), deprecated_range([BOGUS_LINE, 4, 11]),
                                     typed_first=True), SYM_HANDLER_ALPHA, 0),
        ],
        symbols=[],
    )
    return index([alpha, caller])

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

FLAGS = ("--stale", "--external", "--typed", "--blind")

def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    args = [a for a in sys.argv[1:] if a not in FLAGS]
    stale = "--stale" in sys.argv[1:]                 # --stale → an older-commit index (def ok, ref stale/mis-placed)
    external = "--external" in sys.argv[1:]           # --external → adds one unmatchable (std::) ref occurrence (A4-F21)
    typed = "--typed" in sys.argv[1:]                 # --typed → every range in the typed_range form (fields 8/9)
    blind = "--blind" in sys.argv[1:]                 # --blind → --typed with the typed_range fields removed
    if blind and not typed:
        sys.stderr.write("--blind is only meaningful with --typed\n")
        raise SystemExit(2)
    out = args[0] if args else os.path.join(here, "index.scip")
    data = build_typed(blind) if typed else build(stale, external)
    with open(out, "wb") as f:
        f.write(data)
    sys.stderr.write("wrote %s (%d bytes, stale=%s, typed=%s, blind=%s)\n" % (out, len(data), stale, typed, blind))

if __name__ == "__main__":
    main()
