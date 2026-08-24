#pragma once

// Sorts FIRST by path, so every symbol declared here wins the id-ascending tie-break that
// name-exact BM25 falls back on when two candidates are exactly as name-exact as each other.
// That is the whole point of the fixture: before the definition-over-declaration tiebreak this
// file's bodyless `class Widget;` outranks the real definition in z_widget.hpp.

namespace fixture
{

/// Forward declaration of the widget type; the real definition lives in z_widget.hpp.
class Widget;

/// Declared here and NOWHERE defined — the control that keeps the tiebreak a REORDER and not a
/// blanket demotion of declarations. A declaration with no definition competing for its tie is
/// still the best answer to its own name.
class Gadget;

/// Forward declared here and again in m_more.hpp, and never defined anywhere. The two
/// declarations tie with each other and with nothing else, so their relative order must not move.
class Sprocket;

}   // namespace fixture
