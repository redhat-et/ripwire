/* the tmux.h shape: a header PROTOTYPE of the body-carrying owner (rv-gates-for-noise CHANGE 5) — a body slot must never pick it */
#ifndef CMD_FIND_H
#define CMD_FIND_H
struct cmd_find_state;
int cmd_find_target(struct cmd_find_state *fs, const char *target, int flags);
#endif
