#pragma once
#include <string>
struct DepsLog {
  /// Rewrite the known log entries.
  bool Recompact(const std::string& path, std::string* err);
};
