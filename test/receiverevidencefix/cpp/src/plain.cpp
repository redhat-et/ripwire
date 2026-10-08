#include "plain.hpp"

// A bare flush() inside a member: the outside base's member, never Base::flush or Exporter::flush.
void Plain::finish() { flush(); }
