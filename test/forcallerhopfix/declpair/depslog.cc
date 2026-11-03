#include "depslog.h"
using namespace std;
bool DepsLog::Recompact(const string& path, string* err) {
  if (err) err->clear();
  return !path.empty();
}
