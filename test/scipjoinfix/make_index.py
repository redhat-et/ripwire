#!/usr/bin/env python3
# make_index.py — the scipjoinfix SCIP index, hand-rolled protobuf (stdlib only; the same wire helpers
# as test/scipfix/make_index.py). It encodes the THREE join traps docs/EVALS.md "Phase 3 — the SCIP join
# diagnosed" registered, plus one ordinary in-repo resolution as the control:
#
#   a.py  (1-based lines: sum@2  Box@4  Box.model@5  Box.total@7  Box.go@9  model@11)
#     def   `a/sum().`            line 2   an in-repo def named like a builtin
#     def   `local 0`             line 2   THE LOCAL TRAP: a document-scoped local on a line that holds a
#                                          real symbol. A matcher that keys `local N` globally binds
#                                          a.py::sum for every `local 0` in every other file.
#     def   `a/Box#`              line 4
#     def   `a/Box#model().`      line 5
#     def   `a/Box#total().`      line 7   + parameter `a/Box#total().(vals)` on the SAME line
#     ref   `builtins/sum().`     line 8   `sum(vals)` — SCIP resolves the bare call to the BUILTIN.
#                                          ripwire resolves it to a.py::sum (unique). EXTERNAL resolution.
#     def   `a/Box#go().`         line 9   + parameter `a/Box#go().(model)` on the SAME line — THE
#                                          PARAMETER TRAP: first-on-the-line binding maps the parameter
#                                          to Box.go itself.
#     ref   `a/Box#go().(model)`  line 10  `model(1)` — SCIP: the PARAMETER. ripwire: tier {Box.model,
#                                          model} -> S6-C pins Box.model. A NON-DEF resolution that
#                                          disconfirms a locality pin.
#     def   `a/model().`          line 11
#   b.py  (helper@2  K@4  K.run@5)
#     def   `b/helper().`         line 2
#     def   `b/K#` line 4, `b/K#run().` line 5
#     ref   `b/helper().`         line 6   the control: an ordinary in-repo resolution -> O row to b.py::helper
#     ref   `local 0`             line 6   the other half of the local trap: under the global-key bug this
#                                          becomes a phantom (K.run -> a.py::sum) covered site.
#
# Usage: python3 test/scipjoinfix/make_index.py [OUT.scip]   (default: index.scip beside this file)
import os
import sys

import importlib.util

# The protobuf wire helpers are test/scipfix/make_index.py's, imported rather than copied: one writer for
# every hand-rolled fixture index, so a field-number fix lands once.
_SCIPFIX = os.path.join( os.path.dirname( os.path.abspath( __file__ ) ), "..", "scipfix", "make_index.py" )
_spec = importlib.util.spec_from_file_location( "scipfix_make_index", _SCIPFIX )
_wire = importlib.util.module_from_spec( _spec )
_spec.loader.exec_module( _wire )
field_varint, field_bytes, field_string, packed_int32 = _wire.field_varint, _wire.field_bytes, _wire.field_string, _wire.packed_int32

ROLE_DEFINITION = 0x1
PFX = "scip-python python scipjoinfix 1 "


def occurrence( line1, col, symbol, roles ):
    m = packed_int32( 1, [ line1 - 1, col, col + 1 ] )
    m += field_string( 2, symbol )
    if roles:
        m += field_varint( 3, roles )
    return m


def symbol_information( symbol ):
    return field_string( 1, symbol )


def document( rel, occs, syms ):
    return _wire.document( rel, occs, syms )


def build():
    D = ROLE_DEFINITION
    a = [
        occurrence( 2, 4, PFX + "a/sum().", D ),
        occurrence( 2, 8, "local 0", D ),
        occurrence( 4, 6, PFX + "a/Box#", D ),
        occurrence( 5, 8, PFX + "a/Box#model().", D ),
        occurrence( 7, 8, PFX + "a/Box#total().", D ),
        occurrence( 7, 20, PFX + "a/Box#total().(vals)", D ),
        occurrence( 8, 15, PFX + "builtins/sum().", 0 ),
        occurrence( 9, 8, PFX + "a/Box#go().", D ),
        occurrence( 9, 17, PFX + "a/Box#go().(model)", D ),
        occurrence( 10, 15, PFX + "a/Box#go().(model)", 0 ),
        occurrence( 11, 4, PFX + "a/model().", D ),
    ]
    a_syms = [ symbol_information( PFX + s ) for s in ( "a/sum().", "a/Box#", "a/Box#model().", "a/Box#total().", "a/Box#go().", "a/model()." ) ]
    b = [
        occurrence( 2, 4, PFX + "b/helper().", D ),
        occurrence( 4, 6, PFX + "b/K#", D ),
        occurrence( 5, 8, PFX + "b/K#run().", D ),
        occurrence( 6, 15, PFX + "b/helper().", 0 ),
        occurrence( 6, 8, "local 0", 0 ),
    ]
    b_syms = [ symbol_information( PFX + s ) for s in ( "b/helper().", "b/K#", "b/K#run()." ) ]
    idx = field_bytes( 2, document( "a.py", a, a_syms ) ) + field_bytes( 2, document( "b.py", b, b_syms ) )
    return idx


def main():
    out = sys.argv[ 1 ] if len( sys.argv ) > 1 else os.path.join( os.path.dirname( os.path.abspath( __file__ ) ), "index.scip" )
    with open( out, "wb" ) as fh:
        fh.write( build() )
    print( "wrote", out )


if __name__ == "__main__":
    main()
