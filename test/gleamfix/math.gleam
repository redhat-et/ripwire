import gleam/io
import gleam/list

pub type Color {
  Red
  Green
}

pub type Point {
  Point(x: Int, y: Int)
}

pub type Meters = Int

@external(erlang, "math", "native")
pub fn native(value: Int) -> Int

pub fn add(a: Int, b: Int) -> Int {
  a + b
}

fn increment(value: Int) -> Int {
  add(value, 1)
}

pub fn pipeline(value: Int) -> Int {
  value
  |> increment
  |> add(2)
}

pub fn announce(values: List(Int)) {
  values
  |> list.map(increment)
  |> io.debug
}
