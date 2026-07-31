// FIX #2 repro (C++): an interface Outer with a class Nested declared INSIDE it. The Lego
// method-contract for Outer must list ONLY Outer's own methods (outerMethod) — NOT Nested's
// methods (nestedMethod), which belong to Outer::Nested. Concrete impls give each interface an
// implementor so packLego emits a contract. Type names Outer/Nested/Widget/Gadget unique here.
#pragma once

class Outer
{
public:
    virtual ~Outer() = default;
    virtual void outerMethod() = 0;

    class Nested
    {
    public:
        virtual ~Nested() = default;
        virtual void nestedMethod() = 0;
    };
};

class Widget : public Outer
{
public:
    void outerMethod() override {}
};

class Gadget : public Outer::Nested
{
public:
    void nestedMethod() override {}
};
