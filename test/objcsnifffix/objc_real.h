// objc_real.h — the objcsniffcheck CONTROL fixture: a genuine Objective-C header. Its @interface is
// LIVE CODE, so the comment/string-masked sniff must still route this file to the objc grammar —
// the fix narrows the sniff, it must not blind it.
#import <Foundation/Foundation.h>

@interface RealObjCThing : NSObject
- (void)doRealThing;
@end
