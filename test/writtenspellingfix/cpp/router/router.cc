namespace Envoy {
namespace Router {
class Filter {
public:
  void decodeHeaders(int h);
};
static int cppRouterHelper(int h) { return h; }
void Filter::decodeHeaders(int h) { cppRouterHelper(h); }
} // namespace Router
namespace Upstream {
class Filter {
public:
  void decodeHeaders(int h);
};
static int cppUpstreamHelper(int h) { return h; }
void Filter::decodeHeaders(int h) { cppUpstreamHelper(h); }
} // namespace Upstream
} // namespace Envoy
