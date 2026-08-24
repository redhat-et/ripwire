#pragma once

// Sorts between a_headers.hpp and z_widget.hpp. It exists so the Widget tie group holds more
// than one declaration (a single-declaration tie could be reordered by accident) and so Sprocket
// has an all-declaration tie group with a checkable internal order.

namespace fixture
{

/// Second forward declaration of the widget type.
class Widget;

/// Second forward declaration of the sprocket type; still nothing defines it.
class Sprocket;

}   // namespace fixture
