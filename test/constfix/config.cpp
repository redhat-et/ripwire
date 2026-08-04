// C++ config translation unit — namespace-scope and file-scope SCREAMING_SNAKE constants.

namespace cfg
{
inline constexpr int CPP_MAX_DEPTH = 12;
}

static const char* CPP_DEFAULT_HOSTS[] = { "a.example", "b.example" };

int cppDepth()
{
    return cfg::CPP_MAX_DEPTH;
}
