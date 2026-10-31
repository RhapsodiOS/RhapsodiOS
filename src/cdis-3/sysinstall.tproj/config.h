/* config.h -- sysinstall's template rendering and master.passwd edit.
 * Pure logic: no curses, no crypt(); steps.c makes the hash. */

#ifndef CONFIG_H
#define CONFIG_H

/* tmpl with every @DISK@ replaced by disk.  malloc'd; NULL if out of memory. */
char *render(const char *tmpl, const char *disk);

/* passwd with the password field of its "root:" line replaced by hash.
 * malloc'd; NULL if there is no root line. */
char *passwd_set_root(const char *passwd, const char *hash);

/* A two-character crypt() salt from [./0-9A-Za-z], NUL-terminated. */
void make_salt(unsigned seed, char out[3]);

#endif
