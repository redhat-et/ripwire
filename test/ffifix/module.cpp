// A minimal pybind11 module. ctxpack A4-R5 should link the Python-visible names
// ("fast_transform", "step") to the C++ definitions they bind.
#include <pybind11/pybind11.h>

namespace py = pybind11;

// A free C++ function exposed to Python under the alias "fast_transform".
double fast_transform_impl( double x )
{
    return x * 2.0 + 1.0;
}

// A free C++ function exposed under the alias "combine" — used by the control test:
// control.py defines its OWN local `combine`, which must win (no edge to this one).
int combine_impl( int a, int b )
{
    return a + b;
}

// A C++ class with a method exposed to Python.
class Solver
{
public:
    int step( int n )
    {
        return n + advance_internal();
    }

    int advance_internal()
    {
        return 7;
    }
};

PYBIND11_MODULE( ffimod, m )
{
    m.def( "fast_transform", &fast_transform_impl );
    m.def( "combine", &combine_impl );
    py::class_<Solver>( m, "Solver" )
        .def( "step", &Solver::step );
}
