export function gapOf<T extends number>( x: T, y: T, margin: T ): number
{
    return ( x < y ? y - x : x - y ) + ( margin > 0 ? margin * 2 : 0 ) - ( x > y ? 1 : 0 ) + ( y > margin ? y - margin : margin - y );
}
