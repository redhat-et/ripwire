#pragma once
namespace Envoy {
namespace Http {
class ConnectionManagerImpl {
public:
  class ActiveStream {
  public:
    void decodeHeaders(int h);
  };
};
} // namespace Http
} // namespace Envoy
