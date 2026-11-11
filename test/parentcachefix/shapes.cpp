// parent-cache fixture: nested namespace / class members, qualified calls, template-wrapped member calls
namespace outer
{
namespace inner
{
int helper( int v );
struct Box
{
    struct Lid
    {
        void open();
        void close( int a, int b );
    };
};
void Box::Lid::open() {}
template <class T> struct W
{
    template <class U> void m( U u );
};
template <class T> void use( W<T>& w ) { w.template m<int>( 1 ); w.m<long>( 2 ); }
void caller()
{
    Box::Lid lid;
    lid.close( 1, 2 );
    outer::inner::helper( 3 );
    ::outer::inner::helper( helper( 4 ) );
}
}   // namespace inner
}   // namespace outer
