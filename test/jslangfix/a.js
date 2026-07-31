// a.js — JavaScript ingest fixture for jslangcheck.sh.
// Two functions where addTwo() calls addOne() → one intra-file call edge addTwo -> addOne.

function addOne( x )
{
    return x + 1;
}

const addTwo = ( x ) =>
{
    return addOne( addOne( x ) );
};

module.exports = { addOne, addTwo };
