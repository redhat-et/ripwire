import ffimod


def run_pipeline(value):
    # Calls the pybind11-exposed C++ free function by its Python-visible alias.
    result = ffimod.fast_transform(value)
    # Calls the pybind11-exposed C++ method by its Python-visible alias.
    solver = ffimod.Solver()
    return solver.step(result)
