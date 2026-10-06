/* ui.c -- sysinstall's screens on 4.4BSD curses.  See ui.h.
 *
 * The screen: a title bar on row 0, the widget's title from row 2, its
 * items or text below that, and a line of help on the last row.  The
 * console's terminal has no standout, so the current item is marked with
 * a ">" rather than drawn in reverse. */

#include <stdio.h>
#include <string.h>
#include <curses.h>
#include "ui.h"

#define K_EOF	(-1)
#define K_UP	(-2)
#define K_DOWN	(-3)

#define LEFT	2		/* the left margin */
#define TOP	2		/* the first row under the title bar */
#define WIDTH	(COLS - 2 * LEFT)
#define BOTTOM	(LINES - 3)	/* the last row of the widget */

/* ---- drawing ---- */

/* At most w characters of s at (y, x); control characters as spaces. */
static void put(int y, int x, const char *s, int w)
{
	int i;

	if (y < 0 || y > LINES - 1)
		return;
	move(y, x);
	for (i = 0; i < w && s[i] != '\0'; i++)
		addch((s[i] < ' ' || s[i] > '~') ? ' ' : s[i]);
}

/* Draws s from row y, wrapped at WIDTH, no lower than row ymax, unless
 * draw is 0.  Returns the number of rows the whole text needs. */
static int wrap(int y, int ymax, const char *s, int draw)
{
	const char *p = s, *e, *brk;
	int rows = 0, w;

	while (*p != '\0') {
		e = p;
		brk = NULL;
		for (w = 0; *e != '\0' && *e != '\n' && w < WIDTH; w++, e++)
			if (*e == ' ')
				brk = e;
		if (w == WIDTH && *e != '\0' && *e != '\n' && *e != ' ' &&
		    brk != NULL)
			e = brk;
		if (draw && y + rows <= ymax)
			put(y + rows, LEFT, p, (int)(e - p));
		rows++;
		p = e;
		if (*p == '\n' || *p == ' ')
			p++;
	}
	return rows;
}

/* Clears the screen to the title bar, the title and the help line.
 * Returns the first free row under the title. */
static int frame(const char *title, const char *help)
{
	int i, rows, ymax = BOTTOM - 3;

	erase();
	standout();
	move(0, 0);
	addstr(" RhapsodiOS");
	for (i = 11; i < COLS; i++)
		addch(' ');
	standend();
	put(LINES - 1, LEFT, help, WIDTH);
	rows = wrap(TOP, ymax, title, 1);
	if (TOP + rows > ymax + 1)
		rows = ymax + 1 - TOP;
	return TOP + rows + 1;
}

/* ---- keys ---- */

static int getkey(void)
{
	int c;

	move(LINES - 1, 0);
	refresh();
	c = getch();
	if (c == EOF)
		return K_EOF;
	if (c == 033) {			/* ESC [ A, ESC O A: the arrows */
		c = getch();
		if (c == '[' || c == 'O') {
			c = getch();
			if (c == 'A')
				return K_UP;
			if (c == 'B')
				return K_DOWN;
		}
		return c == EOF ? K_EOF : 0;
	}
	if (c == 020)			/* ^P, ^N */
		return K_UP;
	if (c == 016)
		return K_DOWN;
	return c;
}

static int is_return(int c)
{
	return c == '\n' || c == '\r';
}

/* Item i's key: 1-9, then a-z; a space past them. */
static int label(int i)
{
	if (i < 9)
		return '1' + i;
	if (i < 35)
		return 'a' + i - 9;
	return ' ';
}

/* The item a key names, or -1. */
static int index_of(int c)
{
	if (c >= '1' && c <= '9')
		return c - '1';
	if (c >= 'a' && c <= 'z')
		return c - 'a' + 9;
	if (c >= 'A' && c <= 'Z')
		return c - 'A' + 9;
	return -1;
}

/* ---- lists ---- */

/* Draws items from row y, scrolled so that cur shows.  on is NULL for a
 * menu, else the checklist's ticks. */
static void list(int y, const char **items, const int *on, int n, int cur)
{
	char line[16];
	int rows = BOTTOM - y + 1, top = 0, i, row;

	if (rows < 1)
		rows = 1;
	if (cur >= rows)
		top = cur - rows + 1;
	for (i = top, row = y; i < n && row <= BOTTOM; i++, row++) {
		if (on != NULL)
			sprintf(line, "%c %c  [%c] ", i == cur ? '>' : ' ',
				label(i), on[i] ? 'x' : ' ');
		else
			sprintf(line, "%c %c  ", i == cur ? '>' : ' ',
				label(i));
		put(row, LEFT, line, WIDTH);
		put(row, LEFT + (int)strlen(line), items[i],
		    WIDTH - (int)strlen(line));
	}
	if (top > 0)
		put(y - 1, LEFT, "  (more above)", WIDTH);
	if (i < n)
		put(BOTTOM + 1, LEFT, "  (more below)", WIDTH);
}

int ui_start(void)
{
	if (initscr() == NULL)
		return -1;
	cbreak();
	noecho();
	return 0;
}

void ui_stop(void)
{
	erase();
	refresh();
	endwin();
}

int ui_menu(const char *title, const char **items, int n)
{
	int cur = 0, y, k, i;

	if (n <= 0)
		return -1;
	for (;;) {
		y = frame(title, "Press an item's key, or choose with the "
			  "arrows and Return.");
		list(y, items, NULL, n, cur);
		k = getkey();
		if (k == K_EOF)
			return -1;
		if (k == K_UP)
			cur = (cur + n - 1) % n;
		else if (k == K_DOWN)
			cur = (cur + 1) % n;
		else if (is_return(k))
			return cur;
		else if ((i = index_of(k)) >= 0 && i < n)
			return i;
	}
}

int ui_checklist(const char *title, const char **items, int *on, int n,
		 const int *locked)
{
	int cur = 0, y, k, i;

	for (;;) {
		y = frame(title, "Press an item's key or Space to tick it, "
			  "and Return when done.");
		list(y, items, on, n, cur);
		k = getkey();
		if (k == K_EOF)
			return -1;
		if (is_return(k))
			return 0;
		i = -1;
		if (n > 0 && k == K_UP)
			cur = (cur + n - 1) % n;
		else if (n > 0 && k == K_DOWN)
			cur = (cur + 1) % n;
		else if (n > 0 && k == ' ')
			i = cur;
		else if ((i = index_of(k)) >= n)
			i = -1;
		if (i >= 0) {
			cur = i;
			if (locked == NULL || !locked[i])
				on[i] = !on[i];
		}
	}
}

int ui_input(const char *title, char *buf, int len, int hide)
{
	int pos = (int)strlen(buf), y, k;

	for (;;) {
		y = frame(title, "Type, then press Return.");
		put(y, LEFT, "> ", WIDTH);
		if (!hide)
			put(y, LEFT + 2, buf, WIDTH - 2);
		k = getkey();
		if (k == K_EOF)
			return -1;
		if (is_return(k))
			return pos;
		if ((k == 010 || k == 0177) && pos > 0)
			buf[--pos] = '\0';
		else if (k == 025)	/* ^U */
			buf[pos = 0] = '\0';
		else if (k >= ' ' && k <= '~' && pos < len - 1) {
			buf[pos++] = (char)k;
			buf[pos] = '\0';
		}
	}
}

void ui_message(const char *title, const char *text)
{
	int y, k;

	for (;;) {
		y = frame(title, "Press Return to continue.");
		wrap(y, BOTTOM, text, 1);
		k = getkey();
		if (k == K_EOF || is_return(k))
			return;
	}
}

void ui_progress(int step, int nsteps, const char *what, const char *tail)
{
	char head[160];
	const char *p, *e;
	int y, rows, lines = 0, skip;

	if (nsteps > 0)
		sprintf(head, "Step %d of %d: %.120s", step, nsteps, what);
	else
		sprintf(head, "%.150s", what);
	y = frame(head, "Please wait.");
	if (tail == NULL)
		tail = "";
	for (p = tail; *p != '\0'; p++)
		if (*p == '\n' && p[1] != '\0')
			lines++;
	if (*tail != '\0')
		lines++;
	rows = LINES - 2 - y + 1;
	skip = lines > rows ? lines - rows : 0;
	for (p = tail; *p != '\0'; p = *e ? e + 1 : e) {
		e = strchr(p, '\n');
		if (e == NULL)
			e = p + strlen(p);
		if (skip > 0) {
			skip--;
			continue;
		}
		put(y++, LEFT, p, (int)(e - p) < WIDTH ? (int)(e - p) : WIDTH);
	}
	move(LINES - 1, 0);
	refresh();
}
