namespace Envoy {
namespace HttpConnectionManager {
class Utility {
public:
  static int createSingletons(int c);
};
static int cppSingletonHelper(int c) { return c; }
int Utility::createSingletons(int c) { return cppSingletonHelper(c); }
} // namespace HttpConnectionManager
} // namespace Envoy
