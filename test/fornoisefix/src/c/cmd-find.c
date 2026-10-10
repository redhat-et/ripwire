#include <stdlib.h>
#include <string.h>

struct session { const char *name; };
struct window { int id; };
struct window_pane { int id; };
struct client { struct session *session; };

struct cmd_find_state {
    struct session *s;
    struct window *w;
    struct window_pane *wp;
    int flags;
};

/* The current client of the command queue, used when no -t target is given. */
static struct client *
cmd_find_current_client(struct cmd_find_state *fs)
{
    (void)fs;
    return NULL;
}

/* Find the session a target names. */
static int
cmd_find_get_session(struct cmd_find_state *fs, const char *session)
{
    if (session == NULL || *session == '\0')
        return (-1);
    fs->s = NULL;
    return (0);
}

/* Find the window a target names, inside the session already found. */
static int
cmd_find_get_window(struct cmd_find_state *fs, const char *window)
{
    if (window == NULL)
        return (-1);
    fs->w = NULL;
    return (0);
}

/* Find the pane a target names, inside the window already found. */
static int
cmd_find_get_pane(struct cmd_find_state *fs, const char *pane)
{
    if (pane == NULL)
        return (-1);
    fs->wp = NULL;
    return (0);
}

/* Is the state complete: session, window and pane all resolved? */
static int
cmd_find_valid_state(struct cmd_find_state *fs)
{
    return (fs->s != NULL && fs->w != NULL && fs->wp != NULL);
}

/* Fill in the state from the current client. */
static int
cmd_find_from_client(struct cmd_find_state *fs, struct client *c)
{
    if (c == NULL || c->session == NULL)
        return (-1);
    fs->s = c->session;
    return (0);
}

/*
 * Resolve the -t target of a command into a session, window and pane: split
 * the target on ':' and '.', then look each part up in turn.
 */
int
cmd_find_target(struct cmd_find_state *fs, const char *target, int flags)
{
    struct client *c;
    char *copy, *colon, *period;
    const char *session, *window, *pane;

    memset(fs, 0, sizeof *fs);
    fs->flags = flags;
    c = cmd_find_current_client(fs);
    if (target == NULL || *target == '\0') {
        if (cmd_find_from_client(fs, c) != 0)
            return (-1);
        return (cmd_find_valid_state(fs) ? 0 : -1);
    }
    copy = strdup(target);
    colon = strchr(copy, ':');
    if (colon != NULL)
        *colon++ = '\0';
    period = strchr(colon != NULL ? colon : copy, '.');
    if (period != NULL)
        *period++ = '\0';
    session = copy;
    window = colon;
    pane = period;
    if (cmd_find_get_session(fs, session) != 0)
        goto error;
    if (window != NULL && cmd_find_get_window(fs, window) != 0)
        goto error;
    if (pane != NULL && cmd_find_get_pane(fs, pane) != 0)
        goto error;
    free(copy);
    return (cmd_find_valid_state(fs) ? 0 : -1);

error:
    free(copy);
    return (-1);
}
