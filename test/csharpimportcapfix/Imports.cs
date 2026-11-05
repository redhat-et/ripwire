using System;
using Demo.Widget;
using Alias = Demo.Widget;
global using GlobalAlias = Demo.Widget;
using static Demo.Widget;
global using static Demo.Widget;
global using Demo;
using global::Demo.Widget;
using Generic = Demo.Box<int>;
using Pair = (int left, string right);
using Items = Demo.Widget[];
using Maybe = Demo.Widget?;
using unsafe Ptr = int*;
using Demo;
using Demo;
using /* before */ Demo /* middle */ . Widget;
using /* before */ CommentAlias /* alias */ = Demo . Widget;

namespace Outer
{
    using Nested = Demo.Widget;
    public class Caller
    {
        public static void Run(bool chooseWidget)
        {
            Alias.Ping();
            if (chooseWidget)
            {
                Widget.Ping();
            }
            else
            {
                Ping();
            }
        }
        public void Resource()
        {
            using var resource = new Disposable();
        }
    }
}
