export function widthBetween<T extends number>( lo: T, hi: T, pad: T ): number
{
    return ( lo < hi ? hi - lo : lo - hi ) + ( pad > 0 ? pad * 2 : 0 ) - ( lo > hi ? 1 : 0 ) + ( hi > pad ? hi - pad : pad - hi );
}
