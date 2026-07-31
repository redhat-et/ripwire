namespace CsharpFix.Services
{
    class Greeter : IGreeter
    {
        public string Greet()
        {
            return "hello";
        }

        public string SayHello()
        {
            return Greet();
        }
    }
}
