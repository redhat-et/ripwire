// C# block-scoped namespaces put their `using` directives INSIDE the namespace body — the pre-2021 house
// style of most C# trees, and the same top-level-only scan dropped every one of them. The file-scoped
// form (`namespace Foo;`) is the negative control: it does NOT nest, its usings stay children of the
// compilation unit, and they were never affected.

using Top.Ns;

namespace Outer
{
    using Outer.Inner.Ns;

    namespace Deeper
    {
        using Deeper.Inner.Ns;

        class Deep
        {
            void Method()
            {
            }
        }
    }

    class Shallow
    {
        void Method()
        {
        }
    }
}
