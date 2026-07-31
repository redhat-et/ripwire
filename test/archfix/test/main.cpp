// test/main.cpp — a test-layer file that includes a render-layer header.
// With `deny test -> render` in the rules, ripwire should flag this as a violation.
#include "../render/shader.h"

int main()
{
    compileShader( "void main(){}" );
    return 0;
}
