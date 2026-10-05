#include <findlib.h>
#include "mux.h"

static const struct opts_parse copy_args = { "", 0, 1 };

/* A true caller of the function opts_parse, never of the struct. */
int
copy_command(const char **argv, int argc)
{
	struct args *a = opts_parse(&copy_args, argv, argc);
	return a == 0;
}

/* find_type is an enum here; the function of that name comes from an outside library. */
int
classify(const char *s)
{
	return find_type(s) + window_count();
}
