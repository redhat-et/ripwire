// Rust trait Vehicle + two impls via `impl Vehicle for T` + a factory.
// `impl Trait for T` is a top-level `impl_item` SIBLING of the struct def — not reachable from
// the struct's children — so captureBases (which walks a class node's children) cannot see it.
// P2 adds a small post-pass over impl_item nodes reading the trait: / type: fields.

pub trait Vehicle
{
    fn wheels( &self ) -> u32;
    fn name( &self ) -> &str;
}

pub struct Car;
pub struct Bike;

impl Vehicle for Car
{
    fn wheels( &self ) -> u32 { 4 }
    fn name( &self ) -> &str { "car" }
}

impl Vehicle for Bike
{
    fn wheels( &self ) -> u32 { 2 }
    fn name( &self ) -> &str { "bike" }
}

// factory: constructs both sibling impls of Vehicle.
pub fn make_vehicle( kind: &str ) -> Box<dyn Vehicle>
{
    if kind == "car" { Box::new( Car ) } else { Box::new( Bike ) }
}
