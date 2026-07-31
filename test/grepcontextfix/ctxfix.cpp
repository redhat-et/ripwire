NEEDLE_TOP
line2
line3
line4
line5
line6
line7
line8
line9
line10

int widget( int x )
{
    // café line above — naïve, 日本語, emoji present but no needle here
    int y = x + 1;         // café line directly before the hit
    int hitline = NEEDLE_MID_ONCE;
    int z = y + 1;         // 日本語 line directly after the hit
    return z;
}
