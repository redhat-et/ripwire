#ifndef MUX_H
#define MUX_H

/* A struct and an enum spelled like functions the program calls. */
struct opts_parse {
	const char *template;
	int lower;
	int upper;
};

enum find_type {
	FIND_PANE,
	FIND_WINDOW,
	FIND_SESSION
};

/* A struct spelled like the C library's clock(): only the library function is callable. */
struct clock {
	long ticks;
};

struct args *opts_parse(const struct opts_parse *, const char **, int);
int window_count(void);

#endif
