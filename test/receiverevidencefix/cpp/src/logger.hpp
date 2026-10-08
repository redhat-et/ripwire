#pragma once
#include <string>

std::string render(const std::string& s);

class Base {
public:
    void flush();
};

class Logger : public Base {
public:
    std::string line(const std::string& s);
    void close();
private:
    void reset();
};
