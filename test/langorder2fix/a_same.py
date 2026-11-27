# langorder2fix: same rung (Function, rank 2) as z_lib.js's `same`, and the LOWER id by path sort —
# the pre-tie-break front. Under the adopted rule its def answers first only if the majority tie-break
# never fired; here it does, so js fronts and this row must still be present (a tie-break orders, it
# never filters).
def same():
    return 1

def other():
    return 2
