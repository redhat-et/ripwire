namespace App
{
    public class Base
    {
        public virtual string Render() { return "base"; }
    }

    public class Widget
    {
        public string Render() { return "widget"; }
    }
}
