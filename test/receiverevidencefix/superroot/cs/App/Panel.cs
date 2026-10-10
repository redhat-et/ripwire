using Outside;

namespace App
{
    public class Panel : Base
    {
        public string Typed()
        {
            var super = new Widget();
            return super.Render();
        }

        public string Untyped()
        {
            var super = Factory.Make();
            return super.Render();
        }

        public string RealBase()
        {
            return base.Render();
        }
    }
}
