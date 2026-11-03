#include <memory>
namespace Http {
class StreamDecoderFilter {
public:
  virtual ~StreamDecoderFilter() = default;
  virtual int decodeHeaders(int h) = 0;
  virtual void reset() = 0;
};
using StreamDecoderFilterSharedPtr = std::shared_ptr<StreamDecoderFilter>;
typedef std::unique_ptr<StreamDecoderFilter> StreamDecoderFilterPtr;
using FilterHandle = StreamDecoderFilterSharedPtr;
class BufferFilter : public StreamDecoderFilter { public: int decodeHeaders(int h) override; void reset() override {} };
}
namespace Router {
class Filter : public Http::StreamDecoderFilter { public: int decodeHeaders(int h) override; void reset() override {} };
}
class Codec {
public:
  int encodeFrame(int h) { return h * 2; }
};
using CodecSharedPtr = std::shared_ptr<Codec>;
namespace text { class string { public: int size() { return 1; } }; }   // an in-tree namesake of std::string (N5)
using NameSharedPtr = std::shared_ptr<std::string>;
class Other { public: int encodeFrame(int h) { return h; } };
class ActiveStreamDecoderFilter {
public:
  int viaAlias(int h) { return handle_->decodeHeaders(h); }
  int viaTypedef(int h) { return owned_->decodeHeaders(h); }
  int viaChain(int h) { return chained_->decodeHeaders(h); }
  int viaConcrete(int h) { return codec_->encodeFrame(h); }
  int viaDot(int h) { handle_.reset(); return h; }
  Http::StreamDecoderFilterSharedPtr handle_;
  Http::StreamDecoderFilterPtr owned_;
  Http::FilterHandle chained_;
  CodecSharedPtr codec_;
  NameSharedPtr name_;
};
inline int nameLen(ActiveStreamDecoderFilter& f) { return static_cast<int>(f.name_->size()); }
