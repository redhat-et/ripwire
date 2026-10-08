#pragma once
#include <string>

class Exporter {
public:
    void flush();
    std::string render(const std::string& s);
};
