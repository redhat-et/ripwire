#pragma once
#include <memory>
namespace Envoy {
namespace Network {
// the contract is declared by a BASE of the pointee; the one implementor inherits its body from a sibling base
class Socket { public: virtual ~Socket() = default; virtual bool isOpen() const = 0; };
class ConnectionSocket : public virtual Socket { public: virtual void setDetected() = 0; };
using ConnectionSocketPtr = std::unique_ptr<ConnectionSocket>;
class IoHandle { public: virtual ~IoHandle() = default; virtual bool isOpen() const = 0; };
class IoSocketHandleImpl : public IoHandle { public: bool isOpen() const override { return true; } };
class SocketImpl : public virtual Socket { public: bool isOpen() const override { return true; } };
class ConnectionSocketImpl : public SocketImpl, public virtual ConnectionSocket { public: void setDetected() override {} };
class ListenSocketImpl : public SocketImpl { public: bool isOpen() const override { return false; } };
class Conn {
public:
  void onRead();
private:
  ConnectionSocketPtr socket_;
};
} // namespace Network
} // namespace Envoy
