// valueShadow.cpp — the SHADOW case. This file never includes valueGates.h; its `kTurns` is its own local
// constant that merely shares a house-style name with the gate's binding. Plain C++ scoping says these uses
// belong to the declaration right above them, so --flip must NOT count them as newly-live branch sites.
// (Without this rule the value lane cross-wires on short names — it did, on the motivating repo, crediting a
// weapons header's `constexpr float kSpeed` to a canyon-generator gate.)

int shadowEntry()
{
    constexpr int kTurns = 3;
    return kTurns * 2;
}
