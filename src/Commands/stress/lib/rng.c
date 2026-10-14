#include "stress.h"

unsigned long
st_mix(unsigned long x)
{
	x &= ST_MASK;
	x ^= x >> 16;
	x = (x * 0x7feb352dUL) & ST_MASK;
	x ^= x >> 15;
	x = (x * 0x846ca68bUL) & ST_MASK;
	x ^= x >> 16;
	return x;
}

unsigned long
st_strhash(const char *s)
{
	unsigned long h = 0x811c9dc5UL;

	while (*s) {
		h ^= (unsigned char)*s++;
		h = (h * 0x01000193UL) & ST_MASK;
	}
	return h;
}

void
st_rng_init(struct st_rng *r, unsigned long seed, const char *test, int idx)
{
	r->s = st_mix(seed ^ st_strhash(test) ^ (((unsigned long)idx * 0x9e3779b9UL) & ST_MASK));
	if (r->s == 0)
		r->s = 1;
}

unsigned long
st_rand(struct st_rng *r)
{
	unsigned long x = r->s;

	x ^= (x << 13) & ST_MASK;
	x ^= x >> 17;
	x ^= (x << 5) & ST_MASK;
	r->s = x;
	return x;
}

unsigned long
st_range(struct st_rng *r, unsigned long lo, unsigned long hi)
{
	return lo + st_rand(r) % (hi - lo + 1);
}
