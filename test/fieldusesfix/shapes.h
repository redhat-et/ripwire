// fieldusesfix/shapes.h — two classes declaring SAME-NAMED member variables (count, label) beside distinct
// ones, so `--uses=Counter.count` and `--uses=Gauge.count` must be told apart per use-site (fieldusescheck.sh).
// Line numbers are LOAD-BEARING only in shapes.cpp; declarations here are addressed by canonical id.

struct Counter
{
    int   count = 0;          // Counter.count
    int   step  = 1;          // Counter.step
    char* label = nullptr;    // Counter.label
    static constexpr int kMax = 99;   // a class-static CONSTANT: stays t="var" (moduleconstcheck), never a field
    static int           live;        // a static data member: NOT a field (disclosed — no per-object state)

    void bump();
    void set( int count );    // the parameter deliberately SHADOWS the field
    int  peek() const;
};

struct Gauge
{
    int    count = 0;         // Gauge.count — same name as Counter.count
    double level = 0.0;       // Gauge.level
    char*  label = nullptr;   // Gauge.label — same name as Counter.label
    Counter inner;            // Gauge.inner — a member whose TYPE is another owner (Rule 2b fuel)

    void fill( double amount );
    void relay();
};
