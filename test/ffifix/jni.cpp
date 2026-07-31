// A JNI native method implementation. ripwire A4-R5 decodes the mangled export
// name to the readable Java name `com.example.Foo.bar` (visible as the binding label).
#include <jni.h>

extern "C"
{
    JNIEXPORT jint JNICALL Java_com_example_Foo_bar( JNIEnv* env, jobject self, jint n )
    {
        (void) env;
        (void) self;
        return n * 3;
    }
}
