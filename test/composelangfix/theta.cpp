// A SECOND, same-language definition of `Thing` — widget.cpp declares the first. Nothing here is
// cross-language, so the compose lang guard admits BOTH candidates for the C++ member `Thing m_thing;`.
// A field has exactly one DECLARED type, so <compose> must still carry exactly one row per field: the
// extra candidates are resolver ambiguity about WHICH definition the name binds to, not extra members.
// This file sorts before widget.cpp, so its `Thing` gets the LOWER symbol id.
struct Thing
{
    int z;
};
