#pragma once

// textalias.h — the alias lives in a DIFFERENT file from both the template and the struct that uses it (refnames.h's
// `using InternedText = InternedTextOf<RefNames>;` shape), so the struct's own file has no definition of the name.

#include "textid.h"

namespace layoutfix
{
struct TextTag;
using TextId = TextIdOf<TextTag>;
}   // namespace layoutfix
