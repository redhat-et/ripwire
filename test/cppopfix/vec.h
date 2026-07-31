// C++ operator-method coverage fixture. Every operator declarator kind ctxpack must now capture:
//   - symbolic member ops (operator==/=/+), whose declarator is `operator_name`
//   - subscript/call/arrow (operator[]/()/->)
//   - ops whose NAME carries XML-special chars: <, <<, <=, <=> (spaceship), &, &&, >  (the escaping proof)
//   - a conversion operator (`operator bool`), whose declarator is the DISTINCT `operator_cast`
// The out-of-line `Vec::operator==` / `Vec::operator=` definitions live in vec.cpp (qualified form).
struct Vec
{
    double x;

    bool    operator==( const Vec& o ) const;
    Vec&    operator=( const Vec& o );
    Vec     operator+( const Vec& o ) const;

    double  operator[]( int i ) const;
    double& operator()( int i );
    Vec*    operator->();

    bool    operator<( const Vec& o ) const;
    Vec     operator<<( int n ) const;
    bool    operator<=( const Vec& o ) const;
    int     operator<=>( const Vec& o ) const;
    Vec     operator&( const Vec& o ) const;
    bool    operator&&( const Vec& o ) const;
    bool    operator>( const Vec& o ) const;

    operator bool() const;
    operator double() const;
};
