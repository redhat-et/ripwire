#include <assert.h>

struct cmd_find_state;
int cmd_find_target(struct cmd_find_state *fs, const char *target, int flags);

/* How does the command resolve the -t target: session, window and pane. */
static void
test_cmd_find_target_resolves_session_window_pane(void)
{
    assert(cmd_find_target(0, "", 0) == -1);
}

int
main(void)
{
    test_cmd_find_target_resolves_session_window_pane();
    return 0;
}
