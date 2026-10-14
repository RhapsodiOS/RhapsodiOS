/* stress-exec-child: run by the exec test. Prints st_mix(N) in hex and exits
 * N & 0x7f; a second argument makes it print a wrong value (the -x check). */
#include <stdio.h>
#include <stdlib.h>
#include "stress.h"

int
main(int argc, char **argv)
{
	unsigned long n, v;

	if (argc < 2)
		return 126;
	n = strtoul(argv[1], NULL, 10);
	v = st_mix(n) & ST_MASK;
	if (argc > 2)
		v ^= 1;
	printf("%lx\n", v);
	fflush(stdout);
	return n & 0x7f;
}
