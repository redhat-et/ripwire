# dead.py — Python fixture for the "unreachable-code" built-in lint rule.


# MUST flag: statement after a same-block return.
def after_return(x):
    return x + 1
    dead = compute()   # UNREACHABLE — flagged


# MUST flag: statement after a raise (Python's throw).
def after_raise(x):
    raise ValueError(x)
    cleanup()          # UNREACHABLE — flagged


# MUST NOT flag: the return is inside an if-branch; the following statement is reachable.
def guarded_return(x):
    if x < 0:
        return -1
    reachable = x * 2  # REACHABLE — must NOT be flagged
    return reachable


# MUST NOT flag: bare return as the last statement.
def last_return(x):
    do_work(x)
    return
