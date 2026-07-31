// d.h - standalone ObjC header. It has no neighboring .m/.mm file on purpose:
// .h defaults to C++, so ingest must sniff @interface and prewarm the ObjC query.

@interface HeaderOnly : NSObject
- (int)headerValue;
@end
