# Every PLACE a Python import can be written that is not a module-top-level statement. One distinct
# module name per arm on purpose: a gate can name the arm that regressed from the missing `t="..."`
# alone, without counting.
#
# The `if TYPE_CHECKING:` and `try: … except ImportError:` arms are not exotica — they are THE two
# canonical Python idioms for a conditional dependency, the direct analogue of a C `#ifdef` guard, and
# a file that used either one handed --cochange's StaticIncludeCoupling an empty import list.

import mod_toplevel   # CONTROL — a plain module-level import, captured before this change and after it

if TYPE_CHECKING:
    import mod_if
elif OTHER_FLAG:
    import mod_elif
else:
    import mod_else

try:
    import mod_try
except ImportError:
    import mod_except
finally:
    import mod_finally

with open( "x" ) as fh:
    import mod_with

for _ in range( 1 ):
    import mod_for

while False:
    import mod_while


class Holder:
    import mod_class                      # class-body import (legal; binds as a class attribute)

    def method( self ):
        import mod_method
        return mod_method


def func():
    import mod_func
    from pkg.deep import thing            # from-import at function scope
    if NESTED_FLAG:
        import mod_nested_in_func         # two containers deep: function_definition → if_statement
    return thing


def outer():
    def inner():
        import mod_inner_func             # nested function body
        return mod_inner_func
    return inner


try:
    pass
except* ValueError:                       # except* group (3.11) → except_group_clause
    import mod_except_group


@decorator
def decorated():                          # decorated_definition → function_definition
    import mod_decorated
    return mod_decorated


def dispatch( value ):
    match value:                          # match_statement → case_clause
        case 0:
            import mod_case
            return mod_case
        case _:
            return None
