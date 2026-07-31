// C++ interface Shape + two concrete impls + a factory. Single-language (name unique to C++)
// so the <lego> method-contract (<m>) block is exercised where it is SOUND.
#pragma once

#include <memory>
#include <string>

class Shape
{
public:
    virtual ~Shape() = default;
    virtual double area() const = 0;
    virtual void draw() const = 0;
};

class Circle : public Shape
{
public:
    explicit Circle( double r ) : radius( r ) {}
    double area() const override { return 3.14159 * radius * radius; }
    void   draw() const override {}
private:
    double radius;
};

class Square : public Shape
{
public:
    explicit Square( double s ) : side( s ) {}
    double area() const override { return side * side; }
    void   draw() const override {}
private:
    double side;
};

// factory: constructs BOTH sibling impls of Shape (constructor-clustering site).
inline std::unique_ptr<Shape> makeShape( const std::string& kind )
{
    if( kind == "circle" ) return std::make_unique<Circle>( 1.0 );
    return std::make_unique<Square>( 1.0 );
}

// D8 regression fixture: a real, resolvable interface with ZERO implementors — deliberately never
// subclassed. --lego=Renderer must return the interface + its contract with implementors="0", not a
// bare <ctx></ctx> and not the same "not found" outcome as a typo'd name.
class Renderer
{
public:
    virtual ~Renderer() = default;
    virtual void present() const = 0;
};
