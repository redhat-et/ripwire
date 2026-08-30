#pragma once
// Two bucketing ladders with DISJOINT identifiers but the SAME enclosing context (one file, one
// namespace). Copy-paste next door is a real duplicate, so the conjunction must refuse to demote it.
namespace boxed
{

enum class WidthClass : unsigned char { Thin, Slim, Wide, Vast };
enum class DepthClass : unsigned char { Shallow, Middling, Sunken, Abyssal };

inline WidthClass widthClassOf( float w )
{
    if( w <  4.0f ) return WidthClass::Thin;
    if( w <  9.0f ) return WidthClass::Slim;
    if( w < 15.0f ) return WidthClass::Wide;
    return WidthClass::Vast;
}

inline DepthClass depthClassOf( float d )
{
    if( d <  7.0f ) return DepthClass::Shallow;
    if( d < 21.0f ) return DepthClass::Middling;
    if( d < 44.0f ) return DepthClass::Sunken;
    return DepthClass::Abyssal;
}

}   // namespace boxed
