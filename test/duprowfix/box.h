// test/duprowfix/box.h — a minimal const/non-const accessor-overload pair, mirroring src/infra/svector.h's
// buf()/buf() const shape that motivated §P6.3: the two overloads canonicalize to the SAME
// id="...Box::data" (canonicalId is path::scope::name — it has no notion of signature or
// const-qualification), so before the fix the default map printed the identical <s ... id="...Box::data">
// row twice, byte-for-byte except whatever float noise separates their independently-ranked PageRank
// scores. touch() calls data() once; the name-based resolver cannot tell which overload a call site
// means, so it links to both — the real-repo mechanism (svector.h's push_back() calling buf() twice).

class Box
{
public:
    int*       data()       { return p_; }
    const int* data() const { return p_; }
    void       touch() { data(); }

private:
    int* p_ = nullptr;
};
