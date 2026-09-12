// test/macroreparsecheck.sh fixture — the member-macro leak followed by a lambda whose body holds a structured
// binding. Without the re-parse the last struct swallows the rest of the namespace and becomes the RETURN TYPE of a
// function, and a definition after the namespace is filed as a scopeless method. With it, every function is a
// free function again.
#include <map>
#include <string>

#define NAME_OF(T) static const char* kindName() { return #T; }

namespace {

struct OrchardError : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(OrchardError)
};

struct PastureError : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(PastureError)
};

struct QuarryError : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(QuarryError)
};

int weighHarvest(const std::map<std::string, int> &bins) {
  int total = 0;
  auto add = [&total](const auto &entry) {
    const auto &[label, weight] = entry;
    if (weight > 0) {
      total += weight;
    }
  };
  for (const auto &entry : bins) {
    add(entry);
  }
  return total;
}

std::string gradeYield(int kilos) {
  if (kilos == 0) {
    return "empty";
  }
  return "some";
}

}  // namespace

int afterOrchard(int v) {
  return v + 1;
}
