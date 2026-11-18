#pragma once
namespace Envoy {
namespace Stats {
// namesakes the alias-typed calls must never reach
class Gauge {
public:
  bool enabled() { return true; }
  void enableTimer(int) {}
};
} // namespace Stats
} // namespace Envoy
