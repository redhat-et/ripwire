#!/usr/bin/env python3
"""flaguniverse.py — the CLI flag UNIVERSE, derived from src/cli.h at gate time (capture-audit 2026-09-04, L1).

Every "accepted and silently ignored" family this repo has closed was closed by ENUMERATING members, and every
one of them re-opened on the member nobody enumerated (jsonUnsupportedVerb's 77-arm deny chain missed 12 verbs;
the --top-k/--max-tokens/--token-budget guards missed 18). The cure is one derivation the gates share: read
the flag tables (kBoolFlags / kViewFlags / kIntFlags) and the hand-written parseArgs arms out of cli.h, so a
flag that is added tomorrow is probed tomorrow without anyone editing a list in test/.

    python3 test/flaguniverse.py src/cli.h        →  TSV rows:  flag <TAB> kind <TAB> example <TAB> policy

    kind     bool        exact-match kBoolFlags row       ("--dmm")
             view        prefix kViewFlags row            ("--callers=")   policy = its EmptyValue column
             int         prefix kIntFlags row             ("--zoom=")
             hand-bool   exact `a == "--x"` arm in parseArgs
             hand-value  prefix `startsWith( a, "--x=" )` arm in parseArgs
    example  the row's own runnable example when the table carries one, else "-"

Consumers: test/jsoncheck.sh (arm #8b), test/shapingflagcheck.sh (arm F), test/emptyvaluerefusecheck.sh
(the hand-written sweep). The row counts are asserted by each consumer against a floor, so a scrape that
silently breaks fails the gate rather than shrinking the universe.
"""
import io
import re
import sys

STR = r'"((?:[^"\\]|\\.)*)"'


def stripComments( body ):
    # a `//` preceded by ':' is a URL inside a string literal ("https://…"), never a comment
    return re.sub( r'(?<!:)//[^\n]*', '', body )


def tableBody( src, header ):
    start = src.index( header )
    end   = src.index( "\n};", start )
    return stripComments( src[ start:end ] )


def main():
    if len( sys.argv ) != 2:
        sys.stderr.write( "usage: flaguniverse.py src/cli.h\n" )
        return 2
    src = io.open( sys.argv[ 1 ], encoding = "utf-8" ).read()
    rows = []

    # kBoolFlags: { "--name", &Config::member },
    for lit in re.findall( r'\{\s*"(--[^"]+)"\s*,\s*&Config::\w+\s*\}', tableBody( src, "inline constexpr BoolFlag kBoolFlags[] =" ) ):
        rows.append( ( lit, "bool", "-", "-" ) )

    # kViewFlags: { "--name=", &Config::member, EmptyValue::Policy, needs|nullptr, example|nullptr, … }
    view = tableBody( src, "inline constexpr ViewFlag kViewFlags[] =" )
    for m in re.finditer( r'\{\s*"(--[^"]+=)"\s*,\s*&Config::\w+\s*,\s*EmptyValue::(\w+)\s*(?:,\s*(?:nullptr|' + STR + r')\s*,\s*(?:nullptr|' + STR + r'))?', view ):
        example = m.group( 4 ) if m.group( 4 ) else "-"
        rows.append( ( m.group( 1 ), "view", example.replace( '\\"', '"' ), m.group( 2 ) ) )

    # kIntFlags: { "--name=", &Config::member, isZeroAllowed, most, "wanted", "example", … }
    ints = tableBody( src, "inline constexpr IntFlag kIntFlags[] =" )
    for m in re.finditer( r'\{\s*"(--[^"]+=)"\s*,\s*&Config::\w+\s*,\s*(?:true|false)\s*,\s*\w+\s*,\s*' + STR + r'\s*,\s*' + STR, ints ):
        rows.append( ( m.group( 1 ), "int", m.group( 3 ), "-" ) )

    # the hand-written residue in parseArgs (kHandWrittenFlagArms): exact arms and prefix arms
    parse = stripComments( src[ src.index( "inline Config parseArgs(" ) : ] )
    seen  = { r[ 0 ] for r in rows }
    for lit in re.findall( r'a == "(--[a-z0-9=.-]+)"', parse ):
        if lit not in seen:
            seen.add( lit ); rows.append( ( lit, "hand-bool", "-", "-" ) )
    for lit in re.findall( r'startsWith\(\s*a\s*,\s*"(--[a-z-]+=)"\s*\)', parse ):
        if lit not in seen:
            seen.add( lit ); rows.append( ( lit, "hand-value", "-", "-" ) )

    for r in rows:
        print( "\t".join( r ) )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
