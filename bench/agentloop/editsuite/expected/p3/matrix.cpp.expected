#include <vector>

using Matrix = std::vector<std::vector<double>>;

Matrix transpose( const Matrix& m )
{
    if( m.empty() )
    {
        return {};
    }
    Matrix out( m[0].size(), std::vector<double>( m.size(), 0.0 ) );
    for( std::size_t r = 0; r < m.size(); ++r )
    {
        for( std::size_t c = 0; c < m[r].size(); ++c )
        {
            out[c][r] = m[r][c];
        }
    }
    return out;
}

double trace( const Matrix& m )
{
    double sum = 0.0;
    for( std::size_t i = 0; i < m.size(); ++i )
    {
        if( i < m[i].size() )
        {
            sum += m[i][i];
        }
    }
    return sum;
}

double frobenius( const Matrix& m )
{
    double sum = 0.0;
    for( const auto& row : m )
    {
        for( double v : row )
        {
            sum += v * v;
        }
    }
    return sum;
}
