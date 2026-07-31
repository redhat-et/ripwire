// chafix/cha.cpp — gate fixture for B2.1 CHA-lite (class-hierarchy devirtualization of an ambiguous,
// receiver-typed method call).
//
// Animal is a base with a bodied speak(). Dog and Cat are two implementors; NEITHER overrides speak(),
// so both inherit Animal::speak. Robot is an UNRELATED class that happens to define its own speak().
//
// Under the bare §2a ladder a `Dog d; d.speak()` call splits 1/k across Animal::speak AND Robot::speak
// (Dog defines neither, so both same-name defs survive) — a WRONG Robot edge. CHA-lite knows the receiver
// static type is Dog, whose inheritance cone is {Dog} ∪ ancestors{Animal} ∪ descendants{} = {Dog, Animal}.
// Robot is outside that cone → dropped. The call resolves to Animal::speak ONLY (the inherited definition),
// so its ambiguity disappears. The sibling Cat (a second implementor) is present precisely to prove the
// cone is directional: a Dog receiver never reaches Cat's methods, so a Cat method would also be excluded.

struct Animal
{
    void         speak();        // declared here, defined out-of-line below (a real, bodied def)
    virtual void move();         // an unrelated virtual so Animal is a genuine polymorphic base
    int          tag = 0;
};

struct Dog : Animal              // implementor 1 — does NOT define speak (inherits Animal::speak)
{
    void move() override { tag = 1; }
};

struct Cat : Animal              // implementor 2 — sibling of Dog; also does not define speak
{
    void move() override { tag = 2; }
};

struct Robot                     // UNRELATED class that coincidentally also defines speak()
{
    void speak() { power = 1; }
    int  power = 0;
};

void Animal::speak() { tag = 7; }   // the single inherited definition Dog and Cat share

// POSITIVE: a local Dog variable → the narrower knows d : Dog → CHA-lite prunes the call to the Dog cone,
// dropping the unrelated Robot::speak. The call resolves to Animal::speak alone (ambiguity removed).
void g()
{
    Dog d;
    d.speak();                   // CHA-lite: cone(Dog) = {Dog, Animal} → Animal::speak ONLY (Robot excluded)
}

// NEGATIVE control: the SAME call shape, but the receiver is a function PARAMETER — no local var→type
// binding is captured, so the receiver's static type is UNKNOWN to the narrower → CHA-lite cannot fire →
// the call stays HONESTLY AMBIGUOUS (edges to BOTH Animal::speak and Robot::speak). This contrast is the
// proof that the positive case is a REAL hierarchy narrow, not a vacuously-unambiguous fixture.
void h( Dog* p )
{
    p->speak();                  // unknown receiver type → Animal::speak + Robot::speak both survive (amb)
}
