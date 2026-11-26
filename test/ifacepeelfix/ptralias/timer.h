// CPP-PTR-ALIAS fixture (test/ifacepeelcheck.sh arms PA*, NA*): envoy's shapes — an interface behind `using TimerPtr = std::unique_ptr<Timer>`
#pragma once
#include <memory>
#define PURE = 0
namespace Envoy {
namespace Event {
class Timer {
public:
  virtual ~Timer() = default;
  virtual bool enabled() PURE;
  virtual void enableTimer(int ms) PURE;
};
using TimerPtr = std::unique_ptr<Timer>;
class TimerImpl : public Timer {
public:
  bool enabled() override;
  void enableTimer(int ms) override;
};
class ScaledMgr {
public:
  class RangeTimerImpl;
};
} // namespace Event
} // namespace Envoy
