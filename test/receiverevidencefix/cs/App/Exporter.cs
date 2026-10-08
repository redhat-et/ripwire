namespace App
{
    public class Exporter
    {
        public void Flush() { System.Console.WriteLine("exporter flush"); }
        public string Render(string s) { return "<" + s + ">"; }
    }
}
