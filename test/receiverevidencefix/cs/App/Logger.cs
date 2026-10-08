using static Markup.Html;

namespace App
{
    public class Base
    {
        public void Flush() { System.Console.WriteLine("base flush"); }
    }

    // Inherited: a bare Flush() reaches Base.Flush through the class cone; Reset is its own.
    public class Child : Base
    {
        public void Close() { Flush(); Reset(); }
        private void Reset() { System.Console.WriteLine("reset"); }
    }

    // A bare call is this.Method() or a using-static import: Logger inherits Flush() from an OUTSIDE class
    // and imports Render from an outside type; Exporter and Base are unrelated.
    public class Logger : System.IO.StringWriter
    {
        public string Line(string s) { return Render(s); }
        public void Finish() { Flush(); }
    }
}
