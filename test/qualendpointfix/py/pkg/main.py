from pkg.mod import Alpha, Beta
from pkg import mod

def helper(b: Beta):
    return b.run(3)

def driver():
    a = Alpha()
    return a.run(1) + helper(Beta()) + mod.build(2)
