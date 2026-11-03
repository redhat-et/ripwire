#include "ops.h"
static int cmd_alpha_exec( struct cmd_ent *e, int a ) { return a + ( e != 0 ); }
static int cmd_beta_exec( struct cmd_ent *e, int a ) { return a - ( e != 0 ); }
const struct cmd_ent cmd_alpha_entry = { .name = "alpha", .exec = cmd_alpha_exec };
const struct cmd_ent cmd_beta_entry = { .name = "beta", .exec = cmd_beta_exec };
static int other_exec( int a ) { return a; }
const struct other other_entry = { .exec = other_exec };
static int third_exec( int a ) { return -a; }
const struct third third_entry = { .exec = third_exec };
