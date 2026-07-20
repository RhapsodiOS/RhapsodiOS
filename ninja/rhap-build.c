#include "index.h"
#include "mkapk.h"
#include "generate.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static void usage(void)
{
	fprintf(stderr,
"usage: rhap-build [generate-options] [command] [arguments]\n"
"\n"
"commands:\n"
"  generate [generate-options]       write build.ninja\n"
"  build [generate-options] [--samu PATH] [target ...]\n"
"                                      generate, then run samu (default: buildworld)\n"
"  mkapk <PKGINFO> <staging-root> <out.apk>\n"
"  index <repo-dir>                  write APK_INDEX.gz\n"
"  publish <repo-dir> <PKGINFO> <staging-root> [...]\n"
"                                      package pairs and index the repository\n"
"\n"
"Without a command, rhap-build generates build.ninja and prints build hints.\n"
"Generate options: --srcroot, --dstroot, --objroot, --symroot, --srcbase,\n"
"  --toolroot, --apkrepo, --rc-archs, --rc-os, --wrapper, -o/--out.\n");
}

static int is_command(const char *arg)
{
	return !strcmp(arg, "generate") || !strcmp(arg, "build") ||
	       !strcmp(arg, "mkapk") || !strcmp(arg, "index") ||
	       !strcmp(arg, "publish");
}

static int make_dir(const char *path)
{
	char buf[PATH_MAX];
	char *p;
	size_t len;

	if (!path || !*path || strlen(path) >= sizeof(buf))
		return -1;
	strcpy(buf, path);
	len = strlen(buf);
	if (len > 1 && buf[len - 1] == '/')
		buf[len - 1] = '\0';

	for (p = buf + 1; *p; p++) {
		if (*p != '/')
			continue;
		*p = '\0';
		if (mkdir(buf, 0777) != 0 && errno != EEXIST)
			return -1;
		*p = '/';
	}
	if (mkdir(buf, 0777) != 0 && errno != EEXIST)
		return -1;
	return 0;
}

static char *trim(char *s)
{
	char *end;
	while (*s == ' ' || *s == '\t')
		s++;
	end = s + strlen(s);
	while (end > s && (end[-1] == ' ' || end[-1] == '\t' ||
			   end[-1] == '\r' || end[-1] == '\n'))
		*--end = '\0';
	return s;
}

static int pkginfo_field(const char *path, const char *field,
			 char *out, size_t outsz)
{
	FILE *f;
	char line[1024];

	f = fopen(path, "rb");
	if (!f) {
		fprintf(stderr, "rhap-build: cannot read %s: %s\n",
			path, strerror(errno));
		return -1;
	}
	while (fgets(line, sizeof(line), f)) {
		char *eq = strchr(line, '=');
		char *key;
		char *value;
		if (!eq)
			continue;
		*eq = '\0';
		key = trim(line);
		value = trim(eq + 1);
		if (!strcmp(key, field)) {
			if (!*value || strlen(value) >= outsz) {
				fclose(f);
				return -1;
			}
			strcpy(out, value);
			fclose(f);
			return 0;
		}
	}
	fclose(f);
	return -1;
}

static int safe_filename_part(const char *s)
{
	return *s && !strchr(s, '/') && !strchr(s, '\\');
}

static int publish(int argc, char **argv)
{
	const char *repo;
	int i;

	if (argc < 4 || (argc - 2) % 2) {
		usage();
		return 2;
	}
	repo = argv[1];
	if (make_dir(repo) != 0) {
		fprintf(stderr, "rhap-build: cannot create %s: %s\n",
			repo, strerror(errno));
		return 1;
	}
	for (i = 2; i < argc; i += 2) {
		char name[256];
		char version[256];
		char output[PATH_MAX];
		int n;

		if (pkginfo_field(argv[i], "pkgname", name, sizeof(name)) != 0 ||
		    pkginfo_field(argv[i], "pkgver", version, sizeof(version)) != 0 ||
		    !safe_filename_part(name) || !safe_filename_part(version)) {
			fprintf(stderr, "rhap-build: %s: missing or invalid pkgname/pkgver\n",
				argv[i]);
			return 1;
		}
		n = snprintf(output, sizeof(output), "%s/%s-%s.apk",
			repo, name, version);
		if (n < 0 || (size_t)n >= sizeof(output)) {
			fprintf(stderr, "rhap-build: output path too long\n");
			return 1;
		}
		if (mkapk(argv[i], argv[i + 1], output) != 0)
			return 1;
	}
	return index_apk_repo(repo);
}

static int run_samu(const char *samu, char **targets, int ntargets)
{
	char cwd[PATH_MAX];
	char default_samu[PATH_MAX];
	char **args;
	pid_t pid;
	int status;
	int i;

	if (!getcwd(cwd, sizeof(cwd))) {
		fprintf(stderr, "rhap-build: getcwd: %s\n", strerror(errno));
		return 1;
	}
	if (!samu) {
		const char *env_samu = getenv("SAMU");
		if (env_samu && *env_samu)
			samu = env_samu;
		else {
			if (snprintf(default_samu, sizeof(default_samu),
			    "%s/ninja/samurai/samu", cwd) >= (int)sizeof(default_samu)) {
				fprintf(stderr, "rhap-build: default samu path too long\n");
				return 1;
			}
			samu = default_samu;
		}
	}
	args = malloc((size_t)(ntargets + 2) * sizeof(*args));
	if (!args) {
		fprintf(stderr, "rhap-build: out of memory\n");
		return 1;
	}
	args[0] = (char *)samu;
	if (ntargets == 0)
		args[1] = "buildworld";
	else
		for (i = 0; i < ntargets; i++)
			args[i + 1] = targets[i];
	args[ntargets ? ntargets + 1 : 2] = NULL;

	pid = fork();
	if (pid < 0) {
		fprintf(stderr, "rhap-build: fork: %s\n", strerror(errno));
		free(args);
		return 1;
	}
	if (pid == 0) {
		if (chdir(cwd) != 0) {
			fprintf(stderr, "rhap-build: chdir %s: %s\n",
				cwd, strerror(errno));
			_exit(127);
		}
		execvp(samu, args);
		fprintf(stderr, "rhap-build: cannot run %s: %s\n",
			samu, strerror(errno));
		_exit(127);
	}
	free(args);
	if (waitpid(pid, &status, 0) < 0) {
		fprintf(stderr, "rhap-build: waitpid: %s\n", strerror(errno));
		return 1;
	}
	if (WIFEXITED(status))
		return WEXITSTATUS(status);
	return 1;
}

static int parse_build_args(struct config *cfg, int argc, char **argv,
			    const char **samu, char ***targets, int *ntargets)
{
	int i;
	char **out = malloc((size_t)(argc + 1) * sizeof(*out));
	int nout = 1;
	int r;

	if (!out)
		return 1;
	out[0] = argv[0];
	for (i = 0; i < argc; i++) {
		if (!strcmp(argv[i], "--samu")) {
			if (++i >= argc || *samu) {
				free(out);
				return 1;
			}
			*samu = argv[i];
		} else if (argv[i][0] == '-') {
			out[nout++] = argv[i];
			if (strcmp(argv[i], "-h") && strcmp(argv[i], "--help")) {
				if (++i >= argc) {
					free(out);
					return 1;
				}
				out[nout++] = argv[i];
			}
		} else {
			(*targets)[(*ntargets)++] = argv[i];
		}
	}
	i = 1;
	r = generate_parse_args(cfg, nout, out, &i);
	free(out);
	return r == 0 && i == nout ? 0 : 1;
}

int main(int argc, char **argv)
{
	int command = -1;
	int i;
	struct config cfg;
	int r;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
			usage();
			return 0;
		}
		if (argv[i][0] != '-' && is_command(argv[i])) {
			command = i;
			break;
		}
	}

	if (command >= 0 && !strcmp(argv[command], "mkapk")) {
		if (command != 1 || argc != 5) {
			usage();
			return 2;
		}
		return mkapk(argv[2], argv[3], argv[4]);
	}
	if (command >= 0 && !strcmp(argv[command], "index")) {
		if (command != 1 || argc != 3) {
			usage();
			return 2;
		}
		return index_apk_repo(argv[2]);
	}
	if (command >= 0 && !strcmp(argv[command], "publish")) {
		if (command != 1) {
			usage();
			return 2;
		}
		return publish(argc - 1, argv + 1);
	}

	generate_config_defaults(&cfg);
	if (command < 0) {
		i = 1;
		r = generate_parse_args(&cfg, argc, argv, &i);
		if (r < 0)
			return 0;
		if (r || i != argc) {
			usage();
			return 2;
		}
		r = generate_build_ninja(&cfg);
		if (!r)
			fprintf(stderr,
			    "rhap-build: ready. From the repo root run:\n"
			    "  ninja/samurai/samu buildworld\n"
			    "  ninja/samurai/samu buildkernel\n"
			    "Or: ninja/rhap-build build [target...]\n");
		return r;
	}

	if (command != 1) {
		usage();
		return 2;
	}
	if (!strcmp(argv[command], "generate")) {
		i = command + 1;
		r = generate_parse_args(&cfg, argc, argv, &i);
		if (r < 0)
			return 0;
		if (r || i != argc) {
			usage();
			return 2;
		}
		return generate_build_ninja(&cfg);
	}
	if (!strcmp(argv[command], "build")) {
		const char *samu = NULL;
		char **targets = calloc((size_t)argc, sizeof(*targets));
		int ntargets = 0;
		if (!targets ||
		    parse_build_args(&cfg, argc - command - 1, argv + command + 1,
			&samu, &targets, &ntargets) != 0) {
			free(targets);
			usage();
			return 2;
		}
		r = generate_build_ninja(&cfg);
		if (!r)
			r = run_samu(samu, targets, ntargets);
		free(targets);
		return r;
	}

	usage();
	return 2;
}
