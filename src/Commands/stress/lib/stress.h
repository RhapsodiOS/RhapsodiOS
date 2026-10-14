/* Shared helpers for the system stress suite. C89; 32-bit values are held
 * in unsigned long and masked, so i386 and ppc agree bit for bit. */
#ifndef STRESS_H
#define STRESS_H

#define ST_MASK 0xffffffffUL

struct st_rng {
	unsigned long s;
};

unsigned long st_mix(unsigned long x);
unsigned long st_strhash(const char *s);
void st_rng_init(struct st_rng *r, unsigned long seed, const char *test, int idx);
unsigned long st_rand(struct st_rng *r);
unsigned long st_range(struct st_rng *r, unsigned long lo, unsigned long hi);

/* The byte at absolute offset o is byte (o & 3), least significant first,
 * of st_mix(key ^ (o >> 2)). */
void st_fill(void *buf, unsigned long len, unsigned long key, unsigned long off);
long st_check(const void *buf, unsigned long len, unsigned long key, unsigned long off);

const char *st_errname(int err);

#endif
