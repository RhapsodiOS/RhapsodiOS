/* Kernel resource snapshots: zone element counts, wired pages and mbufs in
 * use, so the leader can report what a test left behind. Every part that
 * cannot be read is -1 and is never reported. */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/mbuf.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <nlist.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "stress.h"
#include "zone_types.h"

extern kern_return_t host_zone_info(host_t host, zone_name_t **names, mach_msg_type_number_t *nn,
	zone_info_t **info, mach_msg_type_number_t *ni);

#define LEAK_ZONE_MIN 64	/* a zone grows by more than this and by more than 10% */
#define LEAK_WIRED_MIN 32
#define LEAK_MBUF_MIN 64
#define LEAK_TOP 3

static long
mbufs_in_use(void)
{
	struct nlist nl[2] = { { "_mbstat" }, { "" } };
	struct mbstat ms;
	long n;
	int fd, i;

	if (nlist("/mach_kernel", nl) != 0 || nl[0].n_value == 0)
		return -1;
	if ((fd = open("/dev/kmem", O_RDONLY)) < 0)
		return -1;
	if (lseek(fd, (off_t)nl[0].n_value, SEEK_SET) < 0 || read(fd, &ms, sizeof ms) != sizeof ms) {
		close(fd);
		return -1;
	}
	close(fd);
	for (n = 0, i = 1; i < 256; i++)
		n += ms.m_mtypes[i];
	return n;
}

void
st_leak_snap(struct st_leak *s)
{
	zone_name_t *names = NULL;
	zone_info_t *info = NULL;
	mach_msg_type_number_t nn = 0, ni = 0;
	vm_statistics_data_t vs;
	int i;

	s->nzones = -1;
	if (host_zone_info(host_self(), &names, &nn, &info, &ni) == KERN_SUCCESS) {
		if (nn == ni) {
			s->nzones = nn < ST_LEAK_ZONES ? nn : ST_LEAK_ZONES;
			for (i = 0; i < s->nzones; i++) {
				strncpy(s->name[i], names[i].zn_name, sizeof s->name[i] - 1);
				s->name[i][sizeof s->name[i] - 1] = '\0';
				s->count[i] = info[i].zi_count;
			}
		}
		vm_deallocate(task_self(), (vm_address_t)names, nn * sizeof *names);
		vm_deallocate(task_self(), (vm_address_t)info, ni * sizeof *info);
	}
	s->wired = vm_statistics(task_self(), &vs) == KERN_SUCCESS ? (long)vs.wire_count : -1;
	s->mbufs = mbufs_in_use();
}

int
st_leak_diff(const struct st_leak *before, const struct st_leak *after, char *out, int len)
{
	long grow[ST_LEAK_ZONES], d, b;
	char tmp[512], *p = tmp;
	const char *q;
	int i, j, k, best, top, any = 0;

	*p = '\0';
	memset(grow, 0, sizeof grow);
	if (before->nzones >= 0 && after->nzones >= 0) {
		for (i = 0; i < after->nzones; i++) {
			b = 0;
			for (j = 0; j < before->nzones; j++)
				if (strcmp(before->name[j], after->name[i]) == 0)
					b = before->count[j];
			d = after->count[i] - b;
			if (d > LEAK_ZONE_MIN && d * 10 > b)
				grow[i] = d;
		}
		for (top = 0; top < LEAK_TOP; top++) {
			for (best = -1, k = 0; k < after->nzones; k++)
				if (grow[k] > 0 && (best < 0 || grow[k] > grow[best]))
					best = k;
			if (best < 0)
				break;
			p += sprintf(p, "%s", top ? "," : " leak=");
			for (q = after->name[best]; *q != '\0'; q++)
				*p++ = *q == ' ' ? '_' : *q;
			p += sprintf(p, ":+%ld", grow[best]);
			any = 1;
			grow[best] = 0;
		}
	}
	if (before->wired >= 0 && after->wired - before->wired > LEAK_WIRED_MIN) {
		p += sprintf(p, " wired=+%ld", after->wired - before->wired);
		any = 1;
	}
	if (before->mbufs >= 0 && after->mbufs >= 0 && after->mbufs - before->mbufs > LEAK_MBUF_MIN) {
		p += sprintf(p, " mbufs=+%ld", after->mbufs - before->mbufs);
		any = 1;
	}
	if (any && strlen(tmp) < len)
		strcat(out, tmp);
	return any;
}
