#include "exporter.hpp"
#include <cstdio>

void Exporter::flush() { std::puts("exporter flush"); }
std::string Exporter::render(const std::string& s) { return "<" + s + ">"; }
