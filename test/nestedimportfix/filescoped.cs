// NEGATIVE CONTROL for the C# arm: the file-scoped namespace declaration (`namespace Foo;`) does not
// open a block, so its usings remain direct children of the compilation unit. They were captured before
// this change and must still be captured after it — if this file's count moves, the C# containers were
// widened past what the grammar actually nests.

using FileScoped.Before;

namespace FileScopedNs;

using FileScoped.After;

class OnlyType
{
    void Method()
    {
    }
}
