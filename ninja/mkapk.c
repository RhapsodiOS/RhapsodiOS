#include "mkapk.h"
#include "util.h"
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static int snprintf_ok(int n, size_t size)
{
	return n >= 0 && (size_t)n < size;
}

static void mkapk_usage(void)
{
	fprintf(stderr,
	    "usage: rhap-build mkapk <PKGINFO> <staging-root> <out.apk>\n");
}

static int is_regular_file(const char *path)
{
	struct stat st;

	return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int is_directory(const char *path)
{
	struct stat st;

	return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int copy_file(const char *src, const char *dst)
{
	FILE *in, *out;
	char buf[8192];
	size_t n;

	in = fopen(src, "rb");
	if (!in)
		return -1;
	out = fopen(dst, "wb");
	if (!out) {
		fclose(in);
		return -1;
	}
	while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
		if (fwrite(buf, 1, n, out) != n) {
			fclose(in);
			fclose(out);
			return -1;
		}
	}
	if (ferror(in)) {
		fclose(out);
		fclose(in);
		return -1;
	}
	fclose(in);
	return fclose(out) == 0 ? 0 : -1;
}

static char *make_temp_dir(void)
{
	const char *tmpdir = env_or("TMPDIR", "/tmp");
	char *template;
	char *dir;
	int n;

	template = xmalloc(strlen(tmpdir) + strlen("/mkapk.XXXXXX") + 1);
	sprintf(template, "%s/mkapk.XXXXXX", tmpdir);
	dir = mkdtemp(template);
	if (dir)
		return dir;

	fprintf(stderr, "mkapk: mkdtemp failed under %s: ", tmpdir);
	perror(NULL);
	free(template);
	template = xmalloc(strlen(tmpdir) + 32);
	n = snprintf(template, strlen(tmpdir) + 32, "%s/mkapk.%d", tmpdir,
	    (int)getpid());
	if (!snprintf_ok(n, strlen(tmpdir) + 32)) {
		fprintf(stderr, "mkapk: temp path too long under %s\n", tmpdir);
		free(template);
		return NULL;
	}
	if (mkdir(template, 0700) != 0) {
		fprintf(stderr, "mkapk: cannot create temp dir %s: ", template);
		perror(NULL);
		free(template);
		return NULL;
	}
	return template;
}

static int rm_rf(const char *path)
{
	char cmd[PATH_MAX * 2 + 16];
	int n;

	n = snprintf(cmd, sizeof(cmd), "rm -rf \"%s\"", path);
	if (!snprintf_ok(n, sizeof(cmd))) {
		fprintf(stderr, "mkapk: rm command path too long\n");
		return -1;
	}
	/* Paths from build system; shell escaping not required. */
	return system(cmd);
}

static int run_tar_pipe(const char *root, const char *tmp)
{
	char cmd[PATH_MAX * 4];
	int n;

	n = snprintf(cmd, sizeof(cmd),
	    "(cd \"%s\" && tar cf - .) | (cd \"%s\" && tar xf -)",
	    root, tmp);
	if (!snprintf_ok(n, sizeof(cmd))) {
		fprintf(stderr, "mkapk: tar pipe command too long\n");
		return -1;
	}
	/* Paths from build system; shell escaping not required. */
	if (system(cmd) != 0) {
		fprintf(stderr, "mkapk: tar pipe failed\n");
		return -1;
	}
	return 0;
}

static int have_gzip(void)
{
	/* Fixed command; no user paths. */
	return system("command -v gzip >/dev/null 2>&1") == 0;
}

static int collect_members(const char *tmp, char ***members, size_t *count)
{
	DIR *d;
	struct dirent *de;
	char **list = NULL;
	size_t n = 0;
	size_t cap = 0;

	d = opendir(tmp);
	if (!d) {
		fprintf(stderr, "mkapk: cannot read temp dir %s: ", tmp);
		perror(NULL);
		return -1;
	}

	while ((de = readdir(d)) != NULL) {
		if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
			continue;
		if (n == cap) {
			cap = cap ? cap * 2 : 8;
			list = xrealloc(list, cap * sizeof(char *));
		}
		list[n++] = xstrdup(de->d_name);
	}
	closedir(d);
	*members = list;
	*count = n;
	return 0;
}

static int create_apk(const char *tmp, const char *out, char **members, size_t count)
{
	char cmd[PATH_MAX * 8];
	size_t off = 0;
	size_t i;
	int n;

	if (have_gzip()) {
		n = snprintf(cmd + off, sizeof(cmd) - off,
		    "(cd \"%s\" && tar cf - .PKGINFO", tmp);
		if (!snprintf_ok(n, sizeof(cmd) - off)) {
			fprintf(stderr, "mkapk: create apk command too long\n");
			return -1;
		}
		off += (size_t)n;
		for (i = 0; i < count; i++) {
			if (strcmp(members[i], ".PKGINFO") == 0)
				continue;
			n = snprintf(cmd + off, sizeof(cmd) - off,
			    " \"%s\"", members[i]);
			if (!snprintf_ok(n, sizeof(cmd) - off)) {
				fprintf(stderr, "mkapk: create apk command too long\n");
				return -1;
			}
			off += (size_t)n;
		}
		n = snprintf(cmd + off, sizeof(cmd) - off,
		    ") | gzip -n > \"%s\"", out);
		if (!snprintf_ok(n, sizeof(cmd) - off)) {
			fprintf(stderr, "mkapk: create apk command too long\n");
			return -1;
		}
		off += (size_t)n;
	} else {
		n = snprintf(cmd + off, sizeof(cmd) - off,
		    "cd \"%s\" && tar czf \"%s\" .PKGINFO", tmp, out);
		if (!snprintf_ok(n, sizeof(cmd) - off)) {
			fprintf(stderr, "mkapk: create apk command too long\n");
			return -1;
		}
		off += (size_t)n;
		for (i = 0; i < count; i++) {
			if (strcmp(members[i], ".PKGINFO") == 0)
				continue;
			n = snprintf(cmd + off, sizeof(cmd) - off,
			    " \"%s\"", members[i]);
			if (!snprintf_ok(n, sizeof(cmd) - off)) {
				fprintf(stderr, "mkapk: create apk command too long\n");
				return -1;
			}
			off += (size_t)n;
		}
	}
	/* Paths from build system; shell escaping not required. */
	if (system(cmd) != 0) {
		fprintf(stderr, "mkapk: create apk failed\n");
		return -1;
	}
	return 0;
}

int mkapk(const char *pkginfo, const char *root, const char *out)
{
	char *tmp = NULL;
	char pkginfo_dst[PATH_MAX];
	char **members = NULL;
	size_t nmembers = 0;
	size_t i;
	int ret = 1;
	int n;

	if (!pkginfo || !root || !out || !*out ||
	    !is_regular_file(pkginfo) || !is_directory(root)) {
		mkapk_usage();
		return 2;
	}

	tmp = make_temp_dir();
	if (!tmp)
		return 1;

	n = snprintf(pkginfo_dst, sizeof(pkginfo_dst), "%s/.PKGINFO", tmp);
	if (!snprintf_ok(n, sizeof(pkginfo_dst))) {
		fprintf(stderr, "mkapk: path too long: %s/.PKGINFO\n", tmp);
		goto cleanup;
	}
	if (copy_file(pkginfo, pkginfo_dst) != 0) {
		fprintf(stderr, "mkapk: cannot copy PKGINFO %s -> %s: ", pkginfo,
		    pkginfo_dst);
		perror(NULL);
		goto cleanup;
	}

	if (run_tar_pipe(root, tmp) != 0)
		goto cleanup;

	if (collect_members(tmp, &members, &nmembers) != 0)
		goto cleanup;

	if (create_apk(tmp, out, members, nmembers) != 0)
		goto cleanup;

	ret = 0;

cleanup:
	if (members) {
		for (i = 0; i < nmembers; i++)
			free(members[i]);
		free(members);
	}
	if (tmp) {
		rm_rf(tmp);
		free(tmp);
	}
	return ret;
}
