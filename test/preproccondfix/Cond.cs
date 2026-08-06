// C# is the one non-C-family grammar in our set with a real PREPROCESSOR, and tree-sitter-c-sharp spells
// its conditional nodes with the same public type names (preproc_if / preproc_else / preproc_elif), so a
// `using` inside `#if` was dropped by exactly the same top-level-only scan.
//
// `#region` is the negative control: it is a FLAT directive, not a container, so RegionUsing.Ns was
// captured before this fix and must still be captured after it.

#if RIPWIRE_NET8
using IfArm.Ns;
#else
using ElseArm.Ns;
#endif

#region grouped
using RegionUsing.Ns;
#endregion

using TopLevel.Ns;

namespace Fixture
{
    class Cond
    {
        void Method()
        {
        }
    }
}
