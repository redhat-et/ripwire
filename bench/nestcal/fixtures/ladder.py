def ladder(v, w):
    if v == 1:
        if w == 0:
            if v > 11:
                return 'a' if w else 'b'
            elif 1 < v < 6 and w:
                return 'c'
            elif v == 1:
                return 'd'
            elif w:
                return 'e'
            else:
                return 'f'
        elif w == -127:
            return 'g'
    elif v == 2 and w:
        return 'h'
    return None

def flat_ladder(v):
    if v == 1:
        return 1
    elif v == 2:
        return 2
    elif v == 3:
        return 3
    else:
        return 0
