// a.ts — two functions, one calls the other.
function addOne(x: number): number {
    return x + 1;
}

function addTwo(x: number): number {
    return addOne(addOne(x));
}
