// decoy_a.cpp — one of two files defining the SAME constant name (pathQualifiedKey arm:
// same-named constants in different files must stay separate symbols, never folded).
constexpr int kMcSameDecoy = 1;
int mcReadDecoyA() { return kMcSameDecoy; }
