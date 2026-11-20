#pragma once
#include <memory>
namespace app {
class Widget { public: virtual ~Widget() = default; virtual void draw() = 0; };
class Button : public Widget { public: void draw() override {} };
class Label : public Widget { public: void draw() override {} };
class Codec { public: void encode() {} void reset() {} };
using WidgetPtr = std::unique_ptr<Widget>;
typedef std::shared_ptr<Widget> WidgetSharedPtr;
using WidgetConstSharedPtr = std::shared_ptr<const Widget>;
using CodecPtr = std::unique_ptr<Codec>;
using CodecAlias = Codec;
template <class T> using Ptr = std::unique_ptr<T>;
WidgetPtr makeWidget();
CodecPtr makeCodec();
} // namespace app
namespace other {
class Gadget { public: void draw() {} void encode() {} void reset() {} };
} // namespace other
// two namespaces declare ItemPtr, each for its own Item: an unqualified ItemPtr in a body names one of them, unread
namespace na { class Item { public: void run() {} }; using ItemPtr = std::unique_ptr<Item>; }
namespace nb { class Item { public: void run() {} }; using ItemPtr = std::unique_ptr<Item>; }
