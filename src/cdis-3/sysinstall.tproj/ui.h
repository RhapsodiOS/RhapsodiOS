/* ui.h -- sysinstall's screens on 4.4BSD curses: a menu, a checklist, an
 * input box, a message box and a progress box.  Every item answers its key
 * (1-9, then a-z) as well as the arrow keys and Return, so a script that
 * types keys can drive every screen.  A title may hold several lines; its
 * long lines are wrapped. */

#ifndef UI_H
#define UI_H

/* Start and stop curses.  ui_start returns 0, or -1 if the terminal can't
 * be used.  ui_stop leaves the terminal as it found it. */
int ui_start(void);
void ui_stop(void);

/* The index of the chosen item, or -1 if the input ends. */
int ui_menu(const char *title, const char **items, int n);

/* Ticks items on and off: a key or the space bar toggles, Return accepts.
 * on[i] is 1 for a ticked item.  An item whose locked[i] is set (locked
 * may be NULL) can't be toggled.  0, or -1 if the input ends. */
int ui_checklist(const char *title, const char **items, int *on, int n,
		 const int *locked);

/* Reads a line into buf (len bytes, at most len-1 characters).  buf's
 * contents on entry are the default.  With noecho the characters typed are
 * not shown.  The length read, or -1 if the input ends. */
int ui_input(const char *title, char *buf, int len, int noecho);

/* Shows text under title and waits for Return. */
void ui_message(const char *title, const char *text);

/* Shows "Step step of nsteps: what" (just what if nsteps is 0) and as
 * many of tail's last lines as fit.  Returns at once. */
void ui_progress(int step, int nsteps, const char *what, const char *tail);

#endif
