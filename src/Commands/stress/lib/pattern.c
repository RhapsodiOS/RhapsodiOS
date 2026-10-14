#include "stress.h"

static unsigned char
pat_byte(unsigned long key, unsigned long o)
{
	return (unsigned char)((st_mix(key ^ (o >> 2)) >> (8 * (o & 3))) & 0xff);
}

void
st_fill(void *buf, unsigned long len, unsigned long key, unsigned long off)
{
	unsigned char *p = buf;
	unsigned long i;

	for (i = 0; i < len; i++)
		p[i] = pat_byte(key, off + i);
}

long
st_check(const void *buf, unsigned long len, unsigned long key, unsigned long off)
{
	const unsigned char *p = buf;
	unsigned long i;

	for (i = 0; i < len; i++)
		if (p[i] != pat_byte(key, off + i))
			return (long)i;
	return -1;
}
