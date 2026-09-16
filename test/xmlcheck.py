#!/usr/bin/env python3
"""Small xmllint-compatible well-formedness checker for Windows test runs.

The product has no XML runtime dependency, and Git for Windows does not ship
xmllint.  The harness uses this only for the existing --noout/--format checks;
ElementTree still rejects malformed XML instead of turning the assertion into a
skip.  --html uses the stdlib's deliberately permissive HTML parser, matching
xmllint's recovery-oriented HTML mode closely enough for the gate's validity
check.
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path


class _HtmlProbe(HTMLParser):
    """Consume HTML while allowing the recovery cases accepted by xmllint."""

    def error(self, message: str) -> None:  # pragma: no cover - Python < 3.5 hook
        del message


def _read_input(name: str) -> bytes:
    if name == "-":
        return sys.stdin.buffer.read()
    return Path(name).read_bytes()


def _parse_xml(data: bytes) -> ET.ElementTree:
    return ET.ElementTree(ET.fromstring(data))


def _format_xml(tree: ET.ElementTree) -> None:
    root = tree.getroot()
    ET.indent(tree, space="  ")
    tree.write(sys.stdout.buffer, encoding="utf-8", xml_declaration=False)
    sys.stdout.buffer.write(b"\n")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--noout", action="store_true")
    parser.add_argument("--format", action="store_true")
    parser.add_argument("--html", action="store_true")
    parser.add_argument("--nonet", action="store_true")
    parser.add_argument("inputs", nargs="*")
    options, unknown = parser.parse_known_args(argv)
    if unknown or not options.inputs or ( options.format and len( options.inputs ) != 1 ):
        return 2

    try:
        for name in options.inputs:
            data = _read_input( name )
            if options.html:
                probe = _HtmlProbe( convert_charrefs=True )
                probe.feed( data.decode( "utf-8", "replace" ) )
                probe.close()
            else:
                tree = _parse_xml( data )
                if options.format:
                    _format_xml( tree )
    except (ET.ParseError, OSError, UnicodeError, ValueError):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
