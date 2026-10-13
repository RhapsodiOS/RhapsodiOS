/* sets.h -- sysinstall's *.set file parsing.  Pure logic: no curses. */

#ifndef SETS_H
#define SETS_H

struct set {
	char name[32], title[64], desc[128];
	int required;
	char **pkgs;
	int npkgs;
};

/* Parse a set file's text into *s.  0, or -1 on a malformed file.  The
 * package names are malloc'd; release them with set_free. */
int set_parse(const char *name, const char *text, struct set *s);
void set_free(struct set *s);

/* The packages of the chosen sets (indices into sets, n of them), each
 * once, "files" first.  Returns the count, or -1 if out of memory; *out
 * and its strings are malloc'd. */
int set_union(const struct set *sets, const int *chosen, int n, char ***out);

#endif
