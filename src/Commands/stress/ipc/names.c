/* stress-ipc-names: prints how many bootstrap names start with "stress."
 * (each one on stderr), for make check-ipc. Exits 1 if bootstrap_info fails. */
#include <stdio.h>
#include <string.h>
#include <mach/mach.h>
#include <servers/bootstrap.h>

int
main(void)
{
	name_array_t svc, srv;
	bool_array_t act;
	unsigned int nsvc, nsrv, nact, i, n = 0;
	kern_return_t kr;

	kr = bootstrap_info(bootstrap_port, &svc, &nsvc, &srv, &nsrv, &act, &nact);
	if (kr != KERN_SUCCESS) {
		fprintf(stderr, "stress-ipc-names: bootstrap_info: kr=%d\n", kr);
		return 1;
	}
	for (i = 0; i < nsvc; i++) {
		if (strncmp(svc[i], "stress.", 7) == 0) {
			fprintf(stderr, "%s\n", svc[i]);
			n++;
		}
	}
	printf("%u\n", n);
	return 0;
}
