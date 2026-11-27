#include "timer.h"
namespace Envoy {
namespace Event {
bool TimerImpl::enabled() { return true; }
void TimerImpl::enableTimer(int ms) {}
// an implementor defined OUT OF LINE as a nested class: its members are scoped "ScaledMgr::RangeTimerImpl"
class ScaledMgr::RangeTimerImpl final : public Timer {
public:
  bool enabled() override { return false; }
  void enableTimer(int ms) override {}
};
} // namespace Event
} // namespace Envoy
