// Java interface Animal + two concrete impls + a factory.
// Same name as the TS Animal (animal.ts) — the merge-bug regression: Java Animal must stay
// separate, with only Wolf/Lion as impls, never the TS Dog/Cat.
// Java uses `super_interfaces` (implements) / `superclass` (extends) node kinds — NOT the
// TS `class_heritage` — so captureBases must recognise them (P2).
public interface Animal
{
    String speak();
    int legs();
}

class Wolf implements Animal
{
    public String speak() { return "howl"; }
    public int legs() { return 4; }
}

class Lion implements Animal
{
    public String speak() { return "roar"; }
    public int legs() { return 4; }
}

// a base class exercised via `extends` (superclass node kind).
class Cub extends Wolf
{
    public String speak() { return "yip"; }
}

class AnimalFactory
{
    static Animal make( String kind )
    {
        if( kind.equals( "wolf" ) ) return new Wolf();
        return new Lion();
    }
}
