using System;
using CsharpFix.Services;

namespace CsharpFix
{
    class Program
    {
        static void Main( string[] args )
        {
            Greeter g = new Greeter();
            Console.WriteLine( g.SayHello() );
        }
    }
}
