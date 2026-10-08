# Review B4 (language neutrality): a rebinding of a typed parameter's name, and a type parameter named like a class.
class Tank:
    def spill(self): pass

class Barrel:
    def spill(self): pass

def for_loop(tank: Tank, bs: list):
    for tank in bs:
        tank.spill()

def lambda_param(tank: Tank, bs):
    return list(map(lambda tank: tank.spill(), bs))

def comprehension(tank: Tank, bs):
    return [tank.spill() for tank in bs]

def with_as(tank: Tank, cm):
    with cm as tank:
        tank.spill()

def except_as(tank: Tank):
    try:
        pass
    except Exception as tank:
        tank.spill()

def walrus(tank: Tank, f):
    if (tank := f()):
        tank.spill()

def reassign(tank: Tank, b):
    tank = b
    tank.spill()

def type_param[Tank](t: Tank):
    t.spill()

def typed_param(t: Tank):
    t.spill()

def match_capture(tank: Tank, o):
    match o:
        case [tank, *rest]:
            tank.spill()

def match_as(tank: Tank, o):
    match o:
        case Barrel() as tank:
            tank.spill()
