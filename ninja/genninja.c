/*
 * genninja - thin bridge to the generate library (temporary until rhap-build).
 */

#include "generate.h"
#include <stdio.h>

int main(int argc, char **argv)
{
	struct config cfg;
	int i = 1, r;

	generate_config_defaults(&cfg);
	r = generate_parse_args(&cfg, argc, argv, &i);
	if (r < 0)
		return 0;
	if (r > 0)
		return 2;
	if (i != argc) {
		fprintf(stderr, "genninja: unexpected args\n");
		return 2;
	}
	return generate_build_ninja(&cfg);
}
