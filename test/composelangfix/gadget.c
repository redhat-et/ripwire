/* C-side member type: langCompatible bridges C<->C++, so the C++ member `Gadget m_gadget;` in
   widget.cpp MUST still resolve here. Pins that the compose lang guard is langCompatible, not a
   bare lang==Cpp equality test. */
struct Gadget
{
    int x;
};
