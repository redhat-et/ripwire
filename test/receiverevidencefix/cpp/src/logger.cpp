#include "logger.hpp"
#include <cstdio>

std::string render(const std::string& s) { return "[" + s + "]"; }
void Base::flush() { std::puts("base flush"); }

// A bare call inside a member function: an own/inherited member or a free function, never an unrelated class's member.
std::string Logger::line(const std::string& s) { return render(s); }
void Logger::close() { flush(); reset(); }
void Logger::reset() { std::puts("reset"); }
