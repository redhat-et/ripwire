void cppCodecWrongHelper() {}
namespace Ext {
namespace Http {
struct Codec { static void h(); };
void Codec::h() { cppCodecWrongHelper(); }
}
}
