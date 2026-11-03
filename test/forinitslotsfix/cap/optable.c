struct optable {
    int (*s00)(int);
    int (*s01)(int);
    int (*s02)(int);
    int (*s03)(int);
    int (*s04)(int);
    int (*s05)(int);
    int (*s06)(int);
    int (*s07)(int);
    int (*s08)(int);
    int (*s09)(int);
    int (*s10)(int);
    int (*s11)(int);
    int (*s12)(int);
    int (*s13)(int);
    int (*s14)(int);
    int (*s15)(int);
    int (*s16)(int);
    int (*s17)(int);
    int (*s18)(int);
    int (*s19)(int);
};

static int op00(int x) { return x + 0; }
static int op01(int x) { return x + 1; }
static int op02(int x) { return x + 2; }
static int op03(int x) { return x + 3; }
static int op04(int x) { return x + 4; }
static int op05(int x) { return x + 5; }
static int op06(int x) { return x + 6; }
static int op07(int x) { return x + 7; }
static int op08(int x) { return x + 8; }
static int op09(int x) { return x + 9; }
static int op10(int x) { return x + 10; }
static int op11(int x) { return x + 11; }
static int op12(int x) { return x + 12; }
static int op13(int x) { return x + 13; }
static int op14(int x) { return x + 14; }
static int op15(int x) { return x + 15; }
static int op16(int x) { return x + 16; }
static int op17(int x) { return x + 17; }
static int op18(int x) { return x + 18; }
static int op19(int x) { return x + 19; }

const struct optable big_optable = {
    .s00 = op00,
    .s01 = op01,
    .s02 = op02,
    .s03 = op03,
    .s04 = op04,
    .s05 = op05,
    .s06 = op06,
    .s07 = op07,
    .s08 = op08,
    .s09 = op09,
    .s10 = op10,
    .s11 = op11,
    .s12 = op12,
    .s13 = op13,
    .s14 = op14,
    .s15 = op15,
    .s16 = op16,
    .s17 = op17,
    .s18 = op18,
    .s19 = op19,
};
