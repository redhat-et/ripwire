#include "widget.h"
namespace app {
void localIface() { WidgetPtr w = makeWidget(); w->draw(); }
void localConcrete() { CodecPtr c = makeCodec(); c->encode(); }
void localQualified() { app::CodecPtr d = makeCodec(); d->encode(); }
void localTypedef() { WidgetSharedPtr s; s->draw(); }
void localConst() { WidgetConstSharedPtr k; k->draw(); }
void paramAlias(const CodecPtr& c, WidgetSharedPtr w) { c->encode(); w->draw(); }
void rawLocal() { std::unique_ptr<Codec> c = makeCodec(); c->encode(); }
void rawParam(const std::shared_ptr<Widget>& w, std::unique_ptr<app::Codec> c) { w->draw(); c->encode(); }
void ptrToAlias(CodecPtr* p) { p->encode(); }
void dotOnAlias() { CodecPtr c = makeCodec(); c.reset(); }
void plainAlias() { CodecAlias c; c.encode(); }
void tmplAlias() { Ptr<Codec> p; p->encode(); }
void viaGet() { CodecPtr c = makeCodec(); c.get()->encode(); }
void viaDeref() { CodecPtr c = makeCodec(); (*c).encode(); }
} // namespace app
void ambiguousAlias() { ItemPtr p; p->run(); }
