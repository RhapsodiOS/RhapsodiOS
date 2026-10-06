/* disks.c -- sysinstall's candidate disks.  See disks.h.  The Rhapsody
 * headers are guarded, so this file compiles, empty, anywhere else. */

#include <stdio.h>
#include <string.h>
#include "disks.h"

#ifdef __MACH__

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <bsd/dev/disk.h>

/* The disk of the root filesystem, from mount's "/dev/hd1a on / (local)"
 * line: "hd1".  0, or -1 if there is no such line. */
static int live_root_disk(char out[8])
{
	char line[256], *p;
	FILE *f = popen("/sbin/mount", "r");
	int i, rc = -1;

	if (f == NULL)
		return -1;
	while (rc < 0 && fgets(line, sizeof line, f) != NULL) {
		if (strncmp(line, "/dev/", 5) != 0 ||
		    strstr(line, " on / ") == NULL)
			continue;
		p = line + 5;
		for (i = 0; i < 7 && p[i] != '\0' && p[i] != ' ' &&
		    !(p[i] >= 'a' && p[i] <= 'z' && i >= 2); i++)
			out[i] = p[i];
		out[i] = '\0';	/* "hd1" from "hd1a": up to the partition letter */
		rc = 0;
	}
	pclose(f);
	return rc;
}

int disks_list(char names[][8], unsigned long sizes[], int max)
{
	static const char *kind[2] = { "hd", "sd" };
	static const int count[2] = { 4, 8 };
	char root[8], name[8], path[32];
	int k, n, fd, blocks, found = 0;

	if (live_root_disk(root) < 0)	/* fail closed: it could be any */
		return -1;
	for (k = 0; k < 2; k++) {
		for (n = 0; n < count[k] && found < max; n++) {
			sprintf(name, "%s%d", kind[k], n);
			if (strcmp(name, root) == 0)
				continue;
			sprintf(path, "/dev/r%sh", name);
			fd = open(path, O_RDONLY);
			if (fd < 0)
				continue;
			if (ioctl(fd, DKIOCNUMBLKS, &blocks) == 0 &&
			    blocks > 0) {
				strcpy(names[found], name);
				sizes[found] = (unsigned long)blocks;
				found++;
			}
			close(fd);
		}
	}
	return found;
}

#else

int disks_list(char names[][8], unsigned long sizes[], int max)
{
	(void)names; (void)sizes; (void)max;
	return 0;
}

#endif
