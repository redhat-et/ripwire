// hasa.h — S5-E test fixture for HAS-A composition edges.
//
// CanyonScreen owns:
//   m_pool  — a SpherePool by VALUE (inline-constructed → rel="creates")
//   m_sound — a SoundEngine by REFERENCE (injected → rel="uses")
//
// The gate checks that --for/--around emit a <compose> block naming both,
// AND that neither member appears as a <c> call edge on CanyonScreen's methods.

class SpherePool
{
public:
    void spawn( int count );
    int  active() const;
};

class SoundEngine
{
public:
    void play( const char* clip );
    void stop();
};

class CanyonScreen
{
public:
    void render();
    void update( float dt );

private:
    SpherePool   m_pool;          // creates: inline value member — SpherePool is HAS-A
    SoundEngine& m_sound;         // uses:    injected reference — SoundEngine is HAS-A
};
