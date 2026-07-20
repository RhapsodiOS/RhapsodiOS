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

	template = xmalloc(strlen(tmpdir) + strlen("/mkapk.XXXXXX") + 1);
	sprintf(template, "%s/mkapk.XXXXXX", tmpdir);
	dir = mkdtemp(template);
	if (dir)
		return dir;

	free(template);
	template = xmalloc(strlen(tmpdir) + 32);
	snprintf(template, strlen(tmpdir) + 32, "%s/mkapk.%d", tmpdir, (int)getpid());
	if (mkdir(template, 0700) != 0) {
		free(template);
		return NULL;
	}
	return template;
}

static int rm_rf(const char *path)
{
	char cmd[PATH_MAX * 2 + 16];

	snprintf(cmd, sizeof(cmd), "rm -rf \"%s\"", path);
	return system(cmd);
}

static int run_tar_pipe(const char *root, const char *tmp)
{
	char cmd[PATH_MAX * 4];

	snprintf(cmd, sizeof(cmd),
	    "(cd \"%s\" && tar cf - .) | (cd \"%s\" && tar xf -)",
	    root, tmp);
	return system(cmd);
}

static int have_gzip(void)
{
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
	if (!d)
		return -1;

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

	if (have_gzip()) {
		off += (size_t)snprintf(cmd + off, sizeof(cmd) - off,
		    "(cd \"%s\" && tar cf - .PKGINFO", tmp);
		for (i = 0; i < count; i++) {
			if (strcmp(members[i], ".PKGINFO") == 0)
				continue;
			off += (size_t)snprintf(cmd + off, sizeof(cmd) - off,
			    " \"%s\"", members[i]);
			if (off >= sizeof(cmd))
				return -1;
		}
		off += (size_t)snprintf(cmd + off, sizeof(cmd) - off,
		    ") | gzip -n > \"%s\"", out);
	} else {
		off += (size_t)snprintf(cmd + off, sizeof(cmd) - off,
		    "cd \"%s\" && tar czf \"%s\" .PKGINFO", tmp, out);
		for (i = 0; i < count; i++) {
			if (strcmp(members[i], ".PKGINFO") == 0)
				continue;
			off += (size_t)snprintf(cmd + off, sizeof(cmd) - off,
			    " \"%s\"", members[i]);
			if (off >= sizeof(cmd))
				return -1;
		}
	}
	if (off >= sizeof(cmd))
		return -1;
	return system(cmd);
}

int mkapk(const char *pkginfo, const char *root, const char *out)
{
	char *tmp = NULL;
	char pkginfo_dst[PATH_MAX];
	char **members = NULL;
	size_t nmembers = 0;
	size_t i;
	int ret = 1;

	if (!pkginfo || !root || !out || !*out ||
	    !is_regular_file(pkginfo) || !is_directory(root)) {
		mkapk_usage();
		return 2;
	}

	tmp = make_temp_dir();
	if (!tmp)
		return 1;

	snprintf(pkginfo_dst, sizeof(pkginfo_dst), "%s/.PKGINFO", tmp);
	if (copy_file(pkginfo, pkginfo_dst) != 0)
		goto cleanup;

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
