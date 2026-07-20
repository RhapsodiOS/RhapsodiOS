#ifndef RHAP_GENERATE_H
#define RHAP_GENERATE_H

struct config {
	const char *srcroot;
	const char *dstroot;
	const char *objroot;
	const char *symroot;
	const char *srcbase;
	const char *toolroot;
	const char *apkrepo;
	const char *rc_archs;
	const char *rc_os;
	const char *wrapper;
	const char *outfile;
};

/* Write build.ninja. Returns 0 on success, non-zero on failure. */
int generate_build_ninja(const struct config *cfg);

/* Fill cfg from env defaults. */
void generate_config_defaults(struct config *cfg);

/* Parse generate options from argv[start..argc). Updates *argi past consumed args.
   Returns 0 ok, 1 usage error, -1 if --help printed (caller should exit 0). */
int generate_parse_args(struct config *cfg, int argc, char **argv, int *argi);

#endif
