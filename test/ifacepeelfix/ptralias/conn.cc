#include "conn.h"
namespace Envoy {
namespace Network {
Event::TimerPtr makeTimer();
void ConnectionImpl::onWriteReady() {
  if (delayed_close_timer_->enabled()) {
    delayed_close_timer_->enableTimer(5);
  }
}
void ConnectionImpl::localTimer() {
  Event::TimerPtr t = makeTimer();
  if (t->enabled()) {
  }
}
void ConnectionImpl::paramTimer(const Event::TimerPtr& t) { t->enableTimer(1); }
} // namespace Network
} // namespace Envoy
