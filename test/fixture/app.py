# Tiny Python member of the polyglot fixture. Has a call edge (total_area -> area_of_triangle).


def area_of_triangle(base, height):
    return 0.5 * base * height


def total_area(triangles):
    return sum(area_of_triangle(b, h) for b, h in triangles)
