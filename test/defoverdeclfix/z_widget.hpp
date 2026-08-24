#pragma once

// Sorts LAST by path, so this definition loses the id-ascending tie-break to both bodyless
// declarations of the same name — the defect this fixture is red on.

namespace fixture
{

/// The real widget: the definition an agent that asked for `Widget` actually needs.
class Widget
{
public:
    /// Construct a widget with an initial count.
    explicit Widget( int count )
        : count_( count )
    {
    }

    /// How many times the widget has been advanced.
    int count() const
    {
        return count_;
    }

    /// Advance the widget once and report the new count.
    int advance()
    {
        ++count_;
        return count_;
    }

private:
    int count_ = 0;
};

}   // namespace fixture
