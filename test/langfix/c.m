// c.m — an ObjC class with methods, one calls another via [self ...].
// Exercises the same-file decl/def collapse (ingest 3a-bis): doubleValue/quadrupleValue are
// each DECLARED in @interface and DEFINED in @implementation, so pre-fix they doubled. The
// fix collapses each decl into its def → one node per method. tripleValue: is declared in
// @interface with NO @implementation — that decl must SURVIVE (the "no def anywhere keeps
// the decl" escape hatch), mirroring a C++ extern/pure-virtual decl with no definition.
#import <Foundation/Foundation.h>

@interface Calculator : NSObject
- (int)doubleValue:(int)x;
- (int)quadrupleValue:(int)x;
- (int)tripleValue:(int)x;   // declared only — no @implementation → decl must survive the collapse
@end

@implementation Calculator

- (int)doubleValue:(int)x {
    return x * 2;
}

- (int)quadrupleValue:(int)x {
    return [self doubleValue:[self doubleValue:x]];
}

@end
