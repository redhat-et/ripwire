pub fn rust_declined<T>( t: &T ) -> i32
{
    t.rfetch()
}

pub fn rust_qualified_external() -> usize
{
    let v = Vec::<u32>::new();
    v.len()
}
