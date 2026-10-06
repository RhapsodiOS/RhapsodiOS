/* disks.c -- sysinstall's candidate disks.  See disks.h.  The Rhapsody
 * headers are guarded, so this file compiles, empty, anywhere else. */

#include <stdio.h>
#include <string.h>
#include "disks.h"

int dev_disk_name(unsigned major, unsigned minor, char out[8])
{
	if (major != 3 && major != 6)
		return -1;
	sprintf(out, "%s%u", major == 3 ? "hd" : "sd", minor >> 3);
	return 0;
}

#ifdef __MACH__

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <bsd/dev/disk.h>

/* The disk holding the root filesystem: "hd1" when / is on hd1a.  0, -1
 * if / can't be stat()ed, or 0 with an empty name if / is on no disk.
 * mount can't say: it lists the root the kernel mounted as root_device. */
static int live_root_disk(char out[8])
{
	struct stat st;

	if (stat("/", &st) < 0)
		return -1;
	if (dev_disk_name(major(st.st_dev), minor(st.st_dev), out) < 0)
		out[0] = '\0';
	return 0;
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
