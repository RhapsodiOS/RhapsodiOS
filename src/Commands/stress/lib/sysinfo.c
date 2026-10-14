#include <sys/types.h>
#include <sys/sysctl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "stress.h"

unsigned long
st_physmem(void)
{
	int mib[2], mem = 0;
	size_t len = sizeof mem;

	mib[0] = CTL_HW;
	mib[1] = HW_PHYSMEM;
	if (sysctl(mib, 2, &mem, &len, NULL, 0) < 0)
		return 0;
	return (unsigned long)mem;
}

/* "<dir>/stress.<cat>.<test>.<tag>.<pid>" */
void
st_path(struct st_ctx *c, char *buf, int len, const char *tag)
{
	if (strlen(st_opt.dir) + strlen(c->cat) + strlen(c->test) + strlen(tag) + 24 > (unsigned)len)
		st_fail(c, "reason=path-too-long tag=%s", tag);
	sprintf(buf, "%s/stress.%s.%s.%s.%d", st_opt.dir, c->cat, c->test, tag, (int)getpid());
}
