// hopbodycheck H2: a C++ function Python reaches only through a pybind11 binding alias (a binding edge: amb= "verify in source").
#include <pybind11/pybind11.h>

namespace py = pybind11;

double scale_impl( double x )
{
    double y = x * 2.0 + 1.0;
    return y;
}

PYBIND11_MODULE( ffimod, m )
{
    m.def( "fast_transform", &scale_impl );
}
