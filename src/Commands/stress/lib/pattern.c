#include "stress.h"

static unsigned char
pat_byte(unsigned long key, unsigned long o)
{
	/* the constant keeps the word nonzero where (o >> 2) == key: st_mix(0) == 0 */
	unsigned long w = st_mix(((key ^ (o >> 2)) + 0x9e3779b9UL) & ST_MASK);

	return (unsigned char)((w >> (8 * (o & 3))) & 0xff);
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
