#include "socket.h"
namespace Envoy {
namespace Network {
void Conn::onRead() {
  if (socket_->isOpen()) {
  }
  socket_->setDetected();
}
} // namespace Network
} // namespace Envoy
