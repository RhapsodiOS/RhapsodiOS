#include "index.h"
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

static int is_directory(const char *path)
{
	struct stat st;

	return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int is_executable(const char *path)
{
	return access(path, X_OK) == 0;
}

static int apk_resolved(const char *apk)
{
	char cmd[PATH_MAX + 64];
	int n;

	if (is_executable(apk))
		return 1;
	n = snprintf(cmd, sizeof(cmd), "command -v \"%s\" >/dev/null 2>&1", apk);
	if (!snprintf_ok(n, sizeof(cmd)))
		return 0;
	/* Fixed probe; apk path is quoted. */
	return system(cmd) == 0;
}

static int resolve_apk(char *buf, size_t bufsize)
{
	const char *apk = env_or("APK", "apk");
	const char *dstroot;
	const char *toolroot;
	char candidate[PATH_MAX];
	int n;

	if (apk_resolved(apk)) {
		n = snprintf(buf, bufsize, "%s", apk);
		if (!snprintf_ok(n, bufsize))
			return -1;
		return 0;
	}

	dstroot = getenv("DSTROOT");
	if (dstroot && *dstroot) {
		n = snprintf(candidate, sizeof(candidate), "%s/sbin/apk", dstroot);
		if (snprintf_ok(n, sizeof(candidate)) && is_executable(candidate)) {
			n = snprintf(buf, bufsize, "%s", candidate);
			if (!snprintf_ok(n, bufsize))
				return -1;
			return 0;
		}
	}

	toolroot = getenv("TOOLROOT");
	if (toolroot && *toolroot) {
		n = snprintf(candidate, sizeof(candidate), "%s/sbin/apk", toolroot);
		if (snprintf_ok(n, sizeof(candidate)) && is_executable(candidate)) {
			n = snprintf(buf, bufsize, "%s", candidate);
			if (!snprintf_ok(n, bufsize))
				return -1;
			return 0;
		}
	}

	return -1;
}

static int ends_with_apk(const char *name)
{
	size_t len = strlen(name);

	if (len < 4)
		return 0;
	return strcmp(name + len - 4, ".apk") == 0;
}

static int collect_apk_files(const char *repo, char ***files, size_t *count)
{
	DIR *d;
	struct dirent *de;
	char **list = NULL;
	size_t n = 0;
	size_t cap = 0;
	char path[PATH_MAX];
	int path_n;

	d = opendir(repo);
	if (!d) {
		fprintf(stderr, "index: cannot read %s: ", repo);
		perror(NULL);
		return -1;
	}

	while ((de = readdir(d)) != NULL) {
		if (!ends_with_apk(de->d_name))
			continue;
		path_n = snprintf(path, sizeof(path), "%s/%s", repo, de->d_name);
		if (!snprintf_ok(path_n, sizeof(path))) {
			fprintf(stderr, "index: path too long: %s/%s\n", repo,
			    de->d_name);
			closedir(d);
			return -1;
		}
		if (n == cap) {
			cap = cap ? cap * 2 : 8;
			list = xrealloc(list, cap * sizeof(char *));
		}
		list[n++] = xstrdup(path);
	}
	closedir(d);
	*files = list;
	*count = n;
	return 0;
}

static int run_index_pipeline(const char *apk, char **files, size_t count,
    const char *index_new)
{
	char cmd[PATH_MAX * 16];
	size_t off = 0;
	size_t i;
	int n;

	n = snprintf(cmd + off, sizeof(cmd) - off, "\"%s\" index", apk);
	if (!snprintf_ok(n, sizeof(cmd) - off)) {
		fprintf(stderr, "index: index command too long\n");
		return -1;
	}
	off += (size_t)n;

	for (i = 0; i < count; i++) {
		n = snprintf(cmd + off, sizeof(cmd) - off, " \"%s\"", files[i]);
		if (!snprintf_ok(n, sizeof(cmd) - off)) {
			fprintf(stderr, "index: index command too long\n");
			return -1;
		}
		off += (size_t)n;
	}

	n = snprintf(cmd + off, sizeof(cmd) - off,
	    " | gzip -n > \"%s\"", index_new);
	if (!snprintf_ok(n, sizeof(cmd) - off)) {
		fprintf(stderr, "index: index command too long\n");
		return -1;
	}
	off += (size_t)n;

	/* Paths from build system; shell escaping not required. */
	if (system(cmd) != 0) {
		fprintf(stderr, "index: apk index pipeline failed\n");
		return -1;
	}
	return 0;
}

int index_apk_repo(const char *repo)
{
	char apk[PATH_MAX];
	char index_new[PATH_MAX];
	char index[PATH_MAX];
	char **files = NULL;
	size_t nfiles = 0;
	size_t i;
	int n;
	int ret = 1;

	if (!repo || !is_directory(repo)) {
		fprintf(stderr, "index: not a directory: %s\n",
		    repo ? repo : "(null)");
		return 1;
	}

	if (collect_apk_files(repo, &files, &nfiles) != 0)
		return 1;

	if (nfiles == 0) {
		printf("index: no .apk files in %s (skip)\n", repo);
		return 0;
	}

	if (resolve_apk(apk, sizeof(apk)) != 0) {
		fprintf(stderr,
		    "index: apk not found; wrote packages but no index\n");
		fprintf(stderr,
		    "  set APK=/path/to/apk and re-run: rhap-build index %s\n",
		    repo);
		return 0;
	}

	n = snprintf(index_new, sizeof(index_new), "%s/APK_INDEX.gz.new", repo);
	if (!snprintf_ok(n, sizeof(index_new))) {
		fprintf(stderr, "index: path too long: %s/APK_INDEX.gz.new\n",
		    repo);
		goto cleanup;
	}
	n = snprintf(index, sizeof(index), "%s/APK_INDEX.gz", repo);
	if (!snprintf_ok(n, sizeof(index))) {
		fprintf(stderr, "index: path too long: %s/APK_INDEX.gz\n", repo);
		goto cleanup;
	}

	printf("index: indexing %zu package(s) -> %s\n", nfiles, index);
	if (run_index_pipeline(apk, files, nfiles, index_new) != 0)
		goto cleanup;

	if (rename(index_new, index) != 0) {
		fprintf(stderr, "index: cannot rename %s -> %s: ", index_new,
		    index);
		perror(NULL);
		goto cleanup;
	}

	printf("index: done\n");
	ret = 0;

cleanup:
	for (i = 0; i < nfiles; i++)
		free(files[i]);
	free(files);
	return ret;
}
