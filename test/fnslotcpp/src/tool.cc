// FN-SLOT S2 fixture (test/fnslotcheck.sh C* arms): ninja's ToolFunc shape — a pointer-to-member table and its `.*` call.
#include <string>
struct Options;
struct NinjaMain {
  typedef int (NinjaMain::*ToolFunc)(const Options*, int, char**);
  int ToolBrowse(const Options* o, int argc, char** argv);
  int ToolClean(const Options* o, int argc, char** argv);
};
struct Tool {
  const char* name;
  const char* desc;
  enum { RUN_AFTER_FLAGS, RUN_AFTER_LOAD } when;
  NinjaMain::ToolFunc func;
};
struct Options { int verbose; const Tool* tool; };
int NinjaMain::ToolBrowse(const Options* o, int argc, char** argv) { return argc; }
int NinjaMain::ToolClean(const Options* o, int argc, char** argv) { return argc + 1; }
namespace helpers { int freeFn(const Options* o, int argc, char** argv) { return 0; } }
const Tool* ChooseTool(const std::string& tool_name) {
  static const Tool kTools[] = {
    { "browse", "browse it", Tool::RUN_AFTER_LOAD, &NinjaMain::ToolBrowse },
    { "clean", "clean it", Tool::RUN_AFTER_LOAD, &NinjaMain::ToolClean },
    { nullptr, nullptr, Tool::RUN_AFTER_FLAGS, nullptr }
  };
  for (const Tool* t = &kTools[0]; t->name; ++t)
    if (tool_name == t->name) return t;
  return nullptr;
}
int real_main(int argc, char** argv) {
  NinjaMain ninja;
  Options options;
  options.tool = ChooseTool(argv[1]);
  return (ninja.*options.tool->func)(&options, argc, argv);
}
// near misses: a member pointer in a plain variable, `->*` (the grammar reads an ERROR), a data-member pointer
int plain_var(NinjaMain* self, NinjaMain::ToolFunc pmf) {
  NinjaMain ninja;
  int (NinjaMain::*local)(const Options*, int, char**) = &NinjaMain::ToolClean;
  (self->*pmf)(nullptr, 0, nullptr);
  return (ninja.*local)(nullptr, 0, nullptr);
}
const char* Tool::* data_ptr = &Tool::name;
struct Cb { int (*f)(const Options*, int, char**); };
static Cb kCb = { &helpers::freeFn };
int fire_cb(Cb* c) { return c->f(nullptr, 0, nullptr); }
