// The phase-3b repro, in a language FE-B (test/receiverevidencecheck.sh) does not narrow: a C FUNCTION against a
// same-file Objective-C method. `-[Caller go]` bare-calls `compute()`; the C function `compute` and `-[Helper compute]`
// share exactly `modlevel.m::` with the caller under Graph::localityKey — a full tie — so the call stays an honest split:
// `amb="1"` on `go`, no `lpin=`, and `ambiguous=` counts it. (modlevel.kt was this shape until FE-B: Kotlin's implicit
// receiver now proves the top-level `compute` and never `Helper.compute`, so that file pins the new resolution instead.)
#import <Foundation/Foundation.h>

int compute(void) {
    return 6;
}

@interface Caller : NSObject
- (int)go;
@end

@interface Helper : NSObject
- (int)compute;
@end

@implementation Caller
- (int)go {
    return compute();
}
@end

@implementation Helper
- (int)compute {
    return 5;
}
@end
