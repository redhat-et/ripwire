// b.rs — two fns, one calls the other.
fn square(x: i32) -> i32 {
    x * x
}

fn sum_of_squares(a: i32, b: i32) -> i32 {
    square(a) + square(b)
}
