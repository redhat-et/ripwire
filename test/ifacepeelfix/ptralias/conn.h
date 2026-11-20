#pragma once
#include "timer.h"
#include "stats.h"
namespace Envoy {
namespace Network {
class ConnectionImplBase {
protected:
  Event::TimerPtr delayed_close_timer_;
};
class ConnectionImpl : public ConnectionImplBase {
public:
  void onWriteReady();
  void localTimer();
  void paramTimer(const Event::TimerPtr& t);
};
} // namespace Network
} // namespace Envoy
