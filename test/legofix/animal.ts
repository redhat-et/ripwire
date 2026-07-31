// TypeScript interface Animal + two concrete impls + a factory.
// `Animal` is DELIBERATELY the same name as the Java Animal (animal.java) to exercise the
// mixed-language merge bug: they must resolve to SEPARATE interfaces, own-language impls only.
export interface Animal
{
    speak(): string;
    legs(): number;
}

export class Dog implements Animal
{
    speak(): string { return "woof"; }
    legs(): number { return 4; }
}

export class Cat implements Animal
{
    speak(): string { return "meow"; }
    legs(): number { return 4; }
}

// factory: constructs BOTH sibling impls of the TS Animal.
export function makeAnimal( kind: string ): Animal
{
    if( kind === "dog" ) return new Dog();
    return new Cat();
}
